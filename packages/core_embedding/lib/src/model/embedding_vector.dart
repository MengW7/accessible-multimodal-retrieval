import 'package:meta/meta.dart';

import 'embedding_space.dart';

/// 一条自描述的向量。
///
/// [normalized] 必须写明。向量库存的是余弦还是内积，由这个字段决定，不能靠
/// 调用方记住。文本分块时 [chunkId] 指向对应 `TextChunk.chunkId`；整段查询或
/// 图像没有块时为 null。
@immutable
class EmbeddingVector {
  const EmbeddingVector({
    required this.values,
    required this.space,
    required this.dim,
    required this.modelId,
    required this.normalized,
    this.chunkId,
  }) : assert(dim == values.length, 'dim must match values.length'),
       assert(modelId != '', 'modelId must not be empty'),
       assert(dim > 0, 'dim must be positive');

  final List<double> values;

  final EmbeddingSpace space;

  final int dim;

  /// 训练好的模型名，不含本机路径。量化变体写在 `models/README.md`。
  final String modelId;

  final bool normalized;

  final String? chunkId;

  Map<String, Object?> toJson() => <String, Object?>{
    'space': space.name,
    'dim': dim,
    'modelId': modelId,
    'normalized': normalized,
    'chunkId': chunkId,
    'valuesHead': values.take(3).toList(growable: false),
  };

  @override
  bool operator ==(Object other) {
    if (other is! EmbeddingVector ||
        other.space != space ||
        other.dim != dim ||
        other.modelId != modelId ||
        other.normalized != normalized ||
        other.chunkId != chunkId ||
        other.values.length != values.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      if (other.values[i] != values[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    space,
    dim,
    modelId,
    normalized,
    chunkId,
    Object.hashAll(values),
  );

  @override
  String toString() =>
      'EmbeddingVector(${space.name}, dim: $dim, model: $modelId, '
      'normalized: $normalized)';
}
