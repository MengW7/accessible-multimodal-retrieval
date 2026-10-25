import 'dart:convert';
import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';
import 'package:sqlite3/sqlite3.dart';

import 'model/modality.dart';
import 'model/scored_id.dart';
import 'model/storage_failure.dart';
import 'model/stored_chunk.dart';

ScoredId scoredFromRow(Row row, double score) {
  return ScoredId(
    documentId: _text(row, 'document_id'),
    chunkId: _text(row, 'chunk_id'),
    chunkIndex: _optionalInt(row, 'chunk_index'),
    relativePath: _text(row, 'relative_path'),
    documentKey: _text(row, 'document_key'),
    fileName: _text(row, 'file_name'),
    mimeType: _optionalText(row, 'mime_type'),
    pageNumber: _optionalInt(row, 'page_number'),
    startOffset: _requiredInt(row, 'start_offset'),
    endOffset: _requiredInt(row, 'end_offset'),
    body: _text(row, 'body'),
    imageAsset: _image(row),
    modality: _modality(row),
    score: score,
  );
}

StoredChunk chunkFromRow(Row row) {
  final ScoredId scored = scoredFromRow(row, 0);
  return StoredChunk(
    documentId: scored.documentId,
    chunkId: scored.chunkId,
    chunkIndex: scored.chunkIndex,
    relativePath: scored.relativePath,
    documentKey: scored.documentKey,
    fileName: scored.fileName,
    mimeType: scored.mimeType,
    pageNumber: scored.pageNumber,
    startOffset: scored.startOffset,
    endOffset: scored.endOffset,
    body: scored.body,
    imageAsset: scored.imageAsset,
    modality: scored.modality,
    extension: _text(row, 'extension'),
    modifiedAt: _time(_optionalText(row, 'modified_at')),
    contentHash: _optionalText(row, 'content_hash'),
    parserName: _optionalText(row, 'parser_name'),
    parserVersion: _optionalText(row, 'parser_version'),
    chunkerVersion: _optionalText(row, 'chunker_version'),
  );
}

Uint8List blobOf(Row row, String column) {
  final Object? value = row[column];
  if (value is Uint8List) {
    return value;
  }
  throw StorageException(
    StorageFailure(
      kind: StorageFailureKind.unknown,
      message: 'Column $column is not a BLOB.',
    ),
  );
}

String _text(Row row, String column) {
  final Object? value = row[column];
  if (value is String) {
    return value;
  }
  throw StorageException(
    StorageFailure(
      kind: StorageFailureKind.unknown,
      message: 'Column $column is not text.',
    ),
  );
}

String? _optionalText(Row row, String column) {
  final Object? value = row[column];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw StorageException(
    StorageFailure(
      kind: StorageFailureKind.unknown,
      message: 'Column $column is not text.',
    ),
  );
}

int _requiredInt(Row row, String column) {
  final int? value = _optionalInt(row, column);
  if (value == null) {
    throw StorageException(
      StorageFailure(
        kind: StorageFailureKind.unknown,
        message: 'Column $column is null.',
      ),
    );
  }
  return value;
}

int? _optionalInt(Row row, String column) {
  final Object? value = row[column];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw StorageException(
    StorageFailure(
      kind: StorageFailureKind.unknown,
      message: 'Column $column is not an integer.',
    ),
  );
}

Modality _modality(Row row) {
  final String name = _text(row, 'modality');
  for (final Modality modality in Modality.values) {
    if (modality.name == name) {
      return modality;
    }
  }
  throw StorageException(
    StorageFailure(
      kind: StorageFailureKind.unknown,
      message: 'Unknown modality $name.',
    ),
  );
}

Object? _image(Row row) {
  final String? json = _optionalText(row, 'image_json');
  if (json == null || json.isEmpty) {
    return null;
  }
  final Object? decoded = jsonDecode(json);
  if (decoded is! Map) {
    return null;
  }
  final Map<String, Object?> map = <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
  final Object? format = map['format'];
  final Object? width = map['width'];
  final Object? height = map['height'];
  if (format is! String || width is! int || height is! int) {
    return map;
  }
  final Object? colorMode = map['colorMode'];
  final Object? orientation = map['orientation'];
  return ImageAsset(
    format: format,
    width: width,
    height: height,
    colorMode: colorMode is String ? colorMode : null,
    orientation: orientation is String ? orientation : null,
  );
}

DateTime? _time(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.parse(value);
}
