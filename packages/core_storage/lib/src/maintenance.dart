import 'package:sqlite3/sqlite3.dart';

import 'model/index_stats.dart';

void deleteDocumentRows(Database database, String documentId) {
  final ResultSet rows = database.select(
    'SELECT id FROM chunk WHERE document_id = ?',
    <Object?>[documentId],
  );
  final PreparedStatement terms = database.prepare(
    'DELETE FROM keyword_term WHERE chunk_rowid = ?',
  );
  final PreparedStatement fts = database.prepare(
    'DELETE FROM chunk_fts WHERE chunk_rowid = ?',
  );
  for (final Row row in rows) {
    final Object? id = row.columnAt(0);
    terms.execute(<Object?>[id]);
    fts.execute(<Object?>[id]);
  }
  terms.dispose();
  fts.dispose();
  database.execute(
    'DELETE FROM chunk WHERE document_id = ?',
    <Object?>[documentId],
  );
  database.execute(
    'DELETE FROM index_generation WHERE document_id = ?',
    <Object?>[documentId],
  );
}

void clearRows(Database database) {
  database.execute('DELETE FROM keyword_term');
  database.execute('DELETE FROM chunk_fts');
  database.execute('DELETE FROM chunk');
  database.execute('DELETE FROM index_generation');
}

IndexStats readStats(Database database) {
  int count(String sql) {
    final Object? value = database.select(sql).first.columnAt(0);
    if (value is int) {
      return value;
    }
    return 0;
  }

  return IndexStats(
    chunks: count('SELECT COUNT(*) FROM chunk'),
    documents: count('SELECT COUNT(DISTINCT document_id) FROM chunk'),
    documentText: count(
      "SELECT COUNT(*) FROM chunk WHERE space = 'documentText'",
    ),
    clipShared: count("SELECT COUNT(*) FROM chunk WHERE space = 'clipShared'"),
    keywordTerms: count('SELECT COUNT(*) FROM keyword_term'),
  );
}
