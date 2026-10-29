# 向量模块 API

阶段 D 定稿。文档文本、图像预处理、切块、统一入口和批量服务都已实现。下面列出的是 `lib/core_embedding.dart` 已经导出的符号。`bin/embed_probe.dart` 是命令行探针，不是库符号，不在第 7 节里。

## 1. 调用约定

外部代码 import：

```dart
import 'package:core_embedding/core_embedding.dart';
```

对一句文档正文出向量：

```dart
final EmbeddingVector vector = await TextEmbedder(
  model: documentTextModel,
  tokenizer: UnigramTokenizer.fromFile(tokenizerJsonPath),
  runtime: OnnxProcessEmbeddingRuntime(
    pythonExecutable: pythonExecutable,
    scriptPath: r'engine\embed_text_hidden.py',
    modelPath: modelOnnxPath,
    processRunner: const IoProcessRunner(),
  ),
).embed('离线检索可以在没有网络的电脑上运行。', chunkId: 'chunk-1');
// vector.dim == 384
// vector.space == EmbeddingSpace.documentText
// vector.normalized == true
// vector.modelId == 'paraphrase-multilingual-MiniLM-L12-v2'
```

`IoProcessRunner` 来自 `package:core_parsing/core_parsing.dart`。取消令牌也来自那个包。本包不重新导出它们。

**空间。** `EmbeddingSpace.documentText` 是文档正文和文本查询，维度 384。`EmbeddingSpace.clipShared` 是 MobileCLIP 的图文共享空间，维度 512。两个空间的数不能比较，也不能放进同一个索引。混用时 `DefaultEmbeddingEngine` 抛 `EmbeddingSpaceMismatchException`。没有 CLIP 文本塔时，`clipShared` 的文本不会改走 384 维的文档模型。

**文本单位。** `TextUnit` 只有 `utf16CodeUnit`。偏移与 Dart 的 `String.length`、`String.substring` 以及 `DocumentPage.charCount` 相同。BMP 里的汉字占 1 个 code unit，emoji 这类代理对占 2 个。`TextChunk.startOffset` 含首，`endOffset` 不含尾，所以 `pageText.substring(startOffset, endOffset)` 就是该块在页文本里的跨度。

**超长。** 操作上的上限是 128 个 token，含 `<s>` 和 `</s>`。位置嵌入可以到 512，调用侧不使用那个数。超过 128 时不截断、不返回半句向量。`TextInputBuilder.build` 返回 `TextInputNeedsRechunk`，`TextEmbedder.embed` 抛 `TextOverBudgetException`。

**异常。** 空字符串、空的 `chunkId`、`maxLength < 2` 是调用错误，抛 `ArgumentError`。构造参数的 `assert` 失败抛 `AssertionError`（测试和调试；发布模式会剥掉 `assert`）。运行时不具备、缺张量、超时、维度不符、输出不是有限数，都抛 `EmbeddingRuntimeException` 的子类，不返回空向量。`CancelledException` 从 `core_parsing` 原样冒出来。`TextEmbedder` 在调用运行时之前、以及运行时返回之后检查取消。运行时接口本身不接收取消令牌，所以推理进程进行中的取消要等这次 `run` 返回后才抛出。

**线程。** 分词、拼张量和 pooling 都在调用方的 isolate 上。`OnnxProcessEmbeddingRuntime` 另起一个 Python 进程跑 ONNX Runtime，不在 Dart 里链接 TFLite。这些对象没有内部锁。

**测试。** 默认套件是 `dart test --exclude-tags integration`。它不读 `tokenizer.json`，不读权重，也不读数据集。带 `integration` 标签的用例才加载真模型、NQ 句子、MobileCLIP 分词器和一张 COCO 图。

**词表文件。** 分词器读的是模型目录里的 `tokenizer.json`（Unigram，词表 250002），不是 `vocab.txt`，也不是 `config.json` 里的 `vocab_size`（250037）。`lib/src/text/wordpiece_tokenizer.dart` 只是计划路径上的再导出，不是另一种算法，也不从公开入口导出。`##` 在这个模型里是普通正文，编码成一片 `▁##`，不是 WordPiece 续接。

## 2. 空间、文本单位与模型

### `EmbeddingSpace`

```dart
enum EmbeddingSpace { documentText, clipShared }
```

```dart
const EmbeddingSpace space = EmbeddingSpace.documentText;
// space.name == 'documentText'
```

`documentText` 给文档正文和文本查询。`clipShared` 给 MobileCLIP 图像和用来查图的自然语言。不抛异常。

### `TextUnit`

```dart
enum TextUnit { utf16CodeUnit }
```

```dart
const TextUnit unit = TextUnit.utf16CodeUnit;
// '页'.length == 1
// '🙂'.length == 2
```

唯一合法的偏移单位。高亮、切片和引用必须共用它。不抛异常。

### `TextChunk`

```dart
const TextChunk({
  required String chunkId,
  required String text,
  required int startOffset,
  required int endOffset,
  required TextUnit textUnit,
  required String chunkerVersion,
  int? pageNumber,
});
Map<String, Object?> toJson();
```

```dart
const TextChunk chunk = TextChunk(
  chunkId: 'doc-1',
  text: '页码',
  startOffset: 0,
  endOffset: 2,
  textUnit: TextUnit.utf16CodeUnit,
  chunkerVersion: 'w3-1',
  pageNumber: 1,
);
// chunk.endOffset - chunk.startOffset == chunk.text.length
```

