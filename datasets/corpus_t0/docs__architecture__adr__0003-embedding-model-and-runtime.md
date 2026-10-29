# ADR 0003：Embedding 模型、双空间与运行时

| 项目 | 内容 |
|---|---|
| 状态 | **Accepted**（已采纳） |
| 日期 | 2026-10-15 |
| 决策者 | Week 3 阶段 A |
| 影响范围 | Embedding 层；W4 的索引与融合；W8 能否把权重打进公开包 |
| 相关文档 | `reports/week3/W03_task_plan.md` 决策 1–6；`models/README.md`；`docs/tdd/technical-design-document.md` Q3 |

---

## Context（背景）

Week 3 要回答的唯一问题是：给定文本或图像，向量是什么。开工时的事实：

| 事实 | 证据 |
|---|---|
| 本机没有 `torch`、`transformers`、`sentence-transformers`、`ai-edge-torch` | `reports/week3/W03_task_plan.md` §2.2。不把安装 torch 当成前提 |
| 已装且能离线推理的是 TensorFlow 2.21.0 与 ONNX Runtime 1.30.0，分词用 `tokenizers` 0.23.2 | `engine/.venv`；探针日志里的版本行 |
| `models/raw/`、`models/tflite/` 在本周开始时是空的 | 同计划 §2.3 |
| `native/tflite/windows/` 没有 `libtensorflowlite_c-win.dll` | `native/tflite/README.md` |
| 语料是中英混合 | `datasets/samples` 的 PDF/DOCX，项目文档本身也是中文 |
| 解析层已经能产出可索引记录 | `packages/core_parsing`，W2 行覆盖率 90.99% |
| 覆盖率靠「接口后面注入假实现」，不靠加载真模型 | `ProcessRunner` / `io_process_runner_test.dart` |

官方原文写的是 BERT-base 与 MobileCLIP。下面各节说明实际选型、为什么不照字面用 `bert-base-uncased`，以及运行时为什么先走外部进程。

---

## 决策 1：文本模型

**用 `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` 的 fp32 ONNX，不用 `bert-base-uncased`。**

导出件是 `Xenova/paraphrase-multilingual-MiniLM-L12-v2`，revision `2c4055b12046f11709e9df2c122e59ffbdc2f900`。可加载文件是 `models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/onnx/model.onnx`。

不用 `bert-base-uncased` 的两条理由：

1. **词表是纯英文。** 中文句子会被打成大量 `[UNK]`，中文那一半语料没有可用向量。
2. **它不是检索模型。** 普通预训练 BERT 的 `[CLS]` 或平均池化没有做过句向量训练，直接当检索向量效果差。原文里的 “BERT-base” 按「BERT 类文本编码器」理解，不按这个检查点理解。

选定的模型是句向量模型：12 层、隐藏维 384、mean pooling，sentence-transformers 登记的最大长度是 **128 token**（位置编码容量是 512，运行时仍按 128 截断）。许可证 Apache-2.0。Day 1 探针对一句中文和一句英文都出了 384 维有限向量，中文内容 token 为 13、`unk` 为 0。见 `reports/week3/logs/embed_spike.txt`。

词表不是 WordPiece。`tokenizer.json` 的 `model.type` 是 **Unigram**，词表 250002；同目录 `config.json` 的 `vocab_size` 是 250037，两者不要捏成一个数。归一化是 `tokenizer.json` 里的 **Precompiled**，不是把 `tokenizer_config.json` 的 `do_lower_case` 再实现一遍。这是 XLM-R 一系的 SentencePiece，不是 BERT WordPiece。后续纯 Dart 分词器必须按这份 `tokenizer.json` 逐 id 对齐，不能按 WBS 里的文件名 `wordpiece_tokenizer.dart` 做成 WordPiece。

查询和文档都**不加** `query:` / `passage:` 前缀。漏加前缀这一类问题在这个模型上不存在；换到 E5 或 BGE 时必须重新打开这一条。

### Alternatives（文本模型）

| 方案 | 为什么没选 |
|---|---|
| **A. `bert-base-uncased` → TFLite INT8** | 和原文用词最接近，但是纯英文词表，也没有句向量训练。中文探针过不了。 |
| **B. `intfloat/multilingual-e5-small`** | 更直接地为检索训练过，中英都覆盖，MIT。词表同样是 XLM-R SentencePiece，而且还要求 query/passage 前缀，漏了会静默掉点。纯 Dart 分词器更难，本周不改走这条。接口留在 `EmbeddingRuntime` 后面，以后可以换。 |
| **C. `BAAI/bge-small-zh-v1.5`** | 中文检索强，英文弱。语料是中英混合，不把英文侧让掉。 |

