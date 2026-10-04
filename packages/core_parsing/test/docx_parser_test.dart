import 'dart:io';

import 'package:archive/archive.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  const DocxParser parser = DocxParser();

  test('minimal fixture yields paragraphs and core properties', () async {
    final ParseResult result = await parser.parse(
      fixturePath('docx_minimal.docx'),
    );
    expect(result.outcome, ParseOutcome.ok);
    expect(
      result.document?.fullText,
      'Hello DOCX fixture.\nSecond paragraph with split runs.\n中文段落测试',
    );
    expect(result.document?.pages, hasLength(1));
    expect(result.document?.attributes['dc:title'], 'Core Parsing Fixture');
    expect(result.document?.attributes['dc:creator'], 'Week 2');
    expect(
      result.document?.attributes['dcterms:created'],
      '2026-09-27T00:00:00Z',
    );
  });

  test('sample.docx has body text and a creator', () async {
    final ParseResult result = await parser.parse(
      repoFile('datasets/samples/sample.docx'),
    );
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, contains('Apache Tika Documentation'));
    expect(result.document?.fullText, isNotEmpty);
    expect(result.document?.attributes['dc:creator'], 'Mengxiao Wu');
    expect(result.document?.attributes.containsKey('dc:title'), isTrue);
    expect(
      result.document?.attributes['dcterms:created'],
      '2026-09-24T03:14:00Z',
    );
  });

  test('tabs and line breaks inside a paragraph are kept', () async {
    final File file = await _writeDocx(
      'tab-br.docx',
      documentXml: '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>A</w:t></w:r>
      <w:r><w:tab/></w:r>
      <w:r><w:t>B</w:t></w:r>
      <w:r><w:br/></w:r>
      <w:r><w:t>C</w:t></w:r>
    </w:p>
  </w:body>
</w:document>
''',
    );
    final ParseResult result = await parser.parse(file.path);
    expect(result.document?.fullText, 'A\tB\nC');
  });

  test('a corrupt zip is failed and names the reason', () async {
    final ParseResult result = await parser.parse(fixturePath('corrupt.docx'));
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.kind, ParseFailureKind.corruptedInput);
    expect(result.failure?.message, contains('zip'));
  });

  test('a zip without document.xml is failed', () async {
    final File file = await _writeDocx('no-document.docx', documentXml: null);
    final ParseResult result = await parser.parse(file.path);
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.kind, ParseFailureKind.corruptedInput);
    expect(result.failure?.message, contains('word/document.xml'));
  });
}

Future<File> _writeDocx(String name, {required String? documentXml}) async {
  final Archive archive = Archive();
  if (documentXml != null) {
    final List<int> bytes = documentXml.codeUnits;
    archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  } else {
    const String marker = '<Types/>';
    archive.addFile(
      ArchiveFile('[Content_Types].xml', marker.length, marker.codeUnits),
    );
  }
  final List<int>? encoded = ZipEncoder().encode(archive);
  final File file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$name',
  );
  await file.writeAsBytes(encoded!);
  addTearDown(() => file.existsSync() ? file.delete() : null);
  return file;
}