`pageNumber` 从 1 起；TXT 和 DOCX 没有物理页时为 null，界面不能把它显示成真实页码。`chunkId` 由内容哈希、分块器版本、页码和块序号组成，同一配置下可以复现，但不是稳定主键。`toJson` 写 `textLength`，不写正文。

`chunkId` 或 `chunkerVersion` 为空、`startOffset < 0`、`endOffset < startOffset`、`pageNumber` 不是 null 且小于 1 时，断言失败抛 `AssertionError`。

### `TextChunker`

```dart
abstract interface class TextChunker {
  List<TextChunk> chunk(ParsedDocument document, {String? documentId});
}
```

页用于定位，段落用于切分，超长才切窗口。级联是 `\n\n`、换行、句末标点、硬窗口。实现类是 `CascadeTextChunker`。`documentId` 缺省时用正文内容哈希。跨页合并不在本周。

### `ChunkBudgetException`

```dart
const ChunkBudgetException({
  required int tokenCount,
  required int maxTokens,
});
```

```dart
const ChunkBudgetException over = ChunkBudgetException(tokenCount: 1000, maxTokens: 128);
// over.toString() 含 token 数和上限，不含正文
```

一个 UTF-16 窗口仍然放不进 token 预算。批量服务把它记成 `EmbeddingFailureKind.overBudget`，不截断。不返回向量。

### `CascadeTextChunker`

```dart
CascadeTextChunker({
  required int Function(String text) countTokens,
  int chunkChars = 120,
  int maxTokens = 128,
  String chunkerVersion = 'w3-cascade-1',
  String counterLabel = 'unigram',
});
List<TextChunk> chunk(ParsedDocument document, {String? documentId});
```

```dart
final CascadeTextChunker chunker = CascadeTextChunker(
  countTokens: (String text) => tokenizer.encode(text).ids.length,
);
final List<TextChunk> chunks = chunker.chunk(document, documentId: metadata.contentHash);
```

`countTokens` 必须和嵌入器使用同一个分词器，并且把起止标记算进去。`chunkChars` 是字符窗口初值，默认 120，不是跨语言的最优长度。`datasets/samples` 的 `sample.docx` 和 `sample.pdf` 用真实 Unigram 计数后，120 字窗口都低于 128；这两份文本大约 4 字符一个 token，没有覆盖中文一字一 token 的上沿。分布在 `reports/week3/logs/chunk_chars_calibration.txt`。字符长度超过窗口，或 token 数超过 `maxTokens`，都会继续切。窗口仍然超预算就缩短；一个码位仍然超预算时抛 `ChunkBudgetException`。

DOCX 只有单个换行时按行切开，页码为 null。存在空行时，短的单换行留在段落里。PDF 由 `pageCount` 或 `extractor` 属性，或多于一页，保留页码。偏移相对该页文本。代理对不会从中间切开。

`chunkId` 含 `documentId`、分块器版本、计数标记、`chunkChars`、`maxTokens`、页序号和块序号。同一配置可以复现，但不是稳定主键。`chunkChars < 1`、`maxTokens < 2`、空的版本或计数标记抛 `ArgumentError`。

### `clipVisionModel`

```dart
const ModelInfo clipVisionModel;
```

```dart
// clipVisionModel.modelId == 'mobileclip-s0-vision'
// clipVisionModel.space == EmbeddingSpace.clipShared
// clipVisionModel.dim == 512
// clipVisionModel.pooling == 'none'
// clipVisionModel.normalized == true
```

ADR 0003 冻结的 MobileCLIP-S0 图像塔。图内输出 `image_embeds`，不做 L2。`normalized == true` 表示交给调用方的向量已经归一化。不加 mean/std。不抛异常。

### `clipTextModel`

```dart
const ModelInfo clipTextModel;
```

```dart
// clipTextModel.modelId == 'mobileclip-s0-text'
// clipTextModel.space == EmbeddingSpace.clipShared
// clipTextModel.dim == 512
// clipTextModel.maxInputLength == 77
// clipTextModel.pooling == 'none'
```

用来查图的文本塔。只收 `input_ids`，没有 attention mask。上限 77，含起止标记。不抛异常。

### `ModelInfo`

```dart
const ModelInfo({
  required String modelId,
  required EmbeddingSpace space,
  required int dim,
  required String pooling,
  required bool normalized,
  int? maxInputLength,
  String? queryPrefix,
  String? documentPrefix,
});
Map<String, Object?> toJson();
```

```dart
const ModelInfo info = documentTextModel;
// info.pooling == 'mean'
// info.queryPrefix == null
// info.documentPrefix == null
```

权重路径和校验和不在这里，那些写在 `models/README.md`。`pooling` 是 `mean` 或 `none`。图像塔若图内已经投影好，记 `none`。`maxInputLength` 是文本模型的最大 token 数，图像模型为 null。不需要前后缀时，前缀字段必须是 null，不能用空字符串代替。

`modelId` 为空、`dim <= 0` 或 `pooling` 为空时，断言失败抛 `AssertionError`。

### `documentTextModel`

```dart
const ModelInfo documentTextModel;
```

```dart
// documentTextModel.modelId == 'paraphrase-multilingual-MiniLM-L12-v2'
// documentTextModel.space == EmbeddingSpace.documentText
// documentTextModel.dim == 384
// documentTextModel.maxInputLength == 128
// documentTextModel.normalized == true
```

