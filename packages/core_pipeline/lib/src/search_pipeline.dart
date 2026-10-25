import 'package:core_retrieval/core_retrieval.dart';

/// 查询编排。过滤和取消留在 [Retriever]，这里只转一次调用。
abstract interface class SearchPipeline {
  Future<List<SearchResult>> search(String query, {int topK = 10});
}

final class DefaultSearchPipeline implements SearchPipeline {
  const DefaultSearchPipeline(this.retriever);

  final Retriever retriever;

  @override
  Future<List<SearchResult>> search(String query, {int topK = 10}) {
    return retriever.search(query, topK: topK);
  }
}
