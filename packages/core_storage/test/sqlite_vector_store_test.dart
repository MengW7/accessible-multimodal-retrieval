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

  test('clear empties every table and the store stays usable', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('zh', body: '离线检索')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'zh')],
    );
    // clear 前四张表都有行，否则下面的「都为空」不构成验证。
    expect(_count(store, 'chunk'), 1);
    expect(_count(store, 'keyword_term'), greaterThan(0));
    expect(_count(store, 'chunk_fts'), 1);
    expect(_count(store, 'index_generation'), 1);

    await store.clear();

    expect(_count(store, 'chunk'), 0);
    expect(_count(store, 'keyword_term'), 0);
    expect(_count(store, 'chunk_fts'), 0);
    expect(_count(store, 'index_generation'), 0);
    expect(await store.search(_vector(<double>[1, 0])), isEmpty);
    expect(await store.keyword('离线'), isEmpty);
    expect(await store.stats(), const IndexStats(
      chunks: 0,
      documents: 0,
      documentText: 0,
      clipShared: 0,
      keywordTerms: 0,
    ));

    // 清空后库还要能用：重新写入并查得到。
    await store.write(
      <StoredChunk>[_chunk('zh2', body: '离线检索')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'zh2')],
    );
    expect((await store.search(_vector(<double>[1, 0]))).single.chunkId, 'zh2');
    expect((await store.keyword('离线')).single.chunkId, 'zh2');
  });

  test('the trigram path matches words and mid-word substrings', () async {
    // 纯英文查询不带中文 bigram，KeywordPlan 会走 trigram 分支。
    expect(KeywordPlan.forQuery('retrieval').path, KeywordPath.trigram);
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[
        _chunk('en', body: 'offline retrieval pipeline works'),
        _chunk('other', body: 'unrelated content here'),
      ],
      <EmbeddingVector>[_vector(<double>[1, 0]), _vector(<double>[0, 1])],
    );
    // 整词
    expect((await store.keyword('retrieval')).single.chunkId, 'en');
    // 词内子串：只有 trigram 能命中，LIKE '%…%' 也能，但这里验证通道本身可用。
    expect((await store.keyword('rieval')).single.chunkId, 'en');
    // 跨词片段
    expect((await store.keyword('val pip')).single.chunkId, 'en');
    // 不相关的内容查不到
    expect(await store.keyword('nonexistent'), isEmpty);
  });

  test('short queries fall back to the like path', () async {
    expect(KeywordPlan.forQuery('键').path, KeywordPath.like);
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('zh', body: '键盘操作必须能走完整个流程')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'zh')],
    );
    expect((await store.keyword('键')).single.chunkId, 'zh');
  });

  test('every generation field decides reuse on its own', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('a', hash: 'h1')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'a')],
    );
    expect(await store.canReuse(_generation('h1')), isTrue);

    // sameRecipe 真实比较 6 个字段。逐项改一个，都必须判为不可复用。
    final Map<String, IndexGeneration> changed = <String, IndexGeneration>{
      'contentHash': _generation('h2'),
      'parserName': _generationCopy(parserName: 'docx'),
      'parserVersion': _generationCopy(parserVersion: '2'),
      'chunkerVersion': _generationCopy(chunkerVersion: 'w3-cascade-2'),
      'modelId': _generationCopy(modelId: 'other-model'),
      'vectorDim': _generationCopy(vectorDim: 3),
    };
    for (final MapEntry<String, IndexGeneration> entry in changed.entries) {
      expect(
        await store.canReuse(entry.value),
        isFalse,
        reason: 'changing ${entry.key} must invalidate the generation',
      );
    }
  });

  test('an unnormalized query and a non-positive limit are rejected', () async {
    final SqliteVectorStore store = _memory();
    await store.write(
      <StoredChunk>[_chunk('a', body: 'alpha')],
      <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'a')],
    );

    // 余弦被实现成点积，因此查询向量必须已经 L2 归一化。
    final EmbeddingVector raw = EmbeddingVector(
      values: <double>[3, 4],
      space: EmbeddingSpace.documentText,
      dim: 2,
      modelId: 'test-model',
      normalized: false,
      chunkId: null,
    );
    await expectLater(
      () => store.search(raw),
      throwsA(
        isA<StorageException>().having(
          (StorageException error) => error.failure.kind,
          'kind',
          StorageFailureKind.notNormalized,
        ),
      ),
    );

    // topK 由调用方传入，0 与负数都必须在进 SQL 之前被挡住。
    await expectLater(
      () => store.search(_vector(<double>[1, 0]), topK: 0),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      () => store.keyword('alpha', topK: 0),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a mismatched chunk and vector pair is rejected before writing', () async {
    final SqliteVectorStore store = _memory();
    // 数量不一致
    await expectLater(
      () => store.write(
        <StoredChunk>[_chunk('a'), _chunk('b')],
        <EmbeddingVector>[_vector(<double>[1, 0])],
      ),
      throwsA(isA<ArgumentError>()),
    );
    // chunkId 对不上
    await expectLater(
      () => store.write(
        <StoredChunk>[_chunk('a')],
        <EmbeddingVector>[_vector(<double>[1, 0], chunkId: 'b')],
      ),
      throwsA(
        isA<StorageException>().having(
          (StorageException error) => error.failure.kind,
          'kind',
          StorageFailureKind.conflict,
        ),
      ),
    );
    // 模态与空间不匹配
    await expectLater(
      () => store.write(
        <StoredChunk>[_chunk('a', modality: Modality.image, body: '')],
        <EmbeddingVector>[_vector(<double>[1, 0])],
      ),
      throwsA(
        isA<StorageException>().having(
          (StorageException error) => error.failure.kind,
          'kind',
          StorageFailureKind.spaceMismatch,
        ),
      ),
    );
    // 三次都被拒，库里不应留下任何行。
    expect(_count(store, 'chunk'), 0);
  });

  test('pruning keeps tied rows so the top-k matches a full sort', () async {
    // 回归用例：剪枝曾按「第 topK 名之后全删」收缩。当收缩发生时有多行同分，
    // 其中 tie-break 最优的那行可能正好被删掉，于是结果与全量排序不一致。
    //
    // 构造：topK=2 → 收缩阈值 8。
    //   1 行高分 0.9（必定入选）
    //   8 行同分 0.5，其中只有最后一行的路径最小（tie-break 最优）
    //   其余行 0.4（低于阈值，应被剪掉）
    // 正确结果必须是 [0.9 那行, 路径最小的 0.5 那行]。
    final SqliteVectorStore store = _memory();
    const int topK = 2;

    StoredChunk chunkAt(int index, String path) {
      return _chunk(
        'c$index',
        documentId: 'doc-$index',
        relativePath: path,
        body: 'body$index',
        hash: 'h$index',
      );
    }

    EmbeddingVector vectorAt(double score, int index) {
      // dim=2，[score, 0] 与自身点积即 score（已归一化由 _vector 保证为 1，
      // 这里改为直接给单位向量的分量，使点积等于 score 的平方根比例）。
      final double value = score <= 0 ? 0 : score;
      return EmbeddingVector(
        values: <double>[value, 0],
        space: EmbeddingSpace.documentText,
        dim: 2,
        modelId: 'test-model',
        normalized: true,
        chunkId: 'c$index',
      );
    }

    final List<StoredChunk> chunks = <StoredChunk>[
      chunkAt(0, 'zzz-high.txt'),
      for (var index = 1; index <= 7; index++) chunkAt(index, 'zzz-$index.txt'),
      chunkAt(8, 'aaa-best.txt'),
      for (var index = 9; index < 30; index++) chunkAt(index, 'mmm-$index.txt'),
    ];
    final List<EmbeddingVector> vectors = <EmbeddingVector>[
      vectorAt(0.9, 0),
      for (var index = 1; index <= 8; index++) vectorAt(0.5, index),
      for (var index = 9; index < 30; index++) vectorAt(0.2, index),
    ];
    await store.write(chunks, vectors);

    final List<ScoredId> hits = await store.search(
      _vector(<double>[1, 0]),
      topK: topK,
    );
    expect(
      hits.map((ScoredId hit) => hit.relativePath),
      <String>['zzz-high.txt', 'aaa-best.txt'],
    );
  });

  test('candidate and result tie-break stay in the same order', () {
    // 两阶段查询用 ScoredCandidate 选候选，最终展示用 ScoredId。
    // 两条排序必须同序，否则「先选候选再回表」会悄悄改变名次。
    List<String> label(String relativePath, int? pageNumber, int startOffset) {
      return <String>[
        if (relativePath != 'a.txt') relativePath,
        '${pageNumber ?? 'null'}:$startOffset',
      ];
    }

    final List<ScoredId> byResult = <ScoredId>[
      _scored(1, 'b.txt', null, 0),
      _scored(2, 'a.txt', 2, 0),
      _scored(3, 'a.txt', null, 0),
      _scored(4, 'a.txt', 2, 5),
    ]..sort(ScoredId.compareTie);

    final List<ScoredCandidate> byCandidate = <ScoredCandidate>[
      const ScoredCandidate(rowId: 1, relativePath: 'b.txt', pageNumber: null, startOffset: 0, score: 0.5),
      const ScoredCandidate(rowId: 2, relativePath: 'a.txt', pageNumber: 2, startOffset: 0, score: 0.5),
      const ScoredCandidate(rowId: 3, relativePath: 'a.txt', pageNumber: null, startOffset: 0, score: 0.5),
      const ScoredCandidate(rowId: 4, relativePath: 'a.txt', pageNumber: 2, startOffset: 5, score: 0.5),
    ]..sort(ScoredCandidate.compareTie);

    final List<String> resultOrder = <String>[
      for (final ScoredId hit in byResult)
        ...label(hit.relativePath, hit.pageNumber, hit.startOffset),
    ];
    final List<String> candidateOrder = <String>[
      for (final ScoredCandidate hit in byCandidate)
        ...label(hit.relativePath, hit.pageNumber, hit.startOffset),
    ];
    expect(resultOrder, candidateOrder);
    expect(candidateOrder, <String>['2:0', '2:5', 'null:0', 'b.txt', 'null:0']);
  });

  test('empty extension set and modality filter apply in sql', () async {    final SqliteVectorStore store = _memory();
    const ImageAsset asset = ImageAsset(format: 'png', width: 2, height: 2);
    await store.write(
      <StoredChunk>[
        _chunk('txt', body: 'alpha', relativePath: 'a.txt', extension: '.txt'),
        _chunk('pdf', body: 'beta', relativePath: 'b.pdf', extension: '.pdf'),
        _chunk('pic', documentId: 'doc-2', modality: Modality.image, body: '',
            relativePath: 'c.png', extension: '.png', imageAsset: asset),
      ],
      <EmbeddingVector>[
        _vector(<double>[1, 0]),
        _vector(<double>[0.9, 0.1]),
        _vector(<double>[1, 0], space: EmbeddingSpace.clipShared),
      ],
    );

    // 空集表示没有文件能通过，而不是「不过滤」。
    final List<ScoredId> none = await store.search(
      _vector(<double>[1, 0]),
      filter: const StorageFilter(extensions: <String>{}),
    );
    expect(none, isEmpty);

    // modality 过滤：只有图像能通过。
    final List<ScoredId> images = await store.search(
      _vector(<double>[1, 0], space: EmbeddingSpace.clipShared),
      filter: const StorageFilter(modality: Modality.image),
    );
    expect(images.single.chunkId, 'pic');
  });
}

