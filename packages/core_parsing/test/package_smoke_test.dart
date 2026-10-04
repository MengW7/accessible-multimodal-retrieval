import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

void main() {
  group('ParseOutcome vocabulary is frozen', () {
    test('enum values are stable', () {
      expect(
        ParseOutcome.values.map((ParseOutcome o) => o.name).toList(),
        <String>['ok', 'partial', 'skipped', 'failed'],
      );
    });

    test('only ok and partial are usable downstream', () {
      expect(ParseOutcome.ok.isUsable, isTrue);
      expect(ParseOutcome.partial.isUsable, isTrue);
      expect(ParseOutcome.skipped.isUsable, isFalse);
      expect(ParseOutcome.failed.isUsable, isFalse);
    });
  });

  group('ParseFailure mapping', () {
    const Map<ParseFailureKind, ParseOutcome> expected =
        <ParseFailureKind, ParseOutcome>{
          ParseFailureKind.unsupportedFormat: ParseOutcome.skipped,
          ParseFailureKind.permissionDenied: ParseOutcome.skipped,
          ParseFailureKind.cancelled: ParseOutcome.skipped,
          ParseFailureKind.corruptedInput: ParseOutcome.failed,
          ParseFailureKind.dependencyUnavailable: ParseOutcome.failed,
          ParseFailureKind.timeout: ParseOutcome.failed,
          ParseFailureKind.unknown: ParseOutcome.failed,
        };

    test('every kind is covered by the degradation policy', () {
      expect(expected.keys.toSet(), ParseFailureKind.values.toSet());
    });

    test('kind maps to the documented outcome', () {
      for (final MapEntry<ParseFailureKind, ParseOutcome> entry
          in expected.entries) {
        expect(
          ParseFailure(kind: entry.key, message: 'm').outcome,
          entry.value,
          reason: entry.key.name,
        );
      }
    });

    test('carries no file content, only a message and optional detail', () {
      const ParseFailure failure = ParseFailure(
        kind: ParseFailureKind.dependencyUnavailable,
        message: 'java not found',
        detail: 'stderr tail',
      );
      expect(failure.toJson()['kind'], 'dependencyUnavailable');
      expect(failure.toJson()['outcome'], 'failed');
      expect(failure.detail, 'stderr tail');
    });
  });

  group('ParsedDocument', () {
    test('page count falls back to a single logical page for plain text', () {
      const ParsedDocument doc = ParsedDocument(fullText: 'hello');
      expect(doc.pageCount, 1);
      expect(doc.hasText, isTrue);
    });

    test('empty text has zero pages', () {
      const ParsedDocument doc = ParsedDocument(fullText: '   ');
      expect(doc.pageCount, 0);
      expect(doc.hasText, isFalse);
    });

    test('explicit pages win over the fallback', () {
      const ParsedDocument doc = ParsedDocument(
        fullText: 'a\n\nb',
        pages: <DocumentPage>[
          DocumentPage(pageNumber: 1, text: 'a'),
          DocumentPage(pageNumber: 2, text: 'b'),
        ],
      );
      expect(doc.pageCount, 2);
      expect(doc.pages.first.charCount, 1);
      expect(doc.pages.last.isEmpty, isFalse);
    });

    test('image-only documents are distinguishable', () {
      const ParsedDocument doc = ParsedDocument(
        fullText: '',
        imageAsset: ImageAsset(format: 'png', width: 8, height: 4),
      );
      expect(doc.isImageOnly, isTrue);
      expect(doc.imageAsset?.pixelCount, 32);
      expect(doc.imageAsset?.aspectRatio, 2);
      expect(doc.toJson()['pageCount'], 0);
    });
  });

  group('ParseResult', () {
    test('success derives its outcome from the document', () {
      const ParseResult result = ParseResult.success(
        ParsedDocument(fullText: 'x', outcome: ParseOutcome.partial),
        duration: Duration(milliseconds: 5),
      );
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.outcome, ParseOutcome.partial);
      expect(result.duration.inMilliseconds, 5);
    });

    test('failure derives its outcome from the failure kind', () {
      const ParseResult result = ParseResult.failure(
        ParseFailure(
          kind: ParseFailureKind.unsupportedFormat,
          message: 'no parser',
        ),
      );
      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.outcome, ParseOutcome.skipped);
      expect(result.toJson()['document'], isNull);
    });
  });

  group('FileMetadata', () {
    const FileMetadata base = FileMetadata(
      id: 'abc',
      path: r'E:\docs\a.txt',
      relativePath: 'docs/a.txt',
      fileName: 'a.txt',
      extension: '.txt',
      sizeBytes: 12,
      status: ParseOutcome.ok,
      parserName: 'txt',
      parseDurationMs: 1,
    );

    test('is indexable only for usable outcomes', () {
      expect(base.isIndexable, isTrue);
      expect(
        base.copyWith(status: ParseOutcome.failed).isIndexable,
        isFalse,
      );
    });

    test('copyWith keeps the untouched fields', () {
      final FileMetadata updated = base.copyWith(
        contentHash: 'deadbeef',
        mimeType: 'text/plain',
      );
      expect(updated.contentHash, 'deadbeef');
      expect(updated.mimeType, 'text/plain');
      expect(updated.sizeBytes, base.sizeBytes);
      expect(updated.relativePath, base.relativePath);
    });

    test('serialises every field the retrieval layer filters on', () {
      final Map<String, Object?> json = base.toJson();
      expect(json.keys, containsAll(<String>['id', 'path', 'relativePath',
        'fileName', 'extension', 'sizeBytes', 'modifiedAt', 'status']));
      expect(json['status'], 'ok');
      expect(json['indexedAt'], isNull);
    });

    test('equality is value based', () {
      expect(base, equals(base.copyWith()));
      expect(base == base.copyWith(sizeBytes: 13), isFalse);
    });
  });

  group('IngestionReport', () {
    FileMetadata meta(String name, ParseOutcome outcome) => FileMetadata(
      id: name,
      path: name,
      relativePath: name,
      fileName: name,
      extension: '.txt',
      sizeBytes: 1,
      status: outcome,
    );

    final DateTime start = DateTime.utc(2026, 9, 27, 9);
    final IngestionReport report = IngestionReport(
      rootPath: 'docs',
      startedAt: start,
      finishedAt: start.add(const Duration(seconds: 4)),
      records: <IngestRecord>[
        IngestRecord(
          metadata: meta('a.txt', ParseOutcome.ok),
          document: const ParsedDocument(fullText: 'a'),
        ),
        IngestRecord(
          metadata: meta('b.txt', ParseOutcome.partial),
          document: const ParsedDocument(
            fullText: 'b',
            outcome: ParseOutcome.partial,
          ),
        ),
        IngestRecord(
          metadata: meta('c.bin', ParseOutcome.skipped),
          failure: const ParseFailure(
            kind: ParseFailureKind.unsupportedFormat,
            message: 'no parser',
          ),
        ),
        IngestRecord(metadata: meta('d.txt', ParseOutcome.failed)),
      ],
    );

    test('counts by outcome', () {
      expect(report.total, 4);
      expect(report.succeeded, 1);
      expect(report.partial, 1);
      expect(report.skipped, 1);
      expect(report.failed, 1);
      expect(report.duration.inSeconds, 4);
      expect(report.isClean, isFalse);
      expect(report.indexable.length, 2);
      expect(report.failures.length, 1);
    });

    test('record content is summarised, not duplicated, by default', () {
      final Map<String, Object?> json = report.records.first.toJson();
      expect(json['text'], isNull);
      expect(json['charCount'], 1);
      expect(json.containsKey('metadata'), isTrue);
    });

    test('cancelled runs are never clean', () {
      final IngestionReport cancelled = IngestionReport(
        rootPath: 'docs',
        startedAt: start,
        finishedAt: start,
        cancelled: true,
      );
      expect(cancelled.isClean, isFalse);
      expect(cancelled.toJson()['counts'], isA<Map<String, Object?>>());
    });
  });

  group('IngestProgress', () {
    test('fraction saturates at both ends', () {
      expect(const IngestProgress(processed: 0, total: 0).fraction, 1);
      expect(const IngestProgress(processed: 0, total: 4).fraction, 0);
      expect(const IngestProgress(processed: 2, total: 4).fraction, 0.5);
      expect(const IngestProgress(processed: 9, total: 4).fraction, 1);
    });

    test('is serialisable for the UI layer', () {
      const IngestProgress progress = IngestProgress(
        processed: 1,
        total: 2,
        currentPath: 'a.txt',
      );
      expect(progress.toJson()['fraction'], 0.5);
      expect(progress.currentPath, 'a.txt');
    });
  });

  group('CancellationToken', () {
    test('is not cancelled until the source says so', () {
      final CancellationTokenSource source = CancellationTokenSource();
      expect(source.token.isCancelled, isFalse);
      source.token.throwIfCancelled();
      source.cancel();
      expect(source.token.isCancelled, isTrue);
      expect(source.token.throwIfCancelled, throwsA(isA<CancelledException>()));
    });

    test('cancel is idempotent and notifies listeners once', () {
      final CancellationTokenSource source = CancellationTokenSource();
      var notifications = 0;
      void listener() => notifications++;
      source.token.addListener(listener);
      source.cancel();
      source.cancel();
      expect(notifications, 1);
      source.token.removeListener(listener);
    });

    test('a listener added after cancellation fires immediately', () {
      final CancellationTokenSource source = CancellationTokenSource()
        ..cancel();
      var fired = false;
      source.token.addListener(() => fired = true);
      expect(fired, isTrue);
    });

    test('whenCancelled completes', () async {
      final CancellationTokenSource source = CancellationTokenSource()
        ..cancel();
      await source.token.whenCancelled;
      expect(source.isCancelled, isTrue);
    });
  });

  group('injected seams', () {
    test('ImmediateExecutor runs the action', () async {
      const Executor executor = ImmediateExecutor();
      expect(await executor.run<int>(() async => 7), 7);
    });

    test('ProcessRunResult reports success by exit code', () {
      const ProcessRunResult ok = ProcessRunResult(
        exitCode: 0,
        stdout: 'text',
        stderr: 'INFO noise',
      );
      expect(ok.isSuccess, isTrue);
      expect(ok.toJson()['stderrBytes'], greaterThan(0));
    });

    test('the public interfaces are implementable from another package', () {
      final ParserRegistry registry = _FakeRegistry();
      final DocumentParser parser = _FakeParser();
      final ProcessRunner runner = _FakeRunner();
      final TextExtractor extractor = _FakeExtractor();

      expect(registry.parsers, hasLength(1));
      expect(registry.supports('a.txt'), isTrue);
      expect(registry.resolveForExtension('.txt'), isNotNull);
      expect(parser.supportedExtensions, contains('.txt'));
      expect(runner, isA<ProcessRunner>());
      expect(extractor.name, 'fake');
    });

    test('a fake process runner satisfies the TextExtractor contract', () async {
      final ExtractedText extracted = await _FakeExtractor().extract('a.pdf');
      expect(extracted.pages, hasLength(1));
      expect(extracted.hasText, isTrue);
      expect(extracted.fullText, 'page-one');
    });
  });
}

