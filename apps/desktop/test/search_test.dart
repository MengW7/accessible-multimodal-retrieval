import 'dart:async';
import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:core_storage/core_storage.dart';
import 'package:desktop/src/app.dart';
import 'package:desktop/src/application/app_controller.dart';
import 'package:desktop/src/application/search_models.dart';
import 'package:desktop/src/runtime/file_opener.dart';
import 'package:desktop/src/runtime/library_worker.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'library_test.dart' show FakeLibrary;
import 'widget_test.dart' show StubService;

SearchResult hit(String name, {bool image = false}) => SearchResult(
  documentId: name,
  chunkId: name,
  relativePath: 'notes/$name',
  fileName: name,
  documentKey: p.join(Directory.systemTemp.path, name),
  mimeType: image ? 'image/png' : 'application/pdf',
  startOffset: image ? 0 : 10,
  endOffset: image ? 0 : 14,
  textUnit: TextUnit.utf16CodeUnit,
  snippet: image ? '' : '相邻上下文，命中的文字及后续上下文。',
  score: 0.01,
  channels: {image ? SearchChannel.clipShared : SearchChannel.documentText},
  modality: image ? Modality.image : Modality.text,
  pageNumber: image ? null : 2,
  imageAsset: image
      ? const ImageAsset(format: 'png', width: 640, height: 480)
      : null,
);

class FakeSearch implements SearchService {
  final requests = <SearchRequest>[];
  final pending = <Completer<SearchPage>>[];
  int cancellations = 0;
  @override
  Future<SearchPage> search(SearchRequest request) {
    requests.add(request);
    final result = Completer<SearchPage>();
    pending.add(result);
    return result.future;
  }

  @override
  void cancelSearch() {
    cancellations++;
  }

  void complete(int index, List<SearchResult> hits, {int documents = 1}) =>
      pending[index].complete(
        SearchPage(
          request: requests[index],
          hits: hits,
          indexedDocuments: documents,
        ),
      );
}

class FakeOpener implements FileOpener {
  Completer<FileOpenOutcome>? pending;
  String? path;
  FileOpenOutcome next = const FileOpenOutcome(
    FileOpenStatus.requested,
    '已请求系统打开',
  );
  @override
  Future<FileOpenOutcome> open(String? absolutePath) async {
    path = absolutePath;
    return pending == null ? next : await pending!.future;
  }
}