---

## 决策 2：图像模型

**用 MobileCLIP-S0 的 fp32 ONNX，图像塔和文本塔都留。** 时间盒内不再换第二个图像模型。

导出件是 `Xenova/mobileclip_s0`，revision `757d59c9c6870a76a4b0306f05f5061bca15c39f`。可加载文件：

- 图像塔 `models/raw/image/mobileclip-s0/onnx/vision_model.onnx`，输出 `image_embeds`，512 维
- 文本塔 `models/raw/image/mobileclip-s0/onnx/text_model.onnx`，输出 512 维，和图像塔同一个空间

预处理按该导出附带的 `preprocessor_config.json`，不另加一套 mean/std：

- 短边缩放到 256，双线性
- 中心裁成 256×256
- 像素除以 255，得到 0–1
- `do_normalize` 为 false

对 `datasets/coco/val_sample/images/000000397133.jpg`，fp32 图像塔给出 512 维有限向量，原始 L2 约 0.82。图内**没有**做 L2 归一化。出 `EmbeddingVector` 之前由嵌入器做 L2，`normalized` 记为 true。

### 许可证结论（不是待核对项）

三套许可是分开的，不能用代码许可覆盖权重：

| 对象 | 许可 | 来源 |
|---|---|---|
| `ml-mobileclip` 代码 | MIT | 仓库 README |
| **模型权重** | **Apple Machine Learning Research Model（apple-amlr）** | 同一 README 写明 “ML models: Apple ML Research Model TOU”。Apple 维护者 2025-07-21 在 `apple/MobileCLIP-S0` 的讨论里确认正确许可证是 apple-amlr |
| 训练数据 | CC-BY-NC-ND | 同一 README |

apple-amlr 把使用限制在非商业的科研和学术开发，再分发必须带上协议和署名，并且不能用 Apple 的商标给衍生模型背书。Xenova 的 ONNX 是这份权重的导出件，跟着权重走，不因为换了文件格式就变成 Apache-2.0。

**结论：W8 不能把 MobileCLIP 权重放进公开可下载的安装包。** 交付形态改为本机研究使用：权重留在已 gitignore 的 `models/raw/`，克隆仓库的人按研究许可自行下载。这不是“以后再看”，这是本周的许可证结论。文本模型是 Apache-2.0，没有这一条限制。

### Alternatives（图像模型）

| 方案 | 为什么没选 |
|---|---|
| **A. 官方 `mobileclip_s0.pt`** | 本机没有 torch，`.pt` 也在根 `.gitignore` 里。加载不了。 |
| **B. 另选一个可再分发的小 CLIP** | 许可问题用「不进公开包」解决，不再花半天换模型。换模型留到真的要做公开安装包时。 |
| **C. 只留图像塔、不下载文本塔** | 自然语言查图需要文本塔。文本塔 fp32 已经落盘，INT8 没有通过下面的门槛，所以留的是 fp32。 |

---

## 决策 3：两个向量空间

文本 384 维和 MobileCLIP 512 维**不在同一个空间，不能直接比**。

统一入口显式带空间，不允许只留一个不含空间的 `embed()`：

| 空间 | 谁用 | 维度 |
|---|---|---|
| `EmbeddingSpace.documentText` | 文档正文、文本查文本 | 384，MiniLM |
| `EmbeddingSpace.clipShared` | 图像，以及用来查图的自然语言 | 512，MobileCLIP 图像塔和文本塔 |

`EmbeddingEngine` 在空间和模型不一致时抛 `EmbeddingSpaceMismatchException`。图像输入只能是 `clipShared`；文本输入可以是 `documentText` 或 `clipShared`，后者走 MobileCLIP 文本塔。W4 要做「一句话同时搜到文档和图片」时，只能是两个索引加分数归一化之后再合并，或者用 MobileCLIP 文本塔单独建图像侧的文本索引。不能把 384 维和 512 维拿去算余弦。

### Alternatives（空间）

| 方案 | 为什么没选 |
|---|---|
| **A. 一个共享空间，强行投影到同一维度** | W3 没有这个投影的训练，硬投影会假装两个模型可比。 |
| **B. 接口上不写空间，靠文档提醒** | 文档提醒挡不住一次错误的余弦。异常是代码里的门。 |

---

## 决策 4：运行时与兜底

**W3 的可执行路径是外部 ONNX Runtime 进程，不是进程内 TFLite。**

