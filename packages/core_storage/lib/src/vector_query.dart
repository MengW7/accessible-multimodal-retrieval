import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:sqlite3/sqlite3.dart';

import 'filter_sql.dart';
import 'float_blob.dart';
import 'model/scored_id.dart';
import 'model/storage_failure.dart';
import 'model/storage_filter.dart';
import 'row_map.dart';

/// 展示列。第二阶段才读，避免在打分扫描里搬运 `body` 这类大列。
const String _displayColumns = '''
  id, document_id, chunk_id, relative_path, document_key, file_name,
  extension, mime_type, page_number, chunk_index, start_offset,
  end_offset, body, modality, image_json
''';

/// 打分阶段只读的列。`vec` 是唯一的 BLOB；tie-break 需要的文本列留到
/// 候选回表时再读，避免为 10k 行各分配一次 `relative_path`。
const String _scanColumns = 'id, vec';

/// 候选回表列：tie-break 需要的四个字段。
const String _candidateColumns =
    'id, relative_path, page_number, start_offset';

/// 阶段一的生产语句。`capacity_probe` 拿同一份字符串做
/// `EXPLAIN QUERY PLAN`，保证解释的就是实际执行的 SQL。
///
/// 参数顺序：`space`、`dim`，随后是过滤条件自带的值。
String vectorScanSql(StorageFilter? filter) {
  final SqlClause extra = filterClause(filter);
  final String where = extra.sql.isEmpty ? '' : ' AND ${extra.sql}';
  return 'SELECT $_scanColumns FROM chunk '
      'WHERE space = ? AND dim = ?$where';
}

/// 候选回表语句。[count] 是候选行数。
String vectorCandidateSql(int count) {
  final String marks = List<String>.filled(count, '?').join(', ');
  return 'SELECT $_candidateColumns FROM chunk WHERE id IN ($marks)';
}

/// 阶段二按主键回表取展示列的生产语句。[count] 是阶段一选出的行数。
String vectorDisplaySql(int count) {
  final String marks = List<String>.filled(count, '?').join(', ');
  return 'SELECT $_displayColumns FROM chunk WHERE id IN ($marks)';
}

/// 生产扫描语句的 `EXPLAIN QUERY PLAN`，参数与 [cosineTopK] 的实际调用一致。
///
/// 专门给容量探针用：解释的必须是真正执行的那条 SQL，而不是另抄一份。
List<String> explainVectorScan(
  Database database,
  EmbeddingVector query, {
  StorageFilter? filter,
}) {
  final SqlClause extra = filterClause(filter);
  final ResultSet plan = database.select(
    'EXPLAIN QUERY PLAN ${vectorScanSql(filter)}',
    <Object?>[query.space.name, query.dim, ...extra.args],
  );
  return <String>[
    for (final Row row in plan) row.values.map((Object? value) => '$value').join('|'),
  ];
}

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

  // Stream vector rows so a query does not retain all BLOBs at once.
  final PreparedStatement statement = database.prepare(vectorScanSql(filter));
  final Float32List queryValues = Float32List.fromList(query.values);
  final List<(int, double)> scored = <(int, double)>[];
  var threshold = double.negativeInfinity;
  var improved = 0;
  try {
    final cursor = statement.selectCursor(
      <Object?>[space, query.dim, ...extra.args],
    );
    while (cursor.moveNext()) {
      final Row row = cursor.current;
      final Uint8List blob = blobOf(row, 'vec');
      final double score = dotFloat32(float32View(blob, query.dim), queryValues);
      if (score < threshold) {
        continue;
      }
      scored.add((row.columnAt(0) as int, score));
      // Equal scores cannot raise the cutoff. Re-sorting the growing list
      // on each of them makes an otherwise linear scan quadratic.
      if (score > threshold && ++improved > topK * 4) {
        scored.sort(((int, double) a, (int, double) b) => b.$2.compareTo(a.$2));
        threshold = scored[topK - 1].$2;
        final int keep = scored.indexWhere(
          ((int, double) item) => item.$2 < threshold,
        );
        if (keep > 0) {
          scored.removeRange(keep, scored.length);
        }
        improved = 0;
      }
    }
  } finally {
    statement.dispose();
  }

  // The retained candidates include every cutoff tie. Fetch metadata in
  // batches and retain the best K so a large tie does not hit SQLite's
  // parameter limit or materialize all candidate metadata at once.
  final List<ScoredCandidate> candidates = <ScoredCandidate>[];
  for (var start = 0; start < scored.length; start += _lookupBatch) {
    final int end = _batchEnd(start, scored.length);
    candidates.addAll(_candidates(database, scored.getRange(start, end)));
    candidates.sort(ScoredCandidate.compareTie);
    if (candidates.length > topK) {
      candidates.removeRange(topK, candidates.length);
    }
  }

  // Only the final hits need display columns.
  return _display(database, candidates);
}

const int _lookupBatch = 512;

int _batchEnd(int start, int length) =>
    start + _lookupBatch < length ? start + _lookupBatch : length;

Iterable<ScoredCandidate> _candidates(
  Database database,
  Iterable<(int, double)> scored,
) sync* {
  final Map<int, double> scoreById = <int, double>{
    for (final (int rowId, double score) in scored) rowId: score,
  };
  final ResultSet rows = database.select(
    vectorCandidateSql(scoreById.length),
    scoreById.keys.toList(growable: false),
  );
  for (final Row row in rows) {
    final int rowId = row.columnAt(0) as int;
    yield ScoredCandidate(
      rowId: rowId,
      relativePath: row.columnAt(1) as String,
      pageNumber: row.columnAt(2) as int?,
      startOffset: row.columnAt(3) as int,
      score: scoreById[rowId]!,
    );
  }
}

/// 按 [selected] 给的名次回填展示列。`IN (...)` 不保证顺序，因此这里
/// 以 `chunk.id` 建表后按名次重排。
List<ScoredId> _display(Database database, List<ScoredCandidate> selected) {
  if (selected.isEmpty) {
    return const <ScoredId>[];
  }
  final Map<int, ScoredId> byId = <int, ScoredId>{};
  for (var start = 0; start < selected.length; start += _lookupBatch) {
    final int end = _batchEnd(start, selected.length);
    final Map<int, double> scoreById = <int, double>{
      for (final ScoredCandidate candidate in selected.getRange(start, end))
        candidate.rowId: candidate.score,
    };
    final ResultSet rows = database.select(
      vectorDisplaySql(scoreById.length),
      scoreById.keys.toList(growable: false),
    );
    for (final Row row in rows) {
      final int rowId = rowIdOf(row);
      byId[rowId] = scoredFromRow(row, scoreById[rowId]!);
    }
  }
  return <ScoredId>[
    for (final ScoredCandidate candidate in selected)
      if (byId[candidate.rowId] case final ScoredId hit) hit,
  ];
}