void main() {
  test(
    'late source-open feedback does not reappear after a new query',
    () async {
      final search = FakeSearch();
      final opener = FakeOpener()..pending = Completer<FileOpenOutcome>();
      final app = AppController(
        StubService(),
        searchService: search,
        fileOpener: opener,
      );
      await app.initialize();
      app.updateQuery('first');
      final first = app.submitSearch();
      final old = hit('old.pdf');
      search.complete(0, [old]);
      await first;
      final opening = app.openResult(old);
      app.updateQuery('latest');
      final latest = app.submitSearch();
      search.complete(1, [hit('latest.pdf')]);
      await latest;
      opener.pending!.complete(
        const FileOpenOutcome(FileOpenStatus.failed, 'old error'),
      );
      await opening;
      expect(app.fileOpenOutcomes, isEmpty);
      expect(app.openingPaths, isEmpty);
      expect(app.results.single.fileName, 'latest.pdf');
      app.dispose();
    },
  );
  test('clearing a populated library invalidates results and submitted-query state', () async {
    final search = FakeSearch();
    final library = FakeLibrary();
    final app = AppController(
      StubService(),
      library: library,
      searchService: search,
    );
    await app.initialize();
    app.updateQuery('q');
    final query = app.submitSearch();
    search.complete(0, [hit('old.pdf')]);
    await query;
    await app.clearLibrary();
    expect(app.results, isEmpty);
    expect(app.submittedSearch, isNull);
    expect(app.searchPhase, SearchPhase.idle);
    app.dispose();
  });
  test('draft normalizes relative directories, file types and local dates', () {
    final request = SearchRequest.fromDraft(
      query: '  离线  ',
      type: FileTypeChoice.images,
      path: r'.\notes\',
      modifiedAfter: '2026-10-30',
    );
    expect(request.query, '离线');
    expect(request.filters.extensions, {'.jpg', '.jpeg', '.png'});
    expect(request.filters.pathPrefix, 'notes');
    expect(request.filters.modifiedAfter, DateTime(2026, 10, 30));
    expect(
      () => request.filters.extensions!.add('.pdf'),
      throwsUnsupportedError,
    );
  });
  test(
    'invalid dates, empty queries and absolute path filters are rejected',
    () {
      for (final value in ['2026-02-30', '2026-13-01', '2026/10/30']) {
        expect(
          () => SearchRequest.fromDraft(query: 'q', modifiedAfter: value),
          throwsFormatException,
        );
      }
      expect(() => SearchRequest(query: ' '), throwsFormatException);
      expect(
        () => SearchRequest.fromDraft(query: 'q', path: r'C:\notes'),
        throwsFormatException,
      );
      expect(
        () => SearchRequest.fromDraft(query: 'q', path: '../notes'),
        throwsFormatException,
      );
    },
  );
  test(
    'latest result wins even if older success and failure complete later',
    () async {
      final search = FakeSearch();
      final app = AppController(StubService(), searchService: search);
      await app.initialize();
      app.updateQuery('first');
      final first = app.submitSearch();
      app.updateQuery('second');
      final second = app.submitSearch();
      app.updateQuery('latest');
      final latest = app.submitSearch();
      search.complete(2, [hit('latest.pdf')]);
      await latest;
      search.complete(0, [hit('old.pdf')]);
      await first;
      search.pending[1].completeError(StateError('old failure'));
      await second;
      expect(app.results.single.fileName, 'latest.pdf');
      expect(app.submittedSearch!.query, 'latest');
      expect(app.searchPhase, SearchPhase.matches);
      app.dispose();
    },
  );
  test('invalid submission supersedes the pending query without calling service again', () async {
    final search = FakeSearch();
    final app = AppController(StubService(), searchService: search);
    await app.initialize();
    app.updateQuery('old');
    final pending = app.submitSearch();
    app.updateQuery(' ');
    await app.submitSearch();
    search.complete(0, [hit('old.pdf')]);
    await pending;
    expect(search.requests, hasLength(1));
    expect(app.results, isEmpty);
    expect(app.searchPhase, SearchPhase.invalid);
    app.dispose();
  });
  test(
    'empty library, actual no hits, errors and retry are separate states',
    () async {
      final search = FakeSearch();
      final app = AppController(StubService(), searchService: search);
      await app.initialize();
      app.updateQuery('q');
      var job = app.submitSearch();
      search.complete(0, [], documents: 0);
      await job;
      expect(app.searchPhase, SearchPhase.emptyLibrary);
      job = app.submitSearch();
      search.complete(1, []);
      await job;
      expect(app.searchPhase, SearchPhase.noMatches);
      job = app.submitSearch();
      search.pending[2].completeError(StateError('model missing'));
      await job;
      expect(app.searchPhase, SearchPhase.failed);
      job = app.submitSearch();
      search.complete(3, [hit('recovered.pdf')]);
      await job;
      expect(app.searchPhase, SearchPhase.matches);
      app.dispose();
    },
  );
  test(
    'cancelled query cannot publish late results or overlap an index mutation',
    () async {
      final search = FakeSearch();
      final library = FakeLibrary();
      final app = AppController(
        StubService(),
        library: library,
        searchService: search,
      );
      await app.initialize();
      app.updateQuery('q');
      final job = app.submitSearch();
      app.cancelCurrentSearch();
      expect(app.canIndex, isFalse);
      search.complete(0, [hit('late.pdf')]);
      await job;
      expect(app.results, isEmpty);
      expect(app.canClear, isTrue);
      await app.clearLibrary();
      expect(app.submittedSearch, isNull);
      expect(app.searchPhase, SearchPhase.idle);
      app.dispose();
    },
  );
  test('source-open feedback uses the exact indexed path and stale callbacks are ignored', () async {
    final search = FakeSearch();
    final opener = FakeOpener();
    final app = AppController(
      StubService(),
      searchService: search,
      fileOpener: opener,
    );
    await app.initialize();
    app.updateQuery('q');
    final pending = app.submitSearch();
    final result = hit('源文件.pdf');
    search.complete(0, [result]);
    await pending;
    opener.next = const FileOpenOutcome(FileOpenStatus.missing, '源文件不存在');
    await app.openResult(result);
    expect(opener.path, result.documentKey);
    expect(
      app.fileOpenOutcomes[result.documentKey]!.status,
      FileOpenStatus.missing,
    );
    app.updateQuery('new');
    final next = app.submitSearch();
    opener.path = null;
    await app.openResult(result);
    expect(opener.path, isNull);
    search.complete(1, []);
    await next;
    app.dispose();
  });

  testWidgets(
    'Enter submits text and filters; results preserve source anchors and image metadata',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final search = FakeSearch();
      final opener = FakeOpener();
      final app = AppController(
        StubService(),
        searchService: search,
        fileOpener: opener,
      );
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('query-field')), '离线检索');
      await tester.enterText(
        find.byKey(const Key('path-filter-field')),
        'notes/',
      );
      await tester.enterText(
        find.byKey(const Key('date-filter-field')),
        '2026-10-30',
      );
      await tester.showKeyboard(find.byKey(const Key('query-field')));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(search.requests.single.filters.pathPrefix, 'notes');
      expect(
        search.requests.single.filters.modifiedAfter,
        DateTime(2026, 10, 30),
      );
      search.complete(0, [hit('text.pdf'), hit('image.png', image: true)]);
      await tester.pumpAndSettle();
      expect(find.textContaining('出处：第 2 页'), findsOneWidget);
      expect(find.textContaining('10–14（UTF-16'), findsOneWidget);
      expect(find.textContaining('640 × 480'), findsOneWidget);
      expect(find.text('此结果无物理页码。'), findsOneWidget);
      expect(find.textContaining('来源路径：'), findsNWidgets(2));
      await tester.tap(find.text('打开原文件').first);
      await tester.pumpAndSettle();
      expect(opener.path, hit('text.pdf').documentKey);
      expect(find.text('已请求系统打开'), findsOneWidget);
    },
  );
  testWidgets('clear filters resets the visible fields and type choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(StubService(), searchService: FakeSearch());
    await tester.pumpWidget(RetrievalApp(controller: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('path-filter-field')), 'notes');
    await tester.enterText(
      find.byKey(const Key('date-filter-field')),
      '2026-10-30',
    );
    app.updateFileType(FileTypeChoice.pdf);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(app.fileType, FileTypeChoice.all);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('path-filter-field')))
          .controller!
          .text,
      '',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('date-filter-field')))
          .controller!
          .text,
      '',
    );
  });

  test('file opener distinguishes missing paths from a system launch failure without launching apps', () async {
    final temp = await Directory.systemTemp.createTemp('amr-open-test-');
    try {
      String? launched;
      final opener = NativeFileOpener(
        launcher: (path) async {
          launched = path;
        },
      );
      final file = File(p.join(temp.path, '中文 & spaces.txt'));
      await file.writeAsString('fixture');
      expect((await opener.open(file.path)).status, FileOpenStatus.requested);
      expect(launched, file.path);
      expect(
        (await opener.open(file.path.replaceAll('\\', '/'))).status,
        FileOpenStatus.requested,
      );
      expect(launched, p.normalize(file.path));
      expect(
        (await opener.open(p.join(temp.path, 'absent.txt'))).status,
        FileOpenStatus.missing,
      );
      expect((await opener.open(temp.path)).status, FileOpenStatus.missing);
      expect(
        (await opener.open('relative.txt')).status,
        FileOpenStatus.invalidPath,
      );
      final failing = NativeFileOpener(
        launcher: (_) async => throw StateError('no viewer'),
      );
      expect((await failing.open(file.path)).status, FileOpenStatus.failed);
    } finally {
      await temp.delete(recursive: true);
    }
  });
  test('Windows opener sends a path as a structured channel argument and handles native errors', () async {
    final temp = await Directory.systemTemp.createTemp('amr-open-channel-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    try {
      final file = File(p.join(temp.path, 'test.txt'));
      await file.writeAsString('fixture');
      messenger.setMockMethodCallHandler(NativeFileOpener.channel, (
        call,
      ) async {
        expect(call.method, 'openFile');
        expect(call.arguments, file.path);
        return null;
      });
      final opener = NativeFileOpener();
      expect((await opener.open(file.path)).status, FileOpenStatus.requested);
      messenger.setMockMethodCallHandler(
        NativeFileOpener.channel,
        (_) async => throw PlatformException(code: 'source_missing'),
      );
      expect((await opener.open(file.path)).status, FileOpenStatus.missing);
      messenger.setMockMethodCallHandler(
        NativeFileOpener.channel,
        (_) async => throw PlatformException(
          code: 'open_failed',
          message: 'no association',
        ),
      );
      expect((await opener.open(file.path)).status, FileOpenStatus.failed);
    } finally {
      messenger.setMockMethodCallHandler(NativeFileOpener.channel, null);
      await temp.delete(recursive: true);
    }
  });
  test(
    'an empty worker index returns an empty-library response without any model',
    () async {
      final temp = await Directory.systemTemp.createTemp('amr-empty-search-');
      final worker = WorkerLibraryService(
        RuntimeConfig(
          resourceRoot: temp.path,
          dataDirectory: p.join(temp.path, 'index'),
          development: false,
          javaExecutable: 'java',
        ),
      );
      try {
        final page = await worker.search(SearchRequest(query: 'q'));
        expect(page.indexedDocuments, 0);
        expect(page.hits, isEmpty);
      } finally {
        await worker.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
