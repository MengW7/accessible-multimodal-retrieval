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

  // 阶段一：只取 `id` 与 `vec` 打分。tie-break 需要的文本列在阶段二按
  // 候选回表，避免为 10k 行各分配一次 `relative_path`。
  //
  // 为了不把 10k 个候选都留在内存里，这里只保留「分数不低于当前第 topK 名」的
  // 候选。分数严格低于阈值的不可能进 Top-K（同分时靠 tie-break 决定，
  // 所以用 `>=` 而不是 `>`）。
  final ResultSet rows = database.select(
    vectorScanSql(filter),
    <Object?>[space, query.dim, ...extra.args],
  );
  final Float32List queryValues = Float32List.fromList(query.values);
  final List<(int, double)> scored = <(int, double)>[];
  var threshold = double.negativeInfinity;
  for (final Row row in rows) {
    final Uint8List blob = row.columnAt(1) as Uint8List;
    final Float32List values = float32View(blob, query.dim);
    final double score = dotFloat32(values, queryValues);
    // 只有「严格低于阈值」才安全丢弃：同分的行要靠 tie-break 定名次，
    // 提前扔掉同分行会让结果与全量排序不一致。收缩时同样保留同分边界。
    if (scored.length >= topK && score < threshold) {
      continue;
    }
    scored.add((row.columnAt(0) as int, score));
    if (scored.length > topK * 4) {
      // 收缩前的分数阈值：先按分数降序，找出第 topK 名的分数，把**所有**
      // 同分候选都留下来（它们的先后要由 tie-break 决定，不能在这里判断）。
      scored.sort(((int, double) a, (int, double) b) => b.$2.compareTo(a.$2));
      threshold = scored[topK - 1].$2;
      final int keep = scored.indexWhere(
        ((int, double) item) => item.$2 < threshold,
      );
      if (keep > 0) {
        scored.removeRange(keep, scored.length);
      }
    }
  }

  // 阶段二：候选回表补 tie-break 列，按 [_compare] 排序后取前 topK。
  final List<ScoredCandidate> candidates = _candidates(database, scored);
  // `_candidates` 在空输入上返回 `const []`。只有非空时才需要排序。
  if (candidates.length > 1) {
    candidates.sort(ScoredCandidate.compareTie);
  }
  final List<ScoredCandidate> selected = candidates.length <= topK
      ? candidates
      : candidates.sublist(0, topK);

  // 阶段三：只为选中的行回表取展示列，输出顺序沿用阶段二的名次。
  return _display(database, selected);
}

/// 为 [(rowId, score)] 回表补齐 tie-break 列。`IN (...)` 不保证顺序。
List<ScoredCandidate> _candidates(
  Database database,
  List<(int, double)> scored,
) {
  if (scored.isEmpty) {
    return const <ScoredCandidate>[];
  }
  final Map<int, double> scoreById = <int, double>{
    for (final (int rowId, double score) in scored) rowId: score,
  };
  final ResultSet rows = database.select(
    vectorCandidateSql(scored.length),
    <Object?>[for (final (int rowId, double _) in scored) rowId],
  );
  final List<ScoredCandidate> candidates = <ScoredCandidate>[];
  for (final Row row in rows) {
    final int rowId = row.columnAt(0) as int;
    final double? score = scoreById[rowId];
    if (score == null) {
      continue;
    }
    candidates.add(
      ScoredCandidate(
        rowId: rowId,
        relativePath: row.columnAt(1) as String,
        pageNumber: row.columnAt(2) as int?,
        startOffset: row.columnAt(3) as int,
        score: score,
      ),
    );
  }
  return candidates;
}

/// 按 [selected] 给的名次回填展示列。`IN (...)` 不保证顺序，因此这里
/// 以 `chunk.id` 建表后按名次重排。
List<ScoredId> _display(Database database, List<ScoredCandidate> selected) {
  if (selected.isEmpty) {
    return const <ScoredId>[];
  }
  final Map<int, double> scoreById = <int, double>{
    for (final ScoredCandidate candidate in selected)
      candidate.rowId: candidate.score,
  };
  final ResultSet rows = database.select(
    vectorDisplaySql(selected.length),
    <Object?>[for (final ScoredCandidate candidate in selected) candidate.rowId],
  );
  final Map<int, ScoredId> byId = <int, ScoredId>{};
  for (final Row row in rows) {
    final int rowId = rowIdOf(row);
    final double? score = scoreById[rowId];
    if (score == null) {
      continue;
    }
    byId[rowId] = scoredFromRow(row, score);
  }
  return <ScoredId>[
    for (final ScoredCandidate candidate in selected)
      if (byId[candidate.rowId] case final ScoredId hit) hit,
  ];
}
