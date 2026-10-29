import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:core_storage/core_storage.dart';
import 'package:test/test.dart';

void main() {
  test('rrf ranks the shared hit first and drops an empty channel', () {
    final List<FusedHit> fused = const RrfFusion().fuse(
      text: <ScoredId>[_hit('a'), _hit('b')],
      keyword: <ScoredId>[_hit('b'), _hit('c')],
    );
    expect(
      fused.map((FusedHit hit) => hit.anchor.chunkId),
      <String>['b', 'a', 'c'],
    );
    expect(fused.first.channels, <SearchChannel>{
      SearchChannel.documentText,
      SearchChannel.keyword,
    });
    expect(fused[1].channels, <SearchChannel>{SearchChannel.documentText});
    expect(fused.last.channels, <SearchChannel>{SearchChannel.keyword});
    expect(fused.first.score, closeTo(0.5 / 62 + 0.3 / 61, 1e-12));
  });

  test('image weight keeps an image-only rank 2 inside the top 5', () {
    expect(rrfImageWeight, 0.49);
    expect(rrfTextWeight, 0.5);
    final List<FusedHit> fused = const RrfFusion().fuse(
      text: <ScoredId>[
        for (var index = 0; index < 6; index++) _hit('t$index'),
      ],
      image: <ScoredId>[
        for (var index = 0; index < 6; index++) _hit('i$index'),
      ],
    );
    final List<String> top = fused
        .take(5)
        .map((FusedHit hit) => hit.anchor.chunkId)
        .toList(growable: false);
    expect(top, <String>['t0', 't1', 'i0', 't2', 'i1']);
  });

  test('neighborhood keeps the hit span and stays on the same page', () {
    final StoredChunk previous = _chunk('p', 0, 'before', pageNumber: 2);
    final StoredChunk hit = _chunk('h', 1, 'hit', pageNumber: 2, startOffset: 8);
    final StoredChunk next = _chunk('n', 2, 'after', pageNumber: 2);
    final StoredChunk otherPage = _chunk('x', 0, 'other', pageNumber: 3);
    final SearchResult expanded = expandHit(
      FusedHit(
        anchor: _hit('h', pageNumber: 2, startOffset: 8, endOffset: 11),
        score: 0.2,
        channels: const <SearchChannel>{SearchChannel.documentText},
      ),
      <StoredChunk>[otherPage, previous, hit, next],
    );
    expect(expanded.snippet, 'before\nhit\nafter');
    expect(expanded.startOffset, 8);
    expect(expanded.endOffset, 11);
    expect(expanded.score, 0.2);
    expect(expanded.pageNumber, 2);
    expect(expanded.snippet.contains('other'), isFalse);

    final SearchResult edge = expandHit(
      FusedHit(
        anchor: _hit('p', pageNumber: 2),
        score: 0.1,
        channels: const <SearchChannel>{SearchChannel.keyword},
      ),
      <StoredChunk>[previous, hit, next],
    );
    expect(edge.snippet, 'before\nhit');
    expect(edge.snippet.contains('after'), isFalse);

    final SearchResult unpaged = expandHit(
      FusedHit(
        anchor: _hit('h'),
        score: 0.1,
        channels: const <SearchChannel>{SearchChannel.documentText},
      ),
      <StoredChunk>[_chunk('h', 0, 'only')],
    );
    expect(unpaged.pageNumber, isNull);
    expect(unpaged.snippet, 'only');
  });

  test('neighborhood at the page tail only extends backwards', () {
    final StoredChunk previous = _chunk('p', 0, 'before', pageNumber: 2);
    final StoredChunk hit = _chunk('n', 1, 'last', pageNumber: 2);
    final StoredChunk otherPage = _chunk('x', 0, 'other', pageNumber: 3);
    final SearchResult tail = expandHit(
      FusedHit(
        anchor: _hit('n', pageNumber: 2, startOffset: 8, endOffset: 12),
        score: 0.3,
        channels: const <SearchChannel>{SearchChannel.documentText},
      ),
      <StoredChunk>[previous, hit, otherPage],
    );
    expect(tail.snippet, 'before\nlast');
    expect(tail.snippet.contains('other'), isFalse);
    expect(tail.startOffset, 8);
    expect(tail.endOffset, 12);
    expect(tail.pageNumber, 2);
  });

  test('a query encodes both spaces and degrades when the image tower is missing', () async {
    final _Engine engine = _Engine();
    final QueryEncoder encoder = QueryEncoder(engine);
    final QueryVectors both = await encoder.encode('离线检索');
    expect(engine.calls, 2);
    expect(both.text?.space, EmbeddingSpace.documentText);
    expect(both.clip?.space, EmbeddingSpace.clipShared);
    expect(engine.texts.take(2), <String?>['离线检索', '离线检索']);

    engine.clipError = const EmbeddingSpaceMismatchException(
      requested: EmbeddingSpace.clipShared,
      actual: EmbeddingSpace.documentText,
    );
    final QueryVectors degraded = await encoder.encode('离线检索');
    expect(degraded.clip, isNull);
    expect(engine.calls, 4);
  });

  test('clip text uses offline glosses and document text stays the query', () async {
    final _Engine engine = _Engine();
    await QueryEncoder(engine).encode('哪张图里有人在厨房做披萨');
    expect(engine.texts, <String?>[
      '哪张图里有人在厨房做披萨',
      'person kitchen pizza',
    ]);
    expect(engine.spaces, <EmbeddingSpace>[
      EmbeddingSpace.documentText,
      EmbeddingSpace.clipShared,
    ]);

    engine.texts.clear();
    engine.spaces.clear();
    await QueryEncoder(engine).encode('Tika 的文档');
    expect(engine.texts, <String?>['Tika 的文档', 'Tika document']);
  });

  test('cancellation is not treated as a missing image tower', () async {
    final _Engine engine = _Engine()..cancelOnClip = true;
    expect(
      QueryEncoder(engine).encode('离线检索'),
      throwsA(isA<CancelledException>()),
    );
  });

  test('search fuses the three lists and passes filters into the store', () async {
    final _Store store = _Store()
      ..textHits = <ScoredId>[_hit('a'), _hit('b')]
      ..keywordHits = <ScoredId>[_hit('b'), _hit('c')]
      ..chunks = <String, List<StoredChunk>>{
        'doc': <StoredChunk>[
          _chunk('a', 0, 'alpha'),
          _chunk('b', 1, 'beta'),
          _chunk('c', 2, 'gamma'),
        ],
      };
    final DefaultRetriever retriever = DefaultRetriever(
      store: store,
      encoder: QueryEncoder(_Engine()),
    );
    final List<SearchResult> results = await retriever.search(
      '离线',
      filters: SearchFilters(extensions: <String>{'.md'}, pathPrefix: 'docs'),
      topK: 2,
    );
    expect(results.map((SearchResult hit) => hit.chunkId), <String>['b', 'a']);
    expect(results.first.snippet, 'alpha\nbeta\ngamma');
    expect(store.textSearches, 1);
    expect(store.imageSearches, 1);
    expect(store.keywordQueries, <String>['离线']);
    expect(store.lastFilter?.extensions, <String>{'.md'});
    expect(store.lastFilter?.pathPrefix, 'docs');
  });

  test('a missing image vector skips that channel', () async {
    final _Engine engine = _Engine()
      ..clipError = const EmbeddingRuntimeException('image tower missing');
    final _Store store = _Store()..textHits = <ScoredId>[_hit('a')];
    final List<SearchResult> results = await DefaultRetriever(
      store: store,
      encoder: QueryEncoder(engine),
    ).search('问句');
    expect(results.single.chunkId, 'a');
    expect(store.imageSearches, 0);
  });

  test('a query over the clip budget degrades instead of throwing', () async {
    // MobileCLIP pads to exactly 77 tokens and the encoder does not truncate, so
    // a long query raises TextOverBudgetException from the clip tower. Before
    // the fix that exception escaped `search()` and the whole query failed even
    // though the text channel could still answer.
    final _Engine engine = _Engine()
      ..clipError = const TextOverBudgetException(tokenCount: 79, maxLength: 77);
    final _Store store = _Store()..textHits = <ScoredId>[_hit('a')];
    final List<SearchResult> results = await DefaultRetriever(
      store: store,
      encoder: QueryEncoder(engine),
    ).search('一个很长很长的问句');
    expect(results.single.chunkId, 'a');
    expect(store.textSearches, 1);
    expect(store.imageSearches, 0);
  });

  test('a query over the text budget is a typed error, not a crash', () async {
    final _Engine engine = _Engine()
      ..textError = const TextOverBudgetException(
        tokenCount: 200,
        maxLength: 128,
      );
    final _Store store = _Store();
    await expectLater(
      DefaultRetriever(
        store: store,
        encoder: QueryEncoder(engine),
      ).search('超长问句'),
      throwsA(isA<QueryTooLongException>()),
    );
    expect(store.textSearches, 0);
  });

  test('a keyword-only arm skips encoding and neighborhood', () async {
    final _Engine engine = _Engine();
    final _Store store = _Store()
      ..keywordHits = <ScoredId>[_hit('b')]
      ..chunks = <String, List<StoredChunk>>{
        'doc': <StoredChunk>[
          _chunk('a', 0, 'alpha'),
          _chunk('b', 1, 'beta'),
        ],
      };
    final List<SearchResult> results = await DefaultRetriever(
      store: store,
      encoder: QueryEncoder(engine),
    ).search(
      '离线',
      channels: const <SearchChannel>{SearchChannel.keyword},
      expandNeighborhood: false,
    );
    expect(engine.calls, 0);
    expect(store.textSearches, 0);
    expect(store.imageSearches, 0);
    expect(results.single.snippet, 'b');
    expect(results.single.channels, <SearchChannel>{SearchChannel.keyword});
  });

  test('an empty query or a non-positive limit is rejected', () async {
    final DefaultRetriever retriever = DefaultRetriever(
      store: _Store(),
      encoder: QueryEncoder(_Engine()),
    );
    expect(() => retriever.search('   '), throwsArgumentError);
    expect(() => retriever.search('问句', topK: 0), throwsArgumentError);
  });
}

