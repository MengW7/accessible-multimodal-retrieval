# core_embedding

离线文本与图像向量的纯 Dart 包。文档正文走 Unigram、长度 128 的输入张量和 mean pooling。图像走 MobileCLIP：短边 256、双线性、中心裁剪、除以 255。`DefaultEmbeddingEngine` 按空间分发，`DefaultEmbeddingService` 消费 `IngestionReport.indexable`。

公开入口是 `package:core_embedding/core_embedding.dart`。`lib/src/` 不是稳定 API。计划里的 `wordpiece_tokenizer.dart` 只保留路径；词表方案是 Unigram，文件是 `tokenizer.json`，没有 `vocab.txt`。

两条向量空间不能混用：

- `EmbeddingSpace.documentText`：文档正文和文本查询。`TextEmbedder` 出的向量在这个空间，维度 384。
- `EmbeddingSpace.clipShared`：MobileCLIP 图像和用来查图的自然语言。`ImageEmbedder` 与 `ClipTextEmbedder` 出的向量在这个空间，维度 512。

文本偏移量单位是 UTF-16 code unit，与 `ParsedDocument` 的 `String.length` 一致。句子加上特殊标记后超过 128 时不截断：`TextInputBuilder` 返回重切信号，`TextEmbedder` 抛 `TextOverBudgetException`。CLIP 文本塔上限是 77，含起止标记，不足用 `!` 的 id 补齐，超长同样不截断。

`CascadeTextChunker` 按空行、换行、句末标点和字符窗口切块。页与页之间不合并。`chunkChars` 只是字符窗口初值，token 数才是硬门。

模型文件、维度和转换校验记在仓库根的 `models/README.md`。文档文本走 `OnnxProcessEmbeddingRuntime` 和 `engine/embed_text_hidden.py`。图像和 CLIP 文本走 `OnnxTensorEmbeddingRuntime` 和 `engine/embed_onnx_output.py`。权重不打进包。默认 `dart test --exclude-tags integration` 不读模型，也不读数据集。API 说明见 `docs/api/embedding-module-api.md`。
