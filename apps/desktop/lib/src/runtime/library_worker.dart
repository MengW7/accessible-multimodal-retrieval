import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:core_storage/core_storage.dart';
import 'package:path/path.dart' as p;

import '../application/library_models.dart';
import '../application/library_service.dart';
import '../application/search_models.dart';
import 'runtime_config.dart';
import 'runtime_session.dart';

/// Only immutable DTOs and ports cross the isolate boundary. SQLite, tokenizers
/// and the Python host stay in the worker for its entire lifetime.
final class WorkerLibraryService implements LibraryService, SearchService {
  WorkerLibraryService(this.config);
  final RuntimeConfig config;
  final _progress = StreamController<LibraryProgress>.broadcast(sync: true);
  final _pending = <int, Completer<Object?>>{};
  final _inbox = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  Isolate? _isolate;
  SendPort? _commands;
  Future<void>? _starting;
  Future<void>? _closing;
  int _next = 0;
  int _searchVersion = 0;
  bool _closed = false;
  bool _cancelRequested = false;
  Object? _failure;

  @override
  Stream<LibraryProgress> get progress => _progress.stream;

  Future<void> _start() => _starting ??= _spawn();
  Future<void> _spawn() async {
    _inbox.listen((message) {
      final m = message as Map;
      switch (m['kind']) {
        case 'ready':
          _commands = m['port'] as SendPort;
          if (!_ready.isCompleted) _ready.complete();
        case 'progress':
          if (!_closed) _progress.add(m['value'] as LibraryProgress);
        case 'reply':
          final pending = _pending.remove(m['id']);
          if (m['cancelled'] == true) {
            pending?.completeError(const SearchCancelledException());
          } else if (m['error'] != null) {
            pending?.completeError(StateError(m['error'] as String));
          } else {
            pending?.complete(m['value']);
          }
      }
    });
    _errors.listen((error) => _fail(StateError('索引后台异常：$error')));
    _exits.listen((_) {
      if (_closing == null && !_closed) _fail(StateError('索引后台已意外退出，请重启应用。'));
    });
    try {
      _isolate = await Isolate.spawn(
        _libraryWorkerMain,
        _WorkerBoot(config, _inbox.sendPort),
        onError: _errors.sendPort,
        onExit: _exits.sendPort,
      );
      await _ready.future.timeout(const Duration(seconds: 15));
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  void _fail(Object error) {
    _failure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
  }

  Future<T> _request<T>(
    String operation, {
    String? path,
    bool force = false,
    SearchRequest? search,
  }) async {
    if (_closed || (_closing != null && operation != 'close')) {
      throw StateError('文件库服务已关闭。');
    }
    await _start();
    if (_failure != null) throw StateError(_failure.toString());
    final id = ++_next;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands!.send({
      'id': id,
      'operation': operation,
      'path': path,
      'force': force,
      'search': search,
    });
    if (operation == 'index' && _cancelRequested) {
      _commands!.send({'operation': 'cancel'});
    }
    return await completer.future as T;
  }

  @override
  Future<LibrarySnapshot> load() => _request('load');
  @override
  Future<LibraryResult> index(String path, {bool force = false}) {
    _cancelRequested = false;
    return _request('index', path: path, force: force);
  }

  @override
  Future<LibrarySnapshot> clear() => _request('clear');
  @override
  Future<SearchPage> search(SearchRequest request) async {
    if (_closed || _closing != null) throw StateError('文件库服务已关闭。');
    final version = ++_searchVersion;
    await _start();
    if (version != _searchVersion) throw const SearchCancelledException();
    return _request('search', search: request);
  }

  @override
  void cancelSearch() {
    _searchVersion++;
    _commands?.send({'operation': 'cancelSearch'});
  }

  @override
  void cancel() {
    _cancelRequested = true;
    _commands?.send({'operation': 'cancel'});
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      if (_starting != null && _failure == null) {
        // Cooperative cancellation completes the file boundary and releases the
        // embedding process before the worker is stopped.
        cancel();
        cancelSearch();
        await _request<Object?>('close');
      }
    } finally {
      _closed = true;
      _isolate?.kill(priority: Isolate.immediate);
      _inbox.close();
      _errors.close();
      _exits.close();
      for (final pending in _pending.values) {
        pending.completeError(StateError('文件库服务已关闭。'));
      }
      _pending.clear();
      await _progress.close();
    }
  }
}

final class _WorkerBoot {
  const _WorkerBoot(this.config, this.replies);
  final RuntimeConfig config;
  final SendPort replies;
}

void _libraryWorkerMain(_WorkerBoot boot) {
  final commands = ReceivePort();
  final worker = _LibraryWorker(
    boot.config,
    (progress) => boot.replies.send({'kind': 'progress', 'value': progress}),
  );
  Future<void>? active;
  String? activeOperation;
  Map? queuedSearch;
  bool closing = false;
  void reply(Map m, {Object? value, Object? error, bool cancelled = false}) =>
      boot.replies.send({
        'kind': 'reply',
        'id': m['id'],
        'value': value,
        'error': error?.toString(),
        'cancelled': cancelled,
      });
  void discardQueuedSearch() {
    final queued = queuedSearch;
    queuedSearch = null;
    if (queued != null) reply(queued, cancelled: true);
  }

  Future<void> run(Map m) async {
    final operation = m['operation'];
    final done = Completer<void>();
    active = done.future;
    activeOperation = operation as String;
    try {
      final Object value = switch (operation) {
        'load' => await worker.snapshot(),
        'index' => await worker.index(
          m['path'] as String,
          force: m['force'] == true,
        ),
        'clear' => await worker.clear(),
        'search' => await worker.search(m['search'] as SearchRequest),
        _ => throw UnsupportedError('未知文件库操作：$operation'),
      };
      reply(m, value: value);
    } on CancelledException {
      reply(m, cancelled: true);
    } catch (error) {
      reply(m, error: error);
    } finally {
      active = null;
      activeOperation = null;
      done.complete();
      final next = queuedSearch;
      queuedSearch = null;
      if (next != null && !closing) unawaited(run(next));
    }
  }

  commands.listen((message) async {
    final m = message as Map;
    final operation = m['operation'];
    if (operation == 'cancel') {
      worker.cancel?.cancel();
      return;
    }
    if (operation == 'cancelSearch') {
      worker.searchCancel?.cancel();
      discardQueuedSearch();
      return;
    }
    if (operation == 'close') {
      closing = true;
      worker.cancel?.cancel();
      worker.searchCancel?.cancel();
      discardQueuedSearch();
      await active;
      await worker.close();
      reply(m);
      commands.close();
      return;
    }
    if (operation == 'search' && activeOperation == 'search' && !closing) {
      worker.searchCancel?.cancel();
      discardQueuedSearch();
      queuedSearch = m;
      return;
    }
    if (active != null || closing) {
      reply(m, error: '已有后台任务正在执行，请等待完成。');
      return;
    }
    unawaited(run(m));
  });
  boot.replies.send({'kind': 'ready', 'port': commands.sendPort});
}

final class _LibraryWorker {
  _LibraryWorker(this.config, this.emit);
  final RuntimeConfig config;
  final void Function(LibraryProgress) emit;
  RuntimeSession? session;
  CancellationTokenSource? cancel;
  CancellationTokenSource? searchCancel;
  final files = <String, LibraryFile>{};

