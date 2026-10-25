import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_storage/core_storage.dart';
import 'package:test/test.dart';

void main() {
  test('a missing library is a structured failure', () {
    final OpenedStore opened = openStore(
      const RejectingSqliteLibraryLocator(),
      ':memory:',
    );
    expect(opened.isOk, isFalse);
    expect(opened.failure?.kind, StorageFailureKind.libraryUnavailable);
    expect(opened.store, isNull);
  });

  test('schema can be applied twice and a file database uses wal', () {
    final Directory dir = Directory.systemTemp.createTempSync('core_storage_wal_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final OpenedStore opened = openStore(
      const SystemSqliteLibraryLocator(),
      '${dir.path}/index.sqlite',
    );
    final SqliteVectorStore? store = opened.store;
    expect(store, isNotNull);
    addTearDown(() {
      try {
        store!.close();
      } on Object {
        // 本用例在中途已经关过一次，再关是为了断言失败时不泄漏句柄。
      }
    });
    final Object? mode = store!.database.select('PRAGMA journal_mode').first.columnAt(0);
    expect(mode, 'wal');
    store.close();
    final OpenedStore again = openStore(
      const SystemSqliteLibraryLocator(),
      '${dir.path}/index.sqlite',
    );
    final SqliteVectorStore? reopened = again.store;
    expect(reopened, isNotNull, reason: again.failure?.message);
    addTearDown(reopened!.close);
    expect(reopened.database.select('PRAGMA user_version').first.columnAt(0), 1);
  });

  test('nearest neighbor is the stored vector and the other space is invisible', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('a', body: 'alpha'), _chunk('b', body: 'beta')],
      <EmbeddingVector>[_vector(<double>[1, 0]), _vector(<double>[0, 1])],
    );
    await store.write(
      <StoredChunk>[
        _chunk(
          'pic',
          documentId: 'doc-img',
          modality: Modality.image,
          relativePath: 'pic.png',
          body: '',
        ),
      ],
      <EmbeddingVector>[
        _vector(<double>[1, 0], space: EmbeddingSpace.clipShared),
      ],
    );

    final List<ScoredId> text = await store.search(_vector(<double>[1, 0]), topK: 1);
    expect(text.single.chunkId, 'a');
    expect(text.single.score, closeTo(1, 1e-6));
    final List<String> textIds = [
      for (final ScoredId hit in await store.search(_vector(<double>[1, 0]))) hit.chunkId,
    ];
    expect(textIds, isNot(contains('pic')));

    final List<ScoredId> image = await store.search(
      _vector(<double>[1, 0], space: EmbeddingSpace.clipShared),
    );
    expect(image.single.chunkId, 'pic');

    final IndexStats stats = await store.stats();
    expect(stats.documentText, 2);
    expect(stats.clipShared, 1);
  });

  test('a different dimension in the same space is rejected', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('a')],
      <EmbeddingVector>[_vector(<double>[1, 0])],
    );
    expect(
      () => store.search(_vector(<double>[1, 0, 0])),
      throwsA(
        isA<StorageException>().having(
          (StorageException error) => error.failure.kind,
          'kind',
          StorageFailureKind.dimensionMismatch,
        ),
      ),
    );
  });

  test('an empty space returns no hits', () async {
    final SqliteVectorStore store = _memory();
    final List<ScoredId> hits = await store.search(
      _vector(<double>[1, 0], space: EmbeddingSpace.clipShared),
    );
    expect(hits, isEmpty);
  });

  test('text cannot be stored in the image space', () async {
    final SqliteVectorStore store = _memory();
    expect(
      () => store.write(
        <StoredChunk>[_chunk('a')],
        <EmbeddingVector>[_vector(<double>[1, 0], space: EmbeddingSpace.clipShared)],
      ),
      throwsA(isA<StorageException>()),
    );
  });

  test('a new hash for the same path replaces the previous document', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[
        _chunk('old', documentId: 'hash-old', hash: 'hash-old', body: '旧正文'),
      ],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'old')],
    );
    await store.write(
      <StoredChunk>[
        _chunk(
          'kept',
          documentId: 'other',
          hash: 'other',
          relativePath: 'b.txt',
          body: '另一份',
        ),
      ],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'kept')],
    );
    await store.write(
      <StoredChunk>[
        _chunk('new', documentId: 'hash-new', hash: 'hash-new', body: '新正文'),
      ],
      <EmbeddingVector>[_vector(<double>[0, 1], chunkId: 'new')],
    );
    final IndexStats stats = await store.stats();
    expect(stats.documents, 2);
    expect(stats.chunks, 2);
    expect(await store.chunksForDocument('hash-old'), isEmpty);
    expect((await store.chunksForDocument('hash-new')).single.body, '新正文');
    expect((await store.chunksForDocument('other')).single.chunkId, 'kept');
  });

  test('a failed rewrite rolls back to the previous rows', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('a', hash: 'h1')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'a')],
    );
    await expectLater(
      () => store.write(
        <StoredChunk>[
          _chunk('a', hash: 'h1'),
          _chunk('b', documentId: 'doc-1', hash: 'h2'),
        ],
        <EmbeddingVector>[
          _vector(<double>[1, 0], chunkId: 'a'),
          _vector(<double>[0, 1], chunkId: 'b'),
        ],
      ),
      throwsA(isA<StorageException>()),
    );
    final IndexStats stats = await store.stats();
    expect(stats.chunks, 1);
    expect((await store.search(_vector(<double>[1, 0]))).single.chunkId, 'a');
  });

  test('equal scores use path, page, then offset', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[
        _chunk('b', relativePath: 'b.txt', pageNumber: 1, startOffset: 5),
        _chunk('a-null', relativePath: 'a.txt', startOffset: 0),
        _chunk('a-page', relativePath: 'a.txt', pageNumber: 1, startOffset: 9),
        _chunk('a-early', relativePath: 'a.txt', pageNumber: 1, startOffset: 2),
      ],
      <EmbeddingVector>[
        _vector(<double>[1, 0]),
        _vector(<double>[1, 0]),
        _vector(<double>[1, 0]),
        _vector(<double>[1, 0]),
      ],
    );
    final List<String> ids = [
      for (final ScoredId hit in await store.search(_vector(<double>[1, 0]))) hit.chunkId,
    ];
    expect(ids, <String>['a-early', 'a-page', 'a-null', 'b']);
  });

  test('filters apply before the limit', () async {
    final SqliteVectorStore store = _memory();
    final DateTime older = DateTime.utc(2026, 1, 1);
    final DateTime newer = DateTime.utc(2026, 6, 1);
    await store.write(
      <StoredChunk>[
        _chunk('pdf', extension: '.pdf', modifiedAt: newer),
        _chunk('txt', extension: '.txt', relativePath: 'notes/a.txt', modifiedAt: older),
      ],
      <EmbeddingVector>[_vector(<double>[1, 0]), _vector(<double>[1, 0])],
    );
    final List<ScoredId> hits = await store.search(
      _vector(<double>[1, 0]),
      filter: StorageFilter(
        extensions: <String>{'.txt'},
        pathPrefix: 'notes',
        modifiedAfter: DateTime.utc(2026, 3, 1),
      ),
    );
    expect(hits, isEmpty);
    final List<ScoredId> pdf = await store.search(
      _vector(<double>[1, 0]),
      filter: const StorageFilter(extensions: <String>{'.pdf'}),
    );
    expect(pdf.single.chunkId, 'pdf');
  });

  test('chinese bigrams hit two-character and three-character queries', () async {
    final SqliteVectorStore store = _memory();
    expect(chineseBigrams('离线检索'), <String>['离线', '线检', '检索']);
    await store.write(
      <StoredChunk>[
        _chunk('zh', body: '离线检索可以在没有网络的电脑上运行。键盘操作必须能走完整个流程。'),
        _chunk('en', body: 'offline retrieval uses json config'),
      ],
      <EmbeddingVector>[_vector(<double>[1, 0]), _vector(<double>[0, 1])],
    );
    expect((await store.keyword('离线')).single.chunkId, 'zh');
    expect((await store.keyword('电脑上')).single.chunkId, 'zh');
    expect((await store.keyword('json')).single.chunkId, 'en');
    expect((await store.keyword('键')).single.chunkId, 'zh');
    expect(await store.keyword(''), isEmpty);
  });

  test('delete removes the vector and the keyword row together', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('zh', body: '离线检索')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'zh')],
    );
    await store.deleteDocument('doc-1');
    expect(await store.stats(), const IndexStats(
      chunks: 0,
      documents: 0,
      documentText: 0,
      clipShared: 0,
      keywordTerms: 0,
    ));
    expect(await store.keyword('离线'), isEmpty);
    expect(await store.search(_vector(<double>[1, 0])), isEmpty);
  });

  test('five-field generation decides reuse', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('a', hash: 'h1')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'a')],
    );
    final IndexGeneration current = _generation('h1');
    expect(await store.canReuse(current), isTrue);
    expect(await store.canReuse(_generation('h2')), isFalse);
    final List<StoredChunk> loaded = await store.chunksForDocument('doc-1');
    expect(loaded.single.chunkIndex, 0);
    expect(loaded.single.imageAsset, isNull);
  });

  test('an image asset round-trips', () async {
    final SqliteVectorStore store = _memory();
    const ImageAsset asset = ImageAsset(format: 'png', width: 8, height: 4, colorMode: 'rgb');
    await store.write(
      <StoredChunk>[
        _chunk('pic', modality: Modality.image, body: '', imageAsset: asset),
      ],
      <EmbeddingVector>[
        _vector(<double>[1, 0], space: EmbeddingSpace.clipShared),
      ],
    );
    final StoredChunk loaded = (await store.chunksForDocument('doc-1')).single;
    expect(loaded.imageAsset, asset);
    expect(loaded.modality, Modality.image);
  });
}