ScoredId _hit(
  String chunkId, {
  int? pageNumber,
  int startOffset = 0,
  int endOffset = 4,
}) {
  return ScoredId(
    documentId: 'doc',
    chunkId: chunkId,
    relativePath: 'docs/$chunkId.txt',
    fileName: '$chunkId.txt',
    startOffset: startOffset,
    endOffset: endOffset,
    body: chunkId,
    modality: Modality.text,
    score: 1,
    pageNumber: pageNumber,
    chunkIndex: 0,
  );
}

StoredChunk _chunk(
  String chunkId,
  int chunkIndex,
  String body, {
  int? pageNumber,
  int startOffset = 0,
}) {
  return StoredChunk(
    documentId: 'doc',
    chunkId: chunkId,
    relativePath: 'docs/$chunkId.txt',
    fileName: '$chunkId.txt',
    startOffset: startOffset,
    endOffset: startOffset + body.length,
    body: body,
    modality: Modality.text,
    pageNumber: pageNumber,
    chunkIndex: chunkIndex,
  );
}

final class _Engine implements EmbeddingEngine {
  int calls = 0;

  final List<String?> texts = <String?>[];

  final List<EmbeddingSpace> spaces = <EmbeddingSpace>[];

  Object? clipError;

  Object? textError;

  bool cancelOnClip = false;