  File get rootsFile =>
      File(p.join(config.dataDirectory, 'library-roots.json'));
  void _validateConfig() {
    if (config.configurationErrors.isNotEmpty) {
      throw StateError(config.configurationErrors.join('\n'));
    }
  }

  Future<List<LibraryRun>> _readRoots() async {
    if (!await rootsFile.exists()) return [];
    try {
      final json =
          jsonDecode(await rootsFile.readAsString()) as Map<String, dynamic>;
      if (json['version'] != 1) {
        throw const FormatException('Unknown library version');
      }
      return (json['roots'] as List)
          .map((r) => LibraryRun.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (error) {
      throw StateError(
        '无法读取文件库记录 ${rootsFile.path}：$error。'
        '请备份修复该文件，或通过“清除索引”重置；源文件不受影响。',
      );
    }
  }

  Future<void> _saveRoots(List<LibraryRun> roots) async {
    final temporary = File('${rootsFile.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'roots': roots.map((r) => r.toJson()).toList(),
      }),
      flush: true,
    );
    await temporary.rename(rootsFile.path);
  }

  Future<T> _withStore<T>(Future<T> Function(SqliteVectorStore) action) async {
    _validateConfig();
    final existing = session;
    if (existing != null) return action(existing.store);
    await Directory(config.dataDirectory).create(recursive: true);
    final opened = openStore(
      const SystemSqliteLibraryLocator(),
      config.databasePath,
    );
    final store = opened.store;
    if (store == null) {
      throw StateError(
        '无法打开索引：${opened.failure?.message} ${opened.failure?.detail}',
      );
    }
    try {
      return await action(store);
    } finally {
      store.close();
    }
  }

  Future<LibrarySnapshot> snapshot() async {
    final stats = await _withStore((store) => store.stats());
    final roots = await _readRoots();
    return LibrarySnapshot(roots: List.unmodifiable(roots), stats: stats);
  }