ADR 0003 冻结的文档文本模型。图内不归一化。`normalized == true` 表示交给调用方的 `EmbeddingVector` 已经做了 L2。没有查询前缀，也没有文档前缀。不抛异常。

## 3. 分词与输入张量

### `AddedToken`

```dart
AddedToken({
  required String content,
  required int id,
  bool lstrip = false,
  bool rstrip = false,
  bool special = false,
  bool normalized = false,
});
```

```dart
final AddedToken mask = AddedToken(
  content: '<mask>',
  id: 250001,
  lstrip: true,
  special: true,
);
```

`tokenizer.json` 里的一个 added token。`normalized` 为 false 时，在归一化之前按原文切开。`lstrip` 把紧挨在标记左边的空白吃进这个标记。`rstrip` 吃掉右边的空白。本模型的五个特殊标记都是 `normalized: false`。`content` 为空时抛 `ArgumentError`，空字符串会让编码停在同一个下标。`UnigramTokenizer` 另外拒绝 `normalized: true`。

### `TokenEncoding`

```dart
const TokenEncoding({required List<int> ids, required List<String> tokens});
int get length;
```

```dart
const TokenEncoding encoding = TokenEncoding(
  ids: <int>[0, 10, 2],
  tokens: <String>['<s>', '▁a', '</s>'],
);
// encoding.length == 3
```

一次分词结果，不含 padding。`ids` 与 `tokens` 等长。未知片段的 `tokens` 保留原文，不改写成字符串 `<unk>`；id 才是 `unk`。不抛异常。

### `UnigramTokenizer`

```dart
UnigramTokenizer({
  required List<(String, double)> pieces,
  required int unkId,
  required List<AddedToken> addedTokens,
  String bosContent = '<s>',
  String eosContent = '</s>',
  String padContent = '<pad>',
  String metaspace = '▁',
  bool addPrefixSpace = true,
});
factory UnigramTokenizer.fromFile(String path);
factory UnigramTokenizer.fromJsonString(String jsonText);
factory UnigramTokenizer.fromJson(Map<String, Object?> json);
int get bosId;
int get eosId;
int get padId;
String normalize(String input);
TokenEncoding encode(String text, {int? truncateTo});
```

```dart
final UnigramTokenizer tokenizer = UnigramTokenizer.fromFile(tokenizerJsonPath);
final TokenEncoding encoding = tokenizer.encode('Hello');
// encoding.ids == [0, 35378, 2]
final TokenEncoding marker = tokenizer.encode('##');
// marker.tokens == ['<s>', '▁##', '</s>']
```

构造函数还有一个可选的 `normalizer`。它的类型不从公开入口导出，库外调用省略即可。`fromFile` 和 `fromJson` 会自己读 Precompiled 表。

顺序与 tokenizers 0.23 相同：先按 added token 从左到右、先长后短切开，再做 Precompiled 归一化，再按 Rust `char::is_whitespace` 切开并丢掉空白，再把 U+0020 换成 `▁` 并在段首补 `▁`，最后做 Unigram。单句模板是 `<s>` + 序列 + `</s>`。默认不截断，也不补 `<pad>`。

`normalize` 只做 Precompiled 归一化。没有归一化表时原样返回。空串仍是空串。

`truncateTo` 只给和 Python 对照。它从右侧丢掉多余正文，但保留末尾那一串特殊标记。产品路径不要传它。`truncateTo < 2` 抛 `ArgumentError`。

`fromFile` 读整个 `tokenizer.json`。文件大约十几 MB，只在集成测试和真推理时读。JSON 不是对象、模型不是 Unigram、词条不是 `[token, score]`、归一化不是 Precompiled，都抛 `FormatException`。文件不存在抛 `FileSystemException`。

`pieces` 为空，或 `unkId` 不在词表下标里，抛 `ArgumentError`。某个 added token 的 `normalized` 为 true，或 `bosContent` / `eosContent` / `padContent` 在 added token 里找不到，抛 `ArgumentError`。`metaspace` 为空也抛 `ArgumentError`，空字符串会让按标记切开的循环停住。

### `ClipBpeTokenizer`

```dart
ClipBpeTokenizer({
  required Map<String, int> vocab,
  required List<String> merges,
  String endOfWordSuffix = '</w>',
  String bosToken = '<|startoftext|>',
  String eosToken = '<|endoftext|>',
  String padToken = '!',
  int? bosId,
  int? eosId,
  int? padId,
  int? unkId,
});
factory ClipBpeTokenizer.fromJsonString(String jsonText);
TokenEncoding encode(String text);
```

```dart
final ClipBpeTokenizer clip = ClipBpeTokenizer.fromJsonString(tokenizerJson);
final TokenEncoding hello = clip.encode('Hello');
// hello.ids == [49406, 3306, 49407]
// clip.padId == 0
```

MobileCLIP 文本塔的字节级 BPE。归一化是 NFC、空白压成一个空格、再小写。预切分用 CLIP 的词块正则，数字按单个字符切开，再映射 UTF-8 字节。词尾加 `</w>` 后按 merge 表合并。`encode` 包上 `<|startoftext|>` 和 `<|endoftext|>`，不补齐、不截断。补齐在 `ClipTextEmbedder` 里做。空文本是 `[bos, eos]`。

