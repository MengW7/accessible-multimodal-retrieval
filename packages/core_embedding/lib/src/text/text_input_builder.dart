import 'dart:typed_data';

import '../spi/embedding_runtime.dart';
import 'unigram_tokenizer.dart';

/// 输入没有超过模型长度，三份张量都已经补到 [TextInputTensors.maxLength]。
final class TextInputTensors extends TextInputResult {
  const TextInputTensors({
    required this.tensors,
    required this.ids,
    required this.tokens,
    required this.maxLength,
  });

  /// `input_ids`、`attention_mask`、`token_type_ids`。形状都是 `[1, maxLength]`。
  final Map<String, Tensor> tensors;

  /// 补 pad 之前的 id，含 `<s>` 和 `</s>`。
  final List<int> ids;

  final List<String> tokens;

  final int maxLength;
}

/// 整句加上特殊标记之后长于模型上限。调用方要重切，不能拿这里的 id 去推理。
final class TextInputNeedsRechunk extends TextInputResult {
  const TextInputNeedsRechunk({
    required this.tokenCount,
    required this.maxLength,
  });

  final int tokenCount;

  final int maxLength;
}

/// [TextInputBuilder.build] 的两种结果。超长是一个结果，不是截断后的张量。
sealed class TextInputResult {
  const TextInputResult();
}

// 测试会继承这个类，把 attention mask 换成非 Int64List。
/// 把一句正文变成 MiniLM 的三份 int64 输入。
///
/// 长度不到 [maxLength] 时右侧补 `<pad>`，attention 为 0，token type 为 0。
/// 长度超过 [maxLength] 时返回 [TextInputNeedsRechunk]，不改写 id。
class TextInputBuilder {
  TextInputBuilder({required this.tokenizer, required this.maxLength}) {
    if (maxLength < 2) {
      throw ArgumentError.value(maxLength, 'maxLength', 'must be at least 2');
    }
  }

  final UnigramTokenizer tokenizer;

  final int maxLength;

  TextInputResult build(String text) {
    final TokenEncoding encoding = tokenizer.encode(text);
    if (encoding.length > maxLength) {
      return TextInputNeedsRechunk(
        tokenCount: encoding.length,
        maxLength: maxLength,
      );
    }
    final Int64List ids = Int64List(maxLength);
    final Int64List mask = Int64List(maxLength);
    final Int64List types = Int64List(maxLength);
    for (var i = 0; i < encoding.length; i++) {
      ids[i] = encoding.ids[i];
      mask[i] = 1;
    }
    for (var i = encoding.length; i < maxLength; i++) {
      ids[i] = tokenizer.padId;
    }
    return TextInputTensors(
      tensors: <String, Tensor>{
        'input_ids': Tensor(
          dtype: TensorDType.int64,
          shape: <int>[1, maxLength],
          data: ids,
        ),
        'attention_mask': Tensor(
          dtype: TensorDType.int64,
          shape: <int>[1, maxLength],
          data: mask,
        ),
        'token_type_ids': Tensor(
          dtype: TensorDType.int64,
          shape: <int>[1, maxLength],
          data: types,
        ),
      },
      ids: encoding.ids,
      tokens: encoding.tokens,
      maxLength: maxLength,
    );
  }
}
