import 'package:sqlite3/sqlite3.dart';

import 'filter_sql.dart';
import 'model/scored_id.dart';
import 'model/storage_filter.dart';
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

/// 查询走哪一层。有中文 bigram 时以 bigram 为主。
enum KeywordPath { bigram, trigram, like }

class KeywordPlan {
  const KeywordPlan(this.path, this.terms);

  final KeywordPath path;

  /// bigram 路径里是去重后的两字词。其他路径为空。
  final List<String> terms;

  static KeywordPlan forQuery(String query) {
    final String trimmed = query.trim();
    final List<String> terms = chineseBigrams(trimmed).toSet().toList(growable: false);
    if (terms.isNotEmpty) {
      return KeywordPlan(KeywordPath.bigram, terms);
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
    KeywordPath.bigram => _bigram(database, plan.terms, filter),
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
void replaceKeywords(Database database, int chunkRowId, String body) {
  final List<String> terms = chineseBigrams(body).toSet().toList(growable: false);
  if (terms.isNotEmpty) {
    final PreparedStatement insert = database.prepare(
      'INSERT OR IGNORE INTO keyword_term(term, chunk_rowid) VALUES (?, ?)',
    );
    for (final String term in terms) {
      insert.execute(<Object?>[term, chunkRowId]);
    }
    insert.dispose();
  }
  if (body.trim().isNotEmpty) {
    database.execute(
      'INSERT INTO chunk_fts(body, chunk_rowid) VALUES (?, ?)',
      <Object?>[body, chunkRowId],
    );
  }
}

const String _chunkColumns = '''
  c.id, c.document_id, c.chunk_id, c.relative_path, c.document_key, c.file_name,
  c.extension, c.mime_type, c.page_number, c.chunk_index, c.start_offset,
  c.end_offset, c.body, c.modality, c.image_json
''';

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
    final ResultSet rows = database.select(
      '''
      SELECT $_chunkColumns
      FROM chunk_fts f
      JOIN chunk c ON c.id = f.chunk_rowid
      WHERE f MATCH ?$where
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
