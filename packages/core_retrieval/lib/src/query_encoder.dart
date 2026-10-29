import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_storage/core_storage.dart';
import 'package:meta/meta.dart';

/// 一次查询在两个空间里的向量。图像塔不可用时 [clip] 为 null。
@immutable
class QueryVectors {
  const QueryVectors({required this.text, required this.clip});

  /// 这次检索没有打开文档文本路时为 null。
  final EmbeddingVector? text;

  final EmbeddingVector? clip;
}

/// 问句超过了文本塔的 token 预算，无法编码。
///
/// 单独成一个类型，而不是把 `TextOverBudgetException` 透出去，是因为调用方
/// （W5 的界面）要能区分「问句太长」和「向量运行时坏了」：前者要提示用户
/// 缩短问句，后者要提示重试。两者都不可用同一条错误文案。
class QueryTooLongException implements Exception {
  const QueryTooLongException({
    required this.tokenCount,
    required this.maxLength,
    required this.query,
  });

  final int tokenCount;

  final int maxLength;

  final String query;

  @override
  String toString() =>
      'QueryTooLongException: query is $tokenCount tokens, limit is $maxLength.';
}

/// 一次搜索只编码两次：文档文本一次，MobileCLIP 文本塔一次。
///
/// 文档文本塔收到原问句。图像塔收到 [clipQueryText]：词表命中时是英文词，
/// 未命中时仍是原问句。图像塔缺失或运行失败时降级成纯文本，不把这次搜索变成错误。
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
      try {
        text = await engine.embed(EmbeddingInput.text(query), cancel: cancel);
      } on TextOverBudgetException catch (error) {
        // The text tower has a 128-token budget and, by design, does not
        // truncate: `TextEmbedder` raises instead of returning a half-sentence
        // vector. A query is user input, so "too long" must be a typed error
        // the caller can explain, not an unhandled crash deep inside search.
        throw QueryTooLongException(
          tokenCount: error.tokenCount,
          maxLength: error.maxLength,
          query: query,
        );
      }
    }
    EmbeddingVector? clip;
    if (includeClipText) {
      try {
        clip = await engine.embed(
          EmbeddingInput.text(
            clipQueryText(query),
            space: EmbeddingSpace.clipShared,
          ),
          cancel: cancel,
        );
      } on EmbeddingSpaceMismatchException {
        clip = null;
      } on EmbeddingRuntimeException {
        clip = null;
      } on TextOverBudgetException {
        // MobileCLIP's text tower pads to exactly 77 tokens and this encoder
        // does not truncate. A long query therefore exceeds the budget. That is
        // a property of the tower, not a failure of the search, so the image
        // channel is dropped and the text channel still answers. Without this
        // clause the exception escaped `search()` and a long query crashed
        // instead of degrading.
        clip = null;
      }
    }
    return QueryVectors(text: text, clip: clip);
  }
}
