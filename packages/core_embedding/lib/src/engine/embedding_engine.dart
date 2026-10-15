import 'package:core_parsing/core_parsing.dart';

import '../model/embedding_input.dart';
import '../model/embedding_space.dart';
import '../model/embedding_vector.dart';
import '../model/model_info.dart';

/// 一次调用混用了两个向量空间。
///
/// 文本空间和 MobileCLIP 空间不能比较，也不能当成同一次 `embed` 的两侧。
/// 实现必须抛这个异常，不能靠文档约定。
class EmbeddingSpaceMismatchException implements Exception {
  const EmbeddingSpaceMismatchException({
    required this.requested,
    required this.actual,
    this.message = 'Embedding spaces cannot be mixed.',
  });

  final EmbeddingSpace requested;

  final EmbeddingSpace actual;

  final String message;

  @override
  String toString() =>
      'EmbeddingSpaceMismatchException: $message '
      '(requested: ${requested.name}, actual: ${actual.name})';
}

/// 文本和图像共用的入口。
///
/// 图像输入的空间必须是 [EmbeddingSpace.clipShared]。文本输入用
/// [EmbeddingSpace.documentText] 走文档模型，用 [EmbeddingSpace.clipShared]
/// 走 MobileCLIP 文本塔。空间和模型不一致时抛
/// [EmbeddingSpaceMismatchException]。
abstract interface class EmbeddingEngine {
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  });

  List<ModelInfo> get models;
}
