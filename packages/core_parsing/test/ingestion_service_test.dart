import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  // coco and rvlcdip images are gitignored, so this stays off the default suite.
  test('coco and rvlcdip yield 66 image records without failures', () async {
    final IngestionService service = _images();
    final IngestionReport coco = await service.ingestDirectory(
      repoFile('datasets/coco/val_sample/images'),
    );
    final IngestionReport rvl = await service.ingestDirectory(
      repoFile('datasets/rvlcdip/sample'),
    );
    expect(coco.total, 50);
    expect(rvl.total, 16);
    expect(coco.total + rvl.total, 66);
    expect(coco.failed, 0);
    expect(rvl.failed, 0);
    expect(coco.succeeded, 50);
    expect(rvl.succeeded, 16);
    expect(
      coco.records.every(
        (IngestRecord record) => record.metadata.imageAsset != null,
      ),
      isTrue,
    );
    expect(
      coco.records.every(
        (IngestRecord record) => record.metadata.contentHash != null,
      ),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 2)), tags: 'integration');

  test('a corrupt file is isolated and the rest still succeed', () async {
    final Directory root = await _temp();
    await File(fixturePath('hello.txt')).copy(p.join(root.path, 'hello.txt'));
    await File(fixturePath('corrupt.docx')).copy(p.join(root.path, 'bad.docx'));
    final IngestionReport report = await _documents().ingestDirectory(
      root.path,
    );
    expect(report.total, 2);
    expect(report.succeeded, 1);
    expect(report.failed, 1);
    expect(report.failures, hasLength(1));
    expect(report.cancelled, isFalse);
  });

  test('an empty directory is an empty report', () async {
    final Directory root = await _temp();
    final List<IngestProgress> progress = <IngestProgress>[];
    final IngestionReport report = await _documents().ingestDirectory(
      root.path,
      onProgress: progress.add,
    );
    expect(report.total, 0);
    expect(report.records, isEmpty);
    expect(report.cancelled, isFalse);
    expect(progress.single.total, 0);
    expect(progress.single.fraction, 1);
  });

  test('duplicate content is skipped and not parsed twice', () async {
    final Directory root = await _temp();
    await File(p.join(root.path, 'a.txt')).writeAsString('same');
    await File(p.join(root.path, 'b.txt')).writeAsString('same');
    final IngestionReport report = await _documents().ingestDirectory(
      root.path,
    );
    expect(report.total, 2);
    expect(report.succeeded, 1);
    expect(report.skipped, 1);
    expect(report.indexable, hasLength(1));
    final IngestRecord skipped = report.records.firstWhere(
      (IngestRecord record) => record.outcome == ParseOutcome.skipped,
    );
    expect(skipped.metadata.errorMessage, contains('Duplicate content'));
    expect(
      skipped.metadata.contentHash,
      report.indexable.single.metadata.contentHash,
    );
  });

  test('an unsupported file is skipped without a parser call', () async {
    final Directory root = await _temp();
    await File(p.join(root.path, 'note.bin')).writeAsString('bin');
    await File(p.join(root.path, 'ok.txt')).writeAsString('ok');
    final _CountingParser parser = _CountingParser();
    final IngestionService service = IngestionService(
      registry: StandardParserRegistry(<DocumentParser>[parser]),
      metadata: FileMetadataExtractor(),
      concurrency: 1,
    );
    final IngestionReport report = await service.ingestDirectory(
      root.path,
      extensions: const <String>{'.txt', '.bin'},
    );
    expect(report.skipped, 1);
    expect(report.succeeded, 1);
    expect(parser.calls, 1);
  });

  test('a throwing parser is recorded and the batch continues', () async {
    final Directory root = await _temp();
    await File(p.join(root.path, 'a.txt')).writeAsString('a');
    await File(p.join(root.path, 'b.txt')).writeAsString('b');
    final IngestionService service = IngestionService(
      registry: StandardParserRegistry(<DocumentParser>[_ThrowingParser()]),
      metadata: FileMetadataExtractor(),
      concurrency: 1,
    );
    final IngestionReport report = await service.ingestDirectory(root.path);
    expect(report.total, 2);
    expect(report.failed, 1);
    expect(report.succeeded, 1);
    expect(report.failures.single.failure?.message, contains('StateError'));
  });

  test('cancel before start yields a cancelled empty report', () async {
    final Directory root = await _temp();
    await File(p.join(root.path, 'a.txt')).writeAsString('a');
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    final IngestionReport report = await _documents().ingestDirectory(
      root.path,
      cancel: source.token,
    );
    expect(report.cancelled, isTrue);
    expect(report.total, 0);
  });

  test('cancel after the first file stops the rest', () async {
    final Directory root = await _temp();
    for (var index = 0; index < 4; index++) {
      await File(p.join(root.path, 'f$index.txt')).writeAsString('file $index');
    }
    final CancellationTokenSource source = CancellationTokenSource();
    final IngestionReport report = await _documents().ingestDirectory(
      root.path,
      cancel: source.token,
      onProgress: (IngestProgress progress) {
        if (progress.processed >= 1) {
          source.cancel();
        }
      },
    );
    expect(report.cancelled, isTrue);
    expect(report.total, lessThan(4));
    expect(report.total, greaterThan(0));
    expect(report.succeeded, report.total);
  });

  test('a missing root is a failed report, not an exception', () async {
    final String missing = p.join(
      Directory.systemTemp.path,
      'core_parsing_missing_${DateTime.now().microsecondsSinceEpoch}',
    );
    final IngestionReport report = await _documents().ingestDirectory(missing);
    expect(report.total, 1);
    expect(report.failed, 1);
    expect(report.cancelled, isFalse);
    expect(report.failures.single.failure?.message, 'Directory not found');
  });

  test('a file used as the root is a failed report', () async {
    final Directory root = await _temp();
    final File file = File(p.join(root.path, 'hello.txt'))
      ..writeAsStringSync('x');
    final IngestionReport report = await _documents().ingestDirectory(
      file.path,
    );
    expect(report.failed, 1);
    expect(report.failures.single.failure?.message, 'Not a directory');
  });

  test('an unreadable root is skipped', () async {
    final IngestionService service = IngestionService(
      registry: StandardParserRegistry(<DocumentParser>[TxtParser()]),
      metadata: FileMetadataExtractor(),
      scanner: _DeniedScanner(),
    );
    final IngestionReport report = await service.ingestDirectory(
      Directory.systemTemp.path,
    );
    expect(report.skipped, 1);
    expect(report.failed, 0);
    expect(
      report.failures.single.failure?.kind,
      ParseFailureKind.permissionDenied,
    );
  });
}

