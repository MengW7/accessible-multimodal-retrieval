import 'package:core_embedding/core_embedding.dart';
import 'package:core_storage/core_storage.dart';
import 'package:meta/meta.dart';

import 'search_channel.dart';

/// 一条可以直接播报的检索结果。
///
/// [snippet] 可以带同页相邻块的上下文。[startOffset] 和 [endOffset] 始终是
/// 命中块自己的跨度，不是扩展后的跨度。[pageNumber] 为 null 时不是真实页码。
@immutable
class SearchResult {
  const SearchResult({
    required this.documentId,
    required this.chunkId,
    required this.relativePath,
    required this.fileName,
    required this.startOffset,
    required this.endOffset,
    required this.textUnit,
    required this.snippet,
    required this.score,
    required this.channels,
    required this.modality,
    this.chunkIndex,
    this.mimeType,
    this.pageNumber,
    this.imageAsset,
    this.documentKey,
  });

  final String documentId;

  /// 回指切块结果，不是主键。
  final String chunkId;

  final int? chunkIndex;

  final String relativePath;

  final String fileName;

  final String? mimeType;

  /// 1-based。没有物理页时为 null。
  final int? pageNumber;

  final int startOffset;

  final int endOffset;

  final TextUnit textUnit;

  final String snippet;

  /// RRF 分数。各路原始余弦不在这里比较。
  final double score;

  final Set<SearchChannel> channels;

  final Modality modality;

  /// 图像命中时是 `ImageAsset`。文本命中为 null。
  final Object? imageAsset;

  /// 相对仓库根的路径。评测集用它对齐，不参与打分。
  final String? documentKey;
}
