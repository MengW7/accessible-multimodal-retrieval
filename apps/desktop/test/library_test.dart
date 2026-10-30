import 'dart:async';
import 'dart:io';

import 'package:core_storage/core_storage.dart';
import 'package:desktop/src/app.dart';
import 'package:desktop/src/application/app_controller.dart';
import 'package:desktop/src/application/library_models.dart';
import 'package:desktop/src/application/library_service.dart';
import 'package:desktop/src/runtime/directory_picker.dart';
import 'package:desktop/src/runtime/library_worker.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'widget_test.dart' show StubService;

const empty = LibrarySnapshot(
  roots: [],
  stats: IndexStats(
    documents: 0,
    chunks: 0,
    documentText: 0,
    clipShared: 0,
    keywordTerms: 0,
  ),
);

class FakeLibrary implements LibraryService {
  Future<LibrarySnapshot>? loading;
  final updates = StreamController<LibraryProgress>.broadcast(sync: true);
  final pending = Completer<LibraryResult>();
  int indexes = 0;
  int clears = 0;
  int cancellations = 0;
  bool closed = false;
  @override
  Stream<LibraryProgress> get progress => updates.stream;
  @override
  Future<LibrarySnapshot> load() => loading ?? Future.value(empty);
  @override
  Future<LibraryResult> index(String path, {bool force = false}) {
    indexes++;
    return pending.future;
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<LibrarySnapshot> clear() async {
    clears++;
    return empty;
  }

  @override
  Future<void> close() async {
    closed = true;
    await updates.close();
  }
}

class FakePicker implements DirectoryPicker {
  String? selected;
  @override
  Future<String?> choose() async => selected;
}

void main() {
  testWidgets(
    'directory selection is retained and picker cancellation changes nothing',
    (tester) async {
      final picker = FakePicker()..selected = r'C:\资料';
      final app = AppController(
        StubService(),
        library: FakeLibrary(),
        directoryPicker: picker,
      );
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择目录'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('directory-field')))
            .controller!
            .text,
        r'C:\资料',
      );
      picker.selected = null;
      await tester.tap(find.text('选择目录'));
      await tester.pumpAndSettle();
      expect(app.directoryDraft, r'C:\资料');
    },
  );

