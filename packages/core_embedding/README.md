# core_embedding

离线文本与图像向量的纯 Dart 包。阶段 B 打通了文档文本这条链路：Unigram 分词、长度 128 的输入张量、mean pooling 和 L2。图像预处理、切块实现和统一入口还在后面的阶段。

公开入口是 `package:core_embedding/core_embedding.dart`。`lib/src/` 不是稳定 API。计划里的 `wordpiece_tokenizer.dart` 只保留路径；词表方案是 Unigram，文件是 `tokenizer.json`，没有 `vocab.txt`。

两条向量空间不能混用：

- `EmbeddingSpace.documentText`：文档正文和文本查询。`TextEmbedder` 出的向量在这个空间，维度 384。
- `EmbeddingSpace.clipShared`：MobileCLIP 图像，以及用来查图的自然语言。阶段 B 还不出这个空间的向量。

文本偏移量单位是 UTF-16 code unit，与 `ParsedDocument` 的 `String.length` 一致。句子加上特殊标记后超过 128 时不截断：`TextInputBuilder` 返回重切信号，`TextEmbedder` 抛 `TextOverBudgetException`。

模型文件、维度和转换校验记在仓库根的 `models/README.md`。真推理走 `OnnxProcessEmbeddingRuntime` 和 `engine/embed_text_hidden.py`，权重不打进包。默认 `dart test --exclude-tags integration` 不读模型，也不读数据集。API 说明见 `docs/api/embedding-module-api.md`。
