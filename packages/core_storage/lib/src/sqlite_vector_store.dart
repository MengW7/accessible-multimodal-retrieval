import 'package:core_embedding/core_embedding.dart';
import 'package:sqlite3/sqlite3.dart';

import 'index_generation.dart';
import 'keyword_index.dart';
import 'maintenance.dart';
import 'model/index_generation.dart';
import 'model/index_stats.dart';
import 'model/scored_id.dart';
import 'model/storage_filter.dart';
import 'model/stored_chunk.dart';
import 'row_map.dart';
import 'schema.dart';
import 'vector_query.dart';
import 'vector_store.dart';
import 'vector_writer.dart';

final class SqliteVectorStore implements VectorStore {
  SqliteVectorStore(this._database);

  final Database _database;

  Database get database => _database;

  @override
  Future<WriteOutcome> write(
    Iterable<StoredChunk> chunks,
    Iterable<EmbeddingVector> vectors,
  ) async {
    return writeChunks(database, chunks.toList(growable: false), vectors.toList(growable: false));
  }

  @override
  Future<List<ScoredId>> search(
    EmbeddingVector query, {
    StorageFilter? filter,
    int topK = 50,
  }) async {
    return cosineTopK(database, query, filter: filter, topK: topK);
  }

  @override
  Future<List<ScoredId>> keyword(
    String query, {
    StorageFilter? filter,
    int topK = 50,
  }) async {
    return keywordTopK(database, query, filter: filter, topK: topK);
  }

  @override
  Future<List<StoredChunk>> chunksForDocument(String documentId) async {
    final ResultSet rows = database.select(
      '''
      SELECT id, document_id, chunk_id, relative_path, document_key, file_name,
             extension, mime_type, page_number, chunk_index, start_offset,
             end_offset, body, modality, image_json, modified_at, content_hash,
             parser_name, parser_version, chunker_version
      FROM chunk
      WHERE document_id = ?
      ORDER BY page_number IS NULL, page_number, chunk_index, start_offset
      ''',
      <Object?>[documentId],
    );
    return <StoredChunk>[for (final Row row in rows) chunkFromRow(row)];
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    database.execute('BEGIN');
    try {
      deleteDocumentRows(database, documentId);
      database.execute('COMMIT');
    } catch (error) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    database.execute('BEGIN');
    try {
      clearRows(database);
      database.execute('COMMIT');
    } catch (error) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<IndexStats> stats() async => readStats(database);

  @override
  Future<bool> canReuse(IndexGeneration generation) async {
    return generationMatches(database, generation);
  }

  bool _closed = false;

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    database.dispose();
  }
}

/// 给已经打开、但还没建表的连接补上 schema。打开失败不在这里处理。
void prepareDatabase(Database database, {required bool wal}) {
  applySchema(database);
  if (wal) {
    database.execute('PRAGMA journal_mode = WAL');
  }
}
