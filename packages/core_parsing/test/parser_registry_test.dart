import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final StandardParserRegistry registry = StandardParserRegistry(
    <DocumentParser>[
      _StubParser(const <String>{'.txt', '.pdf'}),
    ],
  );

  test('extensions match regardless of case or a leading dot', () {
    expect(registry.resolveForExtension('.TXT')?.name, 'stub');
    expect(registry.resolveForExtension('Pdf')?.name, 'stub');
    expect(registry.resolveForPath(p.join('docs', 'Notes.Pdf'))?.name, 'stub');
    expect(registry.supports(p.join('docs', 'A.TXT')), isTrue);
    expect(registry.supportedExtensions, <String>{'.txt', '.pdf'});
  });

  test('an unknown extension is skipped and does not throw', () async {
    expect(registry.resolveForPath(p.join('docs', 'picture.bin')), isNull);
    final ParseResult result = await registry.parse(
      p.join('docs', 'picture.bin'),
    );
    expect(result.failure?.kind, ParseFailureKind.unsupportedFormat);
    expect(result.outcome, ParseOutcome.skipped);
  });

  test('a matching parser is invoked', () async {
    final ParseResult result = await registry.parse(p.join('docs', 'A.TXT'));
    expect(result.document?.fullText, p.join('docs', 'A.TXT'));
  });
}

class _StubParser implements DocumentParser {
  _StubParser(this.supportedExtensions);

  @override
  final Set<String> supportedExtensions;

  @override
  String get name => 'stub';

  @override
  String get version => '1';

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    return ParseResult.success(ParsedDocument(fullText: absolutePath));
  }
}
