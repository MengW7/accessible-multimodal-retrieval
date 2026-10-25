import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_storage/core_storage.dart';

/// Ranks exported float32 vectors with the product SQLite index.
///
/// Query vectors are the bytes in `vectorB64`. This command does not embed.
Future<void> main(List<String> args) async {
  final Map<String, String> flags = _flags(args);
  final String samples = flags['samples'] ?? '';
  final String queries = flags['queries'] ?? '';
  final String outPath = flags['out'] ?? '';
  if (samples.isEmpty || queries.isEmpty || outPath.isEmpty) {
    stderr.writeln(
      'Usage: dart run packages/core_storage/bin/rank_exported.dart '
      '--samples <jsonl> --queries <jsonl> --out <jsonl> [--evidence <jsonl>]',
    );
    exitCode = 64;
    return;
  }

  final List<Map<String, Object?>> records = <Map<String, Object?>>[
    ..._lines(samples),
    if (flags['evidence'] != null) ..._lines(flags['evidence']!),
  ];
  final Set<String> ids = <String>{};
  for (final Map<String, Object?> record in records) {
    final String chunkId = _text(record, 'chunkId');
    if (!ids.add(chunkId)) {
      stderr.writeln('Duplicate chunkId: $chunkId');
      exitCode = 1;
      return;
    }
  }

  final OpenedStore opened = openStore(const SystemSqliteLibraryLocator(), ':memory:');
  final SqliteVectorStore? store = opened.store;
  if (store == null) {
    stderr.writeln(opened.failure?.message ?? 'SQLite did not open.');
    exitCode = 1;
    return;
  }
  final StringBuffer out = StringBuffer();
  try {
    final List<StoredChunk> chunks = <StoredChunk>[];
    final List<EmbeddingVector> vectors = <EmbeddingVector>[];
    for (final Map<String, Object?> record in records) {
      final EmbeddingVector vector = _vector(record);
      chunks.add(_chunk(record));
      vectors.add(vector);
    }
    await store.write(chunks, vectors);
    for (final Map<String, Object?> query in _lines(queries)) {
      final List<ScoredId> hits = await store.search(_vector(query), topK: 5);
      out.writeln(
        jsonEncode(<String, Object?>{
          'queryId': _text(query, 'id'),
          'top5': <Map<String, Object?>>[
            for (final ScoredId hit in hits)
              <String, Object?>{
                'chunkId': hit.chunkId,
                'score': hit.score,
                'relativePath': hit.relativePath,
                'pageNumber': hit.pageNumber,
                'startOffset': hit.startOffset,
              },
          ],
        }),
      );
    }
  } finally {
    store.close();
  }
  await File(outPath).parent.create(recursive: true);
  await File(outPath).writeAsString(out.toString());
  stderr.writeln('dart_top5=$outPath queries=${_lines(queries).length}');
}

List<Map<String, Object?>> _lines(String path) {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (final String line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty) {
      continue;
    }
    final Object? decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw FormatException('JSONL row is not an object: $path');
    }
    rows.add(<String, Object?>{
      for (final MapEntry<Object?, Object?> entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
  }
  return rows;
}

StoredChunk _chunk(Map<String, Object?> record) {
  final String modality = _text(record, 'modality');
  return StoredChunk(
    documentId: _text(record, 'documentId'),
    chunkId: _text(record, 'chunkId'),
    relativePath: _text(record, 'relativePath'),
    documentKey: _optionalText(record, 'documentKey'),
    fileName: _text(record, 'fileName'),
    extension: _optionalText(record, 'extension'),
    mimeType: _optionalText(record, 'mimeType'),
    pageNumber: _optionalInt(record, 'pageNumber'),
    chunkIndex: _optionalInt(record, 'chunkIndex'),
    startOffset: _int(record, 'startOffset'),
    endOffset: _int(record, 'endOffset'),
    body: _optionalText(record, 'body') ?? '',
    modality: modality == 'image' ? Modality.image : Modality.text,
    contentHash: _optionalText(record, 'contentHash'),
    parserName: _optionalText(record, 'parserName'),
    parserVersion: _optionalText(record, 'parserVersion'),
    chunkerVersion: _optionalText(record, 'chunkerVersion'),
  );
}

EmbeddingVector _vector(Map<String, Object?> record) {
  final int dim = _int(record, 'dim');
  final EmbeddingSpace space = EmbeddingSpace.values.byName(_text(record, 'space'));
  return EmbeddingVector(
    values: _floats(_text(record, 'vectorB64'), dim),
    space: space,
    dim: dim,
    modelId: _text(record, 'modelId'),
    normalized: true,
    chunkId: _optionalText(record, 'chunkId'),
  );
}

Float32List _floats(String encoded, int dim) {
  final Uint8List bytes = base64Decode(encoded);
  if (bytes.length != dim * 4) {
    throw FormatException('vectorB64 length ${bytes.length} is not $dim float32 values');
  }
  final ByteData view = ByteData.sublistView(bytes);
  final Float32List values = Float32List(dim);
  for (var index = 0; index < dim; index++) {
    values[index] = view.getFloat32(index * 4, Endian.little);
  }
  return values;
}

Map<String, String> _flags(List<String> args) {
  final Map<String, String> flags = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (arg.startsWith('--') && index + 1 < args.length) {
      flags[arg.substring(2)] = args[index + 1];
      index += 1;
    }
  }
  return flags;
}

String _text(Map<String, Object?> record, String key) {
  final Object? value = record[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Missing $key');
}

String? _optionalText(Map<String, Object?> record, String key) {
  final Object? value = record[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('$key is not text');
}

int _int(Map<String, Object?> record, String key) {
  final int? value = _optionalInt(record, key);
  if (value == null) {
    throw FormatException('Missing $key');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> record, String key) {
  final Object? value = record[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('$key is not an integer');
}
