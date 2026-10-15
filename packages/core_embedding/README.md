# core_embedding

离线文本与图像向量的纯 Dart 包。Week 3 阶段 A 只冻结公开类型和运行时缝；分词器、预处理和真正的推理适配器在后续阶段补上。

公开入口是 `package:core_embedding/core_embedding.dart`。`lib/src/` 不是稳定 API。

两条向量空间不能混用：

- `EmbeddingSpace.documentText`：文档正文和文本查询
- `EmbeddingSpace.clipShared`：MobileCLIP 图像，以及用来查图的自然语言

文本偏移量单位是 UTF-16 code unit，与 `ParsedDocument` 的 `String.length` 一致。模型文件、维度和转换校验记在仓库根的 `models/README.md`。Day 1 的可运行探针是 `engine/embed_spike.py`，它走本机已有的 ONNX Runtime，不从本包加载权重。
