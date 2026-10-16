import 'package:meta/meta.dart';

import 'embedding_space.dart';

/// 一个已冻结模型的调用侧描述。
///
/// 权重路径、校验和和转换余弦不在这里。那些写在 `models/README.md`，避免
/// 把本机路径编进包。
@immutable
class ModelInfo {
  const ModelInfo({
    required this.modelId,
    required this.space,
    required this.dim,
    required this.pooling,
    required this.normalized,
    this.maxInputLength,
    this.queryPrefix,
    this.documentPrefix,
  }) : assert(modelId != '', 'modelId must not be empty'),
       assert(dim > 0, 'dim must be positive'),
       assert(pooling != '', 'pooling must not be empty');

  final String modelId;

  final EmbeddingSpace space;

  final int dim;

  /// `mean` 或 `none`。图像塔如果图内已经投影好，记 `none`。
  final String pooling;

  final bool normalized;

  /// 文本模型的最大 token 数。图像模型为 null。
  final int? maxInputLength;

  /// 查询前缀。不需要前缀的模型为 null，不能用空字符串代替。
  final String? queryPrefix;

  /// 文档前缀。不需要前缀的模型为 null。
  final String? documentPrefix;

  Map<String, Object?> toJson() => <String, Object?>{
    'modelId': modelId,
    'space': space.name,
    'dim': dim,
    'pooling': pooling,
    'normalized': normalized,
    'maxInputLength': maxInputLength,
    'queryPrefix': queryPrefix,
    'documentPrefix': documentPrefix,
  };

  @override
  bool operator ==(Object other) =>
      other is ModelInfo &&
      other.modelId == modelId &&
      other.space == space &&
      other.dim == dim &&
      other.pooling == pooling &&
      other.normalized == normalized &&
      other.maxInputLength == maxInputLength &&
      other.queryPrefix == queryPrefix &&
      other.documentPrefix == documentPrefix;

  @override
  int get hashCode => Object.hash(
    modelId,
    space,
    dim,
    pooling,
    normalized,
    maxInputLength,
    queryPrefix,
    documentPrefix,
  );

  @override
  String toString() =>
      'ModelInfo($modelId, ${space.name}, dim: $dim, pooling: $pooling)';
}
