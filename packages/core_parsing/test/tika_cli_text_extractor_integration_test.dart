@Tags(['integration'])
library;

import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  test('sample.pdf yields two pages through the real Tika CLI', () async {
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: const IoProcessRunner(),
      tikaHome: repoFile('tools/tika-app'),
    );
    final ExtractedText text = await extractor.extract(
      repoFile('datasets/samples/sample.pdf'),
    );
    expect(text.pages, hasLength(2));
    expect(text.pages[0].pageNumber, 1);
    expect(text.pages[1].pageNumber, 2);
    expect(text.fullText, contains('Apache Tika'));
    expect(text.attributes['mode'], 'xhtml');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
