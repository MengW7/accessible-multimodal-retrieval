import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_storage/core_storage.dart';

import 'model/retriever.dart';
import 'model/search_channel.dart';
import 'model/search_filters.dart';
import 'model/search_result.dart';
import 'neighborhood.dart';
import 'query_encoder.dart';
import 'rrf_fusion.dart';

/// 过滤在每一路进存储层之前就带上。扩展只作用于融合后的前 [topK] 条。
final class DefaultRetriever implements Retriever {
  DefaultRetriever({
    required this.store,
    required this.encoder,
    this.fusion = const RrfFusion(),
    this.recallK = 50,
  }) : assert(recallK > 0, 'recallK must be positive');

  final VectorStore store;

  final QueryEncoder encoder;

  final RrfFusion fusion;

  /// 每一路先取这么多，再融合后截到调用方的 `topK`。
  final int recallK;

  /// 上一次 [search] 里编码查询花的毫秒。模型冷加载算在第一次调用上。
  int lastEncodeMs = 0;

  /// 上一次 [search] 里存储查询和邻域读块花的毫秒。
  int lastStoreMs = 0;

  /// 上一次 [search] 里 RRF 融合花的毫秒。
  int lastFuseMs = 0;

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    int topK = 10,
    CancellationToken? cancel,
    Set<SearchChannel>? channels,
    bool expandNeighborhood = true,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(query, 'query', 'must not be empty');
    }
    if (topK < 1) {
      throw ArgumentError.value(topK, 'topK', 'must be positive');
    }
    final Set<SearchChannel> enabled = channels == null
        ? Set<SearchChannel>.of(SearchChannel.values)
        : Set<SearchChannel>.of(channels);
    if (enabled.isEmpty) {
      throw ArgumentError.value(channels, 'channels', 'must not be empty');
    }
    cancel?.throwIfCancelled();
    final bool wantText = enabled.contains(SearchChannel.documentText);
    final bool wantImage = enabled.contains(SearchChannel.clipShared);
    final bool wantKeyword = enabled.contains(SearchChannel.keyword);
    final Stopwatch encodeWatch = Stopwatch()..start();
    QueryVectors? vectors;
    if (wantText || wantImage) {
      vectors = await encoder.encode(
        trimmed,
        includeDocumentText: wantText,
        includeClipText: wantImage,
        cancel: cancel,
      );
    }
    encodeWatch.stop();
    lastEncodeMs = encodeWatch.elapsedMilliseconds;
    final StorageFilter? filter = filters?.toStorageFilter();
    final int limit = topK > recallK ? topK : recallK;
    final Stopwatch storeWatch = Stopwatch()..start();
    final List<ScoredId> text;
    if (wantText) {
      final EmbeddingVector? encoded = vectors?.text;
      if (encoded == null) {
        throw StateError('Document text vector is missing.');
      }
      text = await store.search(encoded, filter: filter, topK: limit);
    } else {
      text = const <ScoredId>[];
    }
    final List<ScoredId> image;
    if (!wantImage) {
      image = const <ScoredId>[];
    } else {
      final EmbeddingVector? clip = vectors?.clip;
      image = clip == null
          ? const <ScoredId>[]
          : await store.search(clip, filter: filter, topK: limit);
    }
    final List<ScoredId> keyword = wantKeyword
        ? await store.keyword(trimmed, filter: filter, topK: limit)
        : const <ScoredId>[];
    storeWatch.stop();
    cancel?.throwIfCancelled();
    final Stopwatch fuseWatch = Stopwatch()..start();
    final List<FusedHit> fused = fusion.fuse(
      text: text,
      keyword: keyword,
      image: image,
    );
    fuseWatch.stop();
    lastFuseMs = fuseWatch.elapsedMilliseconds;
    final int count = fused.length < topK ? fused.length : topK;
    if (!expandNeighborhood) {
      lastStoreMs = storeWatch.elapsedMilliseconds;
      return <SearchResult>[
        for (var index = 0; index < count; index++) _unexpanded(fused[index]),
      ];
    }
    final Stopwatch extraWatch = Stopwatch()..start();
    final List<SearchResult> results = <SearchResult>[];
    final Map<String, List<StoredChunk>> loaded = <String, List<StoredChunk>>{};
    for (var index = 0; index < count; index++) {
      final FusedHit hit = fused[index];
      final String documentId = hit.anchor.documentId;
      final List<StoredChunk> chunks = loaded[documentId] ??=
          await store.chunksForDocument(documentId);
      results.add(expandHit(hit, chunks));
    }
    extraWatch.stop();
    lastStoreMs = storeWatch.elapsedMilliseconds + extraWatch.elapsedMilliseconds;
    return results;
  }
}

SearchResult _unexpanded(FusedHit hit) {
  final ScoredId anchor = hit.anchor;
  return SearchResult(
    documentId: anchor.documentId,
    chunkId: anchor.chunkId,
    chunkIndex: anchor.chunkIndex,
    relativePath: anchor.relativePath,
    fileName: anchor.fileName,
    mimeType: anchor.mimeType,
    pageNumber: anchor.pageNumber,
    startOffset: anchor.startOffset,
    endOffset: anchor.endOffset,
    textUnit: TextUnit.utf16CodeUnit,
    snippet: anchor.body,
    score: hit.score,
    channels: hit.channels,
    modality: anchor.modality,
    imageAsset: anchor.imageAsset,
    documentKey: anchor.documentKey,
  );
}