IngestionService _images() {
  return IngestionService(
    registry: StandardParserRegistry(const <DocumentParser>[ImageParser()]),
    metadata: FileMetadataExtractor(),
  );
}

IngestionService _documents() {
  return IngestionService(
    registry: StandardParserRegistry(<DocumentParser>[
      TxtParser(),
      const DocxParser(),
    ]),
    metadata: FileMetadataExtractor(),
    concurrency: 1,
  );
}

Future<Directory> _temp() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'core_parsing_ingest_',
  );
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

final class _CountingParser implements DocumentParser {
  int calls = 0;

  @override
  String get name => 'txt';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{'.txt'};

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    calls += 1;
    return ParseResult.success(
      ParsedDocument(
        fullText: absolutePath,
        pages: <DocumentPage>[DocumentPage(pageNumber: 1, text: absolutePath)],
      ),
    );
  }
}

final class _DeniedScanner extends FileScanner {
  @override
  Future<List<String>> scan(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    CancellationToken? cancel,
  }) {
    throw FileSystemException(
      'Access is denied',
      rootPath,
      OSError('Access is denied', 5),
    );
  }
}

final class _ThrowingParser implements DocumentParser {
  int calls = 0;

  @override
  String get name => 'txt';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{'.txt'};

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    calls += 1;
    if (calls == 1) {
      throw StateError('boom');
    }
    return const ParseResult.success(ParsedDocument(fullText: 'ok'));
  }
}
