import 'package:sqlite3/sqlite3.dart';

import 'model/index_generation.dart';

bool generationMatches(Database database, IndexGeneration candidate) {
  final ResultSet rows = database.select(
    '''
    SELECT content_hash, parser_name, parser_version, chunker_version,
           model_id, vector_dim
    FROM index_generation
    WHERE document_id = ? AND model_id = ?
    ''',
    <Object?>[candidate.documentId, candidate.modelId],
  );
  if (rows.isEmpty) {
    return false;
  }
  final Row row = rows.first;
  final IndexGeneration stored = IndexGeneration(
    documentId: candidate.documentId,
    contentHash: _text(row, 0),
    parserName: _text(row, 1),
    parserVersion: _text(row, 2),
    chunkerVersion: _text(row, 3),
    modelId: _text(row, 4),
    vectorDim: _int(row, 5),
    embeddedAt: candidate.embeddedAt,
  );
  return stored.sameRecipe(candidate);
}

void saveGeneration(Database database, IndexGeneration generation) {
  database.execute(
    '''
    INSERT INTO index_generation(
      document_id, model_id, content_hash, parser_name, parser_version,
      chunker_version, vector_dim, embedded_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(document_id, model_id) DO UPDATE SET
      content_hash = excluded.content_hash,
      parser_name = excluded.parser_name,
      parser_version = excluded.parser_version,
      chunker_version = excluded.chunker_version,
      vector_dim = excluded.vector_dim,
      embedded_at = excluded.embedded_at
    ''',
    <Object?>[
      generation.documentId,
      generation.modelId,
      generation.contentHash,
      generation.parserName,
      generation.parserVersion,
      generation.chunkerVersion,
      generation.vectorDim,
      generation.embeddedAt.toUtc().toIso8601String(),
    ],
  );
}

String _text(Row row, int column) {
  final Object? value = row.columnAt(column);
  return value is String ? value : '';
}

int _int(Row row, int column) {
  final Object? value = row.columnAt(column);
  return value is int ? value : 0;
}
