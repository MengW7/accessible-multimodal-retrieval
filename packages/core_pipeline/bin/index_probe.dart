import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:core_storage/core_storage.dart';
import 'package:path/path.dart' as p;

import 'probe_common.dart';

/// 扫描、解析、切块、常驻向量化，写入系统 SQLite。
///
/// ```text
/// dart run packages/core_pipeline/bin/index_probe.dart --path <dir> --db <file>
/// ```
Future<void> main(List<String> args) async {
  final ProbeArgs flags;
  try {
    flags = parseProbeArgs(
      args,
      valued: const <String>{'path', 'prefix', 'db', 'cancel-after'},
      flags: const <String>{'force', 'clear'},
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _usage();
    exitCode = 64;
    return;
  }

  final String? databasePath = flags.optional('db');
  final List<String> paths = flags.many('path');
  if (databasePath == null ||
      databasePath.isEmpty ||
      (paths.isEmpty && !flags.has('clear'))) {
    stderr.writeln('Pass --db and at least one --path, or --clear.');
    _usage();
    exitCode = 64;
    return;
  }

  final ProbePaths repo = findProbePaths();
  final List<String> directories = <String>[];
  for (final String path in paths) {
    final String resolved = _resolveDirectory(repo.root, path);
    if (resolved.isEmpty) {
      stderr.writeln('Directory not found: $path');
      exitCode = 64;
      return;
    }
    directories.add(resolved);
  }

  SqliteVectorStore? store;
  ProbeRuntime? runtime;
  try {
    if (directories.isNotEmpty) {
      requireProbeFiles(repo);
      runtime = openProbeRuntime(repo);
    }
    final String db = p.isAbsolute(databasePath)
        ? databasePath
        : p.join(repo.root, databasePath);
    final Directory parent = Directory(p.dirname(db));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final OpenedStore opened = openStore(const SystemSqliteLibraryLocator(), db);
    store = opened.store;
    if (store == null) {
      stderr.writeln(opened.failure?.message ?? 'SQLite could not be opened.');
      exitCode = 1;
      return;
    }
    stdout.writeln('db=$db');
    if (flags.has('clear')) {
      final IndexStats before = await store.stats();
      await store.clear();
      final IndexStats after = await store.stats();
      stdout.writeln(
        'clear_before_chunks=${before.chunks} clear_after_chunks=${after.chunks}',
      );
    }
    final ProbeRuntime? live = runtime;
    if (live == null) {
      return;
    }
    final SqliteVectorStore ready = store;
    final List<String> requested = flags.many('prefix');
    final List<String> resolvedPrefixes = <String>[
      for (var index = 0; index < directories.length; index++)
        index < requested.length && requested[index].isNotEmpty
            ? requested[index].replaceAll('\\', '/')
            : repoPrefix(repo.root, directories[index]),
    ];
    final _LoggingSource source = _LoggingSource(
      IngestionIndexSource(
        IngestionService(
          registry: probeRegistry(repo),
          metadata: FileMetadataExtractor(),
        ),
        extensions: probeExtensions,
      ),
    );
    var prefixSlot = 0;
    final CascadeTextChunker chunker = probeChunker(live.tokenizer);
    final DefaultIndexingPipeline indexing = DefaultIndexingPipeline(
      source: source,
      engine: live.engine,
      store: ready,
      chunker: chunker,
      images: const PackageImageDecoder(),
      textModel: documentTextModel,
      imageModel: clipVisionModel,
      chunkerVersion: chunker.chunkerVersion,
      documentKeyOf: (FileMetadata metadata) {
        return joinDocumentKey(
          resolvedPrefixes[prefixSlot],
          metadata.relativePath,
        );
      },
    );
    final int? cancelAfter = flags.optionalInt('cancel-after');
    var indexMsTotal = 0;
    var unexpectedFailure = false;
    for (var index = 0; index < directories.length; index++) {
      prefixSlot = index;
      final CancellationTokenSource cancel = CancellationTokenSource();
      final Stopwatch watch = Stopwatch()..start();
      final IndexReport report = await indexing.index(
        directories[index],
        cancel: cancel.token,
        force: flags.has('force'),
        onProgress: (IndexProgress progress) {
          stderr.writeln(
            'progress ${progress.processed}/${progress.total} '
            '${directories[index]}',
          );
          if (cancelAfter != null &&
              cancelAfter > 0 &&
              progress.processed >= cancelAfter) {
            cancel.cancel();
          }
        },
      );
      watch.stop();
      indexMsTotal += watch.elapsedMilliseconds;
      _writeReport(
        directory: directories[index],
        prefix: resolvedPrefixes[index],
        ingest: source.last,
        report: report,
        indexMs: watch.elapsedMilliseconds,
      );
      if (report.failed > 0 || (report.cancelled && cancelAfter == null)) {
        unexpectedFailure = true;
      }
    }
    final IndexStats stats = await ready.stats();
    stdout.writeln(
      'stats_chunks=${stats.chunks} stats_documents=${stats.documents} '
      'stats_document_text=${stats.documentText} '
      'stats_clip_shared=${stats.clipShared} '
      'stats_keyword_terms=${stats.keywordTerms}',
    );
    stdout.writeln('index_ms_total=$indexMsTotal');
    if (unexpectedFailure) {
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await runtime?.close();
    store?.close();
  }
}

void _writeReport({
  required String directory,
  required String prefix,
  required IngestionReport? ingest,
  required IndexReport report,
  required int indexMs,
}) {
  stdout.writeln('path=$directory');
  stdout.writeln('key_prefix=$prefix');
  final IngestionReport? loaded = ingest;
  if (loaded != null) {
    stdout.writeln(
      'ingest_total=${loaded.total} ingest_ok=${loaded.succeeded} '
      'ingest_partial=${loaded.partial} ingest_skipped=${loaded.skipped} '
      'ingest_failed=${loaded.failed} ingest_cancelled=${loaded.cancelled} '
      'ingest_ms=${loaded.duration.inMilliseconds}',
    );
  }
  stdout.writeln(
    'documents=${report.documents} written=${report.written} '
    'reused=${report.reused} failed=${report.failed} '
    'cancelled=${report.cancelled} chunks=${report.chunksWritten} '
    'index_ms=$indexMs',
  );
}

void _usage() {
  stderr.writeln(
    'Usage: dart run packages/core_pipeline/bin/index_probe.dart '
    '--db <sqlite> --path <directory> [--prefix <repo-relative>] '
    '[--force] [--clear] [--cancel-after <n>]',
  );
}

String _resolveDirectory(String repoRoot, String input) {
  final String candidate = p.isAbsolute(input)
      ? input
      : p.join(repoRoot, input);
  if (Directory(candidate).existsSync()) {
    return candidate;
  }
  return '';
}

final class _LoggingSource implements IndexSource {
  _LoggingSource(this.inner);

  final IndexSource inner;

  IngestionReport? last;

  @override
  Future<IngestionReport> load(
    String rootPath, {
    CancellationToken? cancel,
  }) async {
    final IngestionReport report = await inner.load(rootPath, cancel: cancel);
    last = report;
    return report;
  }
}
