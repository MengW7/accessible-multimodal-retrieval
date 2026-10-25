import 'package:core_embedding/core_embedding.dart';
import 'package:core_storage/core_storage.dart';

import 'model/search_result.dart';
import 'rrf_fusion.dart';

/// 排序之后再扩展。分数、顺序和命中跨度都不变。
///
/// 只拼接同一 `pageNumber` 上 `chunkIndex ± 1` 的正文。页的两端缺一侧就不补，
/// 也不到邻页去借。`pageNumber == null` 仍是 null，只是这些块之间可以互为相邻。
SearchResult expandHit(FusedHit hit, List<StoredChunk> documentChunks) {
  final ScoredId anchor = hit.anchor;
  final StoredChunk? self = _match(anchor, documentChunks);
  return SearchResult(
    documentId: anchor.documentId,
    chunkId: anchor.chunkId,
    chunkIndex: self?.chunkIndex ?? anchor.chunkIndex,
    relativePath: anchor.relativePath,
    fileName: anchor.fileName,
    mimeType: anchor.mimeType,
    pageNumber: anchor.pageNumber,
    startOffset: anchor.startOffset,
    endOffset: anchor.endOffset,
    textUnit: TextUnit.utf16CodeUnit,
    snippet: self == null ? anchor.body : _snippet(self, documentChunks),
    score: hit.score,
    channels: hit.channels,
    modality: anchor.modality,
    imageAsset: anchor.imageAsset,
    documentKey: anchor.documentKey,
  );
}

StoredChunk? _match(ScoredId hit, List<StoredChunk> chunks) {
  for (final StoredChunk chunk in chunks) {
    if (chunk.documentId == hit.documentId && chunk.chunkId == hit.chunkId) {
      return chunk;
    }
  }
  return null;
}

String _snippet(StoredChunk hit, List<StoredChunk> chunks) {
  final int? index = hit.chunkIndex;
  if (index == null) {
    return hit.body;
  }
  StoredChunk? previous;
  StoredChunk? next;
  for (final StoredChunk chunk in chunks) {
    if (chunk.pageNumber != hit.pageNumber || chunk.chunkIndex == null) {
      continue;
    }
    if (chunk.chunkIndex == index - 1) {
      previous = chunk;
    } else if (chunk.chunkIndex == index + 1) {
      next = chunk;
    }
  }
  return <String>[
    if (previous != null && previous.body.isNotEmpty) previous.body,
    hit.body,
    if (next != null && next.body.isNotEmpty) next.body,
  ].join('\n');
}
