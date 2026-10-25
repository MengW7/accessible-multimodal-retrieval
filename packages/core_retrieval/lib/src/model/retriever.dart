import 'package:core_parsing/core_parsing.dart';

import 'search_channel.dart';
import 'search_filters.dart';
import 'search_result.dart';

/// 三路召回、RRF 融合、邻域扩展。不碰文件系统。
abstract interface class Retriever {
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    int topK = 10,
    CancellationToken? cancel,
    Set<SearchChannel>? channels,
    bool expandNeighborhood = true,
  });
}
