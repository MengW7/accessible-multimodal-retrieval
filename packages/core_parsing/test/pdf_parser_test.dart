import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  test('pages from the extractor become an ok document', () async {
    final _FakeExtractor extractor = _FakeExtractor(
      onExtract: () async => const ExtractedText(
        pages: <DocumentPage>[
          DocumentPage(pageNumber: 1, text: 'Apache Tika'),
          DocumentPage(pageNumber: 2, text: 'second'),
        ],
        extractorName: 'fake',
        attributes: <String, Object?>{'mode': 'xhtml'},
      ),
    );
    final PdfParser parser = PdfParser(textExtractor: extractor);
    final ParseResult result = await parser.parse(fixturePath('truncated.pdf'));
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.pageCount, 2);
    expect(result.document?.fullText, contains('Apache Tika'));
    expect(result.document?.attributes['pageCount'], 2);
    expect(result.document?.attributes['extractor'], 'fake');
    expect(extractor.calls, 1);
  });

  test('an empty pdf fails before the extractor runs', () async {
    final _FakeExtractor extractor = _FakeExtractor(
      onExtract: () async => throw StateError('should not run'),
    );
    final PdfParser parser = PdfParser(textExtractor: extractor);
    final ParseResult result = await parser.parse(fixturePath('zero.pdf'));
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.kind, ParseFailureKind.corruptedInput);
    expect(result.failure?.message, contains('empty'));
    expect(extractor.calls, 0);
  });

  test('an encrypted pdf keeps the extractor reason', () async {
    final PdfParser parser = PdfParser(
      textExtractor: _FakeExtractor(
        onExtract: () async => throw const TextExtractionException(
          'PDF is encrypted.',
          stderr: 'Encrypted document',
        ),
      ),
    );
    final ParseResult result = await parser.parse(fixturePath('truncated.pdf'));
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.kind, ParseFailureKind.corruptedInput);
    expect(result.failure?.message, 'PDF is encrypted.');
    expect(result.failure?.detail, 'Encrypted document');
  });

  test('a missing java runtime is dependencyUnavailable', () async {
    final PdfParser parser = PdfParser(
      textExtractor: _FakeExtractor(
        onExtract: () async =>
            throw const ProcessStartException('java', 'not found'),
      ),
    );
    final ParseResult result = await parser.parse(fixturePath('truncated.pdf'));
    expect(result.failure?.kind, ParseFailureKind.dependencyUnavailable);
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.detail, 'not found');
  });

  test('a timed out extractor is timeout and failed', () async {
    final PdfParser parser = PdfParser(
      textExtractor: _FakeExtractor(
        onExtract: () async =>
            throw const ProcessTimeoutException('java', Duration(seconds: 1)),
      ),
    );
    final ParseResult result = await parser.parse(fixturePath('truncated.pdf'));
    expect(result.failure?.kind, ParseFailureKind.timeout);
    expect(result.outcome, ParseOutcome.failed);
  });

  test('a missing path is a failure, not an exception', () async {
    final PdfParser parser = PdfParser(
      textExtractor: _FakeExtractor(
        onExtract: () async => throw StateError('should not run'),
      ),
    );
    final ParseResult result = await parser.parse('missing-file.pdf');
    expect(result.failure?.kind, ParseFailureKind.unknown);
    expect(result.outcome, ParseOutcome.failed);
  });

  test('cancellation still throws', () async {
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    final PdfParser parser = PdfParser(
      textExtractor: _FakeExtractor(
        onExtract: () async => throw StateError('should not run'),
      ),
    );
    expect(
      parser.parse(fixturePath('truncated.pdf'), cancel: source.token),
      throwsA(isA<CancelledException>()),
    );
  });
}

final class _FakeExtractor implements TextExtractor {
  _FakeExtractor({required this.onExtract});

  final Future<ExtractedText> Function() onExtract;
  int calls = 0;

  @override
  String get name => 'fake';

  @override
  String get version => '1';

  @override
  Future<ExtractedText> extract(
    String absolutePath, {
    CancellationToken? cancel,
  }) {
    calls += 1;
    cancel?.throwIfCancelled();
    return onExtract();
  }
}