`engine/embed_spike.py` 已经用 `onnxruntime` 1.30.0 对文本和图像各跑出向量，`gate=pass`。这就是决策 1 里「拿不到 TFLite DLL 就走 W2 同款外部进程」的那条兜底，而且探针已经把它跑通。

原因：

1. 通过转换门槛的权重是 ONNX fp32。`libtensorflowlite_c` 不能加载 ONNX。
2. 本机没有 torch / optimum / ai-edge-torch，不能在「不新装一套训练框架」的前提下把这些图转成 TFLite，还保证余弦 ≥ 0.999。
3. 因此没有把一个来源未经核对的 `libtensorflowlite_c-win.dll` 放进 `native/tflite/windows/`。那个目录仍是预留位置。

Dart 侧已经把缝留好，单测不必加载真模型：

- `EmbeddingRuntime`：TFLite 或外部进程实现同一接口
- `TfliteBindings`：以后的 `dlopen` 只允许出现在这个接口的一个实现里，默认套件用假绑定覆盖

打包时运行时怎么进安装包，留给 W8，和 ADR 0002 把 JRE 留给 W8 是同一类技术债。W3 不把 Python 虚拟环境打进发布包。

### Alternatives（运行时）

| 方案 | 为什么没选 |
|---|---|
| **A. 现在就放 `libtensorflowlite_c-win.dll` + `dart:ffi`** | 没有一份通过 0.999 门槛的 TFLite 权重可跑。空 DLL 不能证明这条链路。 |
| **B. `tflite_flutter` 插件** | 它是 Flutter 插件，纯 `dart test` 跑不到，覆盖率会靠真模型。和 W2 的打法相反。桌面工程里已有这个依赖，W3 不把它当成包的运行时。 |
| **C. 为了转 TFLite 先装 torch** | 计划明确不把装 torch 当前提。现成的推理引擎是 ONNX Runtime。 |

---

## 决策 5：转换等价性

门槛是同一批输入上，转换前后余弦 **≥ 0.999**。参考侧是上面的 fp32 ONNX（本机能跑的导出，不是 PyTorch，因为没有 torch）。比较时关闭了会话级图优化，mean pooling 用同一套 attention mask。5 句文本、3 张 COCO 图。原始数字在 `reports/week3/logs/convert_check.txt`。

| 转换 | 最低余弦 | 判定 |
|---|---|---|
| 文本 fp32 → 公布的 int8 | **0.982951** | 不通过，不使用 `model_int8.onnx` |
| 图像 fp32 → 公布的 int8 | **0.045810** | 不通过。两边输入都是 float NCHW，不是类型喂错。不使用 `vision_model_int8.onnx` |
| MobileCLIP 文本塔 fp32 → int8 | **0.768964** | 不通过，不使用 `text_model_int8.onnx` |
| 三份 fp32 → ONNX Runtime 1.30.0 `ORT_ENABLE_ALL` 重写 | **1.000000** | 通过 |

通过的那一项说明：在这台机器上，图优化没有改数值。ORT 在写出优化图时警告过，`ORT_ENABLE_ALL` 可能带上本机硬件相关的核，优化后的文件只应在同一环境使用。因此**可携带的产物仍是原始 fp32**，`*_ort.onnx` 只作本机证据。int8 文件留在磁盘上，作为「为什么不用」的证据，任何后续代码都不要改去加载它们。

### Alternatives（转换）

| 方案 | 为什么没选 |
|---|---|
| **A. 余弦不够也先用 int8，图小** | 图像塔 0.046 已经不是量化噪声。用了会让后面的评测变成在测一个坏模型。 |
| **B. 把 `*_ort.onnx` 当成要提交的运行时文件** | 和原始 fp32 余弦是 1，但文件可能含本机核。换一台机器就不保证。 |
| **C. 装 torch 后从 `.pt` 再导出一次，拿 PyTorch 输出当参考** | 能补上「相对原始训练框架」的对比，但违反「不装 torch」的约束。当前参考是已可执行的 fp32 ONNX。 |

---

## 决策 6：切块（Q3）

**页面用于定位，段落用于切分，超过长度上限才切窗口。** 跨页合并不做，交给 W4 的邻域扩展。

```text
保留页码和原文偏移
        ↓
沿 \n\n 切
        ↓
没有段落或仍然过长 → 沿单个 \n
        ↓
仍过长 → 沿句末标点（。！？；. ! ? ;）
        ↓
仍过长 → 按 token 预算做硬窗口
```

三种格式的段落边界不一样，这是 W2 解析器的实测，不是假设：

