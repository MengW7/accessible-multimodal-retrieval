import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

import 'toy_tokenizer.dart';

void main() {
  final UnigramTokenizer tokenizer = toyTokenizer();

  test('short text is padded to maxLength and does not drop tokens', () {
    final TextInputResult result = TextInputBuilder(
      tokenizer: tokenizer,
      maxLength: 4,
    ).build('a');
    expect(result, isA<TextInputTensors>());
    final TextInputTensors tensors = result as TextInputTensors;
    expect(tensors.ids, <int>[0, 5, 2]);
    final Int64List ids = tensors.tensors['input_ids']!.data as Int64List;
    final Int64List mask = tensors.tensors['attention_mask']!.data as Int64List;
    final Int64List types = tensors.tensors['token_type_ids']!.data as Int64List;
    expect(ids, <int>[0, 5, 2, 1]);
    expect(mask, <int>[1, 1, 1, 0]);
    expect(types, <int>[0, 0, 0, 0]);
    expect(tensors.tensors['input_ids']!.shape, <int>[1, 4]);
  });

  test('text over the budget returns a rechunk signal and no tensor', () {
    final TextInputResult result = TextInputBuilder(
      tokenizer: tokenizer,
      maxLength: 4,
    ).build('a a a');
    expect(result, isA<TextInputNeedsRechunk>());
    final TextInputNeedsRechunk signal = result as TextInputNeedsRechunk;
    expect(signal.tokenCount, 5);
    expect(signal.maxLength, 4);
  });
}