  @override
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  }) async {
    calls += 1;
    texts.add(input.text);
    spaces.add(input.space);
    cancel?.throwIfCancelled();
    if (input.space == EmbeddingSpace.clipShared) {
      if (cancelOnClip) {
        throw const CancelledException();
      }
      final Object? error = clipError;
      if (error != null) {
        throw error;
      }
    } else {
      final Object? error = textError;
      if (error != null) {
        throw error;
      }
    }
    return EmbeddingVector(
      values: const <double>[1, 0],
      space: input.space,
      dim: 2,
      modelId: 'test-model',
      normalized: true,
    );
  }

  @override
  List<ModelInfo> get models => const <ModelInfo>[];
}

final class _Store implements VectorStore {
  List<ScoredId> textHits = const <ScoredId>[];
  List<ScoredId> imageHits = const <ScoredId>[];
  List<ScoredId> keywordHits = const <ScoredId>[];
  Map<String, List<StoredChunk>> chunks = <String, List<StoredChunk>>{};
  int textSearches = 0;
  int imageSearches = 0;
  final List<String> keywordQueries = <String>[];
  StorageFilter? lastFilter;

  @override
  Future<List<ScoredId>> search(
    EmbeddingVector query, {
    StorageFilter? filter,
    int topK = 50,
  }) async {
    lastFilter = filter;
    final List<ScoredId> source = query.space == EmbeddingSpace.clipShared
        ? imageHits
        : textHits;
    if (query.space == EmbeddingSpace.clipShared) {
      imageSearches += 1;
    } else {
      textSearches += 1;
    }
    return source.take(topK).toList(growable: false);
  }

  @override
  Future<List<ScoredId>> keyword(
    String query, {
    StorageFilter? filter,
    int topK = 50,
  }) async {
    lastFilter = filter;
    keywordQueries.add(query);
    return keywordHits.take(topK).toList(growable: false);
  }

  @override
  Future<List<StoredChunk>> chunksForDocument(String documentId) async {
    return chunks[documentId] ?? const <StoredChunk>[];
  }

  @override
  Future<WriteOutcome> write(
    Iterable<StoredChunk> chunks,
    Iterable<EmbeddingVector> vectors,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteDocument(String documentId) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<IndexStats> stats() async {
    return const IndexStats(
      chunks: 0,
      documents: 0,
      documentText: 0,
      clipShared: 0,
      keywordTerms: 0,
    );
  }

  @override
  Future<bool> canReuse(IndexGeneration generation) async => false;
}