  Future<SearchPage> search(SearchRequest request) async {
    _validateConfig();
    searchCancel = CancellationTokenSource();
    try {
      final stats = await _withStore((store) => store.stats());
      searchCancel!.token.throwIfCancelled();
      if (stats.documents == 0) {
        return SearchPage(
          request: request,
          hits: const [],
          indexedDocuments: 0,
        );
      }
      final live = _ensureSession();
      final hits = await live.search.search(
        request.query,
        filters: request.filters,
        topK: request.topK,
        cancel: searchCancel!.token,
      );
      searchCancel!.token.throwIfCancelled();
      return SearchPage(
        request: request,
        hits: List.unmodifiable(hits),
        indexedDocuments: stats.documents,
      );
    } finally {
      searchCancel = null;
    }
  }

  RuntimeSession _ensureSession() => session ??= RuntimeSession.open(
    config,
    onIngestProgress: (progress) => emit(
      LibraryProgress(
        stage: LibraryStage.parsing,
        processed: progress.processed,
        total: progress.total,
        currentPath: progress.currentPath,
      ),
    ),
    onIngested: (ingest) {
      files.clear();
      for (final record in ingest.records) {
        final failed =
            record.outcome == ParseOutcome.failed ||
            record.failure?.kind == ParseFailureKind.permissionDenied;
        files[record.metadata.path] = LibraryFile(
          path: record.metadata.path,
          status: failed
              ? LibraryFileStatus.failed
              : record.metadata.isIndexable
              ? LibraryFileStatus.queued
              : LibraryFileStatus.skipped,
          detail: record.failure?.message ?? record.metadata.errorMessage,
          warning: record.outcome == ParseOutcome.partial,
        );
      }
      emit(
        LibraryProgress(
          stage: LibraryStage.indexing,
          total: ingest.indexable.length,
          files: List.unmodifiable(files.values),
        ),
      );
    },
  );

  Future<LibraryResult> index(String input, {required bool force}) async {
    _validateConfig();
    if (!p.isAbsolute(input)) throw ArgumentError('请输入目录的绝对路径。');
    final root = p.normalize(input);
    cancel = CancellationTokenSource();
    final roots = await _readRoots();
    await Directory(config.dataDirectory).create(recursive: true);
    files.clear();
    emit(const LibraryProgress(stage: LibraryStage.preparing));
    try {
      if (!cancel!.isCancelled) {
        _ensureSession();
      }
      final indexed = cancel!.isCancelled
          ? const IndexReport(
              documents: 0,
              written: 0,
              reused: 0,
              failed: 0,
              cancelled: true,
              chunksWritten: 0,
            )
          : await session!.indexing.index(
              root,
              force: force,
              cancel: cancel!.token,
              onProgress: (progress) {
                final path = progress.path;
                LibraryFile? file;
                if (path != null && progress.outcome != null) {
                  file = LibraryFile(
                    path: path,
                    status: switch (progress.outcome!) {
                      IndexFileOutcome.written => LibraryFileStatus.indexed,
                      IndexFileOutcome.reused => LibraryFileStatus.reused,
                      IndexFileOutcome.failed => LibraryFileStatus.failed,
                    },
                    detail: progress.errorMessage ?? files[path]?.detail,
                    warning: files[path]?.warning ?? false,
                  );
                  files[path] = file;
                }
                emit(
                  LibraryProgress(
                    stage: LibraryStage.indexing,
                    processed: progress.processed,
                    total: progress.total,
                    currentPath: path,
                    files: file == null ? const [] : [file],
                  ),
                );
              },
            );
      for (final entry in files.entries.toList()) {
        if (entry.value.status == LibraryFileStatus.queued) {
          files[entry.key] = LibraryFile(
            path: entry.key,
            status: LibraryFileStatus.cancelled,
            detail: '取消后未处理，已提交的索引保留。',
          );
        }
      }
      final run = LibraryRun(
        root: root,
        finishedAt: DateTime.now(),
        written: indexed.written,
        reused: indexed.reused,
        cancelled: indexed.cancelled,
        files: List.unmodifiable(files.values),
      );
      emit(LibraryProgress(stage: LibraryStage.saving, files: run.files));
      // Normalize comparison on Windows; adding the same folder updates its
      // saved row. Equal-content documents retain the core's deduplication rule.
      roots.removeWhere((r) => p.equals(r.root, root));
      roots.add(run);
      try {
        await _saveRoots(roots);
      } catch (error) {
        throw StateError(
          '索引数据已按文件提交，但保存文件库记录失败：$error。'
          '请检查数据目录权限后重新进行增量更新；源文件未修改。',
        );
      }
      return LibraryResult(run: run, snapshot: await snapshot());
    } finally {
      cancel = null;
    }
  }

  Future<LibrarySnapshot> clear() async {
    await _withStore((store) => store.clear());
    try {
      await _saveRoots([]);
    } catch (error) {
      throw StateError('索引已清除，但目录记录重置失败：$error。请修复数据目录权限后重试。');
    }
    return snapshot();
  }

  Future<void> close() async {
    await session?.close();
    session = null;
  }
}
