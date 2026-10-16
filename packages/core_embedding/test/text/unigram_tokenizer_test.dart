import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

import 'toy_tokenizer.dart';

void main() {
  final UnigramTokenizer tokenizer = toyTokenizer();

  test('a word becomes one metaspace piece between the boundary tokens', () {
    final TokenEncoding encoding = tokenizer.encode('a');
    expect(encoding.ids, <int>[0, 5, 2]);
    expect(encoding.tokens, <String>['<s>', '▁a', '</s>']);
  });

  test('a second character that is not glued to the prefix stays its own piece', () {
    final TokenEncoding encoding = tokenizer.encode('ab');
    expect(encoding.ids, <int>[0, 5, 6, 2]);
    expect(encoding.tokens, <String>['<s>', '▁a', 'b', '</s>']);
  });

  test('whitespace-only text keeps the boundary tokens and drops the spaces', () {
    expect(tokenizer.encode('  \n').ids, <int>[0, 2]);
    expect(tokenizer.encode('').ids, <int>[0, 2]);
  });

  test('a literal unk marker is the added token, not a metaspace piece', () {
    final TokenEncoding encoding = tokenizer.encode('a<unk>b');
    expect(encoding.ids, <int>[0, 5, 3, 4, 6, 2]);
    expect(encoding.tokens[2], '<unk>');
  });

  test('mask lstrip eats the spaces in front of the marker', () {
    final TokenEncoding encoding = tokenizer.encode('  <mask>');
    expect(encoding.ids, <int>[0, 7, 2]);
    expect(encoding.tokens, <String>['<s>', '  <mask>', '</s>']);
  });

  test('## is one ordinary piece, not a WordPiece continuation', () {
    final TokenEncoding encoding = tokenizer.encode('##');
    expect(encoding.ids, <int>[0, 8, 2]);
    expect(encoding.tokens, <String>['<s>', '▁##', '</s>']);
  });

  test('explicit truncation keeps the closing special token', () {
    final TokenEncoding full = tokenizer.encode('a a a a');
    expect(full.ids, <int>[0, 5, 5, 5, 5, 2]);
    final TokenEncoding truncated = tokenizer.encode('a a a a', truncateTo: 4);
    expect(truncated.ids, <int>[0, 5, 5, 2]);
    expect(truncated.tokens.last, '</s>');
  });

  test('an unknown character keeps its surface and uses the unk id', () {
    final TokenEncoding encoding = tokenizer.encode('\u0378');
    expect(encoding.ids, <int>[0, 4, 3, 2]);
    expect(encoding.tokens[2], '\u0378');
  });

  test('two unknown characters fuse into one unk piece', () {
    final TokenEncoding encoding = tokenizer.encode('\u0378\u0378');
    expect(encoding.ids, <int>[0, 4, 3, 2]);
    expect(encoding.tokens[2], '\u0378\u0378');
  });

  test('jsonDecode lists are accepted, including an integer score', () {
    const String jsonText = '''
{"model":{"type":"Unigram","unk_id":3,"vocab":[["<s>",0],["<pad>",0],["</s>",0],["<unk>",0],["▁",-1],["▁a",-0.1]]},"added_tokens":[{"id":0,"content":"<s>","special":true},{"id":1,"content":"<pad>","special":true},{"id":2,"content":"</s>","special":true},{"id":3,"content":"<unk>","special":true}]}
''';
    final UnigramTokenizer parsed = UnigramTokenizer.fromJsonString(jsonText);
    expect(parsed.encode('a').ids, <int>[0, 5, 2]);
    expect(parsed.normalize('A'), 'A');
  });

  test('a tokenizer that is not Unigram is rejected', () {
    expect(
      () => UnigramTokenizer.fromJsonString('{"model":{"type":"BPE"}}'),
      throwsFormatException,
    );
  });

  test('an added token that asks to be normalized is rejected', () {
    expect(
      () => UnigramTokenizer(
        pieces: const <(String, double)>[
          ('<s>', 0),
          ('<pad>', 0),
          ('</s>', 0),
          ('<unk>', 0),
        ],
        unkId: 3,
        addedTokens: <AddedToken>[
          AddedToken(content: '<s>', id: 0, special: true),
          AddedToken(content: '<pad>', id: 1, special: true),
          AddedToken(content: '</s>', id: 2, special: true),
          AddedToken(content: '<unk>', id: 3, special: true),
          AddedToken(content: '<mask>', id: 4, normalized: true),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('an added token with empty content is rejected', () {
    expect(() => AddedToken(content: '', id: 4), throwsArgumentError);
    const String jsonText = '''
{"model":{"type":"Unigram","unk_id":0,"vocab":[["<s>",0],["<pad>",0],["</s>",0]]},"added_tokens":[{"id":0,"content":"<s>"},{"id":1,"content":"<pad>"},{"id":2,"content":"</s>"},{"id":3,"content":""}]}
''';
    expect(
      () => UnigramTokenizer.fromJsonString(jsonText),
      throwsArgumentError,
    );
  });

  test('an empty metaspace is rejected', () {
    expect(
      () => UnigramTokenizer(
        pieces: const <(String, double)>[
          ('<s>', 0),
          ('<pad>', 0),
          ('</s>', 0),
          ('<unk>', 0),
        ],
        unkId: 3,
        addedTokens: <AddedToken>[
          AddedToken(content: '<s>', id: 0, special: true),
          AddedToken(content: '<pad>', id: 1, special: true),
          AddedToken(content: '</s>', id: 2, special: true),
          AddedToken(content: '<unk>', id: 3, special: true),
        ],
        metaspace: '',
      ),
      throwsArgumentError,
    );
  });

  test('truncation must keep both boundary tokens', () {
    expect(() => tokenizer.encode('a', truncateTo: 1), throwsArgumentError);
  });
}