`fromJsonString` 只接受和当前 `tokenizer.json` 相同的 BPE 结构。模型不是 BPE、`byte_fallback` 为 true、continuing prefix 非空、缺 `</w>`，或归一化、预切分、后处理对不上，抛 `FormatException`。空词表、空的词尾后缀、merge 不是用空格分开的两段，抛 `ArgumentError`。默认套件用玩具词表，不读这份两兆字节的文件。

### `TextInputResult`

```dart
sealed class TextInputResult {
  const TextInputResult();
}
```

`TextInputBuilder.build` 的两种结果。超长是一个结果，不是截断后的张量。调用方用 `is TextInputTensors` 或 `is TextInputNeedsRechunk` 区分。不抛异常。

### `TextInputTensors`

```dart
const TextInputTensors({
  required Map<String, Tensor> tensors,
  required List<int> ids,
  required List<String> tokens,
  required int maxLength,
});
```

```dart
final TextInputResult built = TextInputBuilder(
  tokenizer: tokenizer,
  maxLength: 128,
).build('a');
final TextInputTensors tensors = built as TextInputTensors;
// tensors.tensors['input_ids']!.shape == [1, 128]
```

长度没有超过模型上限。`tensors` 含 `input_ids`、`attention_mask`、`token_type_ids`，类型都是 int64，形状都是 `[1, maxLength]`。真实 id 在左侧，右侧补 `padId`，mask 先 1 后 0，token type 全是 0。`ids` 和 `tokens` 是补 pad 之前的序列，含 `<s>` 和 `</s>`。不抛异常。

### `TextInputNeedsRechunk`

```dart
const TextInputNeedsRechunk({required int tokenCount, required int maxLength});
```

```dart
final TextInputResult over = TextInputBuilder(
  tokenizer: tokenizer,
  maxLength: 4,
).build(longText);
if (over is TextInputNeedsRechunk) {
  // over.tokenCount > over.maxLength
  // 没有张量，不能拿去推理
}
```

整句加上特殊标记之后长于 `maxLength`。`tokenCount` 是未截断的长度。这里没有张量。调用方要重切原文。不抛异常。

### `TextInputBuilder`

```dart
TextInputBuilder({required UnigramTokenizer tokenizer, required int maxLength});
TextInputResult build(String text);
```

```dart
final TextInputBuilder builder = TextInputBuilder(
  tokenizer: tokenizer,
  maxLength: documentTextModel.maxInputLength!,
);
final TextInputResult result = builder.build('离线检索可以在没有网络的电脑上运行。');
```

把一句正文变成 MiniLM 的三份 int64 输入。`encode` 不传 `truncateTo`。`maxLength < 2` 抛 `ArgumentError`。`build` 本身不因为超长而抛异常。

## 4. 文本与图像向量

### `EmbeddingVector`

```dart
const EmbeddingVector({
  required List<double> values,
  required EmbeddingSpace space,
  required int dim,
  required String modelId,
  required bool normalized,
  String? chunkId,
});
Map<String, Object?> toJson();
```

```dart
const EmbeddingVector vector = EmbeddingVector(
  values: <double>[0.6, 0.8],
  space: EmbeddingSpace.documentText,
  dim: 2,
  modelId: 'toy',
  normalized: true,
  chunkId: 'chunk-1',
);
```

一条自描述的向量。`normalized` 必须写明：库存余弦还是内积由它决定。`chunkId` 指向 `TextChunk.chunkId`；整段查询或图像没有块时为 null。`toJson` 只放 `values` 的前三个数（`valuesHead`），不是完整向量。

`dim` 与 `values.length` 不一致、`modelId` 为空或 `dim <= 0` 时，断言失败抛 `AssertionError`。

### `TextOverBudgetException`

```dart
const TextOverBudgetException({required int tokenCount, required int maxLength});
int get tokenCount;
int get maxLength;
```

```dart
try {
  await embedder.embed(veryLongText);
} on TextOverBudgetException catch (error) {
  // error.tokenCount > error.maxLength
}
```

句子加上特殊标记后超过 `ModelInfo.maxInputLength`。这是重切信号，不附带被截断的向量。

### `TextEmbedder`

```dart
TextEmbedder({
  required ModelInfo model,
  required UnigramTokenizer tokenizer,
  required EmbeddingRuntime runtime,
  TextInputBuilder? inputs,
});
Future<EmbeddingVector> embed(
  String text, {
  String? chunkId,
  CancellationToken? cancel,
});
static List<double> meanPool(List<double> hidden, List<int> mask, int dim);
static List<double> l2Normalize(List<double> vector);
```

```dart
final List<double> pooled = TextEmbedder.meanPool(
  <double>[1, 2, 3, 4, 5, 6],
  <int>[1, 1, 0],
  2,
);
// pooled == [2.0, 3.0]
final List<double> unit = TextEmbedder.l2Normalize(<double>[3, 4]);
// unit[0] == 0.6 && unit[1] == 0.8
```

运行时交回展平的 `last_hidden_state`，长度是 `sequence * dim`，不做 pooling，也不做 L2。`embed` 按 attention mask 对非零位置做 mean，再做 L2，并把 `EmbeddingVector.normalized` 设为 true。pad 位置不进平均。

`model.pooling` 不是 `mean`，或 `maxInputLength` 为 null 或小于 2，抛 `ArgumentError`。