class _FakeParser implements DocumentParser {
  @override
  String get name => 'txt';

  @override
  String get version => '0.1.0';

  @override
  Set<String> get supportedExtensions => <String>{'.txt'};

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async => const ParseResult.success(ParsedDocument(fullText: 'x'));
}

class _FakeRegistry implements ParserRegistry {
  final List<DocumentParser> _parsers = <DocumentParser>[_FakeParser()];

  @override
  List<DocumentParser> get parsers => _parsers;

  @override
  Set<String> get supportedExtensions => <String>{'.txt'};

  @override
  DocumentParser? resolveForExtension(String extension) {
    final String normalised = extension.startsWith('.')
        ? extension.toLowerCase()
        : '.${extension.toLowerCase()}';
    return normalised == '.txt' ? _parsers.first : null;
  }

  @override
  DocumentParser? resolveForPath(String absolutePath) {
    final int dot = absolutePath.lastIndexOf('.');
    if (dot < 0 || dot == absolutePath.length - 1) {
      return null;
    }
    return resolveForExtension(absolutePath.substring(dot));
  }

  @override
  bool supports(String absolutePath) => resolveForPath(absolutePath) != null;
}

class _FakeRunner implements ProcessRunner {
  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    CancellationToken? cancel,
  }) async => const ProcessRunResult(exitCode: 0, stdout: 'ok', stderr: '');
}

class _FakeExtractor implements TextExtractor {
  @override
  String get name => 'fake';

  @override
  String get version => '0.1.0';

  @override
  Future<ExtractedText> extract(
    String absolutePath, {
    CancellationToken? cancel,
  }) async => ExtractedText(
    pages: const <DocumentPage>[
      DocumentPage(pageNumber: 1, text: 'page-one'),
    ],
    extractorName: name,
  );
}
