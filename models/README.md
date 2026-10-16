# 模型登记

Week 3 阶段 A 冻结的文本模型和图像模型。权重在 `models/raw/`，根 `.gitignore` 不跟踪 `*.onnx` 和这个目录。`models/tflite/` 这次是空的：通过余弦门槛的文件是 ONNX fp32，没有可加载的 TFLite。运行时决定见 ADR 0003。

重新下载（在仓库根目录，使用 `engine/.venv`）：

```text
engine\.venv\Scripts\python.exe engine\download_w3_models.py
```

探针：

```text
engine\.venv\Scripts\python.exe engine\embed_spike.py
engine\.venv\Scripts\python.exe engine\convert_check.py
```

原始输出在 `reports/week3/logs/embed_spike.txt` 和 `reports/week3/logs/convert_check.txt`。下面的数字以这两份日志为准。工具版本：onnxruntime 1.30.0、tokenizers 0.23.2、pillow 12.3.0、numpy 2.5.3。

可携带的运行时文件是各目录里的 **fp32**。`*_int8.onnx` 没有达到余弦 0.999，不要加载。`*_ort.onnx` 是本机 `ORT_ENABLE_ALL` 的对照，余弦为 1，但 ORT 提示这类优化图可能带本机硬件核，不要当成换机器还能用的产物。

`datasets/README.md` 里 RVL-CDIP 的数量已改为 16，对应 `datasets/rvlcdip/sample/` 的 16 个文件。

## 1. 文本：paraphrase-multilingual-MiniLM-L12-v2

| # | 字段 | 值 |
|---|---|---|
| 1 | 模型名 + revision | 上游 `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`。本机文件来自 `Xenova/paraphrase-multilingual-MiniLM-L12-v2`，revision `2c4055b12046f11709e9df2c122e59ffbdc2f900`（2025-07-22） |
| 2 | 分词器 | `models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json`。Unigram，词表 250002。归一化是 Precompiled。`config.json` 的 `vocab_size` 是 250037，分词对照以 `tokenizer.json` 为准。字节 17082913，sha256 `b60b6b43406a48bf3638526314f3d232d97058bc93472ff2de930d43686fa441` |
| 3 | 最大输入长度 | **128 token**。这是 sentence-transformers 登记的 `max_seq_length`。位置编码容量是 512，运行时仍按 128 截断并补齐 |
| 4 | pooling | mean。对 `last_hidden_state` 按 `attention_mask` 做加权平均，不是 CLS |
| 5 | 是否归一化 | 图内否。探针里中文句原始 L2 为 3.823005，英文句为 4.611503。`EmbeddingVector` 在交出前做 L2，`normalized=true` |
| 6 | query / document 前缀 | 都没有。不要加 `query:` 或 `passage:` |
| 7 | 转换工具与版本 | Xenova 的 ONNX 导出（上表 revision）。本机对照用 onnxruntime 1.30.0 的 `ORT_ENABLE_ALL`。没有用 torch |
| 8 | 转换前后余弦 | 相对 fp32：int8 最低 **0.982951**，不通过。`ORT_ENABLE_ALL` 五句都是 **1.000000**，通过。采用 fp32 |

空间 `documentText`，维度 384。

| 文件 | 字节 | sha256 | 用途 |
|---|---:|---|---|
| `onnx/model.onnx` | 470268510 | `185ae63f47e17a7e8d30d0e6a3cde6a6e4b79bc5b81666ecffc279a6856ca113` | **加载这个** |
| `onnx/model_int8.onnx` | 118054609 | `d6ea442ff6a891daefed7c83b2f596fc5dc66bf697e4d006236f64f34bbcf4c8` | 不通过，留作反例 |
| `onnx/model_ort.onnx` | 470114179 | `1412a30cf1a5ca9b3dc2689edbe60311f736ca1483d9f63e5ae6465af534bd82` | 本机对照，不外带 |

张量签名：

```text
input  input_ids        int64  [batch_size, sequence_length]
input  attention_mask   int64  [batch_size, sequence_length]
input  token_type_ids   int64  [batch_size, sequence_length]
output last_hidden_state float32 [batch_size, sequence_length, 384]
```

来源：<https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2> ，导出 <https://huggingface.co/Xenova/paraphrase-multilingual-MiniLM-L12-v2>。许可证 Apache-2.0。

Day 1 耗时（warmup 一次之后 3 次的平均，不含加载模型）：中文 25.44 ms，英文 26.69 ms。中文内容 token 13 个，unk 0 个。

## 2. 图像塔：MobileCLIP-S0 vision

