import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../application/library_models.dart';
import 'library_worker.dart';
import 'runtime_config.dart';

/// Explicit integration verification through the exact worker used by the UI.
/// The caller supplies a fresh index and dedicated disposable fixture folder.
Future<Map<String, Object?>> verifyLibrary(
  RuntimeConfig config,
  String fixtures,
) async {
  var worker = WorkerLibraryService(config);
  final events = <Map<String, Object?>>[];
  final output = <String, Object?>{
    'ok': false,
    'databasePath': config.databasePath,
  };
  final watch = Stopwatch()..start();
  int heartbeats = 0;
  final heartbeat = Timer.periodic(
    const Duration(milliseconds: 20),
    (_) => heartbeats++,
  );
  StreamSubscription<LibraryProgress>? subscription;
  bool cancelOnWrite = false;
  void listen() {
    subscription = worker.progress.listen((progress) {
      events.add({
        'stage': progress.stage.name,
        'processed': progress.processed,
        'total': progress.total,
        'files': progress.files.map((f) => f.toJson()).toList(),
      });
      if (cancelOnWrite &&
          progress.files.any((f) => f.status == LibraryFileStatus.indexed)) {
        cancelOnWrite = false;
        worker.cancel();
      }
    });
  }

  void require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    require(p.isAbsolute(fixtures), 'Fixtures must be absolute.');
    final initial = await worker.load();
    require(
      initial.stats.chunks == 0 && initial.roots.isEmpty,
      'Library smoke requires a fresh empty application data directory.',
    );
    final good = File(p.join(fixtures, 'good.txt'));
    final bad = File(p.join(fixtures, 'bad.docx'));
    require(
      await good.exists() && await bad.exists(),
      'Dedicated good.txt and bad.docx are required.',
    );
    final badBefore = await bad.readAsString();
    listen();
    final first = await worker.index(fixtures);
    require(
      first.run.written == 1 && first.run.failed == 1,
      'Expected one good and one bad file.',
    );
    require(
      first.run.files.any(
        (f) => f.path == bad.path && f.status == LibraryFileStatus.failed,
      ),
      'Bad file must retain its own failure record.',
    );
    output['initial'] = {
      'run': first.run.toJson(),
      'snapshot': first.snapshot.toJson(),
    };

    final repeated = await worker.index(fixtures);
    require(
      repeated.run.written == 0 &&
          repeated.run.reused == 1 &&
          repeated.snapshot.stats == first.snapshot.stats,
      'Unchanged incremental run duplicated data.',
    );
    require(
      repeated.snapshot.roots.length == 1,
      'The same root must not be added twice.',
    );
    output['incremental'] = {
      'written': repeated.run.written,
      'reused': repeated.run.reused,
      'documents': repeated.snapshot.stats.documents,
      'chunks': repeated.snapshot.stats.chunks,
    };

    await good.writeAsString('离线检索已更新。本地资料在设备上建立索引，修改后应替换旧版本。');
    final modified = await worker.index(fixtures);
    require(
      modified.run.written == 1 && modified.snapshot.stats.documents == 1,
      'Changed content must replace the previous document version.',
    );
    output['modified'] = {
      'written': modified.run.written,
      'documents': modified.snapshot.stats.documents,
    };

    await subscription!.cancel();
    await worker.close();
    worker = WorkerLibraryService(config);
    final reopened = await worker.load();
    require(
      reopened.roots.length == 1 && reopened.stats == modified.snapshot.stats,
      'Roots and index statistics must survive restart.',
    );
    output['restart'] = reopened.toJson();
    listen();

    // Test immediate cancellation while the worker is initializing a new job.
    final immediateFuture = worker.index(fixtures);
    worker.cancel();
    final immediate = await immediateFuture;
    require(
      immediate.run.cancelled && immediate.run.written == 0,
      'An early cancellation request must not be lost.',
    );
    output['immediateCancellation'] = immediate.run.toJson();

    final cancellationRoot = Directory(
      p.join(p.dirname(fixtures), 'cancellation-files'),
    );
    await cancellationRoot.create();
    for (var i = 0; i < 20; i++) {
      await File(p.join(cancellationRoot.path, 'file-$i.txt'))
          .writeAsString('取消验证文档 $i。离线资料编号 $i。${'本地检索保留已提交的数据。' * 16}');
    }
    cancelOnWrite = true;
    final cancelled = await worker.index(cancellationRoot.path);
    require(
      cancelled.run.cancelled &&
          cancelled.run.written > 0 &&
          cancelled.run.written < 20,
      'Cancellation must preserve some committed files and leave others pending.',
    );
    require(
      cancelled.snapshot.stats.documents == 1 + cancelled.run.written,
      'Previously committed files disappeared after cancellation.',
    );
    output['cancellation'] = {
      'run': cancelled.run.toJson(),
      'documentsRetained': cancelled.snapshot.stats.documents,
    };
    final resumed = await worker.index(cancellationRoot.path);
    require(
      !resumed.run.cancelled &&
          resumed.run.failed == 0 &&
          resumed.run.reused == cancelled.run.written &&
          resumed.snapshot.stats.documents == 21,
      'Incremental resume must reuse committed files and finish the remainder.',
    );
    output['resume'] = {
      'written': resumed.run.written,
      'reused': resumed.run.reused,
      'documents': resumed.snapshot.stats.documents,
    };

    final missing = await worker.index(
      p.join(p.dirname(fixtures), 'absent-directory'),
    );
    require(
      missing.run.failed == 1 && missing.snapshot.stats.documents == 21,
      'Invalid root must report failure without clearing existing data.',
    );
    output['missingDirectory'] = missing.run.toJson();

    final sources = [
      good,
      bad,
      ...await cancellationRoot
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList(),
    ];
    final contents = <String, String>{
      for (final file in sources) file.path: await file.readAsString(),
    };
    final cleared = await worker.clear();
    require(
      cleared.stats.chunks == 0 &&
          cleared.stats.documents == 0 &&
          cleared.roots.isEmpty,
      'Clear must reset all application index data and folder records.',
    );
    for (final file in sources) {
      require(
        await file.readAsString() == contents[file.path],
        'Source file changed during clear.',
      );
    }
    require(
      await bad.readAsString() == badBefore,
      'Bad source file was modified.',
    );
    require(
      heartbeats > 10,
      'Main-isolate heartbeat did not run during indexing.',
    );
    output.addAll({
      'ok': true,
      'clear': cleared.toJson(),
      'sourceFilesPreserved': sources.length,
      'mainIsolateHeartbeats': heartbeats,
    });
  } catch (error, stack) {
    output['error'] = error.toString();
    output['stack'] = stack.toString();
  } finally {
    heartbeat.cancel();
    await subscription?.cancel();
    await worker.close();
    output['elapsedMs'] = watch.elapsedMilliseconds;
    output['progressEvents'] = events;
  }
  return output;
}
