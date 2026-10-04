import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('value objects expose equality, json, and text', () {
    const DocumentPage page = DocumentPage(pageNumber: 1, text: '  ');
    const DocumentPage filled = DocumentPage(pageNumber: 1, text: 'hello');
    expect(page.isEmpty, isTrue);
    expect(filled.charCount, 5);
    expect(page.toJson()['pageNumber'], 1);
    expect(filled, isNot(page));
    expect(filled.hashCode, isNot(page.hashCode));
    expect(filled.toString(), contains('DocumentPage'));

    const ImageAsset image = ImageAsset(
      format: 'png',
      width: 2,
      height: 0,
      colorMode: 'rgb',
    );
    const ImageAsset otherImage = ImageAsset(
      format: 'jpeg',
      width: 2,
      height: 2,
    );
    expect(image.pixelCount, 0);
    expect(image.aspectRatio, 0);
    expect(otherImage.aspectRatio, 1);
    expect(image.toJson()['format'], 'png');
    expect(image, isNot(otherImage));
    expect(image.hashCode, isNot(otherImage.hashCode));
    expect(image.toString(), contains('png'));

    const ParseFailure failure = ParseFailure(
      kind: ParseFailureKind.timeout,
      message: 'timed out',
      detail: 'stderr',
    );
    expect(failure.toJson()['kind'], 'timeout');
    expect(failure, isNot(equals(const ParseFailure(
      kind: ParseFailureKind.unknown,
      message: 'other',
    ))));
    expect(failure.hashCode, isNot(0));
    expect(failure.toString(), contains('timeout'));

    const ParsedDocument document = ParsedDocument(
      fullText: 'hello',
      pages: <DocumentPage>[filled],
      attributes: <String, Object?>{'title': 'T'},
      warnings: <String>['encoding-fallback:gbk'],
    );
    const ParsedDocument same = ParsedDocument(
      fullText: 'hello',
      pages: <DocumentPage>[filled],
      attributes: <String, Object?>{'title': 'T'},
      warnings: <String>['encoding-fallback:gbk'],
    );
    final ParsedDocument imageOnly = ParsedDocument(
      fullText: '',
      imageAsset: otherImage,
    );
    expect(document, same);
    expect(document.hashCode, same.hashCode);
    expect(document.toJson()['warnings'], <String>['encoding-fallback:gbk']);
    expect(document.toString(), contains('ParsedDocument'));
    expect(imageOnly.isImageOnly, isTrue);
    expect(imageOnly.pageCount, 0);

    final ParseResult success = ParseResult.success(
      document,
      duration: const Duration(milliseconds: 3),
    );
    final ParseResult failed = ParseResult.failure(failure);
    expect(success.toJson()['outcome'], 'ok');
    expect(success, isNot(failed));
    expect(success.hashCode, isNot(failed.hashCode));
    expect(failed.toString(), contains('failed'));

    final FileMetadata metadata = _metadata();
    final FileMetadata copy = metadata.copyWith(status: ParseOutcome.failed);
    expect(metadata, _metadata());
    expect(metadata.hashCode, _metadata().hashCode);
    expect(metadata.toString(), contains('a.txt'));
    expect(copy.status, ParseOutcome.failed);

    final IngestRecord record = IngestRecord(
      metadata: metadata,
      document: document,
      failure: failure,
    );
    final IngestRecord bare = IngestRecord(metadata: metadata);
    expect(record.hasContent, isTrue);
    expect(bare.hasContent, isFalse);
    expect(record.toJson(includeText: true)['text'], 'hello');
    expect(record, isNot(bare));
    expect(record.toString(), contains('a.txt'));

    final DateTime stamp = DateTime.utc(2026, 10, 5);
    final IngestionReport report = IngestionReport(
      rootPath: r'C:\in',
      startedAt: stamp,
      finishedAt: stamp.add(const Duration(milliseconds: 12)),
      records: <IngestRecord>[
        record,
        IngestRecord(
          metadata: metadata.copyWith(status: ParseOutcome.partial),
        ),
      ],
    );
    expect(report.partial, 1);
    expect(report.toJson()['counts'], isA<Map<String, Object?>>());
    expect(report.toString(), contains('partial: 1'));

    const IngestProgress progress = IngestProgress(processed: 1, total: 4);
    const IngestProgress done = IngestProgress(processed: 0, total: 0);
    expect(progress.fraction, 0.25);
    expect(done.fraction, 1);
    expect(progress.toJson()['processed'], 1);
    expect(progress.toString(), contains('1/4'));

    const ProcessRunResult run = ProcessRunResult(
      exitCode: 0,
      stdout: 'out',
      stderr: 'err',
      duration: Duration(milliseconds: 4),
    );
    expect(run.toJson()['exitCode'], 0);
    expect(run, isNot(const ProcessRunResult(exitCode: 1, stdout: '', stderr: '')));
    expect(run.toString(), contains('exitCode: 0'));
    expect(
      const ProcessStartException('java', 'missing').toString(),
      contains('java'),
    );
    expect(
      const ProcessTimeoutException('java', Duration(seconds: 1)).toString(),
      contains('1000'),
    );

    const ExtractedText extracted = ExtractedText(
      pages: <DocumentPage>[filled],
      extractorName: 'tika-cli',
      title: 'Title',
    );
    const ExtractedText empty = ExtractedText(
      pages: <DocumentPage>[],
      extractorName: 'tika-cli',
    );
    expect(extracted.fullText, 'hello');
    expect(extracted.hasText, isTrue);
    expect(empty.hasText, isFalse);
    expect(extracted, isNot(empty));
    expect(extracted.hashCode, isNot(empty.hashCode));
    expect(extracted.toString(), contains('tika-cli'));

    expect(const CancelledException('stop').toString(), contains('stop'));
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    var heard = 0;
    source.token.addListener(() => heard += 1);
    expect(source.token.whenCancelled, completes);
    expect(heard, 1);
  });

  test('xhtml entity forms become page text', () {
    final List<String> pages = pageTextsFromXhtml(
      '<div class="page">&#x41; &#65; &amp;&lt;&gt;&quot;&apos;&nbsp;</div>',
    );
    expect(pages.single, 'A A &<>"\'');
  });

  test('a bad numeric entity is left unchanged', () {
    final List<String> pages = pageTextsFromXhtml(
      '<div class="page">&amp; &unknown; &##;</div>',
    );
    expect(pages.single, contains('&'));
  });

  test('maxDepth below zero is an argument error', () {
    expect(
      const FileScanner().scan(Directory.systemTemp.path, maxDepth: -1),
      throwsArgumentError,
    );
  });

  test('an extension without a dot still matches', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'core_parsing_ext_',
    );
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'note.txt')).writeAsString('note');
    final List<String> paths = await const FileScanner().scan(
      root.path,
      extensions: <String>{'txt', '.', ''},
    );
    expect(paths, hasLength(1));
  });

  test('an already cancelled ingest reports progress and stops', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'core_parsing_cancel_',
    );
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'a.txt')).writeAsString('a');
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    final List<IngestProgress> progress = <IngestProgress>[];
    final IngestionReport report = await IngestionService(
      registry: StandardParserRegistry(<DocumentParser>[TxtParser()]),
      metadata: FileMetadataExtractor(),
    ).ingestDirectory(
      root.path,
      cancel: source.token,
      onProgress: progress.add,
    );
    expect(report.cancelled, isTrue);
    expect(report.total, 0);
    expect(progress.single.total, 0);
  });

  test('cancellation during the scan is a cancelled report', () async {
    final IngestionReport report = await IngestionService(
      registry: StandardParserRegistry(<DocumentParser>[TxtParser()]),
      metadata: FileMetadataExtractor(),
      scanner: _CancelScanner(),
    ).ingestDirectory(Directory.systemTemp.path);
    expect(report.cancelled, isTrue);
    expect(report.records, isEmpty);
  });

  test('a metadata failure is recorded and does not throw', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'core_parsing_meta_',
    );
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'a.txt')).writeAsString('a');
    await File(p.join(root.path, 'b.txt')).writeAsString('b');
    final IngestionReport report = await IngestionService(
      registry: StandardParserRegistry(<DocumentParser>[TxtParser()]),
      metadata: _FailingMetadata(),
      concurrency: 1,
    ).ingestDirectory(root.path);
    expect(report.total, 2);
    expect(report.skipped, 1);
    expect(report.failed, 1);
    expect(
      report.failures.map((IngestRecord record) => record.failure?.kind),
      containsAll(<ParseFailureKind>[
        ParseFailureKind.permissionDenied,
        ParseFailureKind.unknown,
      ]),
    );
  });

  test('an empty image file fails as corrupted input', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'core_parsing_img_',
    );
    addTearDown(() => root.delete(recursive: true));
    final File file = File(p.join(root.path, 'empty.png'))..writeAsBytesSync(
      <int>[],
    );
    final ParseResult result = await const ImageParser().parse(file.path);
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.kind, ParseFailureKind.corruptedInput);
  });
}

FileMetadata _metadata() {
  return FileMetadata(
    id: 'id',
    path: r'C:\in\a.txt',
    relativePath: 'a.txt',
    fileName: 'a.txt',
    extension: '.txt',
    sizeBytes: 4,
    mimeType: 'text/plain',
    status: ParseOutcome.ok,
  );
}

final class _CancelScanner extends FileScanner {
  @override
  Future<List<String>> scan(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    CancellationToken? cancel,
  }) async {
    throw const CancelledException();
  }
}

final class _FailingMetadata implements MetadataExtractor {
  @override
  Future<FileMetadata> describe(
    String absolutePath, {
    required String rootPath,
    int? maxFileSizeBytes,
    CancellationToken? cancel,
  }) async {
    final bool denied = p.basename(absolutePath).startsWith('a');
    return FileMetadata(
      id: absolutePath,
      path: absolutePath,
      relativePath: p.basename(absolutePath),
      fileName: p.basename(absolutePath),
      extension: '.txt',
      sizeBytes: 1,
      status: denied ? ParseOutcome.skipped : ParseOutcome.failed,
      errorMessage: denied ? 'Permission denied.' : 'Unable to read file.',
    );
  }
}
