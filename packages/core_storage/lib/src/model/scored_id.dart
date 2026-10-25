import 'package:meta/meta.dart';

import 'modality.dart';

/// 单路查询的一条命中。分数只在这一路内有意义。
@immutable
class ScoredId {
  const ScoredId({
    required this.documentId,
    required this.chunkId,
    required this.relativePath,
    required this.fileName,
    required this.startOffset,
    required this.endOffset,
    required this.body,
    required this.modality,
    required this.score,
    this.chunkIndex,
    this.mimeType,
    this.pageNumber,
    this.imageAsset,
    this.documentKey,
  });

  final String documentId;

  final String chunkId;

  final int? chunkIndex;

  final String relativePath;

  final String fileName;

  final String? mimeType;

  final int? pageNumber;

  final int startOffset;

  final int endOffset;

  final String body;

  final Object? imageAsset;

  final Modality modality;

  final double score;

  final String? documentKey;

  /// 分数降序，路径升序，页码升序且 null 在后，偏移升序。
  static int compareTie(ScoredId left, ScoredId right) {
    final int score = right.score.compareTo(left.score);
    if (score != 0) {
      return score;
    }
    final int path = left.relativePath.compareTo(right.relativePath);
    if (path != 0) {
      return path;
    }
    final int page = _page(left.pageNumber, right.pageNumber);
    if (page != 0) {
      return page;
    }
    return left.startOffset.compareTo(right.startOffset);
  }

  static int _page(int? left, int? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }
}
