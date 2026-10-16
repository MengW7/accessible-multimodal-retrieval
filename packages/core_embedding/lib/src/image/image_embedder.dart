import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';

import '../model/embedding_space.dart';
import '../model/embedding_vector.dart';
import '../model/model_info.dart';
import '../spi/embedding_runtime.dart';
import '../text/text_embedder.dart';
import 'image_preprocess.dart';

/// ADR 0003 冻结的 MobileCLIP-S0 图像塔。
///
/// 图内输出 `image_embeds`，不做 L2。`normalized` 为 true 表示交给调用方的
/// 向量已经归一化。不加 mean/std。
const ModelInfo clipVisionModel = ModelInfo(
  modelId: 'mobileclip-s0-vision',
  space: EmbeddingSpace.clipShared,
  dim: 512,
  pooling: 'none',
  normalized: true,
);

/// 一张图出一条 `clipShared` 向量。
///
/// 运行时交回展平的 `image_embeds`。这里只做 L2。维度不符、运行时不可用、
/// 缺张量和超时都原样抛出。
final class ImageEmbedder {
  ImageEmbedder({
    required this.model,
    required this.runtime,
    ImagePreprocessor? preprocessor,
  }) : _preprocessor = preprocessor ?? const ImagePreprocessor() {
    if (model.space != EmbeddingSpace.clipShared) {
      throw ArgumentError.value(
        model.space,
        'model.space',
        'Image embeddings use EmbeddingSpace.clipShared.',
      );
    }
    if (model.pooling != 'none') {
      throw ArgumentError.value(model.pooling, 'model.pooling', 'ImageEmbedder does not pool.');
    }
  }

  final ModelInfo model;

  final EmbeddingRuntime runtime;

  final ImagePreprocessor _preprocessor;

  /// [bytes] 是行优先 RGB24，长度等于 `width * height * 3`。
  Future<EmbeddingVector> embed({
    required Uint8List bytes,
    required int width,
    required int height,
    CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    if (!runtime.isAvailable) {
      throw const RuntimeUnavailableException('Embedding runtime is not available.');
    }
    final PreprocessedImage prepared = _preprocessor.preprocess(
      rgb24: bytes,
      width: width,
      height: height,
    );
    cancel?.throwIfCancelled();
    final Float32List raw = await runtime.run(model.modelId, <String, Tensor>{
      'pixel_values': Tensor(
        dtype: TensorDType.float32,
        shape: prepared.shape,
        data: prepared.pixels,
      ),
    });
    cancel?.throwIfCancelled();
    if (raw.length != model.dim) {
      throw DimensionMismatchException(
        'image_embeds length ${raw.length} is not ${model.dim}.',
      );
    }
    return EmbeddingVector(
      values: TextEmbedder.l2Normalize(raw),
      space: model.space,
      dim: model.dim,
      modelId: model.modelId,
      normalized: true,
    );
  }
}
