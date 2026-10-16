import 'package:core_parsing/core_parsing.dart';

import '../model/embedding_report.dart';

/// 批量向量化。接口形状对齐 `IngestionService.ingestDirectory`。
///
/// 只消费 [IngestionReport.indexable]。单条失败写进 [EmbeddingReport]，
/// 不中断后面的文件。取消是协作式的，沿用 [CancellationToken]。
abstract interface class EmbeddingService {
  Future<EmbeddingReport> embedAll(
    IngestionReport ingestion, {
    void Function(EmbeddingProgress)? onProgress,
    CancellationToken? cancel,
  });
}
