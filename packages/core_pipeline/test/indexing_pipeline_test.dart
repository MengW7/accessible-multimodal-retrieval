import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:core_storage/core_storage.dart';
import 'package:test/test.dart';

void main() {
  test('a matching generation skips embedding', () async {
    final _Engine engine = _Engine();
    final _Store store = _Store()..reusable.add('h1:text-model');
    final IndexReport report = await _pipeline(
      engine: engine,
      store: store,
      records: <IngestRecord>[_record('h1', 'hello')],
    ).index('root');
    expect(report.reused, 1);
    expect(report.written, 0);
    expect(engine.calls, 0);
    expect(store.writes, isEmpty);
  });

  test('force rebuilds and a bad file does not stop the next one', () async {
    final _Engine engine = _Engine();
    final _Chunker chunker = _Chunker();
    final _Store store = _Store()..reusable.add('h1:text-model');
    final IndexReport report = await _pipeline(
      engine: engine,
      store: store,
      chunker: chunker,
      records: <IngestRecord>[
        _record('bad', 'bad'),
        _record('h1', 'hello'),
      ],
    ).index('root', force: true);
    expect(report.failed, 1);
    expect(report.written, 1);
    expect(report.chunksWritten, 1);
    expect(store.writes.single.single.body, 'hello-0');
    expect(engine.calls, 1);
  });

  test('the second chunk is embedded before anything is written', () async {
    final _Engine engine = _Engine()..failOnCall = 2;
    final _Store store = _Store();
    final IndexReport report = await _pipeline(
      engine: engine,
      store: store,
      chunker: _Chunker()..pieces = 2,
      records: <IngestRecord>[_record('h1', 'hello')],
    ).index('root');
    expect(report.failed, 1);
    expect(report.written, 0);
    expect(store.writes, isEmpty);
    expect(engine.calls, 2);
  });

  test('cancel after the first file keeps that write', () async {
    final CancellationTokenSource source = CancellationTokenSource();
    final _Store store = _Store();
    final List<IndexProgress> progress = <IndexProgress>[];
    final IndexReport report = await _pipeline(
      engine: _Engine(),
      store: store,
      records: <IngestRecord>[_record('h1', 'one'), _record('h2', 'two')],
    ).index(
      'root',
      cancel: source.token,
      onProgress: (IndexProgress update) {
        progress.add(update);
        if (update.processed == 1) {
          source.cancel();
        }
      },
    );
    expect(report.cancelled, isTrue);
    expect(report.written, 1);
    expect(store.writes.single.single.documentId, 'h1');
    expect(progress.first.total, 2);
    expect(progress.last.processed, 1);
    expect(progress.last.total, 2);
  });

  test('an image file is stored in the shared space without a text chunker version', () async {
    const ImageAsset asset = ImageAsset(format: 'png', width: 1, height: 1);
    final _Store store = _Store();
    final IndexReport report = await _pipeline(
      engine: _Engine(),
      store: store,
      records: <IngestRecord>[
        _record('h1', '', image: asset, extension: '.png'),
      ],
    ).index('root');
    expect(report.written, 1);
    final StoredChunk chunk = store.writes.single.single;
    expect(chunk.modality, Modality.image);
    expect(chunk.chunkerVersion, 'none');
    expect(chunk.imageAsset, asset);
    expect(store.vectors.single.single.space, EmbeddingSpace.clipShared);
  });

  test('search pipeline forwards the limit', () async {
    final _Retriever retriever = _Retriever();
    final List<SearchResult> results = await DefaultSearchPipeline(retriever).search(
      '离线',
      topK: 3,
    );
    expect(retriever.queries, <String>['离线']);
    expect(retriever.limits, <int>[3]);
    expect(results, isEmpty);
  });

  test('a document key can use the repository path', () async {
    final _Store store = _Store();
    final IndexReport report = await _pipeline(
      engine: _Engine(),
      store: store,
      records: <IngestRecord>[_record('h1', 'hello')],
      documentKeyOf: (FileMetadata metadata) {
        return 'datasets/samples/${metadata.relativePath}';
      },
    ).index('root');
    expect(report.written, 1);
    expect(store.writes.single.single.documentKey, 'datasets/samples/h1.txt');
  });

  test('blank chunks fail the file and write nothing', () async {
    final _Store store = _Store();
    final IndexReport report = await _pipeline(
      engine: _Engine(),
      store: store,
      chunker: _Chunker()..blank = true,
      records: <IngestRecord>[_record('h1', 'hello')],
    ).index('root');
    expect(report.failed, 1);
    expect(report.written, 0);
    expect(store.writes, isEmpty);
  });

  test('cancellation before the image embed writes nothing', () async {
    final CancellationTokenSource source = CancellationTokenSource();
    const ImageAsset asset = ImageAsset(format: 'png', width: 1, height: 1);
    final _Store store = _Store()..onReuse = source.cancel;
    final IndexReport report = await _pipeline(
      engine: _Engine(),
      store: store,
      records: <IngestRecord>[
        _record('h1', '', image: asset, extension: '.png'),
      ],
    ).index('root', cancel: source.token);
    expect(report.cancelled, isTrue);
    expect(report.written, 0);
    expect(store.writes, isEmpty);
  });
}

