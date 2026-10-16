import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';

import '../model/embedding_space.dart';
import '../model/embedding_vector.dart';
import '../model/model_info.dart';
import '../spi/embedding_runtime.dart';
import 'text_input_builder.dart';
import 'unigram_tokenizer.dart';

/// ADR 0003 冻结的文档文本模型。图内不归一化，交出前由 [TextEmbedder] 做 L2。
const ModelInfo documentTextModel = ModelInfo(
  modelId: 'paraphrase-multilingual-MiniLM-L12-v2',
  space: EmbeddingSpace.documentText,
  dim: 384,
  pooling: 'mean',
  normalized: true,
  maxInputLength: 128,
);

/// 句子加上特殊标记后超过 [ModelInfo.maxInputLength]。
///
/// 这是重切信号。不返回被截断的向量。
class TextOverBudgetException implements Exception {
  const TextOverBudgetException({required this.tokenCount, required this.maxLength});

  final int tokenCount;

  final int maxLength;

  @override
  String toString() =>
      'TextOverBudgetException: $tokenCount tokens exceed maxLength $maxLength.';
}

/// 文档文本向量。
///
/// 运行时交回展平的 `last_hidden_state`。这里按 attention mask 做 mean
/// pooling，再做 L2，并把 [EmbeddingVector.normalized] 设为 true。
/// 运行时不具备、缺张量、超时、维度不符都原样抛出，不换成空向量。
final class TextEmbedder {
  TextEmbedder({
    required this.model,
    required UnigramTokenizer tokenizer,
    required this.runtime,
    TextInputBuilder? inputs,
  }) : _inputs =
           inputs ??
           TextInputBuilder(
             tokenizer: tokenizer,
             maxLength: model.maxInputLength ?? 0,
           ) {
    if (model.pooling != 'mean') {
      throw ArgumentError.value(model.pooling, 'model.pooling', 'TextEmbedder pools by mean.');
    }
    final int? maxLength = model.maxInputLength;
    if (maxLength == null || maxLength < 2) {
      throw ArgumentError.value(maxLength, 'model.maxInputLength', 'must be at least 2');
    }
  }

  final ModelInfo model;

  final EmbeddingRuntime runtime;

  final TextInputBuilder _inputs;

  /// 对 [text] 出一条向量。[text] 不能是空串。
  ///
  /// 超长抛 [TextOverBudgetException]。已取消抛 [CancelledException]。
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
    final TextInputResult built = _inputs.build(text);
    if (built is TextInputNeedsRechunk) {
      throw TextOverBudgetException(
        tokenCount: built.tokenCount,
        maxLength: built.maxLength,
      );
    }
    if (built is! TextInputTensors) {
      throw StateError('Unexpected text input result ${built.runtimeType}.');
    }
    cancel?.throwIfCancelled();
    final Float32List hidden = await runtime.run(model.modelId, built.tensors);
    cancel?.throwIfCancelled();
    final Int64List mask = _maskOf(built);
    final List<double> pooled = meanPool(hidden, mask, model.dim);
    final List<double> values = l2Normalize(pooled);
    return EmbeddingVector(
      values: values,
      space: model.space,
      dim: model.dim,
      modelId: model.modelId,
      normalized: true,
      chunkId: chunkId,
    );
  }

  /// 对 [hidden] 按 [mask] 做 mean。pad 位置不进平均。
  ///
  /// [hidden] 的长度必须是 `mask.length * dim`。全 0 的 mask 抛
  /// [BadOutputException]。
  static List<double> meanPool(List<double> hidden, List<int> mask, int dim) {
    if (dim <= 0) {
      throw ArgumentError.value(dim, 'dim', 'must be positive');
    }
    if (hidden.length != mask.length * dim) {
      throw DimensionMismatchException(
        'Hidden length ${hidden.length} is not ${mask.length} * $dim.',
      );
    }
    final List<double> sum = List<double>.filled(dim, 0);
    var counted = 0;
    for (var row = 0; row < mask.length; row++) {
      if (mask[row] == 0) {
        continue;
      }
      final int offset = row * dim;
      for (var column = 0; column < dim; column++) {
        final double value = hidden[offset + column];
        if (!value.isFinite) {
          throw const BadOutputException('Hidden state has a non-finite value.');
        }
        sum[column] += value;
      }
      counted += 1;
    }
    if (counted == 0) {
      throw const BadOutputException('Attention mask is empty.');
    }
    for (var column = 0; column < dim; column++) {
      sum[column] /= counted;
    }
    return sum;
  }

  /// 把 [vector] 变成 L2 范数为 1 的向量。范数为 0 或结果非有限时抛
  /// [BadOutputException]。
  static List<double> l2Normalize(List<double> vector) {
    if (vector.isEmpty) {
      throw const BadOutputException('Cannot normalize an empty vector.');
    }
    var square = 0.0;
    for (final double value in vector) {
      if (!value.isFinite) {
        throw const BadOutputException('Vector has a non-finite value.');
      }
      square += value * value;
    }
    final double norm = math.sqrt(square);
    if (norm == 0 || !norm.isFinite) {
      throw const BadOutputException('Vector L2 norm is zero.');
    }
    return <double>[for (final double value in vector) value / norm];
  }

  Int64List _maskOf(TextInputTensors built) {
    final TypedData data = built.tensors['attention_mask']!.data;
    if (data is! Int64List) {
      throw const MissingTensorException('attention_mask is not int64.');
    }
    return data;
  }
}
