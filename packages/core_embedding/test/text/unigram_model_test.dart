import 'package:core_embedding/src/text/unigram_model.dart';
import 'package:test/test.dart';

void main() {
  final UnigramModel model = UnigramModel(
    pieces: <(String, double)>[
      ('<unk>', 0),
      ('a', 0),
      ('b', 0),
      ('c', 0),
      ('d', 0),
      ('cd', 1),
      ('ab', 2),
      ('abc', 5),
      ('abcd', 10),
    ],
    unkId: 0,
  );

  test('the highest score keeps the whole string', () {
    expect(
      model.encode('abcd').map((UnigramToken token) => token.text),
      <String>['abcd'],
    );
  });

  test('unknown bytes stay as one fused surface with the unk id', () {
    final List<UnigramToken> tokens = model.encode('abcdacdxx');
    expect(
      tokens.map((UnigramToken token) => token.text),
      <String>['abcd', 'a', 'cd', 'xx'],
    );
    expect(tokens.last.id, 0);
    expect(tokens.first.id, 8);
  });

  test('an empty piece has no tokens', () {
    expect(model.encode(''), isEmpty);
  });

  test('unk id outside the vocab is rejected', () {
    expect(
      () => UnigramModel(pieces: <(String, double)>[('a', 0)], unkId: 3),
      throwsArgumentError,
    );
  });
}
