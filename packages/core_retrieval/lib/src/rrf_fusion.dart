import 'package:core_storage/core_storage.dart';
import 'package:meta/meta.dart';

import 'model/search_channel.dart';

/// RRF 的常规 k。不是在开发集上调出来的。
const int rrfK = 60;

/// 开工时冻结的三路权重：文本向量、关键词、图像。
const double rrfTextWeight = 0.5;
const double rrfKeywordWeight = 0.3;
const double rrfImageWeight = 0.2;

/// 融合后的一条。分数只来自名次。
@immutable
class FusedHit {
  const FusedHit({
    required this.anchor,
    required this.score,
    required this.channels,
  });

  /// 展示用的那一路原命中。分数仍是那一路自己的分数。
  final ScoredId anchor;

  final double score;

  final Set<SearchChannel> channels;
}

/// `score = Σ w_i / (k + rank_i)`，rank 从 1 开始。
///
/// 某一路没有出现就略过，不补 0 名次。同一路里同一块只取第一次出现的名次。
class RrfFusion {
  const RrfFusion({
    this.k = rrfK,
    this.textWeight = rrfTextWeight,
    this.keywordWeight = rrfKeywordWeight,
    this.imageWeight = rrfImageWeight,
  }) : assert(k > 0, 'k must be positive');

  final int k;

  final double textWeight;

  final double keywordWeight;

  final double imageWeight;

  List<FusedHit> fuse({
    List<ScoredId> text = const <ScoredId>[],
    List<ScoredId> keyword = const <ScoredId>[],
    List<ScoredId> image = const <ScoredId>[],
  }) {
    final Map<String, _Accumulator> rows = <String, _Accumulator>{};
    _add(rows, text, textWeight, SearchChannel.documentText);
    _add(rows, keyword, keywordWeight, SearchChannel.keyword);
    _add(rows, image, imageWeight, SearchChannel.clipShared);
    final List<FusedHit> fused = <FusedHit>[
      for (final _Accumulator row in rows.values)
        FusedHit(
          anchor: row.anchor,
          score: row.score,
          channels: Set<SearchChannel>.unmodifiable(row.channels),
        ),
    ];
    fused.sort((FusedHit left, FusedHit right) {
      return ScoredId.compareTie(
        _scored(left),
        _scored(right),
      );
    });
    return fused;
  }

  void _add(
    Map<String, _Accumulator> rows,
    List<ScoredId> ranked,
    double weight,
    SearchChannel channel,
  ) {
    if (weight == 0 || ranked.isEmpty) {
      return;
    }
    final Set<String> seen = <String>{};
    for (var index = 0; index < ranked.length; index++) {
      final ScoredId hit = ranked[index];
      final String key = '${hit.documentId}\u0000${hit.chunkId}';
      if (!seen.add(key)) {
        continue;
      }
      final _Accumulator row = rows.putIfAbsent(key, () => _Accumulator(hit));
      row.score += weight / (k + index + 1);
      row.channels.add(channel);
    }
  }

  ScoredId _scored(FusedHit hit) {
    return ScoredId(
      documentId: hit.anchor.documentId,
      chunkId: hit.anchor.chunkId,
      chunkIndex: hit.anchor.chunkIndex,
      relativePath: hit.anchor.relativePath,
      documentKey: hit.anchor.documentKey,
      fileName: hit.anchor.fileName,
      mimeType: hit.anchor.mimeType,
      pageNumber: hit.anchor.pageNumber,
      startOffset: hit.anchor.startOffset,
      endOffset: hit.anchor.endOffset,
      body: hit.anchor.body,
      imageAsset: hit.anchor.imageAsset,
      modality: hit.anchor.modality,
      score: hit.score,
    );
  }
}

class _Accumulator {
  _Accumulator(this.anchor);

  final ScoredId anchor;

  double score = 0;

  final Set<SearchChannel> channels = <SearchChannel>{};
}
