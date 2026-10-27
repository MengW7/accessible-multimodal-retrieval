import 'package:sqlite3/sqlite3.dart';

import 'filter_sql.dart';
import 'model/scored_id.dart';
import 'model/storage_filter.dart';
import 'offline_glossary.dart';
import 'row_map.dart';

/// 连续 CJK 切成两字词。BMP 里的汉字一个 code unit 一个字。
List<String> chineseBigrams(String text) {
  final List<String> terms = <String>[];
  final List<int> run = <int>[];
  void flush() {
    if (run.length >= 2) {
      final String word = String.fromCharCodes(run);
      for (var index = 0; index < word.length - 1; index++) {
        terms.add(word.substring(index, index + 2));
      }
    }
    run.clear();
  }

  for (final int rune in text.runes) {
    if (_isCjk(rune)) {
      run.add(rune);
    } else {
      flush();
    }
  }
  flush();
  return terms;
}

bool _isCjk(int rune) {
  return (rune >= 0x3400 && rune <= 0x4DBF) || (rune >= 0x4E00 && rune <= 0x9FFF);
}

/// 查询的主路径。有中文 bigram 时主路径仍是 bigram。
enum KeywordPath { bigram, trigram, like }

class KeywordPlan {
  const KeywordPlan(
    this.path,
    this.terms, {
    this.trigramProbes = const <String>[],
  });

  final KeywordPath path;

  /// bigram 路径里是去重后的两字词。其他路径为空。
  final List<String> terms;

  /// bigram 路径上额外走 trigram 的拉丁串和英文词。其他路径为空。
  ///
  /// 这里没有整句中文。纯英文查询走 [KeywordPath.trigram]，用原问句，
  /// 不使用这份名单。
  final List<String> trigramProbes;

  static KeywordPlan forQuery(String query) {
    final String trimmed = query.trim();
    final List<String> terms = chineseBigrams(trimmed).toSet().toList(growable: false);
    if (terms.isNotEmpty) {
      return KeywordPlan(
        KeywordPath.bigram,
        terms,
        trigramProbes: keywordTrigramProbes(trimmed),
      );
    }
    if (trimmed.length >= 3) {
      return KeywordPlan(KeywordPath.trigram, const <String>[]);
    }
    return KeywordPlan(KeywordPath.like, const <String>[]);
  }
}

const int keywordLikeLimit = 50;

List<ScoredId> keywordTopK(
  Database database,
  String query, {
  StorageFilter? filter,
  int topK = 50,
}) {
  if (topK < 1) {
    throw ArgumentError.value(topK, 'topK', 'must be positive');
  }
  final String trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const <ScoredId>[];
  }
  final KeywordPlan plan = KeywordPlan.forQuery(trimmed);
  final List<ScoredId> hits = switch (plan.path) {
    KeywordPath.bigram => _bigramAndProbes(database, plan, filter, topK),
    KeywordPath.trigram => _trigram(database, trimmed, filter, topK),
    KeywordPath.like => _like(database, trimmed, filter, topK),
  };
  hits.sort(ScoredId.compareTie);
  if (hits.length <= topK) {
    return hits;
  }
  return hits.sublist(0, topK);
}

/// 给刚插入的行写关键词。旧行已经按文档删掉，这里的 rowid 是新的。
///
/// 批量写入请用 [KeywordWriter]：它把两条 `INSERT` 只 prepare 一次，
/// 避免每行各编译一遍（10k 块下这是写入耗时的主要来源之一）。
void replaceKeywords(Database database, int chunkRowId, String body) {
  final KeywordWriter writer = KeywordWriter(database);
  try {
    writer.write(chunkRowId, body);
  } finally {
    writer.dispose();
  }
}

/// 可复用的关键词写入器。调用方负责 [dispose]。
final class KeywordWriter {
  KeywordWriter(Database database)
    : _term = database.prepare(
        'INSERT OR IGNORE INTO keyword_term(term, chunk_rowid) VALUES (?, ?)',
      ),
      _fts = database.prepare(
        'INSERT INTO chunk_fts(body, chunk_rowid) VALUES (?, ?)',
      );

  final PreparedStatement _term;

  final PreparedStatement _fts;

  /// 写一行。正文为空时不写 FTS 行，与 [replaceKeywords] 行为一致。
  void write(int chunkRowId, String body) {
    final List<String> terms = chineseBigrams(body).toSet().toList(growable: false);
    for (final String term in terms) {
      _term.execute(<Object?>[term, chunkRowId]);
    }
    if (body.trim().isNotEmpty) {
      _fts.execute(<Object?>[body, chunkRowId]);
    }
  }

