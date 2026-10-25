# 检索模块 API

Week 4 定稿。三路召回之后做 RRF，再按需要做同页邻域扩展。下面列出的是 `lib/core_retrieval.dart` 已经导出的符号。权重和 `k` 在这里是常量，不在评测集上搜索。

## 1. 调用约定

外部代码 import：

```dart
import 'package:core_retrieval/core_retrieval.dart';
```

一次默认检索：

```dart
final Retriever retriever = DefaultRetriever(
  store: store,
  encoder: QueryEncoder(engine),
);
final List<SearchResult> hits = await retriever.search(
  '工具靠什么判断文件类型？',
  topK: 10,
);
// hits.first.documentKey 相对仓库根
// hits.first.pageNumber 没有物理页时为 null
// hits.first.startOffset 仍是命中块自己的起点
```

`store` 是 `package:core_storage` 的 `VectorStore`。`engine` 是 `package:core_embedding` 的 `EmbeddingEngine`。取消令牌 `CancellationToken` 来自 `package:core_parsing`，本包不重新导出它。

**三路。** `documentText` 用文档文本模型，384 维。`keyword` 用存储层的中文 bigram、FTS5 trigram 或 LIKE。`clipShared` 用 MobileCLIP 文本塔去对图像向量，512 维。一次默认 `search` 对文本编码两次。图像塔缺失或运行失败时这一路变成空，不把整次搜索变成错误。取消请求原样抛出。

**融合。** `score = Σ w_i / (k + rank_i)`，`rank` 从 1 起。`k` 是 60。权重是文本 0.5、关键词 0.3、图像 0.2。某一路没有命中，或权重为 0，这一路不加入求和。这不是把余弦和关键词覆盖率做加权和。同分仍按存储层的规则：分数降序，`relativePath` 升序，页码升序且 null 在后，起点升序。

**邻域。** 默认在融合并截到 `topK` 之后，把同一 `pageNumber` 上 `chunkIndex ± 1` 的正文拼进 `snippet`。不跨页。页的两端缺一侧就不补。`pageNumber == null` 的块之间仍可相邻，例如 DOCX。偏移和分数不变。`expandNeighborhood: false` 时 `snippet` 就是命中块正文。

**过滤。** `SearchFilters` 在每一路进存储层之前就生效，不是融合之后再滤。

**通道开关。** `channels` 缺省是三路都开。传入的集合是这次真正要跑的路。空集合抛 `ArgumentError`。关掉一路不是改权重。产品默认是三路加上邻域。评测里的 A0 到 A4 用这个参数关路，并关掉邻域。

**线程。** 编码、查询和融合都在调用方的 isolate 上。嵌入运行时如果自己起进程，那个进程不在本包里。

## 2. 查询与结果

### `Retriever`

```dart
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
```

`query` 空白抛 `ArgumentError`。`topK < 1` 抛 `ArgumentError`。`channels` 为空集合抛 `ArgumentError`。打开了文档文本路但编码器没有给出向量时抛 `StateError`，消息是 `Document text vector is missing.`。取消抛 `CancelledException`。

### `DefaultRetriever`

```dart
DefaultRetriever({
  required VectorStore store,
  required QueryEncoder encoder,
  RrfFusion fusion = const RrfFusion(),
  int recallK = 50,
});
```

每一路先取 `max(topK, recallK)` 条，融合后再截到 `topK`。`recallK` 必须为正，否则构造断言失败。

```dart
int lastEncodeMs;
int lastStoreMs;
int lastFuseMs;
```

上一次 `search` 的三段毫秒。第一次编码包含模型冷加载。`lastStoreMs` 在扩展邻域时含按文档读块的时间。

### `QueryEncoder`

```dart
const QueryEncoder(EmbeddingEngine engine);

Future<QueryVectors> encode(
  String query, {
  bool includeDocumentText = true,
  bool includeClipText = true,
  CancellationToken? cancel,
});
```

`includeDocumentText` 为真时调用一次 `EmbeddingInput.text`。`includeClipText` 为真时再调用一次 `clipShared`。CLIP 抛 `EmbeddingSpaceMismatchException` 或 `EmbeddingRuntimeException` 时 `clip` 为 null。其他异常不吞。取消不当成缺塔。

