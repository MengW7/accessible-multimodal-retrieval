import 'dart:convert';
import 'dart:io';

import 'package:desktop/src/app.dart';
import 'package:desktop/src/application/app_controller.dart';
import 'package:desktop/src/application/desktop_service.dart';
import 'package:desktop/src/application/display_settings.dart';
import 'package:desktop/src/application/search_models.dart';
import 'package:desktop/src/runtime/display_settings_store.dart';
import 'package:desktop/src/runtime/file_opener.dart';
import 'package:desktop/src/runtime/library_worker.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Opt in with --dart-define=AMR_E_REAL_RUNTIME=true. This stays inside the
/// flutter_tester process: no desktop window, native picker, viewer or image.
void main() {
  testWidgets(
    'headless UI acceptance with real worker, models, SQLite and settings',
    (tester) async {
      final repo = p.normalize(p.join(Directory.current.path, '../..'));
      final checks = <String, Object?>{};
      final report = <String, Object?>{
        'ok': false,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'desktopInteractions': false,
        'nativeOpenMocked': true,
        'screenReaderTested': false,
        'networkIsolated': false,
        'checks': checks,
      };
      final watch = Stopwatch()..start();
      final scratch = (await tester.runAsync(() async {
        final base = await Directory(p.join(repo, 'tmp'))
            .create(recursive: true);
        return base.createTemp('w05-acceptance-');
      }))!;
      final fixtures = Directory(p.join(scratch.path, 'fixtures'));
      final config = RuntimeConfig.fromEnvironment(
        environment: {
          ...Platform.environment,
          'AMR_DEV_ROOT': repo,
          'AMR_DATA_DIR': p.join(scratch.path, 'index'),
        },
      );
      report['fixtureRoot'] = fixtures.path;
      report['dataDirectory'] = config.dataDirectory;
      final sourceBytes = <String, List<int>>{};
      final launches = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeFileOpener.channel, (
        call,
      ) async {
        expect(call.method, 'openFile');
        launches.add(call.arguments as String);
        return null;
      });
      final semantics = tester.ensureSemantics();
      AppController createController() {
        final worker = WorkerLibraryService(config);
        return AppController(
          LocalDesktopService(config),
          library: worker,
          searchService: worker,
          fileOpener: NativeFileOpener(),
          settingsStore: FileDisplaySettingsStore(config.dataDirectory),
        );
      }

      var app = createController();
      void stage(String value) {
        report['stage'] = value;
        stdout.writeln('E acceptance: $value');
      }

      Future<void> waitFor(bool Function() completed) async {
        final timeout = Stopwatch()..start();
        while (!completed()) {
          if (timeout.elapsed > const Duration(minutes: 3)) {
            fail('Timed out: ${app.accessibilityStatus}');
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          // Real I/O needs wall time; Flutter route/focus animations also need
          // fake clock advancement (notably DialogRoute.completed on clear).
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
      }

      Future<void> activate(Finder finder) async {
        await tester.ensureVisible(finder);
        // The live worker may be driving an indeterminate progress animation.
        // Advance a frame, rather than waiting for the whole app to be idle.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(finder);
        await tester.pump();
      }

      Future<void> navigate(String section) async {
        await activate(find.byKey(ValueKey('nav-$section')));
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> shutdown() async {
        var complete = false;
        final closing = app.shutdown().then((_) => complete = true);
        await waitFor(() => complete);
        await closing;
      }

      Future<void> search({
        FileTypeChoice type = FileTypeChoice.all,
        String path = '',
        String date = '',
      }) async {
        await navigate('search');
        await activate(find.byKey(const Key('file-type-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(type.label).last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('path-filter-field')),
          path,
        );
        await tester.enterText(
          find.byKey(const Key('date-filter-field')),
          date,
        );
        await tester.enterText(find.byKey(const Key('query-field')), '离线检索');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await waitFor(() => app.searchPhase != SearchPhase.loading);
      }

      try {
        stage('prepare dedicated sources');
        await tester.runAsync(() async {
          await Directory(p.join(fixtures.path, 'notes'))
              .create(recursive: true);
          await Directory(p.join(fixtures.path, 'archive')).create();
          await File(p.join(fixtures.path, 'notes/guide.txt'))
              .writeAsString('离线检索操作指南：文件在本机建立索引，可以按目录与日期查找资料。');
          await File(p.join(fixtures.path, 'archive/old.txt'))
              .writeAsString('旧版离线检索记录，与新版操作指南分开存放。');
          await File(p.join(repo, 'datasets/samples/sample.pdf'))
              .copy(p.join(fixtures.path, 'notes/sample.pdf'));
          await File(p.join(repo, 'datasets/samples/sample.png'))
              .copy(p.join(fixtures.path, 'sample.png'));
          await File(p.join(fixtures.path, 'bad.docx'))
              .writeAsString('deliberately invalid DOCX archive');
          await for (final entity in fixtures.list(recursive: true)) {
            if (entity is File) {
              await entity.setLastModified(DateTime(2020));
              sourceBytes[entity.path] = await entity.readAsBytes();
            }
          }
          await File(p.join(fixtures.path, 'notes/guide.txt'))
              .setLastModified(DateTime(2026, 10, 29, 12));
        });
        await tester.pumpWidget(RetrievalApp(controller: app));
        stage('inspect runtime and load library');
        await waitFor(
          () => app.phase != StartupPhase.checking && !app.libraryLoading,
        );
        expect(
          app.phase,
          StartupPhase.ready,
          reason: '${app.runtime?.toJson()}',
        );
        expect(app.libraryError, isNull);
        report['runtime'] = app.runtime!.toJson();
        checks['runtimeAndEmptyLibrary'] = app.librarySnapshot!.stats.documents;

        stage('empty library search');
        await search();
        expect(app.searchPhase, SearchPhase.emptyLibrary);
        expect(find.text('前往文件库'), findsOneWidget);
        checks['emptyLibraryUI'] = true;

        stage('mixed import and navigation');
        await navigate('library');
        await tester.enterText(
          find.byKey(const Key('directory-field')),
          fixtures.path,
        );
        await activate(find.text('建立 / 增量更新索引'));
        expect(app.libraryBusy, isTrue);
        // Traverse real pages while the worker is still processing. This does
        // not measure native UI frame rate or read-screen responsiveness.
        await navigate('settings');
        expect(find.byKey(const Key('font-size-setting')), findsOneWidget);
        await navigate('library');
        await waitFor(() => !app.libraryBusy);
        expect(app.libraryError, isNull);
        expect(app.lastRun!.written, 4);
        expect(app.lastRun!.failed, 1);
        expect(app.librarySnapshot!.stats.documents, 4);
        expect(find.textContaining('bad.docx'), findsWidgets);
        checks['mixedImportAndNavigation'] = app.lastRun!.toJson();

        stage('PDF and image search');
        await search(type: FileTypeChoice.pdf);
        expect(app.searchPhase, SearchPhase.matches);
        expect(app.results, isNotEmpty);
        expect(
          app.results.every(
            (h) => h.fileName.endsWith('.pdf') && h.pageNumber != null,
          ),
          isTrue,
        );
        checks['pdfFilterAndAnchors'] = app.results.length;

        await search(type: FileTypeChoice.images);
        expect(app.results, hasLength(1));
        expect(app.results.single.imageAsset, isNotNull);
        expect(
          find.bySemanticsLabel(RegExp('图片文件：sample.png')),
          findsOneWidget,
        );
        checks['imageMetadata'] = true;

        stage('no matches and invalid date recovery');
        await search(path: 'absent');
        expect(app.searchPhase, SearchPhase.noMatches);
        expect(app.librarySnapshot!.stats.documents, 4);
        checks['noMatchesDistinctFromEmpty'] = true;

        await search(date: '2026-02-30');
        expect(app.searchPhase, SearchPhase.invalid);
        expect(app.searchError, contains('日期不存在'));
        await search(
          type: FileTypeChoice.txt,
          path: 'notes/',
          date: '2026-10-25',
        );
        expect(app.searchPhase, SearchPhase.matches);
        expect(app.results, hasLength(1));
        expect(app.results.single.relativePath, 'notes/guide.txt');
        final sourcePath = app.results.single.documentKey!;
        expect(p.isAbsolute(sourcePath), isTrue);
        checks['invalidDateRecoveryAndCombinedFilter'] = app.submittedSearch!
            .toJson();

        stage('mock open, missing source and recovery');
        final open = find.bySemanticsLabel('打开原文件：guide.txt');
        await activate(open);
        await waitFor(() => app.openingPaths.isEmpty);
        expect(launches, [p.normalize(sourcePath)]);
        expect(
          app.fileOpenOutcomes[sourcePath]!.status,
          FileOpenStatus.requested,
        );
        final moved = '$sourcePath.hidden-for-test';
        await tester.runAsync(() => File(sourcePath).rename(moved));
        try {
          await activate(open);
          await waitFor(() => app.openingPaths.isEmpty);
          expect(
            app.fileOpenOutcomes[sourcePath]!.status,
            FileOpenStatus.missing,
          );
          expect(launches, hasLength(1));
        } finally {
          await tester.runAsync(() => File(moved).rename(sourcePath));
        }
        await activate(open);
        await waitFor(() => app.openingPaths.isEmpty);
        expect(
          app.fileOpenOutcomes[sourcePath]!.status,
          FileOpenStatus.requested,
        );
        expect(launches, hasLength(2));
        checks['sourceOpenMockMissingAndRecovery'] = true;

        stage('save settings and restart controller');
        await navigate('settings');
        await activate(find.byKey(const Key('font-size-setting')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('150%').last);
        await tester.pump();
        await waitFor(() => !app.settingsSaving);
        expect(app.displaySettings.fontSize, FontSizeMode.percent150);
        await shutdown();
        await tester.pumpWidget(const SizedBox.shrink());
        app = createController();
        await tester.pumpWidget(RetrievalApp(controller: app));
        await waitFor(
          () =>
              app.phase != StartupPhase.checking &&
              !app.libraryLoading &&
              !app.settingsLoading,
        );
        expect(app.phase, StartupPhase.ready);
        expect(app.displaySettings.fontSize, FontSizeMode.percent150);
        expect(app.librarySnapshot!.stats.documents, 4);
        expect(app.librarySnapshot!.roots, hasLength(1));
        checks['controllerRestartWithRealStores'] = true;

        stage('incremental reuse and clear confirmation');
        await activate(find.text('增量重建此目录'));
        await waitFor(() => !app.libraryBusy);
        expect(app.lastRun!.written, 0);
        expect(app.lastRun!.reused, 4);
        expect(app.lastRun!.failed, 1);
        checks['incrementalReuseAfterRestart'] = app.lastRun!.toJson();
        await activate(find.text('清除全部索引'));
        await tester.pumpAndSettle();
        await activate(find.text('保留索引'));
        await tester.pumpAndSettle();
        expect(app.librarySnapshot!.stats.documents, 4);
        await activate(find.text('清除全部索引'));
        await tester.pumpAndSettle();
        await activate(find.text('确认清除索引'));
        await waitFor(
          () => !app.libraryBusy && app.librarySnapshot!.stats.documents == 0,
        );
        expect(app.librarySnapshot!.roots, isEmpty);
        await tester.runAsync(() async {
          for (final source in sourceBytes.entries) {
            expect(await File(source.key).readAsBytes(), source.value);
          }
          final settings = await FileDisplaySettingsStore(config.dataDirectory)
              .load();
          expect(settings.fontSize, FontSizeMode.percent150);
        });
        checks['clearConfirmationPreservesSourcesAndSettings'] = true;
        expect(tester.takeException(), isNull);
        report['ok'] = true;
      } catch (error, stack) {
        stdout.writeln('E acceptance failed at ${report['stage']}: $error');
        report['error'] = error.toString();
        report['stack'] = stack.toString();
        rethrow;
      } finally {
        try {
          await shutdown();
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
          messenger.setMockMethodCallHandler(NativeFileOpener.channel, null);
          report['elapsedMs'] = watch.elapsedMilliseconds;
          report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
          await tester.runAsync(
            () => File(
              p.join(repo, 'reports/week5/logs/E_headless_acceptance.json'),
            ).writeAsString(const JsonEncoder.withIndent('  ').convert(report)),
          );
        }
      }
    },
    skip: !const bool.fromEnvironment('AMR_E_REAL_RUNTIME'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