int _count(SqliteVectorStore store, String table) {
  return store.database.select('SELECT COUNT(*) FROM $table').first.columnAt(0)
      as int;
}

ScoredId _scored(
  int index,
  String relativePath,
  int? pageNumber,
  int startOffset,
) {
  return ScoredId(
    documentId: 'doc-$index',
    chunkId: 'c$index',
    relativePath: relativePath,
    fileName: relativePath,
    startOffset: startOffset,
    endOffset: startOffset + 1,
    body: 'body$index',
    modality: Modality.text,
    score: 0.5,
    pageNumber: pageNumber,
  );
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

/// 只改一个字段的 [IndexGeneration]，用于逐项验证代次判等。
IndexGeneration _generationCopy({
  String? parserName,
  String? parserVersion,
  String? chunkerVersion,
  String? modelId,
  int? vectorDim,
}) {
  return IndexGeneration(
    documentId: 'doc-1',
    contentHash: 'h1',
    parserName: parserName ?? 'txt',
    parserVersion: parserVersion ?? '1',
    chunkerVersion: chunkerVersion ?? 'w3-cascade-1',
    modelId: modelId ?? 'test-model',
    vectorDim: vectorDim ?? 2,
    embeddedAt: DateTime.utc(2026, 10, 20),
  );
}