### `QueryVectors`

```dart
const QueryVectors({
  required EmbeddingVector? text,
  required EmbeddingVector? clip,
});
```

这次没打开文档文本路时 `text` 为 null。图像路降级时 `clip` 为 null。

### `SearchChannel`

```dart
enum SearchChannel { documentText, keyword, clipShared }
```

`name` 就是读屏可以播报的标识。一条融合命中的 `channels` 是真正给它加分的那些路。

### `SearchFilters`

```dart
const SearchFilters({
  Set<String>? extensions,
  String? pathPrefix,
  DateTime? modifiedAfter,
  Modality? modality,
});

StorageFilter toStorageFilter();
```

字段含义和存储层的 `StorageFilter` 相同。扩展名示例是 `{'.pdf', '.md'}`。空的扩展名集合表示没有文件能通过。`pathPrefix` 比的是摄取相对路径，不是 `documentKey`。

### `SearchResult`

```dart
const SearchResult({
  required String documentId,
  required String chunkId,
  required String relativePath,
  required String fileName,
  required int startOffset,
  required int endOffset,
  required TextUnit textUnit,
  required String snippet,
  required double score,
  required Set<SearchChannel> channels,
  required Modality modality,
  int? chunkIndex,
  String? mimeType,
  int? pageNumber,
  Object? imageAsset,
  String? documentKey,
});
```

`score` 是 RRF 分数，不是某一路的余弦。`textUnit` 固定为 `TextUnit.utf16CodeUnit`。`startOffset` 含首，`endOffset` 不含尾，始终是命中块自己的跨度，即使 `snippet` 拼进了相邻块。`pageNumber` 为 null 时不是真实页码。`documentKey` 相对仓库根，只用于和评测集对齐，不参与打分。图像命中的 `imageAsset` 是 `ImageAsset`，文本命中为 null。结果里没有颜色语义。

## 3. 融合与邻域

### `rrfK`、`rrfTextWeight`、`rrfKeywordWeight`、`rrfImageWeight`

```dart
const int rrfK = 60;
const double rrfTextWeight = 0.5;
const double rrfKeywordWeight = 0.3;
const double rrfImageWeight = 0.2;
```

开工时冻结。`RrfFusion` 的默认值就是它们。评测脚本把 `parameters_changed_after_freeze` 记为 0，不在 dev 上改这三个权重。

### `RrfFusion`

```dart
const RrfFusion({
  int k = rrfK,
  double textWeight = rrfTextWeight,
  double keywordWeight = rrfKeywordWeight,
  double imageWeight = rrfImageWeight,
});
```

`k` 必须为正，否则构造断言失败。

```dart
List<FusedHit> fuse({
  List<ScoredId> text = const <ScoredId>[],
  List<ScoredId> keyword = const <ScoredId>[],
  List<ScoredId> image = const <ScoredId>[],
});
```

每一路里，同一个 `documentId` 加 `chunkId` 只取第一次出现的名次。权重为 0 或列表为空就跳过该路。返回列表已按第 1 节的同分规则排好，不在这里截断。

### `FusedHit`

```dart
const FusedHit({
  required ScoredId anchor,
  required double score,
  required Set<SearchChannel> channels,
});
```

`anchor` 是展示用的那条原命中，它自己的 `score` 仍是那一路的分数。`FusedHit.score` 才是 RRF。`channels` 不可修改。

### `expandHit`

```dart
SearchResult expandHit(FusedHit hit, List<StoredChunk> documentChunks);
```

`documentChunks` 一般来自 `VectorStore.chunksForDocument`。找不到锚点块时，`snippet` 退回 `anchor.body`。找到时只拼接同页前后一块的非空正文，中间用换行连接。顺序、RRF 分数和命中偏移都不变。

## 4. 公开符号

`lib/core_retrieval.dart` 导出：

`DefaultRetriever`、`Retriever`、`SearchChannel`、`SearchFilters`、`SearchResult`、`expandHit`、`QueryVectors`、`QueryEncoder`、`rrfK`、`rrfTextWeight`、`rrfKeywordWeight`、`rrfImageWeight`、`FusedHit`、`RrfFusion`。

没有从这里导出的名字都不是公开 API。