`embed` 的检查顺序是：已取消、`text` 为空、`chunkId` 为空字符串、运行时不可用、token 超预算，然后才 `runtime.run`。对应地抛 `CancelledException`、`ArgumentError`、`RuntimeUnavailableException`、`TextOverBudgetException`。运行时抛出的 `MissingTensorException`、`EmbeddingTimeoutException`、`DimensionMismatchException`、`BadOutputException` 原样冒出。

`meanPool` 在 `dim <= 0` 时抛 `ArgumentError`。`hidden.length` 不是 `mask.length * dim` 时抛 `DimensionMismatchException`。mask 全是 0，或隐藏状态里有非有限数，抛 `BadOutputException`。

`l2Normalize` 在向量为空、含非有限数、或范数为 0 时抛 `BadOutputException`。

### `ClipTextEmbedder`

```dart
ClipTextEmbedder({
  required ModelInfo model,
  required ClipBpeTokenizer tokenizer,
  required EmbeddingRuntime runtime,
});
Future<EmbeddingVector> embed(
  String text, {
  String? chunkId,
  CancellationToken? cancel,
});
```

```dart
final EmbeddingVector query = await ClipTextEmbedder(
  model: clipTextModel,
  tokenizer: clipTokenizer,
  runtime: clipRuntime,
).embed('a man is in a kitchen making pizzas.', chunkId: 'q1');
// query.space == EmbeddingSpace.clipShared
// query.dim == 512
// query.normalized == true
```

运行时只收到 `input_ids`，形状 `[1, 77]`，int64。不足 77 用 `padId`（`!`，id 0）补齐。超过 77 抛 `TextOverBudgetException`，不截断。图内输出 `text_embeds` 不做 L2，这里做完再把 `normalized` 设为 true。不要拿它和 384 维的文档向量比。

空间不是 `clipShared`、`pooling` 不是 `none`，或 `maxInputLength` 小于 2，抛 `ArgumentError`。空文本、空的 `chunkId`、运行时不可用，也抛对应的调用错误或 `RuntimeUnavailableException`。维度不符原样抛出。

### `DecodedImage`

```dart
const DecodedImage({
  required Uint8List rgb24,
  required int width,
  required int height,
});
```

一行行的 RGB24。解析层只留宽高，像素由解码器按原路径重新读出。不抛异常。

### `ImageDecoder`

```dart
abstract interface class ImageDecoder {
  DecodedImage decodeFile(String path);
}
```

批量服务用这个接口读图像。默认套件注入假实现，不读数据集。

### `PackageImageDecoder`

```dart
const PackageImageDecoder();
DecodedImage decodeFile(String path);
DecodedImage decodeBytes(Uint8List bytes);
```

`package:image` 的 JPEG/PNG 解码。不做 EXIF 旋转。文件不存在抛 `FileSystemException`。空字节或无法解码抛 `FormatException`。

### `PreprocessedImage`

```dart
const PreprocessedImage({
  required Float32List pixels,
  required int edge,
});
int get channels;
List<int> get shape;
```

NCHW float32，值域 0–1。`shape` 是 `[1, 3, edge, edge]`。不抛异常。

### `ImagePreprocessor`

```dart
const ImagePreprocessor({int edge = ImagePreprocessor.mobileClipEdge});
static const int mobileClipEdge = 256;
PreprocessedImage preprocess({
  required Uint8List rgb24,
  required int width,
  required int height,
});
```

短边缩到 `edge`，用 Pillow `Image.BILINEAR`（缩小时加宽卷积核，8-bit 两遍、22 位定点），再中心裁成正方形，像素除以 255。不加 mean/std。`edge < 1`、宽高不是正数、或字节长度不是 `width * height * 3`，抛 `ArgumentError`。

### `ImageEmbedder`

```dart
ImageEmbedder({
  required ModelInfo model,
  required EmbeddingRuntime runtime,
  ImagePreprocessor? preprocessor,
});
Future<EmbeddingVector> embed({
  required Uint8List bytes,
  required int width,
  required int height,
  CancellationToken? cancel,
});
```

```dart
final EmbeddingVector image = await ImageEmbedder(
  model: clipVisionModel,
  runtime: visionRuntime,
).embed(bytes: rgb24, width: width, height: height);
// image.space == EmbeddingSpace.clipShared
// image.dim == 512
// image.normalized == true
```

输入张量名是 `pixel_values`，float32 NCHW。图内 `image_embeds` 不做 L2，这里做完再交出。空间不是 `clipShared` 或 `pooling` 不是 `none`，抛 `ArgumentError`。输出长度不是 `model.dim` 时抛 `DimensionMismatchException`。非有限数抛 `BadOutputException`。

## 5. 运行时

### `TensorDType`

```dart
enum TensorDType { float32, int32, int64, uint8 }
```

```dart
const TensorDType dtype = TensorDType.int64;
```

只覆盖本包模型实际会放进 `TypedData` 的几种。不抛异常。

### `Tensor`

```dart
const Tensor({
  required TensorDType dtype,
  required List<int> shape,
  required TypedData data,
});
```

```dart
final Tensor ids = Tensor(
  dtype: TensorDType.int64,
  shape: const <int>[1, 128],
  data: Int64List(128),
);
```

一次推理的输入或输出。`data` 要和 `dtype` 一致：float32 用 `Float32List`，int32 用 `Int32List`，int64 用 `Int64List`，uint8 用 `Uint8List`。形状按模型签名。构造函数不核对元素类型，对不上的输入在 `OnnxProcessEmbeddingRuntime.run` 里抛 `MissingTensorException`。

