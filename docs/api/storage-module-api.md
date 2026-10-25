# 存储模块 API

Week 4 定稿。产品索引是 Dart 加系统 SQLite。Chroma 只在 `engine/chroma_baseline.py` 里做对照，不从本包导出。下面列出的是 `lib/core_storage.dart` 已经导出的符号。`bin/` 下的探针不是库符号。

## 1. 调用约定

外部代码 import：

```dart
import 'package:core_storage/core_storage.dart';
```

打开文件库并写入一对正文块：

```dart
final OpenedStore opened = openStore(
  const SystemSqliteLibraryLocator(),
  r'week4\.index\evidence.sqlite',
);
final SqliteVectorStore? store = opened.store;
if (store == null) {
  // opened.failure 是结构化失败，不把动态库缺失变成未捕获异常。
  throw StateError(opened.failure!.message);
}
await store.write(
  <StoredChunk>[
    StoredChunk(
      documentId: 'doc-1',
      chunkId: 'doc-1-c0',
      relativePath: 'notes/a.md',
      documentKey: 'docs/notes/a.md',
      fileName: 'a.md',
      extension: '.md',
      startOffset: 0,
      endOffset: 4,
      body: '离线检索',
      modality: Modality.text,
      chunkIndex: 0,
      contentHash: 'abc',
      parserName: 'markdown',
      parserVersion: '1',
      chunkerVersion: 'w3-cascade-1',
    ),
  ],
  <EmbeddingVector>[vector],
);
store.close();
```

`EmbeddingVector` 来自 `package:core_embedding/core_embedding.dart`。本包的运行时依赖除了 `sqlite3`、`ffi`、`path`，还有 `core_parsing` 和 `core_embedding`。图像块要留下 `ImageAsset`，向量类型也在嵌入包里。这是相对「存储包只依赖 sqlite3」的偏差，ADR 0004 记了原因。

**两个空间。** 文本块必须配 `EmbeddingSpace.documentText`。图像块必须配 `EmbeddingSpace.clipShared`。混用抛 `StorageException`，`kind` 是 `spaceMismatch`。查询也按空间分开：拿 384 维向量去扫 512 维的空间会得到 `dimensionMismatch`。

**向量格式。** 库存的是小端 float32 BLOB。查询向量必须已经 L2 归一化（`normalized == true`），余弦就是点积。没有 ANN。

**过滤。** `StorageFilter` 写进 SQL 的 `WHERE`，在取 Top-K 之前生效。路径前缀比的是 `relativePath`：等于该前缀，或者以 `前缀/` 开头。`sample` 匹配不了 `sample.pdf`。扩展名带点、按小写比较。`modifiedAfter` 是严格大于，空的修改时间不会被选中。

**事务。** `write`、`deleteDocument`、`clear` 各自包在一个事务里。写入中途失败会回滚，旧行还在。同一次写入会先删掉这些 `documentId`，以及同一 `documentKey` 上还挂着的旧 `documentId`，再插入新行。内容哈希变了以后，上一版不会留在库里。

**线程。** 这些调用跑在调用方的 isolate 上。`package:sqlite3` 的连接不要跨 isolate 共用。用完调用 `SqliteVectorStore.close`。

**测试。** 默认套件是 `dart test --exclude-tags integration`。它不加载模型，也不读数据集。

## 2. 打开库

### `SqliteLibraryLocator`

```dart
abstract interface class SqliteLibraryLocator {
  SqliteOpenResult open(String databasePath);
}
```

动态库从哪来。`databasePath` 用 `:memory:` 表示内存库，其他值是文件路径。失败时返回 `SqliteOpenResult.failed`，不抛。单测可以换成下面的拒绝实现。

### `SystemSqliteLibraryLocator`

```dart
const SystemSqliteLibraryLocator();
```

```dart
const SqliteLibraryLocator locator = SystemSqliteLibraryLocator();
```

交给 `package:sqlite3` 自己的查找顺序。本机落到 `C:\Windows\System32\winsqlite3.dll`（本次实测 SQLite 3.53.4）。不写死这条绝对路径。找不到库时 `kind` 是 `libraryUnavailable`。

### `RejectingSqliteLibraryLocator`

```dart
const RejectingSqliteLibraryLocator({this.message = 'SQLite library is missing.'});
```

不加载动态库。`open` 总是返回 `libraryUnavailable`。给单测用。

### `SqliteOpenResult`

```dart
const SqliteOpenResult.opened(Database database);
const SqliteOpenResult.failed(StorageFailure failure);
```

`database` 和 `failure` 恰有一个为 null。`isOk` 表示 `database != null`。`Database` 来自 `package:sqlite3`。调用方通常不直接用这个类型，而用 `openStore`。

