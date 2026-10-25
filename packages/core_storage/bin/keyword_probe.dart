import 'dart:convert';
import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_storage/core_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Shows the unicode61 miss, then the product bigram path on real markdown.
///
/// The unicode61 table is a side probe. The product index is [VectorStore].
Future<void> main() async {
  final String root = _repoRoot();
  final StringBuffer log = StringBuffer();
  void line(String text) {
    log.writeln(text);
    stdout.writeln(text);
  }

  final String sentence = '离线检索可以在没有网络的电脑上运行';
  final int unicodeHits = _unicode61Hits(sentence, '离线');
  line('unicode61_table=side_probe');
  line('unicode61_body=$sentence');
  line('unicode61_query=离线');
  line('unicode61_hits=$unicodeHits');

  final OpenedStore opened = openStore(const SystemSqliteLibraryLocator(), ':memory:');
  final SqliteVectorStore? store = opened.store;
  if (store == null) {
    stderr.writeln(opened.failure?.message ?? 'SQLite did not open.');
    exitCode = 1;
    return;
  }
  try {
    await store.write(
      <StoredChunk>[_chunk('sentence', sentence)],
      <EmbeddingVector>[_vector('sentence')],
    );
    final List<File> files = _markdown(Directory(p.join(root, 'docs')), 40);
    final List<StoredChunk> chunks = <StoredChunk>[];
    final List<EmbeddingVector> vectors = <EmbeddingVector>[];
    for (final File file in files) {
      final String body = _bounded(await file.readAsString());
      if (body.trim().isEmpty) {
        continue;
      }
      final String relative = p
          .relative(file.path, from: root)
          .replaceAll('\\', '/');
      chunks.add(_chunk(relative, body, relativePath: relative));
      vectors.add(_vector(relative));
    }
    await store.write(chunks, vectors);
    line('product_path=bigram');
    line('markdown_files=${chunks.length}');
    await _printHits(store, '离线', line);
    await _printHits(store, '文件', line);
    await _printHits(store, '键盘', line);
    await _printHits(store, '电脑上', line);
  } finally {
    store.close();
  }
  final File report = File(p.join(root, 'week4', 'logs', 'keyword_probe.txt'));
  await report.parent.create(recursive: true);
  await report.writeAsString(log.toString(), encoding: utf8);
}

Future<void> _printHits(
  VectorStore store,
  String query,
  void Function(String text) line,
) async {
  final List<ScoredId> hits = await store.keyword(query);
  line('bigram_query=$query');
  line('bigram_hits=${hits.length}');
  if (hits.isNotEmpty) {
    line('bigram_first=${hits.first.relativePath}');
  }
}

int _unicode61Hits(String body, String query) {
  late final Database database;
  try {
    database = sqlite3.openInMemory();
  } on ArgumentError {
    stderr.writeln('unicode61_error=library_unavailable');
    return -1;
  }
  try {
    database.execute(
      "CREATE VIRTUAL TABLE uni USING fts5(body, tokenize = 'unicode61')",
    );
    database.execute('INSERT INTO uni(body) VALUES (?)', <Object?>[body]);
    final ResultSet rows = database.select(
      'SELECT COUNT(*) FROM uni WHERE uni MATCH ?',
      <Object?>[query],
    );
    final Object? value = rows.first.columnAt(0);
    return value is int ? value : 0;
  } on SqliteException catch (error) {
    stderr.writeln('unicode61_error=${error.message}');
    return -1;
  } finally {
    database.dispose();
  }
}

List<File> _markdown(Directory root, int limit) {
  if (!root.existsSync()) {
    return const <File>[];
  }
  final List<File> files = <File>[];
  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
      files.add(entity);
      if (files.length >= limit) {
        break;
      }
    }
  }
  files.sort((File left, File right) => left.path.compareTo(right.path));
  return files;
}

String _bounded(String text) {
  const int cap = 4000;
  if (text.length <= cap) {
    return text;
  }
  return text.substring(0, cap);
}

StoredChunk _chunk(String chunkId, String body, {String relativePath = 'probe.txt'}) {
  return StoredChunk(
    documentId: 'probe-$chunkId',
    chunkId: chunkId,
    relativePath: relativePath,
    fileName: p.basename(relativePath),
    extension: '.md',
    startOffset: 0,
    endOffset: body.length,
    body: body,
    modality: Modality.text,
    chunkIndex: 0,
    contentHash: 'probe',
    parserName: 'txt',
    parserVersion: '1',
    chunkerVersion: 'w3-cascade-1',
  );
}

EmbeddingVector _vector(String chunkId) {
  return EmbeddingVector(
    values: const <double>[1, 0],
    space: EmbeddingSpace.documentText,
    dim: 2,
    modelId: 'probe',
    normalized: true,
    chunkId: chunkId,
  );
}

String _repoRoot() {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    if (File(p.join(dir.path, 'engine', 'embed_text_hidden.py')).existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return Directory.current.path;
}