### `TensorDirection`

```dart
enum TensorDirection { input, output }
```

```dart
const TensorDirection direction = TensorDirection.input;
```

端口属于输入还是输出。只靠名字区分不了。不抛异常。

### `TensorInfo`

```dart
const TensorInfo({
  required String name,
  required TensorDirection direction,
  required TensorDType dtype,
  required List<int> shape,
});
```

```dart
const TensorInfo info = TensorInfo(
  name: 'input_ids',
  direction: TensorDirection.input,
  dtype: TensorDType.int64,
  shape: <int>[-1, -1],
);
```

模型端口。动态维可以是 -1。不抛异常。

### `EmbeddingRuntime`

```dart
abstract interface class EmbeddingRuntime {
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs);
  bool get isAvailable;
}
```

TFLite 动态库和外部 ONNX 进程实现同一个接口。文本模型的 `run` 返回展平的 `last_hidden_state`。单测注入假实现，不加载真模型。维度不符、缺张量、超时、运行时不可用都抛 `EmbeddingRuntimeException` 的子类。

### `EmbeddingRuntimeException`

```dart
const EmbeddingRuntimeException(String message, {String? detail});
String get message;
String? get detail;
```

```dart
const EmbeddingRuntimeException failure = EmbeddingRuntimeException(
  'ONNX process exited 1.',
  detail: 'boom',
);
```

运行时失败的根类型。批量服务以后把它收成一条失败记录。`detail` 放 stderr 或底层异常文本，不放正文。

### `RuntimeUnavailableException`

```dart
const RuntimeUnavailableException(String message, {String? detail});
```

动态库、解释器或外部进程不存在，或者进程根本起不来。`TextEmbedder` 在 `isAvailable` 为 false 时抛它。

### `DimensionMismatchException`

```dart
const DimensionMismatchException(String message, {String? detail});
```

隐藏状态的长度和 `mask.length * dim` 不一致。

### `MissingTensorException`

```dart
const MissingTensorException(String message, {String? detail});
```

模型签名里的某个输入没有提供，或提供的元素类型不是 int64。`OnnxProcessEmbeddingRuntime` 要求三份输入都在：`input_ids`、`attention_mask`、`token_type_ids`。

### `EmbeddingTimeoutException`

```dart
const EmbeddingTimeoutException(String message, {String? detail});
```

单次推理超过 `OnnxProcessEmbeddingRuntime.timeout`。默认 120 秒。

### `BadOutputException`

```dart
const BadOutputException(String message, {String? detail});
```

进程 stdout 不是小端 float32 的 base64，长度不是 4 的倍数，向量为空，含非有限数，或 L2 范数为 0。

### `OnnxProcessEmbeddingRuntime`

```dart
OnnxProcessEmbeddingRuntime({
  required String pythonExecutable,
  required String scriptPath,
  required String modelPath,
  required ProcessRunner processRunner,
  Duration timeout = const Duration(seconds: 120),
});
bool get isAvailable;
Future<Float32List> run(String modelId, Map<String, Tensor> inputs);
```

```dart
final OnnxProcessEmbeddingRuntime runtime = OnnxProcessEmbeddingRuntime(
  pythonExecutable: pythonExecutable,
  scriptPath: r'engine\embed_text_hidden.py',
  modelPath: modelOnnxPath,
  processRunner: const IoProcessRunner(),
);
// runtime.isAvailable 为真当三个路径都指向已存在的文件
```

ADR 0003 的运行时。Dart 不链接 TFLite。`run` 把请求写成临时 JSON，参数是解释器、脚本路径和请求文件路径。脚本把 `last_hidden_state` 以小端 float32 的 base64 写到 stdout。pooling 不在这里做。

`isAvailable` 检查解释器、脚本和模型文件是否存在，不抛异常。三者缺一时 `run` 抛 `RuntimeUnavailableException`。`ProcessStartException` 映射为 `RuntimeUnavailableException`，`ProcessTimeoutException` 映射为 `EmbeddingTimeoutException`，非零退出码抛 `EmbeddingRuntimeException`，stdout 无法解码抛 `BadOutputException`。`CancelledException` 不在这里接住。

环境在当前进程环境上加上 `PYTHONIOENCODING=utf-8` 和 `PYTHONUNBUFFERED=1`。请求文件放在临时目录，调用结束后删除。

### `OnnxTensorEmbeddingRuntime`

```dart
OnnxTensorEmbeddingRuntime({
  required String pythonExecutable,
  required String scriptPath,
  required String modelPath,
  required ProcessRunner processRunner,
  required String outputName,
  Duration timeout = const Duration(seconds: 120),
});
```

```dart
final OnnxTensorEmbeddingRuntime vision = OnnxTensorEmbeddingRuntime(
  pythonExecutable: pythonExecutable,
  scriptPath: r'engine\embed_onnx_output.py',
  modelPath: visionOnnxPath,
  processRunner: const IoProcessRunner(),
  outputName: 'image_embeds',
);
```

图像塔和 CLIP 文本塔共用的进程运行时。请求 JSON 带每个输入张量：float32 用小端 base64，int64 用数字列表。stdout 是 `outputName` 的小端 float32 base64。`outputName` 对图像是 `image_embeds`，对 CLIP 文本是 `text_embeds`。文档 MiniLM 仍走 `OnnxProcessEmbeddingRuntime`，请求形状不改。