### `openStore`

```dart
OpenedStore openStore(SqliteLibraryLocator locator, String databasePath);
```

打开连接，建表，文件库再执行 `PRAGMA journal_mode = WAL`。内存库不设 WAL。表可以重复建。schema 版本号是 1。动态库缺失或建表失败时返回 `OpenedStore.failed`，连接已释放。不抛未捕获异常。

### `OpenedStore`

```dart
const OpenedStore.ready(SqliteVectorStore store);
const OpenedStore.failed(StorageFailure failure);
```

`store` 和 `failure` 恰有一个为 null。`isOk` 表示库可用。

### `StorageFailureKind`

```dart
enum StorageFailureKind {
  libraryUnavailable,
  schemaUnsupported,
  spaceMismatch,
  dimensionMismatch,
  notNormalized,
  conflict,
  unknown,
}
```

打开失败用前两个和 `unknown`。写入和查询用后面几项，包在 `StorageException` 里。

### `StorageFailure`

```dart
const StorageFailure({
  required StorageFailureKind kind,
  required String message,
  String? detail,
});
```

`detail` 可以空。`toString` 形如 `StorageFailure(libraryUnavailable: ...)`。

### `StorageException`

```dart
const StorageException(StorageFailure failure);
```

实现 `Exception`。`toString` 带 `failure.message`。空间不符、维度不符、查询向量没归一化、同一文档混了两套代次，都抛它。长度不一致的 `chunks` / `vectors` 抛的是 `ArgumentError`，不是这个类型。

## 3. 记录、过滤与代次

### `Modality`

```dart
enum Modality { text, image }
```

文本行和图像行。和向量空间一一对应，不能混放。

### `StoredChunk`

```dart
const StoredChunk({
  required String documentId,
  required String chunkId,
  required String relativePath,
  required String fileName,
  required int startOffset,
  required int endOffset,
  required String body,
  required Modality modality,
  String? mimeType,
  int? pageNumber,
  Object? imageAsset,
  int? chunkIndex,
  String? extension,
  String? documentKey,
  DateTime? modifiedAt,
  String? contentHash,
  String? parserName,
  String? parserVersion,
  String? chunkerVersion,
});
```

一条块。`chunkId` 回指切块结果，不是主键。`documentId` 在产品编排里是内容哈希，缺哈希时用文件 id。

`relativePath` 相对摄取根，分隔符写成 `/`。`documentKey` 相对仓库根，评测集用它对齐；空则回落到 `relativePath`。`storedDocumentKey` 和 `storedExtension` 是写入前的规范化结果。扩展名缺省时从 `fileName` 取，并转成小写。

`startOffset` 含首，`endOffset` 不含尾，单位是 UTF-16 code unit。`pageNumber` 从 1 起；TXT、DOCX、单页且没有页数的 Markdown 为 null，不能把它显示成真实页码。`chunkIndex` 供同页 ±1。图像行的 `imageAsset` 在读回时是 `ImageAsset`。

构造断言：`documentId`、`chunkId` 非空，偏移不倒序，页码要么 null 要么大于 0。断言失败抛 `AssertionError`。

代次五项是 `contentHash`、`parserName`、`parserVersion`、`chunkerVersion`，再加上向量的 `modelId` 和 `dim`。缺任何一项时这行仍可写入，但 `canReuse` 对不上。

### `StorageFilter`

```dart
const StorageFilter({
  Set<String>? extensions,
  String? pathPrefix,
  DateTime? modifiedAfter,
  Modality? modality,
});
```

全部可选。`extensions` 为空集时条件恒假，没有行能通过。`pathPrefix` 见第 1 节。检索层不要让存储层依赖自己，所以那里的 `SearchFilters` 用 `toStorageFilter()` 转成这个类型。

### `ScoredId`

```dart
const ScoredId({
  required String documentId,
  required String chunkId,
  required String relativePath,
  required String fileName,
  required int startOffset,
  required int endOffset,
  required String body,
  required Modality modality,
  required double score,
  int? chunkIndex,
  String? mimeType,
  int? pageNumber,
  Object? imageAsset,
  String? documentKey,
});
```

单路命中。`score` 只在这一路里有意义：向量路是余弦，关键词路是覆盖率。不要把两路的分数加在一起。

```dart
static int compareTie(ScoredId left, ScoredId right);
```

同分时：`relativePath` 升序，`pageNumber` 升序且 null 在后，`startOffset` 升序。向量路和关键词路都用它。融合后的名次也用同一套规则，只是比的是 RRF 分数。

### `IndexGeneration`

```dart
const IndexGeneration({
  required String documentId,
  required String contentHash,
  required String parserName,
  required String parserVersion,
  required String chunkerVersion,
  required String modelId,
  required int vectorDim,
  required DateTime embeddedAt,
});
```

