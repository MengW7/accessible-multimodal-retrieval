import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:desktop/src/application/search_models.dart';
import 'package:desktop/src/runtime/library_worker.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:desktop/src/runtime/runtime_session.dart';
import 'package:path/path.dart' as p;

/// Headless only: never starts Flutter, an OS picker, a viewer or screenshots.
Future<void> main() async {
  final repo = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '../../..'),
  );
  final base = await Directory(p.join(repo, 'tmp')).create(recursive: true);
  final scratch = await base.createTemp('w05-search-');
  final fixtures = Directory(p.join(scratch.path, 'fixtures'));
  await fixtures.create();
  final config = RuntimeConfig.fromEnvironment(
    environment: {
      ...Platform.environment,
      'AMR_DEV_ROOT': repo,
      'AMR_DATA_DIR': p.join(scratch.path, 'index'),
    },
  );
  final output = <String, Object?>{
    'ok': false,
    'databasePath': config.databasePath,
    'fixtureRoot': fixtures.path,
    'osInteractions': false,
  };
  final watch = Stopwatch()..start();
  var worker = WorkerLibraryService(config);
  RuntimeSession? core;
  void require(bool value, String reason) {
    if (!value) throw StateError(reason);
  }

  List<Map<String, Object?>> describe(List<SearchResult> hits) => [
    for (final h in hits)
      {
        'fileName': h.fileName,
        'sourcePath': h.documentKey,
        'relativePath': h.relativePath,
        'pageNumber': h.pageNumber,
        'startOffset': h.startOffset,
        'endOffset': h.endOffset,
        'modality': h.modality.name,
        'score': h.score,
        'image': h.imageAsset is ImageAsset
            ? (h.imageAsset as ImageAsset).toJson()
            : null,
      },
  ];
  try {
    stdout.writeln('Checking empty library without inference...');
    final empty = await worker.search(SearchRequest(query: '离线检索'));
    require(
      empty.indexedDocuments == 0 && empty.hits.isEmpty,
      'Empty-library classification failed.',
    );
    output['emptyLibrary'] = true;
    for (final folder in ['notes', 'old', 'images', 'notes%_archive']) {
      await Directory(p.join(fixtures.path, folder)).create();
    }
    for (final entry in {
      'notes/recent.txt': '离线检索在本地建立索引。此文档记录新增的目录搜索功能。',
      'old/old.md': '# Earlier notes\n旧版离线检索说明，文件修改日期较早。',
      'root.txt': '根目录的本地检索样本，与子目录筛选区分。',
      'notes%_archive/special.txt': '含百分号与下划线目录的检索文件。',
    }.entries) {
      await File(p.join(fixtures.path, entry.key)).writeAsString(entry.value);
    }
    await File(p.join(repo, 'datasets/samples/sample.pdf'))
        .copy(p.join(fixtures.path, 'notes/sample.pdf'));
    await File(p.join(repo, 'datasets/samples/sample.png'))
        .copy(p.join(fixtures.path, 'images/sample.png'));
    final sources = await fixtures
        .list(recursive: true)
        .where((f) => f is File)
        .cast<File>()
        .toList();
    for (final file in sources) {
      await file.setLastModified(DateTime.utc(2020, 1, 1));
    }
    await File(p.join(fixtures.path, 'notes/recent.txt'))
        .setLastModified(DateTime.utc(2026, 10, 29, 12));
    stdout.writeln(
      'Indexing dedicated TXT/Markdown/PDF/PNG fixtures with real models...',
    );
    final indexed = await worker.index(fixtures.path);
    require(
      indexed.run.failed == 0 && indexed.run.written == 6,
      'Fixture indexing failed.',
    );
    output['indexed'] = indexed.snapshot.toJson();

    final requests = <String, SearchRequest>{
      'all': SearchRequest(query: '离线检索'),
      'pdf': SearchRequest.fromDraft(query: '离线检索', type: FileTypeChoice.pdf),
      'images': SearchRequest.fromDraft(
        query: '图片',
        type: FileTypeChoice.images,
      ),
      'directory': SearchRequest.fromDraft(query: '离线检索', path: 'notes/'),
      'exactFile': SearchRequest.fromDraft(
        query: '离线检索',
        path: 'notes/recent.txt',
      ),
      'literalDirectory': SearchRequest.fromDraft(
        query: '检索',
        path: 'notes%_archive',
      ),
      'date': SearchRequest.fromDraft(
        query: '离线检索',
        modifiedAfter: '2026-10-25',
      ),
      'combined': SearchRequest.fromDraft(
        query: '离线检索',
        type: FileTypeChoice.txt,
        path: 'notes',
        modifiedAfter: '2026-10-25',
      ),
      'noMatches': SearchRequest.fromDraft(
        query: '离线检索',
        type: FileTypeChoice.pdf,
        path: 'absent',
      ),
    };
    final pages = <String, SearchPage>{};
    for (final entry in requests.entries) {
      stdout.writeln('Searching ${entry.key}...');
      pages[entry.key] = await worker.search(entry.value);
    }
    require(pages['all']!.hits.isNotEmpty, 'Expected real search hits.');
    require(
      pages['pdf']!.hits.isNotEmpty &&
          pages['pdf']!.hits.every(
            (h) => h.fileName.endsWith('.pdf') && h.pageNumber != null,
          ),
      'PDF filter/anchors failed.',
    );
    require(
      pages['images']!.hits.isNotEmpty &&
          pages['images']!.hits.every(
            (h) => h.imageAsset is ImageAsset && h.pageNumber == null,
          ),
      'Image metadata or image filtering failed.',
    );
    require(
      pages['directory']!.hits.every(
        (h) => h.relativePath.startsWith('notes/'),
      ),
      'Directory filter escaped its subtree.',
    );
    for (final name in ['exactFile', 'date', 'combined']) {
      require(
        pages[name]!.hits.isNotEmpty &&
            pages[name]!.hits.every(
              (h) => h.relativePath == 'notes/recent.txt',
            ),
        '$name filter failed.',
      );
    }
    require(
      pages['literalDirectory']!.hits.isNotEmpty &&
          pages['literalDirectory']!.hits.every(
            (h) => h.relativePath == 'notes%_archive/special.txt',
          ),
      'SQL wildcard escaping failed.',
    );
    require(
      pages['noMatches']!.indexedDocuments == 6 &&
          pages['noMatches']!.hits.isEmpty,
      'No-match classification failed.',
    );
    for (final page in pages.values) {
      for (final h in page.hits) {
        require(
          h.documentKey != null &&
              p.isAbsolute(h.documentKey!) &&
              await File(h.documentKey!).exists(),
          'Source path is not a real indexed file.',
        );
        require(
          h.startOffset >= 0 && h.endOffset >= h.startOffset,
          'Invalid source offsets.',
        );
      }
    }
    output['cases'] = {
      for (final entry in pages.entries)
        entry.key: {
          'request': entry.value.request.toJson(),
          'indexedDocuments': entry.value.indexedDocuments,
          'hits': describe(entry.value.hits),
        },
    };

    Future<String> tracked(Future<SearchPage> future) => future.then(
      (page) => page.request.query,
      onError: (Object e) {
        if (e is SearchCancelledException) return 'cancelled';
        throw e;
      },
    );
    final first = tracked(worker.search(SearchRequest(query: 'first query')));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = tracked(worker.search(SearchRequest(query: 'second query')));
    final latest = tracked(worker.search(SearchRequest(query: 'latest query')));
    final concurrent = await Future.wait([first, second, latest]);
    require(
      concurrent.last == 'latest query' &&
          concurrent.take(2).contains('cancelled'),
      'Latest-query queue failed.',
    );
    output['concurrentQueries'] = concurrent;

    await worker.close();
    stdout.writeln(
      'Comparing worker results against the directly composed core pipeline...',
    );
    core = RuntimeSession.open(config);
    final comparisons = <String, bool>{};
    for (final entry in requests.entries) {
      final expected = await core.search.search(
        entry.value.query,
        filters: entry.value.filters,
        topK: entry.value.topK,
      );
      comparisons[entry.key] =
          jsonEncode(describe(expected)) ==
          jsonEncode(describe(pages[entry.key]!.hits));
      require(
        comparisons[entry.key]!,
        'Worker/core result mismatch in ${entry.key}.',
      );
    }
    await core.close();
    core = null;
    output['coreEquivalence'] = comparisons;
    worker = WorkerLibraryService(config);
    await worker.search(SearchRequest(query: '离线检索'));
    // Search-first startup must still bind ingestion callbacks for a later B job.
    final again = await worker.index(fixtures.path);
    require(
      again.run.reused == 6 && again.run.files.length == 6,
      'Search-first session lost library callbacks.',
    );
    output['searchThenIndex'] = {
      'reused': again.run.reused,
      'fileStatuses': again.run.files.length,
    };
    output['ok'] = true;
  } catch (error, stack) {
    output['error'] = error.toString();
    output['stack'] = stack.toString();
  } finally {
    await core?.close();
    await worker.close();
    output['elapsedMs'] = watch.elapsedMilliseconds;
    final report = File(p.join(repo, 'reports/week5/logs/C_search_smoke.json'));
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
    );
    stdout.writeln(
      'ok=${output['ok']} elapsedMs=${output['elapsedMs']} report=${report.path}',
    );
    if (output['ok'] != true) {
      stderr.writeln(output['error']);
      exitCode = 1;
    }
  }
}
