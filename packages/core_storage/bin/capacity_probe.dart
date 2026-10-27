import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_storage/core_storage.dart';

/// Times the product writer and the brute-force cosine scan.
///
/// The clock starts at `store.write` / `store.search`. Building the Dart
/// objects is outside that clock. Filters are applied in SQL; the probe
/// prints `EXPLAIN QUERY PLAN` for a filtered scan.
Future<void> main() async {
  final Directory tmp = await Directory.systemTemp.createTemp('w4-capacity-');
  final String dbPath = '${tmp.path}/capacity.sqlite';
  final OpenedStore opened = openStore(const SystemSqliteLibraryLocator(), dbPath);
  final SqliteVectorStore? store = opened.store;
  if (store == null) {
    stderr.writeln(opened.failure?.message ?? 'SQLite could not be opened.');
    exitCode = 1;
    return;
  }
  try {
    final Object? version = store.database.select('select sqlite_version()').first.columnAt(0);
    stdout.writeln('sqlite_version=$version');
    stdout.writeln(
      'journal_mode=${store.database.select('PRAGMA journal_mode').first.columnAt(0)}',
    );
    for (final int count in <int>[1500, 10000]) {
      await _bulk(store, count);
    }
    _explain(store);
    stdout.writeln('write_limit_ms=600');
    stdout.writeln('query_limit_ms=60');
  } finally {
    store.close();
    tmp.deleteSync(recursive: true);
  }
}

Future<void> _bulk(SqliteVectorStore store, int count) async {
  await store.clear();
  final Random random = Random(11);
  final List<StoredChunk> chunks = <StoredChunk>[
    for (var index = 0; index < count; index++) _chunk(index),
  ];
  final List<EmbeddingVector> vectors = <EmbeddingVector>[
    for (var index = 0; index < count; index++)
      _vector(_unit(random, 384), index),
  ];
  final Stopwatch write = Stopwatch()..start();
  await store.write(chunks, vectors);
  write.stop();
  final EmbeddingVector query = _vector(_unit(random, 384), -1);
  final List<int> samples = <int>[];
  for (var repeat = 0; repeat < 5; repeat++) {
    final Stopwatch scan = Stopwatch()..start();
    final List<ScoredId> hits = await store.search(query, topK: 5);
    scan.stop();
    if (hits.length != 5) {
      throw StateError('n=$count returned ${hits.length} hits');
    }
    samples.add(scan.elapsedMilliseconds);
  }
  samples.sort();
  final int median = samples[samples.length ~/ 2];
  stdout.writeln(
    'n=$count write_ms=${write.elapsedMilliseconds} '
    'query_ms_median=$median query_ms_min=${samples.first} '
    'query_ms_max=${samples.last}',
  );
}

void _explain(SqliteVectorStore store) {
  // 解释生产扫描语句本身（与 cosineTopK 用的是同一条 SQL），不再另抄一份。
  final List<String> plan = explainVectorScan(
    store.database,
    _vector(_unit(Random(11), 384), -1),
    filter: const StorageFilter(extensions: <String>{'.txt'}),
  );
  stdout.writeln('explain_filter=extension_in_sql');
  for (final String line in plan) {
    stdout.writeln('explain=$line');
  }
}

StoredChunk _chunk(int index) {
  return StoredChunk(
    documentId: 'capacity',
    chunkId: 'c$index',
    relativePath: 'c$index.txt',
    fileName: 'c$index.txt',
    extension: '.txt',
    startOffset: 0,
    endOffset: 8,
    body: 'capacity',
    modality: Modality.text,
    chunkIndex: index,
    contentHash: 'capacity',
    parserName: 'txt',
    parserVersion: '1',
    chunkerVersion: 'capacity',
  );
}

EmbeddingVector _vector(Float32List values, int index) {
  return EmbeddingVector(
    values: values,
    space: EmbeddingSpace.documentText,
    dim: values.length,
    modelId: 'capacity-probe',
    normalized: true,
    chunkId: index < 0 ? null : 'c$index',
  );
}

Float32List _unit(Random random, int dim) {
  final Float32List values = Float32List(dim);
  var sum = 0.0;
  for (var index = 0; index < dim; index++) {
    final double value = random.nextDouble() * 2 - 1;
    values[index] = value;
    sum += value * value;
  }
  final double norm = sum == 0 ? 1 : sqrt(sum);
  for (var index = 0; index < dim; index++) {
    values[index] = values[index] / norm;
  }
  return values;
}