  testWidgets(
    'busy indexing blocks duplicate submission and shows per-file failure and cancel',
    (tester) async {
      final library = FakeLibrary();
      final app = AppController(StubService(), library: library);
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('directory-field')),
        r'C:\data',
      );
      await tester.tap(find.text('建立 / 增量更新索引'));
      await tester.pump();
      await app.indexDirectory();
      expect(library.indexes, 1);
      library.updates.add(
        const LibraryProgress(
          stage: LibraryStage.indexing,
          processed: 1,
          total: 2,
          files: [
            LibraryFile(path: 'good.txt', status: LibraryFileStatus.indexed),
            LibraryFile(
              path: 'bad.pdf',
              status: LibraryFileStatus.failed,
              detail: '文件已损坏',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(find.textContaining('bad.pdf'), findsOneWidget);
      await tester.ensureVisible(find.text('取消索引任务'));
      await tester.pump();
      await tester.tap(find.text('取消索引任务'));
      await tester.pump();
      expect(library.cancellations, 1);
      expect(find.textContaining('正在取消'), findsOneWidget);
      final run = LibraryRun(
        root: r'C:\data',
        finishedAt: DateTime(2026),
        written: 1,
        reused: 0,
        cancelled: true,
        files: app.currentFiles.values.toList(),
      );
      library.pending.complete(LibraryResult(run: run, snapshot: empty));
      await tester.pumpAndSettle();
      expect(find.textContaining('已取消：新写入 1'), findsOneWidget);
      expect(app.canIndex, isTrue);
    },
  );

  testWidgets(
    'clear requires confirmation and states that source files remain',
    (tester) async {
      final library = FakeLibrary();
      await tester.pumpWidget(
        RetrievalApp(
          controller: AppController(StubService(), library: library),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除全部索引'));
      await tester.pumpAndSettle();
      expect(find.textContaining('所有源文件保留，不会删除'), findsOneWidget);
      expect(library.clears, 0);
      await tester.tap(find.text('保留索引'));
      await tester.pumpAndSettle();
      expect(library.clears, 0);
      await tester.tap(find.text('清除全部索引'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认清除索引'));
      await tester.pumpAndSettle();
      expect(library.clears, 1);
      expect(find.text('索引及目录记录已清除，源文件保留。'), findsOneWidget);
    },
  );

  testWidgets(
    'permission error remains readable and indexing unlocks for retry',
    (tester) async {
      final library = FakeLibrary();
      final app = AppController(StubService(), library: library);
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      app.updateDirectory(r'C:\unreadable');
      unawaited(app.indexDirectory());
      await tester.pump();
      final run = LibraryRun(
        root: r'C:\unreadable',
        finishedAt: DateTime(2026),
        written: 0,
        reused: 0,
        cancelled: false,
        files: const [
          LibraryFile(
            path: 'restricted',
            status: LibraryFileStatus.failed,
            detail: 'Permission denied.',
          ),
        ],
      );
      library.pending.complete(LibraryResult(run: run, snapshot: empty));
      await tester.pumpAndSettle();
      expect(find.text('Permission denied.'), findsOneWidget);
      expect(find.textContaining('失败：新写入 0'), findsOneWidget);
      expect(app.canIndex, isTrue);
    },
  );

  test(
    'native folder channel accepts Unicode paths, cancel and errors',
    () async {
      const picker = NativeDirectoryPicker();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativeDirectoryPicker.channel,
          null,
        ),
      );
      messenger.setMockMethodCallHandler(NativeDirectoryPicker.channel, (
        call,
      ) async {
        expect(call.method, 'chooseDirectory');
        return r'C:\中文目录';
      });
      expect(await picker.choose(), r'C:\中文目录');
      messenger.setMockMethodCallHandler(
        NativeDirectoryPicker.channel,
        (_) async => null,
      );
      expect(await picker.choose(), isNull);
      messenger.setMockMethodCallHandler(
        NativeDirectoryPicker.channel,
        (_) async => throw PlatformException(
          code: 'directory_picker_failed',
          message: 'Unavailable',
        ),
      );
      await expectLater(picker.choose(), throwsA(isA<PlatformException>()));
    },
  );

  test(
    'worker reads and clears its isolated index without loading any model',
    () async {
      final temp = await Directory.systemTemp.createTemp('amr-library-worker-');
      final source = File(p.join(temp.path, 'source.txt'));
      await source.writeAsString('must survive index clear');
      final config = RuntimeConfig(
        resourceRoot: temp.path,
        dataDirectory: p.join(temp.path, 'index'),
        development: false,
        javaExecutable: 'java',
      );
      final worker = WorkerLibraryService(config);
      try {
        expect((await worker.load()).stats.documents, 0);
        await File(p.join(config.dataDirectory, 'library-roots.json'))
            .writeAsString('invalid');
        await expectLater(worker.load(), throwsA(isA<StateError>()));
        final cleared = await worker.clear();
        expect(cleared.roots, isEmpty);
        expect(cleared.stats.chunks, 0);
        expect(await source.readAsString(), 'must survive index clear');
      } finally {
        await worker.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'disposing while library load is pending does not notify after disposal',
    () async {
      final loaded = Completer<LibrarySnapshot>();
      final library = FakeLibrary()..loading = loaded.future;
      final app = AppController(StubService(), library: library);
      final startup = app.initialize();
      await Future<void>.delayed(Duration.zero);
      app.dispose();
      loaded.complete(empty);
      await startup;
      expect(library.closed, isTrue);
    },
  );

  test('shutdown closes the library and prevents new submissions', () async {
    final library = FakeLibrary();
    final app = AppController(StubService(), library: library);
    await app.initialize();
    await app.shutdown();
    expect(app.shuttingDown, isTrue);
    expect(app.canIndex, isFalse);
    expect(app.canClear, isFalse);
    expect(library.closed, isTrue);
    await app.indexDirectory(r'C:\data');
    expect(library.indexes, 0);
    app.dispose();
  });

  test(
    'cancel before worker startup is not lost and needs no models',
    () async {
      final temp = await Directory.systemTemp.createTemp('amr-early-cancel-');
      final worker = WorkerLibraryService(
        RuntimeConfig(
          resourceRoot: temp.path,
          dataDirectory: p.join(temp.path, 'index'),
          development: false,
          javaExecutable: 'java',
        ),
      );
      try {
        final pending = worker.index(p.join(temp.path, 'fixtures'));
        worker.cancel();
        final result = await pending;
        expect(result.run.cancelled, isTrue);
        expect(result.snapshot.stats.chunks, 0);
      } finally {
        await worker.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
