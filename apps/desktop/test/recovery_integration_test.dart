import 'dart:io';

import 'package:core_storage/core_storage.dart';
import 'package:desktop/src/application/library_models.dart';
import 'package:desktop/src/application/search_models.dart';
import 'package:desktop/src/runtime/library_worker.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const runtime = String.fromEnvironment('AMR_E_RUNTIME_ROOT');
  late Directory scratch;
  late RuntimeConfig config;
  late WorkerLibraryService worker;
  late Directory fixtures;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('amr-recovery-');
    addTearDown(() => scratch.delete(recursive: true));
    config = RuntimeConfig.fromEnvironment(
      environment: {
        ...Platform.environment,
        'AMR_DEV_ROOT': '',
        'AMR_RUNTIME_ROOT': runtime,
        'AMR_DATA_DIR': p.join(scratch.path, 'data'),
      },
    );
    fixtures = await Directory(p.join(scratch.path, 'fixtures')).create();
    worker = WorkerLibraryService(config);
    addTearDown(worker.close);
  });

  Future<File> writeText(String name, String text) =>
      File(p.join(fixtures.path, name)).writeAsString(text);

  Future<void> makeBatch() async {
    for (var i = 0; i < 24; i++) {
      await writeText('note-$i.txt', '样本 $i，${'离线检索保留已提交的内容。' * 24}');
    }
  }

  group('real Windows production recovery', () {
    test('a second worker cannot clear or index during a write', () async {
      await makeBatch();
      final other = WorkerLibraryService(config);
      addTearDown(other.close);
      await other.load();
      final preparing = worker.progress.firstWhere(
        (p) => p.stage == LibraryStage.preparing,
      );
      final job = worker.index(fixtures.path);
      try {
        await preparing.timeout(const Duration(seconds: 15));
        final busy = throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('另一个实例'),
          ),
        );
        await expectLater(other.clear(), busy);
        await expectLater(other.index(fixtures.path), busy);
      } finally {
        await job;
      }
      final repeat = await other.index(fixtures.path);
      expect(repeat.run.reused, 24);
      expect(repeat.snapshot.stats.documents, 24);
      expect(repeat.snapshot.roots, hasLength(1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a locked SQLite index preserves old text and is retryable', () async {
      final file = await writeText('guide.txt', '离线检索原始记录。');
      await worker.index(fixtures.path);
      final connection = const SystemSqliteLibraryLocator()
          .open(config.databasePath)
          .database!;
      await file.writeAsString('离线检索修订记录。');
      try {
        connection.execute('BEGIN IMMEDIATE');
        final blocked = await worker.index(fixtures.path);
        expect(blocked.run.failed, 1);
        expect(blocked.run.files.single.detail, contains('locked'));
        final old = await worker.search(SearchRequest(query: '离线检索'));
        expect(old.hits.single.snippet, contains('原始'));
      } finally {
        connection.dispose();
      }
      final resumed = await worker.index(fixtures.path);
      expect(resumed.run.written, 1);
      expect(resumed.snapshot.stats.documents, 1);
      final updated = await worker.search(SearchRequest(query: '离线检索'));
      expect(updated.hits.single.snippet, contains('修订'));
    });

    test(
      'an unusable database path and a corrupt DOCX can be repaired',
      () async {
        final invalid = await Directory(config.databasePath)
            .create(recursive: true);
        final error = isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('无法打开索引'),
        );
        await expectLater(worker.load(), throwsA(error));
        await invalid.rename(p.join(scratch.path, 'removed-obstacle'));
        await writeText('guide.txt', '离线检索校验记录。');
        final broken = await writeText('broken.docx', 'not a ZIP archive');
        final initial = await worker.index(fixtures.path);
        expect(initial.run.failed, 1);
        expect(initial.run.written, 1);
        await File('../../datasets/samples/sample.docx').copy(broken.path);
        final repaired = await worker.index(fixtures.path);
        expect(repaired.run.failed, 0);
        expect(repaired.run.reused, 1);
        expect(repaired.run.written, 1);
        expect(repaired.snapshot.stats.documents, 2);
      },
    );

    test(
      'close while indexing keeps completed files and releases the writer',
      () async {
        await makeBatch();
        final firstCommit = worker.progress.firstWhere(
          (p) => p.files.any((f) => f.status == LibraryFileStatus.indexed),
        );
        final job = worker.index(fixtures.path);
        await firstCommit.timeout(const Duration(seconds: 45));
        final closing = worker.close();
        final stopped = await job.timeout(const Duration(seconds: 30));
        await closing.timeout(const Duration(seconds: 30));
        expect(stopped.run.cancelled, isTrue);
        expect(stopped.run.written, inInclusiveRange(1, 23));
        final reopened = WorkerLibraryService(config);
        addTearDown(reopened.close);
        final resumed = await reopened.index(fixtures.path);
        expect(resumed.run.reused, stopped.run.written);
        expect(resumed.snapshot.stats.documents, 24);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: runtime.isEmpty || !Platform.isWindows);
}
