import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:sqlite3/sqlite3.dart';

import 'filter_sql.dart';
import 'float_blob.dart';
import 'model/scored_id.dart';
import 'model/storage_failure.dart';
import 'model/storage_filter.dart';
import 'row_map.dart';

List<ScoredId> cosineTopK(
  Database database,
  EmbeddingVector query, {
  StorageFilter? filter,
  int topK = 50,
}) {
  if (!query.normalized) {
    throw const StorageException(
      StorageFailure(
        kind: StorageFailureKind.notNormalized,
        message: 'Query vectors must already be L2-normalized.',
      ),
    );
  }
  if (topK < 1) {
    throw ArgumentError.value(topK, 'topK', 'must be positive');
  }
  final String space = query.space.name;
  final ResultSet dims = database.select(
    'SELECT DISTINCT dim FROM chunk WHERE space = ?',
    <Object?>[space],
  );
  if (dims.isEmpty) {
    return const <ScoredId>[];
  }
  final Object? storedDim = dims.first.columnAt(0);
  if (dims.length != 1 || storedDim is! int || storedDim != query.dim) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.dimensionMismatch,
        message: 'Space $space is not stored at dim ${query.dim}.',
      ),
    );
  }
  final SqlClause extra = filterClause(filter);
  final String where = extra.sql.isEmpty ? '' : ' AND ${extra.sql}';
  final ResultSet rows = database.select(
    '''
    SELECT id, document_id, chunk_id, relative_path, document_key, file_name,
           extension, mime_type, page_number, chunk_index, start_offset,
           end_offset, body, modality, image_json, vec
    FROM chunk
    WHERE space = ? AND dim = ?$where
    ''',
    <Object?>[space, query.dim, ...extra.args],
  );
  final List<ScoredId> scored = <ScoredId>[];
  for (final Row row in rows) {
    final Uint8List blob = blobOf(row, 'vec');
    final Float32List values = floatsFromBlob(blob, query.dim);
    scored.add(scoredFromRow(row, dot(values, query.values)));
  }
  scored.sort(ScoredId.compareTie);
  if (scored.length <= topK) {
    return scored;
  }
  return scored.sublist(0, topK);
}
