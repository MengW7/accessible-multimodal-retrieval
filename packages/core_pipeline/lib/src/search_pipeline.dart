import 'package:core_parsing/core_parsing.dart';
import 'package:core_retrieval/core_retrieval.dart';

/// 查询编排。
///
/// 过滤、取消、通道选择与邻域扩展都实现于 [Retriever]；这一层不做打分，
/// 只把调用约定带全，避免上层（探针、W5 的 UI）各自拼参数时丢东西。
abstract interface class SearchPipeline {
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    int topK = 10,
    CancellationToken? cancel,
    Set<SearchChannel>? channels,
    bool expandNeighborhood = true,
  });
}

final class DefaultSearchPipeline implements SearchPipeline {
  const DefaultSearchPipeline(this.retriever);

  final Retriever retriever;

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    int topK = 10,
    CancellationToken? cancel,
    Set<SearchChannel>? channels,
    bool expandNeighborhood = true,
  }) {
    return retriever.search(
      query,
      filters: filters,
      topK: topK,
      cancel: cancel,
      channels: channels,
      expandNeighborhood: expandNeighborhood,
    );
  }
}
