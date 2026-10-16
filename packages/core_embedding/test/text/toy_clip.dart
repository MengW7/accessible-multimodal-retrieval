import 'package:core_embedding/core_embedding.dart';

/// 一个不读 tokenizer.json 的 CLIP BPE。`hi` 合成一片，分开的 `h` 和 `i` 不合并。
ClipBpeTokenizer toyClipTokenizer() {
  return ClipBpeTokenizer(
    vocab: const <String, int>{
      'h': 0,
      'i': 1,
      'h</w>': 2,
      'i</w>': 3,
      'hi</w>': 4,
      '!': 5,
      '<|startoftext|>': 10,
      '<|endoftext|>': 11,
    },
    merges: const <String>['h i</w>'],
    bosId: 10,
    eosId: 11,
    padId: 5,
    unkId: 11,
  );
}