错误映射与文本运行时相同。输入为空，或张量的 `TypedData` 和 dtype 对不上，在起进程之前抛 `MissingTensorException`。脚本目录会加进 Python 路径，以便导入 `w3_embed_lib`。

### `TfliteBindings`

```dart
abstract interface class TfliteBindings {
  int loadModel(List<int> bytes);
  List<TensorInfo> describe(int handle);
  void invoke(int handle, Map<String, Tensor> inputs, Map<String, Tensor> outputs);
  void close(int handle);
}
```

进程内 TFLite 的绑定缝。阶段 B 没有实现，也没有放置 `libtensorflowlite_c-win.dll`。`loadModel` 失败时抛 `RuntimeUnavailableException`。`close` 对同一个句柄重复调用应当无害。默认单测不链接动态库。

## 6. 统一入口与批量报告

输入形状在阶段 A 冻结。`DefaultEmbeddingEngine` 和 `DefaultEmbeddingService` 是阶段 C 的实现。图像字节仍是行优先 RGB24。

### `EmbeddingInput`

```dart
EmbeddingInput.text(
  String text, {
  String? chunkId,
  EmbeddingSpace space = EmbeddingSpace.documentText,
});
EmbeddingInput.image({
  required Uint8List bytes,
  required int width,
  required int height,
  EmbeddingSpace space = EmbeddingSpace.clipShared,
});
bool get isImage;
```

```dart
final EmbeddingInput query = EmbeddingInput.text('页码在哪里', chunkId: 'q1');
// query.space == EmbeddingSpace.documentText
// query.isImage == false
```

文本可以落在 `documentText` 或 `clipShared`。图像只能落在 `clipShared`。图像字节是行优先 RGB24，长度等于 `width * height * 3`。解析结果只保留宽高，不保留像素，所以批量服务会按原路径再读一次文件。

`chunkId` 为空字符串抛 `ArgumentError`。`EmbeddingInput.text` 的 `text` 是非空类型，空字符串在这一层放行，`TextEmbedder.embed` 再拒绝。图像空间不是 `clipShared`、宽或高不是正数、或字节长度不对，抛 `ArgumentError`。

### `EmbeddingSpaceMismatchException`

```dart
const EmbeddingSpaceMismatchException({
  required EmbeddingSpace requested,
  required EmbeddingSpace actual,
  String message = 'Embedding spaces cannot be mixed.',
});
```

```dart
const EmbeddingSpaceMismatchException mismatch = EmbeddingSpaceMismatchException(
  requested: EmbeddingSpace.clipShared,
  actual: EmbeddingSpace.documentText,
);
```

一次调用混用了两个向量空间。实现必须抛它，不能靠文档约定。`DefaultEmbeddingEngine` 在请求空间和模型空间不一致时抛它，也在缺少 CLIP 文本塔时抛它。

### `EmbeddingEngine`

```dart
abstract interface class EmbeddingEngine {
  Future<EmbeddingVector> embed(EmbeddingInput input, {CancellationToken? cancel});
  List<ModelInfo> get models;
}
```

文本和图像共用的入口。返回值带 `space`、`dim`、`modelId`、`normalized`。空间和模型不一致时，实现必须抛 `EmbeddingSpaceMismatchException`。

### `DefaultEmbeddingEngine`

```dart
DefaultEmbeddingEngine({
  required TextEmbedder text,
  required ImageEmbedder image,
  ClipTextEmbedder? clipText,
});
```

```dart
final DefaultEmbeddingEngine engine = DefaultEmbeddingEngine(
  text: textEmbedder,
  image: imageEmbedder,
  clipText: clipTextEmbedder,
);
final EmbeddingVector vector = await engine.embed(
  EmbeddingInput.text('页码在哪里', chunkId: 'q1'),
);
// engine.models 含文档模型、图像模型和 CLIP 文本塔
```

`documentText` 走 `TextEmbedder`。`clipShared` 的文本走 `ClipTextEmbedder`。图像走 `ImageEmbedder`。没有文本塔，或文本塔空间不是 `clipShared`，抛 `EmbeddingSpaceMismatchException`，不改用文档模型。`models` 按文档、图像、CLIP 文本的顺序给出；没传文本塔时只有前两个。

### `EmbeddingFailureKind`

```dart
enum EmbeddingFailureKind {
  runtimeUnavailable,
  badOutput,
  missingTensor,
  timeout,
  spaceMismatch,
  cancelled,
  overBudget,
  unknown,
}
```

```dart
const EmbeddingFailureKind kind = EmbeddingFailureKind.overBudget;
```

单条向量失败的分类。`overBudget` 对应文本超长。批量服务按它汇总，不让一条坏输入中断整批。不抛异常。

### `EmbeddingFailure`

```dart
const EmbeddingFailure({
  required EmbeddingFailureKind kind,
  required String message,
  String? detail,
});
Map<String, Object?> toJson();
```

```dart
const EmbeddingFailure failure = EmbeddingFailure(
  kind: EmbeddingFailureKind.overBudget,
  message: '129 tokens exceed maxLength 128.',
);
```

对一条输入失败的结构化描述。不含向量，也不含正文。不抛异常。

### `EmbeddingRecord`

```dart
const EmbeddingRecord.success({
  required String sourceId,
  required EmbeddingVector vector,
});
const EmbeddingRecord.failure({
  required String sourceId,
  required EmbeddingFailure failure,
});
bool get isSuccess;
Map<String, Object?> toJson();
```