SqliteVectorStore _memory() {
  final OpenedStore opened = openStore(const SystemSqliteLibraryLocator(), ':memory:');
  final SqliteVectorStore? store = opened.store;
  expect(store, isNotNull, reason: opened.failure?.detail ?? opened.failure?.message);
  addTearDown(store!.close);
  return store;
}

StoredChunk _chunk(
  String chunkId, {
  String documentId = 'doc-1',
  String body = 'body',
  String relativePath = 'a.txt',
  String? hash = 'hash',
  int? pageNumber,
  int startOffset = 0,
  Modality modality = Modality.text,
  String extension = '.txt',
  DateTime? modifiedAt,
  Object? imageAsset,
}) {
  return StoredChunk(
    documentId: documentId,
    chunkId: chunkId,
    relativePath: relativePath,
    fileName: relativePath.split('/').last,
    startOffset: startOffset,
    endOffset: startOffset + body.length,
    body: body,
    modality: modality,
    pageNumber: pageNumber,
    chunkIndex: 0,
    extension: extension,
    modifiedAt: modifiedAt,
    contentHash: hash,
    parserName: 'txt',
    parserVersion: '1',
    chunkerVersion: modality == Modality.text ? 'w3-cascade-1' : 'none',
    imageAsset: imageAsset,
  );
}

EmbeddingVector _vector(
  List<double> values, {
  EmbeddingSpace space = EmbeddingSpace.documentText,
  String? chunkId,
}) {
  return EmbeddingVector(
    values: values,
    space: space,
    dim: values.length,
    modelId: 'test-model',
    normalized: true,
    chunkId: chunkId,
  );
}

IndexGeneration _generation(String hash) {
  return IndexGeneration(
    documentId: 'doc-1',
    contentHash: hash,
    parserName: 'txt',
    parserVersion: '1',
    chunkerVersion: 'w3-cascade-1',
    modelId: 'test-model',
    vectorDim: 2,
    embeddedAt: DateTime.utc(2026, 10, 20),
  );
}
