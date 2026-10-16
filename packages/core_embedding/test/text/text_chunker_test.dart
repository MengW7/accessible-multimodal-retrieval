import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

CascadeTextChunker _chunker({
  int Function(String text)? countTokens,
  int chunkChars = 8,
  int maxTokens = 100,
}) {
  return CascadeTextChunker(
    countTokens: countTokens ?? ((String text) => text.length + 2),
    chunkChars: chunkChars,
    maxTokens: maxTokens,
    counterLabel: 'chars',
  );
}

ParsedDocument _doc(
  String text, {
  List<DocumentPage>? pages,
  Map<String, Object?> attributes = const <String, Object?>{},
}) {
  return ParsedDocument(
    fullText: text,
    pages: pages ?? <DocumentPage>[DocumentPage(pageNumber: 1, text: text)],
    attributes: attributes,
  );
}

void _expectSpans(String page, List<TextChunk> chunks) {
  for (final TextChunk chunk in chunks) {
    expect(page.substring(chunk.startOffset, chunk.endOffset), chunk.text);
    expect(chunk.textUnit, TextUnit.utf16CodeUnit);
    expect(chunk.chunkerVersion, CascadeTextChunker.defaultVersion);
  }
}

void main() {
  test('docx single newlines split, and the page number stays null', () {
    const String text = '段落一\n段落二';
    final List<TextChunk> chunks = _chunker().chunk(_doc(text), documentId: 'docx-1');
    expect(chunks.map((TextChunk chunk) => chunk.text), <String>['段落一', '段落二']);
    expect(chunks.every((TextChunk chunk) => chunk.pageNumber == null), isTrue);
    expect(chunks[0].startOffset, 0);
    expect(chunks[0].endOffset, 3);
    expect(chunks[1].startOffset, 4);
    expect(chunks[1].endOffset, 7);
    expect(chunks[0].chunkId, contains('docx-1'));
    expect(chunks[0].chunkId, contains('-pna-i0'));
    expect(chunks[1].chunkId, contains('-pna-i1'));
    _expectSpans(text, chunks);
  });

  test('txt keeps a short single newline inside a blank-line paragraph', () {
    const String text = '甲\n乙\n\n丙';
    final List<TextChunk> chunks = _chunker().chunk(_doc(text), documentId: 'txt-1');
    expect(chunks.map((TextChunk chunk) => chunk.text), <String>['甲\n乙', '丙']);
    expect(chunks[0].pageNumber, isNull);
    expect(chunks[1].startOffset, 5);
    _expectSpans(text, chunks);
  });

  test('a pdf page without paragraphs splits on sentence punctuation', () {
    const String text = '第一句。第二句。';
    final List<TextChunk> chunks = _chunker(maxTokens: 6).chunk(
      _doc(text, attributes: const <String, Object?>{'pageCount': 1}),
      documentId: 'pdf-1',
    );
    expect(chunks.map((TextChunk chunk) => chunk.text), <String>['第一句。', '第二句。']);
    expect(chunks.map((TextChunk chunk) => chunk.pageNumber), <int>[1, 1]);
    expect(chunks[0].chunkId, contains('-p1-i0'));
    _expectSpans(text, chunks);
  });

  test('a pdf page with no breaks falls through to the character window', () {
    const String text = '甲乙丙丁戊己庚辛';
    final CascadeTextChunker chunker = _chunker(chunkChars: 3, maxTokens: 5);
    final List<TextChunk> chunks = chunker.chunk(
      _doc(
        text,
        pages: const <DocumentPage>[
          DocumentPage(pageNumber: 2, text: text),
        ],
        attributes: const <String, Object?>{'extractor': 'tika'},
      ),
      documentId: 'pdf-2',
    );
    expect(chunks.map((TextChunk chunk) => chunk.text), <String>['甲乙丙', '丁戊己', '庚辛']);
    expect(chunks.every((TextChunk chunk) => chunk.pageNumber == 2), isTrue);
    for (final TextChunk chunk in chunks) {
      expect(chunker.countTokens(chunk.text), lessThanOrEqualTo(5));
    }
    _expectSpans(text, chunks);
  });

  test('pages are not merged', () {
    final List<TextChunk> chunks = _chunker().chunk(
      ParsedDocument(
        fullText: '跨页前跨页后',
        pages: const <DocumentPage>[
          DocumentPage(pageNumber: 1, text: '跨页前'),
          DocumentPage(pageNumber: 2, text: '跨页后'),
        ],
      ),
      documentId: 'pdf-pages',
    );
    expect(chunks, hasLength(2));
    expect(chunks[0].pageNumber, 1);
    expect(chunks[1].pageNumber, 2);
    expect(chunks[0].text, '跨页前');
    expect(chunks[1].startOffset, 0);
    expect(chunks[1].endOffset, 3);
  });

  test('the same document and config reproduce the same ids', () {
    final ParsedDocument document = _doc('甲\n\n乙');
    final CascadeTextChunker chunker = _chunker();
    expect(chunker.chunk(document, documentId: 'same'), chunker.chunk(document, documentId: 'same'));
  });

  test('a missing document id uses the body hash', () {
    final List<TextChunk> chunks = _chunker().chunk(_doc('正文'));
    expect(chunks.single.chunkId, matches(RegExp(r'^[0-9a-f]{64}-')));
    expect(chunks.single.pageNumber, isNull);
  });

  test('a hard window does not split a surrogate pair', () {
    const String text = 'ab🙂cd';
    final List<TextChunk> chunks = _chunker(chunkChars: 3).chunk(
      _doc(text),
      documentId: 'emoji',
    );
    expect(chunks.map((TextChunk chunk) => chunk.text), <String>['ab🙂', 'cd']);
    expect(chunks[0].endOffset - chunks[0].startOffset, 4);
    _expectSpans(text, chunks);
  });

  test('one code unit over the token budget throws instead of truncating', () {
    expect(
      () => _chunker(countTokens: (String text) => 1000).chunk(
        _doc('甲'),
        documentId: 'over',
      ),
      throwsA(isA<ChunkBudgetException>()),
    );
  });

  test('blank text and bad settings produce no chunks or an argument error', () {
    expect(_chunker().chunk(const ParsedDocument(fullText: '  \n')), isEmpty);
    expect(
      () => CascadeTextChunker(countTokens: (String text) => text.length, chunkChars: 0),
      throwsArgumentError,
    );
    expect(
      () => _chunker().chunk(_doc('甲'), documentId: ''),
      throwsArgumentError,
    );
  });
}
