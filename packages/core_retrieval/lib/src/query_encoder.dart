import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:meta/meta.dart';

/// 一次查询在两个空间里的向量。图像塔不可用时 [clip] 为 null。
@immutable
class QueryVectors {
  const QueryVectors({required this.text, required this.clip});

  /// 这次检索没有打开文档文本路时为 null。
  final EmbeddingVector? text;

  final EmbeddingVector? clip;
}

/// 一次搜索只编码两次：文档文本一次，MobileCLIP 文本塔一次。
///
/// 图像塔缺失或运行失败时降级成纯文本，不把这次搜索变成错误。
/// 取消请求原样抛出。
class QueryEncoder {
  const QueryEncoder(this.engine);

  final EmbeddingEngine engine;

  Future<QueryVectors> encode(
    String query, {
    bool includeDocumentText = true,
    bool includeClipText = true,
    CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    EmbeddingVector? text;
    if (includeDocumentText) {
      text = await engine.embed(EmbeddingInput.text(query), cancel: cancel);
    }
    EmbeddingVector? clip;
    if (includeClipText) {
      try {
        clip = await engine.embed(
          EmbeddingInput.text(query, space: EmbeddingSpace.clipShared),
          cancel: cancel,
        );
      } on EmbeddingSpaceMismatchException {
        clip = null;
      } on EmbeddingRuntimeException {
        clip = null;
      }
    }
    return QueryVectors(text: text, clip: clip);
  }
}
