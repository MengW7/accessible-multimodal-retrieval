import 'package:core_embedding/core_embedding.dart';

/// 一个不读模型文件的 Unigram。`a` 是一整片，`b` 要跟在 `▁` 后面另成一片。
UnigramTokenizer toyTokenizer() {
  return UnigramTokenizer(
    pieces: <(String, double)>[
      ('<s>', 0),
      ('<pad>', 0),
      ('</s>', 0),
      ('<unk>', 0),
      ('▁', -1),
      ('▁a', -0.1),
      ('b', -0.2),
      ('<mask>', 0),
      ('▁##', -0.3),
    ],
    unkId: 3,
    addedTokens: const <AddedToken>[
      AddedToken(content: '<s>', id: 0, special: true),
      AddedToken(content: '<pad>', id: 1, special: true),
      AddedToken(content: '</s>', id: 2, special: true),
      AddedToken(content: '<unk>', id: 3, special: true),
      AddedToken(content: '<mask>', id: 7, special: true, lstrip: true),
    ],
  );
}
