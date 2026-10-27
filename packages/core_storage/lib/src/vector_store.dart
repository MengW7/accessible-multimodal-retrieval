import 'package:core_embedding/core_embedding.dart';

import 'model/index_generation.dart';
import 'model/index_stats.dart';
import 'model/scored_id.dart';
import 'model/storage_filter.dart';
import 'model/stored_chunk.dart';

/// 向量存储。写入、查询、删除、统计。不打分融合。
abstract interface class VectorStore {
  Future<WriteOutcome> write(
    Iterable<StoredChunk> chunks,
    Iterable<EmbeddingVector> vectors,
  );

  Future<List<ScoredId>> search(
    EmbeddingVector query, {
    StorageFilter? filter,
    int topK = 50,
  });

  Future<List<ScoredId>> keyword(
    String query, {
    StorageFilter? filter,
    int topK = 50,
  });

  Future<List<StoredChunk>> chunksForDocument(String documentId);

  Future<void> deleteDocument(String documentId);

  Future<void> clear();

  Future<IndexStats> stats();

  /// [IndexGeneration.sameRecipe] 的 6 个字段全等才返回 true。决策 4 把
  /// 解析器名和版本合成一项，称作五项。没有代次行时返回 false。
  Future<bool> canReuse(IndexGeneration generation);
}
