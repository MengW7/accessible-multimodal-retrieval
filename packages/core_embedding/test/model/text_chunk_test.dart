import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

const TextChunk _chunk = TextChunk(
  chunkId: 'doc-1',
  text: '页码',
  startOffset: 0,
  endOffset: 2,
  textUnit: TextUnit.utf16CodeUnit,
  chunkerVersion: 'w3-1',
  pageNumber: 1,
);

const TextChunk _same = TextChunk(
  chunkId: 'doc-1',
  text: '页码',
  startOffset: 0,
  endOffset: 2,
  textUnit: TextUnit.utf16CodeUnit,
  chunkerVersion: 'w3-1',
  pageNumber: 1,
);

void main() {
  test('toJson records the span and the text length, not the text', () {
    expect(_chunk.toJson(), <String, Object?>{
      'chunkId': 'doc-1',
      'textLength': 2,
      'pageNumber': 1,
      'startOffset': 0,
      'endOffset': 2,
      'textUnit': 'utf16CodeUnit',
      'chunkerVersion': 'w3-1',
    });
    expect(_chunk.toJson().containsKey('text'), isFalse);
  });

  test('a missing page stays null in json and in toString', () {
    const TextChunk noPage = TextChunk(
      chunkId: 'doc-1',
      text: '页码',
      startOffset: 0,
      endOffset: 2,
      textUnit: TextUnit.utf16CodeUnit,
      chunkerVersion: 'w3-1',
    );
    expect(noPage.toJson()['pageNumber'], isNull);
    expect(
      noPage.toString(),
      'TextChunk(doc-1, page: null, 0:2 utf16CodeUnit)',
    );
  });

  test('equal chunks share a hashCode', () {
    expect(_chunk, _same);
    expect(_chunk.hashCode, _same.hashCode);
  });

  test('a different field or a different type is not equal', () {
    expect(_chunk == Object(), isFalse);
    expect(
      _chunk ==
          const TextChunk(
            chunkId: 'doc-1',
            text: '别的',
            startOffset: 0,
            endOffset: 2,
            textUnit: TextUnit.utf16CodeUnit,
            chunkerVersion: 'w3-1',
            pageNumber: 1,
          ),
      isFalse,
    );
  });

  test('toString shows the page and the half-open span', () {
    expect(_chunk.toString(), 'TextChunk(doc-1, page: 1, 0:2 utf16CodeUnit)');
  });
}