`documentId` 加 `modelId` 找到那一行。`sameRecipe` 比较其余五项：哈希、解析器名、解析器版本、切块器版本、模型名、维度。`embeddedAt` 不参与复用判断。构造断言要求这些字符串非空，且 `vectorDim > 0`。

### `IndexStats`

```dart
const IndexStats({
  required int chunks,
  required int documents,
  required int documentText,
  required int clipShared,
  required int keywordTerms,
});
```

`chunks` 是行数。`documents` 是不同的 `documentId`。`documentText` 和 `clipShared` 是两个空间的行数。`keywordTerms` 是中文 bigram 词表的行数，不是 FTS 行数。英文语料可以是 0，关键词仍可能走 FTS 或 LIKE。

### `WriteOutcome`

```dart
const WriteOutcome({required int written, required int documents});
```

`written` 是这次插入的块数。`documents` 是这次涉及到的文档数。空列表返回两个 0，不建事务。

## 4. 写入、查询与维护

### `VectorStore`

```dart
abstract interface class VectorStore {
  Future<WriteOutcome> write(
    Iterable<StoredChunk> chunks,
    Iterable<EmbeddingVector> vectors,
  );

  Future<List<ScoredId>> search(
    EmbeddingVector query, {
    StorageFilter? filter,
    int topK = 50,
  });

  Future<List<ScoredId>> keyword(
    String query, {
    StorageFilter? filter,
    int topK = 50,
  });

  Future<List<StoredChunk>> chunksForDocument(String documentId);

  Future<void> deleteDocument(String documentId);

  Future<void> clear();

  Future<IndexStats> stats();

  Future<bool> canReuse(IndexGeneration generation);
}
```

不负责融合，也不读文件。`search` 的 `topK < 1` 抛 `ArgumentError`。查询向量未归一化抛 `StorageException(notNormalized)`。该空间没有行时返回空列表。该空间的维度和查询不一致抛 `dimensionMismatch`。

`keyword` 的空查询返回空列表。`topK < 1` 抛 `ArgumentError`。有中文 bigram 时走词表；否则长度不少于 3 的查询走 FTS5 trigram；更短的走带 `LIMIT` 的 `LIKE`。

`chunksForDocument` 按页码、块序号、偏移排序，null 页在后。`deleteDocument` 同时删向量行、关键词行和代次行。`clear` 清整库。`canReuse` 在没有代次行或五项不一致时返回 false。

### `SqliteVectorStore`

```dart
SqliteVectorStore(Database database);

Database get database;
void close();
```

`database` 公开，是为了让探针打 `EXPLAIN QUERY PLAN`。业务代码用上面的方法即可。`close` 可重复调用。文件库的 `journal_mode` 是 `wal`。

暴力扫描会把该空间里通过过滤的行都读出来再排序。本次在 384 维、1 万块、`topK` 为 5 时，写入 576 ms，查询中位 104 ms。写入不超过 0.6 s。查询没有达到 60 ms，数字记在 `week4/logs/storage_capacity.txt`，没有改门槛。

## 5. 关键词

### `chineseBigrams`

```dart
List<String> chineseBigrams(String text);
```

把连续的 CJK 统一表意文字切成重叠的两字词。BMP 里的汉字占一个 code unit。英文、数字和标点会打断这一串。没有两字以上的中文时返回空列表。`unicode61` 对两字中文的命中是 0，所以产品索引先自己切，再交给 FTS。

```dart
chineseBigrams('离线检索');
// ['离线', '线检', '检索']
```

### `KeywordPath`

```dart
enum KeywordPath { bigram, trigram, like }
```

查询计划选中的那一层。

### `KeywordPlan`

```dart
const KeywordPlan(KeywordPath path, List<String> terms);

static KeywordPlan forQuery(String query);
```

`forQuery` 先 `trim`。有 bigram 就走 `bigram`，`terms` 是去重后的两字词。否则长度不少于 3 走 `trigram`，更短走 `like`。后两条的 `terms` 为空。

## 6. 公开符号

`lib/core_storage.dart` 导出：

`chineseBigrams`、`KeywordPath`、`KeywordPlan`、`IndexGeneration`、`IndexStats`、`WriteOutcome`、`Modality`、`ScoredId`、`SqliteOpenResult`、`StorageFailureKind`、`StorageFailure`、`StorageException`、`StorageFilter`、`StoredChunk`、`SqliteLibraryLocator`、`SystemSqliteLibraryLocator`、`RejectingSqliteLibraryLocator`、`SqliteVectorStore`、`OpenedStore`、`openStore`、`VectorStore`。

没有从这里导出的名字都不是公开 API。