| # | 字段 | 值 |
|---|---|---|
| 1 | 模型名 + revision | 上游 `apple/MobileCLIP-S0`。本机文件来自 `Xenova/mobileclip_s0`，revision `757d59c9c6870a76a4b0306f05f5061bca15c39f` |
| 2 | 分词器 | 图像塔不用分词器。文本塔的分词器见下一节，两边必须配套 |
| 3 | 最大输入长度 | 图像 256×256。短边缩放到 256，双线性，中心裁剪，像素除以 255。`preprocessor_config.json` 里 `do_normalize` 为 false，不加另一套 mean/std |
| 4 | pooling | none。图直接输出 `image_embeds`，没有再做 token 平均 |
| 5 | 是否归一化 | 图内否。`000000397133.jpg` 的原始 L2 为 0.821738。交出前做 L2，`normalized=true` |
| 6 | query / document 前缀 | 没有。查图用的是下一节的文本塔，不是给这只图像塔加前缀 |
| 7 | 转换工具与版本 | 同上，Xenova ONNX 导出；对照 onnxruntime 1.30.0 |
| 8 | 转换前后余弦 | 三张 COCO 图，int8 最低 **0.045810**，不通过。输入两边都是 float，不是类型喂错。`ORT_ENABLE_ALL` 三张都是 **1.000000**，通过。采用 fp32 |

空间 `clipShared`，维度 512。

| 文件 | 字节 | sha256 | 用途 |
|---|---:|---|---|
| `onnx/vision_model.onnx` | 45543630 | `17d3c037b1d488c10c50e09f6009ea5a198caef4e0e8f4ea5617b7cb2d067ac0` | **加载这个** |
| `onnx/vision_model_int8.onnx` | 11846808 | `7a1b45f57fb9f3cde9d325759883e9451d7281336caeb9c576ae918e72080f0b` | 不通过，留作反例 |
| `onnx/vision_model_ort.onnx` | 45495166 | `a61d3f6fad89a26e090d609800d905d0ee7d8a6f3ef3a302a870ff5483aeabe4` | 本机对照，不外带 |

张量签名：

```text
input  pixel_values  float32 [batch_size, 3, 256, 256]
output image_embeds  float32 [batch_size, 512]
```

来源：<https://huggingface.co/apple/MobileCLIP-S0> ，导出 <https://huggingface.co/Xenova/mobileclip_s0>。代码仓库 <https://github.com/apple/ml-mobileclip>。

许可证必须分开看：代码 MIT，**权重是 Apple Machine Learning Research Model（apple-amlr）**，训练数据 CC-BY-NC-ND。权重只能用于非商业研究，不能放进公开可下载的安装包。结论和依据在 ADR 0003。

Day 1 耗时：同一张 `000000397133.jpg`，warmup 后 3 次平均 35.26 ms。

## 3. 文本塔：MobileCLIP-S0 text

和图像塔同一个 `clipShared` 空间。自然语言查图用它，不用第 1 节的 MiniLM。

| # | 字段 | 值 |
|---|---|---|
| 1 | 模型名 + revision | 与图像塔同一个 Xenova revision `757d59c9c6870a76a4b0306f05f5061bca15c39f` |
| 2 | 分词器 | `models/raw/image/mobileclip-s0/tokenizer.json`。BPE，词表 49408。归一化是 Sequence。字节 2224081，sha256 `72ed5c96db5729294468543e4bc75fce14ca63f58e37300290189ba1c1e52b85` |
| 3 | 最大输入长度 | **77 token**，含起止标记，不足则补齐 |
| 4 | pooling | none。图输出已经是 `text_embeds`，不要再对 token 做平均 |
| 5 | 是否归一化 | 交出前做 L2，`normalized=true`，与图像塔一致 |
| 6 | query / document 前缀 | 没有 E5 那种前缀。起止标记由分词器自己加 |
| 7 | 转换工具与版本 | 同图像塔 |
| 8 | 转换前后余弦 | 五句最低 int8 **0.768964**，不通过。`ORT_ENABLE_ALL` 五句 **1.000000**，通过。采用 fp32 |

| 文件 | 字节 | sha256 | 用途 |
|---|---:|---|---|
| `onnx/text_model.onnx` | 169807789 | `f6e9bd5742bfc515889e901634d8a2ff2a57fab8564e4ad3760e800b1a51b77c` | **加载这个** |
| `onnx/text_model_int8.onnx` | 42799230 | `fc8d87978623385c17a46331ffb9cb5ab7fe8b61c513c094602b85f08edd0a0b` | 不通过，留作反例 |
| `onnx/text_model_ort.onnx` | 169769538 | `d37b22afe7841f7d3f826aa6a49545b97a50d065fb3cf9977bc18910841e8e4f` | 本机对照，不外带 |

张量签名：

```text
input  input_ids   int64   [batch_size, sequence_length]
output text_embeds float32 [batch_size, 512]
```

这只图没有 `attention_mask` 输入。许可与图像塔相同，不进公开安装包。
