import 'package:sqlite3/sqlite3.dart';

import 'model/storage_failure.dart';

/// 当前库结构。更高的版本直接拒绝，不猜迁移。
const int schemaVersion = 1;

void applySchema(Database database) {
  final int current = _userVersion(database);
  if (current > schemaVersion) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.schemaUnsupported,
        message: 'Index schema $current is newer than $schemaVersion.',
      ),
    );
  }
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('''
    CREATE TABLE IF NOT EXISTS chunk (
      id INTEGER PRIMARY KEY,
      document_id TEXT NOT NULL,
      chunk_id TEXT NOT NULL,
      space TEXT NOT NULL,
      dim INTEGER NOT NULL,
      model_id TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      document_key TEXT NOT NULL,
      file_name TEXT NOT NULL,
      extension TEXT NOT NULL,
      mime_type TEXT,
      page_number INTEGER,
      chunk_index INTEGER,
      start_offset INTEGER NOT NULL,
      end_offset INTEGER NOT NULL,
      body TEXT NOT NULL,
      modality TEXT NOT NULL,
      image_json TEXT,
      modified_at TEXT,
      content_hash TEXT,
      parser_name TEXT,
      parser_version TEXT,
      chunker_version TEXT,
      vec BLOB NOT NULL
    )
  ''');
  database.execute(
    'CREATE INDEX IF NOT EXISTS idx_chunk_document ON chunk(document_id)',
  );
  database.execute(
    'CREATE INDEX IF NOT EXISTS idx_chunk_space ON chunk(space, dim)',
  );
  database.execute('''
    CREATE TABLE IF NOT EXISTS keyword_term (
      term TEXT NOT NULL,
      chunk_rowid INTEGER NOT NULL,
      PRIMARY KEY (term, chunk_rowid)
    )
  ''');
  database.execute(
    'CREATE INDEX IF NOT EXISTS idx_keyword_term ON keyword_term(term)',
  );
  database.execute('''
    CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(
      body,
      chunk_rowid UNINDEXED,
      tokenize = 'trigram'
    )
  ''');
  database.execute('''
    CREATE TABLE IF NOT EXISTS index_generation (
      document_id TEXT NOT NULL,
      model_id TEXT NOT NULL,
      content_hash TEXT NOT NULL,
      parser_name TEXT NOT NULL,
      parser_version TEXT NOT NULL,
      chunker_version TEXT NOT NULL,
      vector_dim INTEGER NOT NULL,
      embedded_at TEXT NOT NULL,
      PRIMARY KEY (document_id, model_id)
    )
  ''');
  if (current != schemaVersion) {
    database.execute('PRAGMA user_version = $schemaVersion');
  }
}

int _userVersion(Database database) {
  final Object? value = database.select('PRAGMA user_version').first.columnAt(0);
  if (value is int) {
    return value;
  }
  throw const StorageException(
    StorageFailure(
      kind: StorageFailureKind.schemaUnsupported,
      message: 'SQLite user_version is not an integer.',
    ),
  );
}
