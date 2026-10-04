@Tags(['integration'])
library;

import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  test('sample.pdf yields two pages through Tika', () async {
    final PdfParser parser = PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: repoFile('tools/tika-app'),
      ),
    );
    final ParseResult result = await parser.parse(
      repoFile('datasets/samples/sample.pdf'),
    );
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.pageCount, 2);
    expect(result.document?.fullText, isNotEmpty);
    expect(result.document?.fullText, contains('Apache Tika'));
    expect(result.document?.attributes['pageCount'], 2);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
