import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';

import '../model/embedding_space.dart';
import '../model/embedding_vector.dart';
import '../model/model_info.dart';
import '../spi/embedding_runtime.dart';
import 'clip_bpe_tokenizer.dart';
import 'text_embedder.dart';
import 'unigram_tokenizer.dart';

/// ADR 0003 冻结的 MobileCLIP-S0 文本塔。和图像塔同一个 `clipShared` 空间。
///
/// 图只收 `input_ids`，没有 attention mask。不足 77 用 `!` 的 id 补齐。
/// 超过 77 不截断。交出前做 L2。
const ModelInfo clipTextModel = ModelInfo(
  modelId: 'mobileclip-s0-text',
  space: EmbeddingSpace.clipShared,
  dim: 512,
  pooling: 'none',
  normalized: true,
  maxInputLength: 77,
);

/// 用来查图的自然语言。不要拿它和 384 维的文档向量比。
final class ClipTextEmbedder {
  ClipTextEmbedder({
    required this.model,
    required this._tokenizer,
    required this.runtime,
  }) {
    if (model.space != EmbeddingSpace.clipShared) {
      throw ArgumentError.value(
        model.space,
        'model.space',
        'CLIP text embeddings use EmbeddingSpace.clipShared.',
      );
    }
    if (model.pooling != 'none') {
      throw ArgumentError.value(model.pooling, 'model.pooling', 'ClipTextEmbedder does not pool.');
    }
    final int? maxLength = model.maxInputLength;
    if (maxLength == null || maxLength < 2) {
      throw ArgumentError.value(maxLength, 'model.maxInputLength', 'must be at least 2');
    }
  }

  final ModelInfo model;

  final EmbeddingRuntime runtime;

  final ClipBpeTokenizer _tokenizer;

  /// [text] 不能是空串。超长抛 [TextOverBudgetException]。
  Future<EmbeddingVector> embed(
    String text, {
    String? chunkId,
    CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    if (text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
    if (chunkId == '') {
      throw ArgumentError.value(chunkId, 'chunkId', 'must be null or non-empty');
    }
    if (!runtime.isAvailable) {
      throw const RuntimeUnavailableException('Embedding runtime is not available.');
    }
    final int maxLength = model.maxInputLength!;
    final TokenEncoding encoding = _tokenizer.encode(text);
    if (encoding.ids.length > maxLength) {
      throw TextOverBudgetException(tokenCount: encoding.ids.length, maxLength: maxLength);
    }
    final Int64List ids = Int64List(maxLength);
    for (var i = 0; i < encoding.ids.length; i++) {
      ids[i] = encoding.ids[i];
    }
    for (var i = encoding.ids.length; i < maxLength; i++) {
      ids[i] = _tokenizer.padId;
    }
    cancel?.throwIfCancelled();
    final Float32List raw = await runtime.run(model.modelId, <String, Tensor>{
      'input_ids': Tensor(
        dtype: TensorDType.int64,
        shape: <int>[1, maxLength],
        data: ids,
      ),
    });
    cancel?.throwIfCancelled();
    if (raw.length != model.dim) {
      throw DimensionMismatchException(
        'text_embeds length ${raw.length} is not ${model.dim}.',
      );
    }
    return EmbeddingVector(
      values: TextEmbedder.l2Normalize(raw),
      space: model.space,
      dim: model.dim,
      modelId: model.modelId,
      normalized: true,
      chunkId: chunkId,
    );
  }
}