| 格式 | 段落边界 | 依据 |
|---|---|---|
| TXT | `\n\n` 保留着 | `txt_parser.dart` 只把 `\r\n` / `\r` 收成 `\n` |
| DOCX | 段落和段内换行都变成 `\n`，分不开 | `docx_parser.dart` 用 `paragraphs.join('\n')`，`w:br` 也写成 `\n` |
| PDF | 没有段落契约 | Tika `-x` 只保证按页切开 |

DOCX 接受按单个 `\n` 切。最坏是一段被切成两块。不回头改 W2 已冻结的 `ParsedDocument`。

偏移量是 **UTF-16 code unit**，和 `DocumentPage.charCount`（`String.length`）一致。`startOffset` 含首，`endOffset` 不含尾，所以 `pageText.substring(startOffset, endOffset)` 就是这块的原文跨度。高亮、切片、引用共用这个单位。代理对（emoji）一个字符占两个 code unit，按字素簇高亮会错位。

TXT 和 DOCX 没有物理页时 `pageNumber` 为 null。界面不得把它显示成真实页码。

`chunkId` 包含内容哈希、分块器版本、页码和块序号。只有同一哈希、同一版本、同一配置才可复现。W4 不得把它当稳定主键。

字符长度用来切，token 长度用来卡。文本模型的运行上限是 128 token。超长必须重切或写明 warning，禁止静默截断。`chunkChars` 的初值跟这个模型和语料走，不写成普遍最优。

`sample.pdf` 两页、4358 字符，大约一页 2179 字符，而 128 token 的中文块远短于一页。所谓答案跨页，实践里就是答案跨过相邻块。W3 把 `pageNumber` 和偏移留下来。**邻域扩展是 W4 的事。** 证据集里可以有跨页题，通过标准也定在 W4。

### Alternatives（切块）

| 方案 | 为什么没选 |
|---|---|
| **A. 只按页，一页一块** | PDF 一页两千字，超过 128 token，塞不进模型。 |
| **B. 改解析层，让 DOCX 输出真段落** | 要改已经冻结的 `ParsedDocument`。W3 不单开这个 ADR。 |
| **C. W3 就把跨页答案合并成一块** | 合并规则会绑死检索。W4 拿相邻块或整页扩展更合适。 |
| **D. 偏移按 Unicode 码点或字素簇** | 和 Dart 的 `substring` 不一致，W5 高亮会对不齐。 |

---

## 决策 7：包的边界

四层分开：

| 层 | 落点 | 约束 |
|---|---|---|
| 类型、切块、编排、错误 | `packages/core_embedding`，纯 Dart，无 Flutter | `dart test` 能跑，能算覆盖率 |
| 运行时 | `EmbeddingRuntime` 后面的外部 ONNX 进程；`TfliteBindings` 先只是接口 | 默认套件不加载模型、不读数据集图片 |
| 下载、转换、探针 | `engine/` 里的 Python | 允许独立工具，不要求 Dart 做 |
| 应用 | `apps/desktop` 只加 path 依赖 | W3 不改 UI |

`core_embedding` 可以依赖 `core_parsing`。`core_parsing` 不能反过来依赖它。批量服务只消费 `IngestionReport.indexable`。解析结果不保留像素，所以图像这一条会按原路径再读一次文件，这是读像素，不是第二次解析。

### Alternatives（边界）

| 方案 | 为什么没选 |
|---|---|
| **A. 向量逻辑写进 `apps/desktop`** | `flutter test` 重，覆盖率门槛会和 UI 绑在一起。和 ADR 0001 的理由相同。 |
| **B. 向量逻辑写进 `engine/`，Dart 只壳一层** | 发布包就不能甩掉 Python。运行时兜底是进程，业务类型仍在 Dart。 |
| **C. 为了省一次读盘，把像素塞进 `ParsedDocument`** | 改 W2 已冻结的结果类型。图像路径再读一次更小。 |

---

## 决策 8：评测口径

四层分开报，不合成一个完成度。Day 1 就把口径定死，避免后面用一个替代实验冒充另一个。

| 层 | 指标 | W3 |
|---|---|---|
| 转换等价性 | 同一批输入，转换前后余弦 ≥ 0.999 | 本 ADR 决策 5，已经出数 |
| embedding 级 | NQ-open 300 题。候选池是 300 个 gold answer 加 300 个 question，共 600 条。报 recall@1、recall@5、MRR | 阶段 D 出数，报告里标明这是代理：测的是「能不能从答案候选里排对」，不是「能不能从知识库找到证据」 |
| 检索级 | 自建证据集的 Hit@5、MRR@10。多证据才报 Recall@5 / Recall@10 | W3 只建集和冻结，不出分。出分在 W4 |
| 生成级 | 答案对不对、引用是否支撑、没资料时是否拒答 | **未规划**。PRD 和官方交付清单都没有生成 |