  void dispose() {
    _term.dispose();
    _fts.dispose();
  }
}

const String _chunkColumns = '''
  c.id, c.document_id, c.chunk_id, c.relative_path, c.document_key, c.file_name,
  c.extension, c.mime_type, c.page_number, c.chunk_index, c.start_offset,
  c.end_offset, c.body, c.modality, c.image_json
''';

/// 词表命中保留。拉丁串和英文词再各查一次 trigram。同一块只留较高分。
List<ScoredId> _bigramAndProbes(
  Database database,
  KeywordPlan plan,
  StorageFilter? filter,
  int topK,
) {
  List<ScoredId> hits = _bigram(database, plan.terms, filter);
  for (final String probe in plan.trigramProbes) {
    hits = _mergeMax(hits, _trigram(database, probe, filter, topK));
  }
  return hits;
}

List<ScoredId> _mergeMax(List<ScoredId> left, List<ScoredId> right) {
  final Map<String, ScoredId> byChunk = <String, ScoredId>{};
  void take(List<ScoredId> rows) {
    for (final ScoredId hit in rows) {
      final String key =
          '${hit.documentId}\u0000${hit.chunkId}\u0000${hit.startOffset}';
      final ScoredId? existing = byChunk[key];
      if (existing == null || hit.score > existing.score) {
        byChunk[key] = hit;
      }
    }
  }

  take(left);
  take(right);
  return byChunk.values.toList(growable: false);
}

List<ScoredId> _bigram(
  Database database,
  List<String> terms,
  StorageFilter? filter,
) {
  final String marks = List<String>.filled(terms.length, '?').join(', ');
  final SqlClause extra = filterClause(filter);
  final String where = extra.sql.isEmpty ? '' : ' AND ${extra.sql}';
  final ResultSet rows = database.select(
    '''
    SELECT $_chunkColumns, COUNT(*) AS hits
    FROM keyword_term t
    JOIN chunk c ON c.id = t.chunk_rowid
    WHERE t.term IN ($marks)$where
    GROUP BY c.id
    ''',
    <Object?>[...terms, ...extra.args],
  );
  return <ScoredId>[
    for (final Row row in rows)
      scoredFromRow(row, _hits(row) / terms.length),
  ];
}

List<ScoredId> _trigram(
  Database database,
  String query,
  StorageFilter? filter,
  int topK,
) {
  final SqlClause extra = filterClause(filter);
  final String where = extra.sql.isEmpty ? '' : ' AND ${extra.sql}';
  try {
    // FTS5 的 MATCH 左侧只认被索引表的表名，不认别名：`f MATCH ?` 在
    // 3.53.4 上直接报 `no such column: f`。这里不取别名，表名在 JOIN
    // 与 MATCH 里都直接可用；`$where` 的过滤条件仍然靠 `c.` 前缀走
    // chunk 表，不进 FTS 表。
    final ResultSet rows = database.select(
      '''
      SELECT $_chunkColumns
      FROM chunk_fts
      JOIN chunk c ON c.id = chunk_fts.chunk_rowid
      WHERE chunk_fts MATCH ?$where
      LIMIT ?
      ''',
      <Object?>['"${query.replaceAll('"', '""')}"', ...extra.args, topK],
    );
    return <ScoredId>[
      for (final Row row in rows) scoredFromRow(row, 1),
    ];
  } on SqliteException {
    return _like(database, query, filter, topK);
  }
}

List<ScoredId> _like(
  Database database,
  String query,
  StorageFilter? filter,
  int topK,
) {
  final int limit = topK < keywordLikeLimit ? topK : keywordLikeLimit;
  final SqlClause extra = filterClause(filter);
  final String where = extra.sql.isEmpty ? '' : ' AND ${extra.sql}';
  final ResultSet rows = database.select(
    '''
    SELECT $_chunkColumns
    FROM chunk c
    WHERE c.body LIKE ? ESCAPE '\\'$where
    LIMIT ?
    ''',
    <Object?>['%${_escapeLike(query)}%', ...extra.args, limit],
  );
  return <ScoredId>[
    for (final Row row in rows) scoredFromRow(row, 1),
  ];
}

double _hits(Row row) {
  final Object? value = row['hits'];
  if (value is int) {
    return value.toDouble();
  }
  return 0;
}

String _escapeLike(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
