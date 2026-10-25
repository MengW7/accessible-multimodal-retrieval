import 'dart:convert';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:sqlite3/sqlite3.dart';

import 'float_blob.dart';
import 'index_generation.dart';
import 'keyword_index.dart';
import 'maintenance.dart';
import 'model/index_generation.dart';
import 'model/index_stats.dart';
import 'model/modality.dart';
import 'model/storage_failure.dart';
import 'model/stored_chunk.dart';

WriteOutcome writeChunks(
  Database database,
  List<StoredChunk> chunks,
  List<EmbeddingVector> vectors,
) {
  if (chunks.length != vectors.length) {
    throw ArgumentError.value(
      vectors.length,
      'vectors',
      'must match chunks (${chunks.length})',
    );
  }
  for (var index = 0; index < chunks.length; index++) {
    _checkPair(chunks[index], vectors[index]);
  }
  if (chunks.isEmpty) {
    return const WriteOutcome(written: 0, documents: 0);
  }
  database.execute('BEGIN');
  try {
    final Set<String> documents = <String>{
      for (final StoredChunk chunk in chunks) chunk.documentId,
    };
    // 内容哈希变了，documentId 也变。同一 documentKey 的上一版要在这个事务里删掉。
    final List<String> keys = <String>{
      for (final StoredChunk chunk in chunks) chunk.storedDocumentKey,
    }.toList(growable: false);
    if (keys.isNotEmpty) {
      final String marks = List<String>.filled(keys.length, '?').join(', ');
      final ResultSet previous = database.select(
        'SELECT DISTINCT document_id FROM chunk WHERE document_key IN ($marks)',
        keys,
      );
      for (final Row row in previous) {
        final Object? id = row.columnAt(0);
        if (id is String && id.isNotEmpty) {
          documents.add(id);
        }
      }
    }
    for (final String documentId in documents) {
      deleteDocumentRows(database, documentId);
    }
    final PreparedStatement insert = database.prepare('''
      INSERT INTO chunk(
        document_id, chunk_id, space, dim, model_id, relative_path,
        document_key, file_name, extension, mime_type, page_number,
        chunk_index, start_offset, end_offset, body, modality, image_json,
        modified_at, content_hash, parser_name, parser_version,
        chunker_version, vec
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    for (var index = 0; index < chunks.length; index++) {
      final StoredChunk chunk = chunks[index];
      final EmbeddingVector vector = vectors[index];
      insert.execute(<Object?>[
        chunk.documentId,
        chunk.chunkId,
        vector.space.name,
        vector.dim,
        vector.modelId,
        chunk.relativePath.replaceAll('\\', '/'),
        chunk.storedDocumentKey,
        chunk.fileName,
        chunk.storedExtension,
        chunk.mimeType,
        chunk.pageNumber,
        chunk.chunkIndex,
        chunk.startOffset,
        chunk.endOffset,
        chunk.body,
        chunk.modality.name,
        _imageJson(chunk.imageAsset),
        chunk.modifiedAt?.toUtc().toIso8601String(),
        chunk.contentHash,
        chunk.parserName,
        chunk.parserVersion,
        chunk.chunkerVersion,
        float32Blob(vector),
      ]);
      final int rowId = database.lastInsertRowId;
      replaceKeywords(database, rowId, chunk.body);
    }
    insert.dispose();
    _saveGenerations(database, chunks, vectors);
    database.execute('COMMIT');
    return WriteOutcome(written: chunks.length, documents: documents.length);
  } catch (error) {
    database.execute('ROLLBACK');
    rethrow;
  }
}

void _checkPair(StoredChunk chunk, EmbeddingVector vector) {
  final String? vectorChunk = vector.chunkId;
  if (vectorChunk != null && vectorChunk != chunk.chunkId) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.conflict,
        message: 'Vector chunkId $vectorChunk does not match ${chunk.chunkId}.',
      ),
    );
  }
  final bool textOk =
      chunk.modality == Modality.text &&
      vector.space == EmbeddingSpace.documentText;
  final bool imageOk =
      chunk.modality == Modality.image &&
      vector.space == EmbeddingSpace.clipShared;
  if (!textOk && !imageOk) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.spaceMismatch,
        message:
            '${chunk.modality.name} cannot be stored in ${vector.space.name}.',
      ),
    );
  }
}

void _saveGenerations(
  Database database,
  List<StoredChunk> chunks,
  List<EmbeddingVector> vectors,
) {
  final Map<String, IndexGeneration> rows = <String, IndexGeneration>{};
  final DateTime now = DateTime.now().toUtc();
  for (var index = 0; index < chunks.length; index++) {
    final StoredChunk chunk = chunks[index];
    final EmbeddingVector vector = vectors[index];
    final String? hash = chunk.contentHash;
    final String? parserName = chunk.parserName;
    final String? parserVersion = chunk.parserVersion;
    final String? chunkerVersion = chunk.chunkerVersion;
    if (hash == null ||
        hash.isEmpty ||
        parserName == null ||
        parserName.isEmpty ||
        parserVersion == null ||
        parserVersion.isEmpty ||
        chunkerVersion == null ||
        chunkerVersion.isEmpty) {
      continue;
    }
    final String key = '${chunk.documentId}\u0000${vector.modelId}';
    final IndexGeneration generation = IndexGeneration(
      documentId: chunk.documentId,
      contentHash: hash,
      parserName: parserName,
      parserVersion: parserVersion,
      chunkerVersion: chunkerVersion,
      modelId: vector.modelId,
      vectorDim: vector.dim,
      embeddedAt: now,
    );
    final IndexGeneration? previous = rows[key];
    if (previous != null && !previous.sameRecipe(generation)) {
      throw StorageException(
        StorageFailure(
          kind: StorageFailureKind.conflict,
          message: 'Document ${chunk.documentId} mixes generation recipes.',
        ),
      );
    }
    rows[key] = generation;
  }
  for (final IndexGeneration generation in rows.values) {
    saveGeneration(database, generation);
  }
}

String? _imageJson(Object? asset) {
  if (asset is ImageAsset) {
    return jsonEncode(asset.toJson());
  }
  return null;
}