Hit@K 是「前 K 里有没有至少一条相关」。Recall@K 是「相关证据找回了多少」。只有一条相关证据时两者相同，有多条时不能混用。

COCO 的主路径是图像向量对 caption 的文本向量，两边都在 `clipShared`。文本塔已有 fp32。不得改用 MiniLM 去编码 caption。只有 50 张有标题的 COCO 图和 16 张无标题的 RVL-CDIP，图像侧只能做健全性检查，给不出有统计意义的精度。COCO 分数也不能用来证明系统读得懂 PDF 里的图表。

证据集一旦用来调切块或换模型，分数会虚高。dev / holdout 必须分开，并写下冻结时间。冻结之后只看 dev 调参。

### Alternatives（评测）

| 方案 | 为什么没选 |
|---|---|
| **A. 把 NQ 代理指标当成检索完成度** | 仓库里的 NQ 子集只有问答对，没有段落。它抓得到模型坏了，抓不到「能不能从本地文件找到证据」。 |
| **B. 没有文本塔就把 image→image 最近邻写成 COCO 完成** | 那是另一个指标。文本塔现在有 fp32，这条退路用不上；万一以后文本塔不能用，必须标未完成，而不是换指标。 |
| **C. W3 就拉官方 NQ 的 Wikipedia 段落** | 体积和网络都超出本周。 |

---

## 决策 9：模型登记

八个字段加来源、许可证、sha256、字节数、张量签名，写在 `models/README.md`，不写进 Dart 常量里的本机路径。缺一不可：模型名和 revision、分词器文件、最大长度、pooling、是否归一化、有没有 query/document 前缀、转换工具和版本、转换前后的余弦。

`datasets/README.md` 里 RVL-CDIP 的张数已从 32 改成 16，和 `datasets/rvlcdip/sample/` 里的 16 个文件一致。评测报告只引用实测行数。

### Alternatives（登记）

| 方案 | 为什么没选 |
|---|---|
| **A. 只在代码注释里写「MiniLM」** | 两周后无法对上 revision 和分词器。 |
| **B. 把权重提交进 Git** | 根 `.gitignore` 已经排除 `*.onnx` 和 `models/raw/`。MobileCLIP 的许可也不允许这样公开再分发。 |

---

## Consequences（后果）

**正面**

1. 中文和英文都能出文本向量，一张 COCO 图能出图像向量。两条链路在 Day 1 都已跑通。
2. 空间写在类型上，并且混用会抛异常。W4 不能再把两个模型当成一个索引。
3. int8 图像塔这种静默坏掉的转换被门槛挡住了，没有进入运行时。
4. 单测仍然不加载模型。覆盖率的打法和 W2 一样。

**代价**

1. W3 推理依赖本机 `engine/.venv` 里的 ONNX Runtime。没有这个环境，`embed_spike.py` 跑不起来。Dart 包本身不带权重。
2. 没有进程内 TFLite。端侧 DLL 和安装包体积留到 W8。
3. MobileCLIP 权重不能进公开包。公开演示若要图像向量，得换可再分发的权重，或者让使用者自己下载。
4. 分词器是 Unigram，不是 WordPiece。下一阶段的 Dart 分词器比计划里的文件名更难，必须对照 `tokenizers` 的 id。
5. 切块编号不稳定。W4 的增量更新不能靠 `chunkId`。

## Follow-up（后续动作）

- [x] 阶段 A：ADR、模型登记、探针日志、`packages/core_embedding` 的公开类型。
- [x] 阶段 B：按 Unigram `tokenizer.json` 做纯 Dart 分词器，和 Python `tokenizers` 逐 id 一致。
- [x] 阶段 C：`TextChunker`、图像预处理、`EmbeddingEngine` 的双空间检查、批量服务。
- [x] 阶段 D：MVP 探针、证据集、NQ / COCO 评测、覆盖率 ≥85%。证据在 `reports/week3/`。覆盖率 1250/1458 = 85.73%。证据集只冻结，没有用来改切块或换模型。
- [ ] W4：两个索引加融合；跨页答案用邻域扩展；不得把 `chunkId` 当主键。
- [ ] W8：公开包不包含 MobileCLIP 权重；若仍要进程内推理，再单开运行时 ADR。