DefaultIndexingPipeline _pipeline({
  required _Engine engine,
  required _Store store,
  _Chunker? chunker,
  required List<IngestRecord> records,
  String Function(FileMetadata metadata)? documentKeyOf,
}) {
  return DefaultIndexingPipeline(
    source: _Source(records),
    engine: engine,
    store: store,
    chunker: chunker ?? _Chunker(),
    images: const _Images(),
    textModel: const ModelInfo(
      modelId: 'text-model',
      space: EmbeddingSpace.documentText,
      dim: 2,
      pooling: 'mean',
      normalized: true,
      maxInputLength: 8,
    ),
    imageModel: const ModelInfo(
      modelId: 'image-model',
      space: EmbeddingSpace.clipShared,
      dim: 2,
      pooling: 'none',
      normalized: true,
    ),
    chunkerVersion: 'w3-cascade-1',
    documentKeyOf: documentKeyOf,
  );
}

IngestRecord _record(
  String hash,
  String text, {
  ImageAsset? image,
  String extension = '.txt',
}) {
  return IngestRecord(
    metadata: FileMetadata(
      id: 'id-$hash',
      path: 'C:/docs/$hash$extension',
      relativePath: '$hash$extension',
      fileName: '$hash$extension',
      extension: extension,
      sizeBytes: text.length,
      contentHash: hash == 'bad' ? 'bad-hash' : hash,
      parserName: 'txt',
      parserVersion: '1',
      status: ParseOutcome.ok,
      imageAsset: image,
    ),
    document: ParsedDocument(fullText: text, imageAsset: image),
  );
}

final class _Source implements IndexSource {
  _Source(this.records);

  final List<IngestRecord> records;

  @override
  Future<IngestionReport> load(String rootPath, {CancellationToken? cancel}) async {
    final DateTime now = DateTime.utc(2026, 10, 20);
    return IngestionReport(
      rootPath: rootPath,
      startedAt: now,
      finishedAt: now,
      records: records,
    );
  }
}

final class _Chunker implements TextChunker {
  int pieces = 1;

  bool blank = false;

  @override
  List<TextChunk> chunk(ParsedDocument document, {String? documentId}) {
    if (document.fullText == 'bad') {
      throw const FormatException('bad file');
    }
    if (blank) {
      return <TextChunk>[
        TextChunk(
          chunkId: 'blank',
          text: ' \n',
          startOffset: 0,
          endOffset: 2,
          textUnit: TextUnit.utf16CodeUnit,
          chunkerVersion: 'w3-cascade-1',
        ),
      ];
    }
    return <TextChunk>[
      for (var index = 0; index < pieces; index++)
        TextChunk(
          chunkId: '${documentId ?? 'doc'}-$index',
          text: '${document.fullText}-$index',
          startOffset: 0,
          endOffset: document.fullText.length,
          textUnit: TextUnit.utf16CodeUnit,
          chunkerVersion: 'w3-cascade-1',
          pageNumber: 1,
        ),
    ];
  }
}

final class _Engine implements EmbeddingEngine {
  int calls = 0;

  int failOnCall = 0;

  @override
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  }) async {
    calls += 1;
    cancel?.throwIfCancelled();
    if (failOnCall == calls) {
      throw StateError('embed failed');
    }
    return EmbeddingVector(
      values: const <double>[1, 0],
      space: input.space,
      dim: 2,
      modelId: input.isImage ? 'image-model' : 'text-model',
      normalized: true,
      chunkId: input.chunkId,
    );
  }

  @override
  List<ModelInfo> get models => const <ModelInfo>[];
}

final class _Images implements ImageDecoder {
  const _Images();

  @override
  DecodedImage decodeFile(String path) {
    return DecodedImage(rgb24: Uint8List.fromList(<int>[1, 2, 3]), width: 1, height: 1);
  }
}

final class _Store implements VectorStore {
  final Set<String> reusable = <String>{};
  final List<List<StoredChunk>> writes = <List<StoredChunk>>[];
  final List<List<EmbeddingVector>> vectors = <List<EmbeddingVector>>[];

  void Function()? onReuse;

  @override
  Future<bool> canReuse(IndexGeneration generation) async {
    onReuse?.call();
    return reusable.contains('${generation.documentId}:${generation.modelId}');
  }

  @override
  Future<WriteOutcome> write(
    Iterable<StoredChunk> chunks,
    Iterable<EmbeddingVector> vectors,
  ) async {
    final List<StoredChunk> stored = chunks.toList(growable: false);
    writes.add(stored);
    this.vectors.add(vectors.toList(growable: false));
    return WriteOutcome(written: stored.length, documents: 1);
  }

  @override
  Future<List<ScoredId>> search(
    EmbeddingVector query, {
    StorageFilter? filter,
    int topK = 50,
  }) async => const <ScoredId>[];

  @override
  Future<List<ScoredId>> keyword(
    String query, {
    StorageFilter? filter,
    int topK = 50,
  }) async => const <ScoredId>[];

  @override
  Future<List<StoredChunk>> chunksForDocument(String documentId) async {
    return const <StoredChunk>[];
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
}

final class _Retriever implements Retriever {
  final List<String> queries = <String>[];
  final List<int> limits = <int>[];

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    int topK = 10,
    CancellationToken? cancel,
    Set<SearchChannel>? channels,
    bool expandNeighborhood = true,
  }) async {
    queries.add(query);
    limits.add(topK);
    return const <SearchResult>[];
  }
}