```dart
final EmbeddingRecord record = EmbeddingRecord.success(
  sourceId: 'chunk-1',
  vector: vector,
);
// record.isSuccess == true
```

批量向量化里的一条记录。成功和失败二选一。`sourceId` 是文件相对路径或 `chunkId`。不抛异常。

### `EmbeddingReport`

```dart
const EmbeddingReport({
  required DateTime startedAt,
  required DateTime finishedAt,
  List<EmbeddingRecord> records = const <EmbeddingRecord>[],
  bool cancelled = false,
});
Duration get duration;
int get total;
int get succeeded;
int get failed;
bool get isClean;
Map<String, Object?> toJson();
```

```dart
final EmbeddingReport report = EmbeddingReport(
  startedAt: started,
  finishedAt: finished,
  records: <EmbeddingRecord>[record],
);
// report.isClean == true
```

一次批量向量化的汇总。形状对齐 `IngestionReport`：单条失败留在记录里。`isClean` 在没有失败且没有取消时为真。不抛异常。

### `EmbeddingProgress`

```dart
const EmbeddingProgress({
  required int processed,
  required int total,
  String? currentId,
  Duration elapsed = Duration.zero,
});
Map<String, Object?> toJson();
```

```dart
const EmbeddingProgress progress = EmbeddingProgress(
  processed: 1,
  total: 4,
  currentId: 'chunk-1',
);
// progress.toString() == 'EmbeddingProgress(1/4)'
```

批量运行期间的进度。`processed` 与 `total` 同时存在，方便读屏播报。不抛异常。

### `EmbeddingService`

```dart
abstract interface class EmbeddingService {
  Future<EmbeddingReport> embedAll(
    IngestionReport ingestion, {
    void Function(EmbeddingProgress)? onProgress,
    CancellationToken? cancel,
  });
}
```

批量向量化。只消费 `IngestionReport.indexable`。单条失败写进 `EmbeddingReport`，不中断后面的文件。

### `DefaultEmbeddingService`

```dart
DefaultEmbeddingService({
  required EmbeddingEngine engine,
  required TextChunker chunker,
  ImageDecoder? images,
  DateTime Function()? clock,
});
```

```dart
final DefaultEmbeddingService service = DefaultEmbeddingService(
  engine: engine,
  chunker: CascadeTextChunker(
    countTokens: (String text) => tokenizer.encode(text).ids.length,
  ),
);
final EmbeddingReport report = await service.embedAll(
  ingestion,
  onProgress: (EmbeddingProgress progress) {},
  cancel: token,
);
```

进度按文件计。开始时回报 `0/total`，每个文件结束后再回报。已经取消的令牌直接返回空报告，`cancelled` 为 true，进度是 `0/0`。取消停在下一个文件或下一块之前，已经写好的记录保留。

文本块的 `sourceId` 是 `chunkId`。图像的 `sourceId` 是相对路径。切块超预算时，这条记录的 `sourceId` 是内容哈希或元数据 id。图像按 `document.imageAsset`，没有则用 `metadata.imageAsset`，再按原路径解码。没有正文也没有图像、或可索引记录没有文档，记成 `unknown`。

失败种类：`ChunkBudgetException` 和 `TextOverBudgetException` 是 `overBudget`；`RuntimeUnavailableException` 是 `runtimeUnavailable`；`BadOutputException` 和 `DimensionMismatchException` 是 `badOutput`；`MissingTensorException` 是 `missingTensor`；`EmbeddingTimeoutException` 是 `timeout`；`EmbeddingSpaceMismatchException` 是 `spaceMismatch`。其余运行时异常、读文件失败、解码失败和未知错误是 `unknown`。失败消息不含正文。服务不扫描目录，调用方先拿 `IngestionReport`。

## 7. 公开符号清单

对照 `lib/core_embedding.dart`：

`DefaultEmbeddingEngine`、`EmbeddingEngine`、`EmbeddingSpaceMismatchException`、`DefaultEmbeddingService`、`EmbeddingService`、`DecodedImage`、`ImageDecoder`、`PackageImageDecoder`、`ImageEmbedder`、`clipVisionModel`、`ImagePreprocessor`、`ImagePreprocessor.mobileClipEdge`、`PreprocessedImage`、`EmbeddingInput`、`EmbeddingFailure`、`EmbeddingFailureKind`、`EmbeddingProgress`、`EmbeddingRecord`、`EmbeddingReport`、`EmbeddingSpace`、`EmbeddingVector`、`ModelInfo`、`TextChunk`、`TextChunker`、`TextUnit`、`BadOutputException`、`DimensionMismatchException`、`EmbeddingRuntime`、`EmbeddingRuntimeException`、`EmbeddingTimeoutException`、`MissingTensorException`、`RuntimeUnavailableException`、`Tensor`、`TensorDirection`、`TensorDType`、`TensorInfo`、`OnnxProcessEmbeddingRuntime`、`OnnxTensorEmbeddingRuntime`、`TfliteBindings`、`ClipBpeTokenizer`、`ClipTextEmbedder`、`clipTextModel`、`CascadeTextChunker`、`ChunkBudgetException`、`documentTextModel`、`TextEmbedder`、`TextOverBudgetException`、`TextInputBuilder`、`TextInputNeedsRechunk`、`TextInputResult`、`TextInputTensors`、`AddedToken`、`TokenEncoding`、`UnigramTokenizer`。
