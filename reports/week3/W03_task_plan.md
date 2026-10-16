# Week 3 执行方案：多模态 Embedding 引擎

| 项目 | 内容 |
|---|---|
| 周期 | W3 ｜ 10/04（周日）– 10/10（周六） |
| 交付日 | **10/10（周六）** |
| 预算工时 | **26h**（原个人计划 24h ＋ 2h 自建证据集，见 §5 说明） |
| 主题 | 多模态 Embedding 引擎 + MVP |
| 上游依据 | `docs/tasks/Software Engineering Project … Retrieval System.pdf`（Week 3 章节） |
| 计划基线 | `reports/week1/个人计划.md`（W3 行）、`docs/tdd/technical-design-document.md`（Q1/Q3/Q7 本周结案） |
| 上游交付 | `packages/core_parsing`（W2 完成，行覆盖率 90.99%） |
| 下游衔接 | W4 向量库 + 混合检索（本包输出向量，不负责存储与排序） |
| 落地目录 | `reports/week3/`（计划、评测、报告、证据）＋ `packages/core_embedding/`（代码） |

> **编号约定**：`Day 1`–`Day 4` 是工作日；`A1`–`A6`、`B1`–`B5`、`C1`–`C6`、`D1`–`D6` 是任务编号；`G1`–`G8` 是交付物编号（§3）。三者含义不同，不要混读。

> **本文状态**：任务本体已全部执行完毕，阶段出口的实际数字写在各阶段末尾。本文是 W3 的任务定义与验收口径的权威副本；执行过程的逐条留证在 `reports/week3/W03_report.md` 与 `reports/week3/logs/`。

### 本文 v3 修订点（相对 v2）

| # | 修订 | 影响章节 |
|---|---|---|
| 1 | 去掉排期处置方案的对比小结。W3 按「23 个任务全做」执行完毕，保留三个备选方案的表只会让读者以为还要选一次 | 原 §12（已删除） |
| 2 | 分词器方案按 ADR 0003 更正为 **Unigram**，不再是 WordPiece。`bert-base-uncased` 换成多语言检索模型后，词表就是 XLM-R 一系的 SentencePiece，`vocab.txt` / `##` 续接那一套不成立 | §0、§4 决策 1、B1 |
| 3 | 覆盖率数字换成实测值：阶段 B **68.71%**（494/719），阶段 C/D **85.73%**（1250/1458） | §0、§5 阶段出口、§6 |
| 4 | 模型许可证从「待核对项」改为已结案结论（apple-amlr，不得再分发） | §4 决策 5 |
| 5 | 交付物清单改为仓库里实际存在的文件，去掉未产出的 `screenshots/*.png`，补上 CLIP 文本塔、图像解码器、Pillow 对照件与后加的评测/探针脚本 | §11 |
| 6 | 附录 A 的接口骨架与冻结后的实际签名对齐（`documentId`、`abstract interface class`） | 附录 A |

### 本文 v2 修订点（相对 v1）

| # | 修订 | 影响章节 |
|---|---|---|
| 1 | 切块：明确「页=定位、段落=切分、窗口兜底」，加防御性级联；记录 DOCX 段落歧义 | §4 决策 3、A5 |
| 2 | 明确偏移量单位为 **UTF-16 code unit**，高亮/切片/引用三处共用 | §4 决策 3、A6、附录 A |
| 3 | chunkId 补 `textUnit`，写明「可复现」的前置条件 | §4 决策 3 |
| 4 | 跨页答案改判为 **W4 邻域扩展**问题，W3 只保证 `pageNumber`+偏移可支撑 | §4 决策 3、附录 B |
| 5 | 文本模型改为**多语言、面向检索训练**的句向量模型（`bert-base-uncased` 是纯英文词表，中文语料会失效） | §4 决策 1、A1、A2 |
| 6 | 模型登记扩到 8 个字段；新增**转换等价性**为第二个硬门槛 | §4 决策 5、A2、A3 |
| 7 | 评测改为**四层分层**，不混在一个完成标准里；NQ 池子从 100 更正为 **600**（300 题） | §4 决策 4、§8、D2–D4 |
| 8 | 新增**自建证据集**（W3 建、W4 起用），含 dev/holdout 防泄漏 | §8.3、D2 |
| 9 | 明确**生成闭环为未规划**，与检索闭环分列 | §0.1、§3、§10 |
| 10 | 新增 `TfliteBindings` 接口，防止 FFI 适配器拖低覆盖率；补许可证待核对项与数据登记纠错 | §4 决策 6、A4、B3、§9、A2 |

---

## 0. 一页速览

**一句话目标**：把「文本」和「图像」两条链路各自跑出向量，收敛到一个统一入口，用**分层的、口径写清楚的**评测给出可复现的数字，并把 embedding 模块的单测覆盖率做到 ≥85%。

**四天节奏**：

| 日 | 时长 | 主产出 | 出口判据 |
|---|---|---|---|
| Day 1 | 8h | 模型与运行时选型冻结 + **可行性探针**（先证明模型真能出向量）+ 转换等价性 | 一句文本、一张图各出一次向量；转换前后余弦 ≥ 0.999 |
| Day 2 | 6h | 纯 Dart **Unigram** 分词器（按所选模型的词表方案）+ `TextEmbedder` | 默认套件全绿，覆盖率 ≥45% |
| Day 3 | 6h | 图像预处理 + `ImageEmbedder` + 统一 `EmbeddingEngine` + 批量服务 + 切块器 | 五格式批次可批量出向量，可取消、有进度 |
| Day 4 | 6h | MVP 探针 + 自建证据集 + NQ 评测 + COCO 健全性 + 覆盖率 ≥85% + 报告 | 三份交付物齐全，覆盖率证据落盘 |

**红线**：W3 不做向量库、不做相似度检索排序、不做 UI、不做 OCR、**不做生成**。本包只回答一个问题——**给定文本或图像，向量是什么**。

### 0.1 范围声明：检索闭环 vs 生成闭环

验收标准必须分成两列，否则会把「检索」的完成度和「RAG 生成」的完成度混成一个数字。

| 列 | 内容 | 状态 | 依据 |
|---|---|---|---|
| **检索闭环** | 导入真实文档 → 命中正确证据 → 展示出处与偏移 → 可打开原文件 → 干净环境可复现 | **承诺**（W3 交付引擎，W4 打通闭环） | PRD §6 MVP：「断网输入一句不含文件名的话，Top 结果里能出现目标文件」「结果可以打开原文件」 |
| **生成闭环** | 引用支撑的回答、资料不足时不硬答、答案正确性人工检查 | **未规划** | PRD §2 功能性需求表与官方 Full Deliverables List **都没有生成**；引入需本地 LLM，撞 C1 完全离线约束 + 风险 R7 体积 + W8 打包，属 W7+ 的独立决策 |

**结论**：本周只承诺检索闭环。生成闭环若要做，是一次**范围扩张**，需单独评估，不能混进 W3 的完成标准。

---

## 1. PDF 原文对 Week 3 的要求（照抄）

> **Week 3: Multimodal Embedding Engine Development**
> Core Focus: Integrate models to build a local, offline embedding engine for text and image content.

**Key Tasks**

1. Optimize and integrate BERT-base model for text embedding, converted for TensorFlow Lite offline CPU inference
2. Integrate MobileCLIP model for lightweight image embedding, optimized for end-side execution
3. Build a unified embedding interface for standardized text/image input processing
4. Validate embedding accuracy using the NQ and COCO validation datasets
5. Implement batch embedding processing for large local file libraries

**Weekly Deliverables**

1. Functional multimodal embedding engine
2. Model accuracy validation report
3. Unit test suite for the embedding module (**≥85% test coverage**)

**个人计划补充的 W3 目标**（`reports/week1/个人计划.md`）

- BERT → TFLite 文本向量可跑通；MobileCLIP 图像向量可跑通
- 统一 Embedding 接口（文本/图像同一调用方式）
- 用 NQ / COCO 小验证集
- **最小 Demo**：选 1 个文件夹 → 解析 → 向量化 → 打出 embedding（尚可不接完整检索 UI）

**与原文的两处刻意偏差**（决策 1 与决策 4 有完整论证，`模型精度验证报告.md` §7 记为已知限制）：

| 原文 | 实际 | 原因 |
|---|---|---|
| BERT-base → TFLite | 多语言检索训练句向量模型 → ONNX fp32 | 原文的词表是纯英文，中英混合语料的中文侧会失效；且普通预训练 BERT 没有做过句向量训练 |
| TensorFlow Lite 端侧推理 | 外部 ONNX Runtime 进程 | 通过 0.999 门槛的产物是 ONNX fp32，`libtensorflowlite_c` 加载不了；本机没有 torch / ai-edge-torch，无法在「不新装训练框架」的前提下重新导出 TFLite |

---

## 2. 当前基线

### 2.1 W2 已交付、W3 直接复用

| 资产 | 证据 | 对 W3 的价值 |
|---|---|---|
| `packages/core_parsing`（TXT/PDF/DOCX/JPG/PNG + 批量入库） | `reports/week2/W02_report.md`：34 个用例全通过 | 向量化的输入已就绪，`IngestionReport.indexable` 就是要喂的东西 |
| **行覆盖率 90.99%**（949/1043，`--report-on=lib`） | `reports/week2/覆盖率报告.md` | 证明「纯逻辑 + 注入外部依赖 + 打桩」这套打法在本项目可稳定过 85% 门槛；`test/io_process_runner_test.dart` 就是适配器被假实现覆盖的样板 |
| `ProcessRunner` / `Executor` / `CancellationToken` 注入缝 | `packages/core_parsing/lib/src/spi/` | **W3 照抄了这个模式**：运行时适配器藏在接口后面，否则覆盖率无从谈起 |
| 探针与证据规范 | `bin/parse_probe.dart`、`bin/ingest_probe.dart`、`bin/probe_common.dart` | W3 的 `embed_probe.dart` 沿用同一套输出格式 |
| `integration` 测试标签 | `packages/core_parsing/dart_test.yaml` | 真模型、读 gitignore 数据集的用例一律带此标签，不污染默认套件与覆盖率 |
| Python 评测环境 `engine/.venv`（3.13.2） | `engine/requirements.txt` | 离线评测与模型转换的工作台 |
| 单文件耗时基线 | `reports/week2/logs/day3_jvm_single_file.txt`、`reports/week3/logs/pdf_stage_timing.txt` | 批量 throughput 的输入侧已知：PDF 中位 **5101 ms/文件，其中 `process_wait` 5050 ms（99%）** |

### 2.2 `engine/.venv` 已装的包（决定技术路线的事实）

| 已装 | 未装 |
|---|---|
| `tensorflow 2.21.0`、`onnxruntime 1.30.0`、`tokenizers 0.23.2`、`numpy 2.5.3`、`pillow 12.3.0`、`huggingface_hub 1.32.0`、`chromadb 1.5.9` | **`torch`、`transformers`、`ai-edge-torch`、`sentence-transformers` 都没有** |

> 含义：**PyTorch 路线的权重（BERT `.bin`、MobileCLIP `.pt`）在本机无法直接加载**。现成可用的推理引擎是 TensorFlow 与 ONNX Runtime。产出的权重文件不要用 `.bin`/`.pt`（两者都在根 `.gitignore` 里）。

### 2.3 开工时的缺口（W3 必须补上，现已全部补齐）

| W3 要求 | 开工时现状 | 做了什么 | 落点 |
|---|---|---|---|
| 文本向量模型 | `models/raw/`、`models/tflite/` **均为空**；`models/README.md` 是 **0 字节** | 获取 + 校验 + 用 8 个字段登记 | `models/raw/text/…`、`models/README.md` |
| 图像向量模型 | 同上，无任何 CLIP 权重 | 获取图像塔**与文本塔** + 登记（含许可证结论） | `models/raw/image/mobileclip-s0/…` |
| 端侧推理运行时 | `native/tflite/windows/` **为空**，没有 `libtensorflowlite_c-win.dll` | 走外部 ONNX Runtime 进程兜底，并在 ADR 写明打包留给 W8 | ADR 0003 决策 4、`native/tflite/README.md` |
| 统一 embedding 接口 | `packages/core_embedding/` **不存在** | 建包 + 冻结 API | `packages/core_embedding/` |
| 切块器 | 无 | `CascadeTextChunker`（Q3 落地物） | `lib/src/text/text_chunker.dart` |
| 评测集与口径 | NQ 实为 **300 题**（`nq_open_val50.jsonl` 50 ＋ `nq_open_val250_part2.jsonl` 250），仅 `{question, answers}`；COCO 50 图 + 50 行 `{file_name, caption}` | 口径分层重设计（§8）＋ **新建自建证据集** | `§8`、`evidence_set.jsonl` |
| 批量 embedding | 无 | `DefaultEmbeddingService`，接口对齐 `IngestionService` | `lib/src/engine/embedding_service.dart` |
| 覆盖率证据 | 只有 W2 的 | 三次落盘的覆盖率证据 | `reports/week3/coverage/`、`覆盖率报告.md` |
| 登记纪律 | `models/README.md` 空；`datasets/README.md` 写 rvlcdip **32** 张，实际 **16** 张 | 一并纠正 | `datasets/README.md`（已改 16） |

### 2.4 TDD 里本周要结案的未决问题

| 编号 | 问题 | 现倾向 | W3 动作 | 结果 |
|---|---|---|---|---|
| Q1 | PDFium / ORT 能否拿到可信预编译产物 | 优先预编译，退化保留 Tika | **结案并写 ADR**：`process_wait` 中位 5050 ms 已满足 ADR 0002 触发条件 T2，但收益是吞吐而非正确性 → W3 只结案、不落地 | 已结案 |
| Q3 | 长文档切块策略 | 按页优先，段内再切 | **本周落地**：`CascadeTextChunker`，方案见决策 3 | 已结案 |
| Q7 | PDF 页码策略会不会随 PDFium 改变 | 以 Tika `-x` 的 page div 为准 | 随 Q1 一并结案 | 已结案 |

---

## 3. 完成定义（DoD）

| 编号 | 交付物（对应 PDF Deliverables） | 落地文件 | 验收方式 | 实测 |
|---|---|---|---|---|
| **G1** | 可用的多模态 embedding 引擎 | `packages/core_embedding/` | `dart analyze` 0 issue；默认套件全绿；`embed_probe` 对真实目录出向量 | No issues；93/93；97 条向量 0 失败 |
| **G2** | 模型精度验证报告 | `reports/week3/模型精度验证报告.md` | 含 §8 的**四层分层指标**、模型/版本/维度/耗时、原始日志索引、范围限制；转换等价性与 NQ 代理指标必须标明口径 | 106 行，四层单列，§8.5 字段齐全 |
| **G3** | embedding 单测套件 ≥85% | `reports/week3/coverage/lcov.info` + `覆盖率报告.md` | lcov 统计 ≥85.00% | **1250/1458 = 85.73%** |
| **G4** | 统一 embedding 接口 | `docs/api/embedding-module-api.md` | 每个 public 类型/方法有签名、参数、异常、示例；含 `space` 与 `textUnit` 语义说明 | 1082 行，公开符号清单与 `core_embedding.dart` 导出逐项吻合 |
| **G5** | MVP（个人计划要求） | `packages/core_embedding/bin/embed_probe.dart` | 选 1 个目录 → 解析 → 向量化 → 打印向量摘要与耗时 | `--path datasets\samples` → 97 条 |
| **G6** | 自建证据集 | `reports/week3/evidence_set.jsonl` + `reports/week3/证据集说明.md` | ≥20 条，dev/holdout 分离，每条含 §8.3 的字段；**W3 只建集与冻结，不据此调参** | 25 条（15 dev / 10 holdout），3 条跨页，已冻结 |
| **G7** | 本周结案的决策 | `docs/architecture/adr/0003-embedding-model-and-runtime.md` + TDD 的 Q1/Q3/Q7 标记为已结案 | 每项含 Decision / Consequences / Alternatives | 9 个决策 + Consequences + Follow-up，每条有 Alternatives |
| **G8** | W3 验收留证 | `reports/week3/W03_report.md` + `logs/` + `coverage/` | 沿用 W2 报告体例：用例 ID — 命令 — 期望 — 实际 — 判定 — 证据 | EMB-01～EMB-09 九条用例齐备 |

---

## 4. 开工前必须冻结的 6 个决策（Day 1 上午完成）

> 这 6 条不冻结就动手，等于把风险 R1 直接留到交付日。每条都要在 `ADR 0003` 里落字。

### 决策 1（最高优先级）：模型与运行时路线

事实约束：本机**没有 torch**，模型权重也**一个都没有**；`models/` 全空；`native/tflite/windows/` 全空。

**文本模型：不要照字面选 `bert-base-uncased`。** 两条硬理由：

1. **词表是纯英文**。本项目语料是中英混合（`datasets/samples` 中英 PDF、中文 DOCX，项目文档本身也全是中文）——照字面选，中文那一半直接失效。
2. **普通预训练 BERT 不是检索模型**。它的 `[CLS]`/mean pooling 向量未经句向量/检索训练，直接当检索向量用效果差；这正是 sentence-transformers 存在的理由。官方原文的 "BERT-base" 更可能是指「BERT 类 Transformer 文本编码器」的泛称。

因此选型是**面向句向量/语义检索训练、且语言覆盖匹配语料**的模型，并用 ADR 记录与原文表述的偏差。

| 子问题 | 选项 | 选择 | 实际结果 |
|---|---|---|---|
| 文本模型 | (a) `bert-base-uncased` → TFLite INT8（贴合原文，~110 MB，**纯英文、非检索训练**）<br>(b) 多语言检索训练句向量模型 → TFLite/ONNX（风险计划 R1 的既定退路） | **(b) 作为主模型**；若时间允许再跑 (a) 作为对照 | 选定 `paraphrase-multilingual-MiniLM-L12-v2`（12 层 / 384 维 / mean pooling / 128 token / Apache-2.0）。**未跑 (a)**：决策 1 的两条理由已足够，且中文探针是硬门槛 |
| 图像模型 | (a) MobileCLIP-S0/S1 官方权重（PyTorch `.pt`，本机无 torch）<br>(b) MobileCLIP ONNX 导出件（`onnxruntime` 已装）<br>(c) 其他 CLIP 小模型 | **(b)**：与现有 venv 唯一无缺口的重合点；**时间盒半天**，不投第二个模型 | 选定 `Xenova/mobileclip_s0` fp32。**图像塔与文本塔都留**——文本塔让 D4 能走 image→caption 主路径 |
| 端侧运行时 | (a) `libtensorflowlite_c-win.dll` + `dart:ffi`<br>(b) `tflite_flutter` 插件（Flutter 依赖，纯 `dart test` 跑不了，覆盖率吃亏）<br>(c) **W2 同款兜底**：推理放 `engine/`，用 `ProcessRunner` 起外部进程 | **默认 (a)**；拿不到 DLL 就用 (c) 兜底 | **实际走 (c)**。(a) 不成立：通过门槛的权重是 ONNX，DLL 加载不了。(b) 与 W2 的打法相反 |
| 兜底原则 | — | 运行时必须藏在 `EmbeddingRuntime` 接口后面；单测一律注入假实现，**绝不为了覆盖率去加载真模型** | 已落实；默认套件不加载模型 |

**分词器方案（v3 更正）**：选定模型的 `tokenizer.json` 里 `model.type` 是 **Unigram**，词表 250002，归一化用 Precompiled——这是 XLM-R 一系的 SentencePiece，**不是 BERT WordPiece**。因此：

- 纯 Dart 分词器按 `tokenizer.json` 逐 id 对齐，**不按 `vocab.txt`**，也不做 `##` 续接（本模型里 `##` 是普通正文，编码成一片 `▁##`）。
- `lib/src/text/wordpiece_tokenizer.dart` 只保留计划路径上的再导出，不是第二种算法，也不从公开入口导出。
- 同目录 `config.json` 的 `vocab_size` 是 250037，与词表 250002 不是同一个数，不要捏在一起。

### 决策 2：向量空间是「两个」而不是「一个」（后果最深远）

文本向量（384 维）与 MobileCLIP 向量（512 维）**不在同一空间，不能直接比大小**。

- 后果：W4 想要的「一句话既能搜到文档片段，也能搜到相关图片」，在 W3 的产物上只能是**两个索引 + 分数归一化后合并**，或再用 MobileCLIP 的 **text tower** 单独建一个图像侧文本索引。
- 因此统一接口必须**显式暴露空间**，不能只有一个 `embed()`：
  - `EmbeddingSpace.documentText`（文本空间，文档正文/查询），384 维，MiniLM
  - `EmbeddingSpace.clipShared`（MobileCLIP 图文共享空间，图像检索与 NL 查图），512 维
- `EmbeddingEngine` 对混用空间**直接抛 `EmbeddingSpaceMismatchException`**，用代码兜住，而不是靠文档提醒。
- 图像输入只能是 `clipShared`；文本输入可以是 `documentText` 或 `clipShared`，后者走 MobileCLIP 文本塔。

### 决策 3：切块策略（Q3 结案）

**原则：页面用于定位，段落用于切分，长度上限才切窗口。**

```text
保留页码与原文偏移
      ↓
沿段落边界切（\n\n）
      ↓
段落不存在/过长 → 沿单换行、再沿句末标点
      ↓
仍超上限 → 硬窗口（按 token 预算）
```

**（a）段落边界在三种格式里可用性不同——这是实测结论**

| 格式 | 段落边界 | 证据 |
|---|---|---|
| TXT | **真实可用**，`\n\n` 被保留 | `txt_parser.dart:113` 只做 `\r\n`/`\r` → `\n` 归一 |
| DOCX | **段落与段内换行不可区分** | `docx_parser.dart:115` `paragraphs.join('\n')`；`:139` `w:br` 也写成 `'\n'` |
| PDF | **无保证** | Tika `-x` 抽出的文本没有段落契约 |

所以切块器必须走**防御性级联**，不能假设段落存在：

```
\n\n  →  \n  →  句末标点（。！？；. ! ? ;）  →  硬窗口
```

DOCX 的歧义两种处置：**(1) 接受按单 `\n` 切**（最坏把一段拆成两块，无害）；**(2) 改解析层输出段落结构**——那是改 W2 已冻结的 `ParsedDocument` schema，要单开 ADR，**W3 不做**。实际选 (1)。

**（b）偏移量的单位必须是 UTF-16 code unit**

`document_page.dart:21` 是 `int get charCount => text.length;`。Dart 的 `String.length` 与 `String.substring` 都以 **UTF-16 code unit** 计。

- 因此 `startOffset`/`endOffset` 明确为 **UTF-16 code unit 偏移**，且**高亮、切片、引用三处共用同一单位**。
- `startOffset` 含首、`endOffset` 不含尾，所以 `pageText.substring(startOffset, endOffset)` 就是该块在页文本里的跨度。
- BMP 内（含绝大多数汉字）code unit == 字符；emoji / 罕用字是代理对，1 字符占 2 个 code unit。读屏高亮若按字素簇算就会与偏移错位。

**（c）字符长度用于切块，token 长度用于校验，且是硬门**

- 中文约 **1 字 ≈ 1 token**；英文约 **4 字符 ≈ 1 token**。`maxLength=128` 时中文安全上限约 120 字符、英文约 500 字符——**`chunkChars` 不可能有一个跨语言通用的默认值**。
- `chunkChars` 初值取 **120**，由「模型 + 语料」标定（`logs/chunk_chars_calibration.txt`：`datasets/samples` 上 4.03 与 3.57 字符/内容 token，120 码位窗口**无一超预算**），**不宣称普遍最优**。
- **tokenizer 校验是硬门**：超长一律重切或显式抛 `ChunkBudgetException`，**绝不静默截断**。

**（d）chunkId 与可复现条件**

字段：`documentId`、`contentHash`（或 documentVersion）、`chunkIndex`、`pageNumber`（可空）、`startOffset`/`endOffset`、`textUnit`、`chunkerVersion`。

可复现的边界条件写进 ADR：**同一 `contentHash` ＋ 同一 `chunkerVersion` ＋ 同一配置**才可复现；文档变了或参数变了，编号与内容都可能变——**W4 不得把它当稳定主键**。

**（e）跨页合并不是 W3 的问题**

`sample.pdf` 实测 2 页 / 4358 字符 ≈ **2179 字符/页**；而 `maxLength=128` 下中文一个 chunk 只有 100–200 字符 → **一页要切 10–20 块**。「答案跨页」在实践中就是「答案横跨两个 chunk」，这是 **W4 检索层的邻域扩展问题**（取回 chunk 后扩展到整页或相邻 chunk）。

W3 的正确动作：**保证 `pageNumber` 与偏移被存下来，让 W4 有东西可扩展**；把「不做跨页合并」记为已知限制，并按 §8.3 在证据集里放几道跨页题——那几道的通过标准定在 **W4**。

> 证据集实测补充：`sample.pdf` 抽出的两页是同一篇说明的**重复排版**，不是一句从页末续到下一页。所以 `ev-08`/`ev-16`/`ev-17` 记录的是「同一证据出现在两页」，W4 的邻域扩展在这批题上没有跨页断句可测——这条已写进 `证据集说明.md` §4。

### 决策 4：评测口径（四层分层，详见 §8）

| 层 | 指标 | 依赖 | W3 是否出数 | 实际 |
|---|---|---|---|---|
| 转换等价性 | 同 3–5 句，转换前后余弦 ≥ 0.999 | 模型 | ✅ | 三份 fp32→ORT 均 1.000000；三份 int8 未过门槛，不加载 |
| embedding 级 | NQ-open **300 题** Q→gold answer 的 recall@1/@5、MRR（**标注为代理**） | 模型 | ✅ | recall@1=0.110000、recall@5=0.210000、MRR=0.166034 |
| 检索级（主） | 自建证据集 **Hit@5、MRR@10**；多证据时 Recall@5/@10 | **W4 流水线** | ❌ 只建集与冻结 | 集子已冻结，`scored=0` |
| 生成级 | 答案正确性、引用支撑度、无答案行为 | 生成器 | ❌ **未规划**（§0.1） | 未做 |

**关键纪律**：四层**单列，不混在同一个完成标准里**。替代实验可以存在，但必须标明它测的不是什么。

### 决策 5：模型与产物的登记（8 个字段，缺一不可）

`models/raw/`（原始权重，gitignore）、`models/tflite/`（运行时产物，gitignore）、`models/README.md`（**必须写满**）：

| # | 字段 | 为什么必须 |
|---|---|---|
| 1 | **精确模型名 + revision（commit/版本号）** | 只写「BERT」等于没写；两周后无法复现 |
| 2 | **tokenizer 文件与版本** | 分词与模型不匹配会静默降质 |
| 3 | **最大输入长度** | 直接决定 `chunkChars` 上限 |
| 4 | **pooling 方式**（mean / CLS / none） | 写错不报错，只是变差 → 必须有单测固定 |
| 5 | **是否归一化向量** | 必须与向量库度量（cosine vs inner product）一致 |
| 6 | **query / document 是否需要不同前缀** | E5/BGE 系需要；漏了 recall 静默下降。本模型**不需要**，前缀字段必须是 null，不能用空串代替 |
| 7 | **转换工具与版本** | TFLite/ONNX 转换链可复现 |
| 8 | **转换前后输出校验结果** | 见 A3 的等价性门槛 |

外加：来源 URL、许可证、sha256、字节数、输入输出张量签名。

**许可证（风险 R8）——已结案，不是待核对项。** 三套许可分开，不能用代码许可覆盖权重：

| 对象 | 许可 | 来源 |
|---|---|---|
| `ml-mobileclip` 代码 | MIT | 仓库 README |
| **模型权重** | **Apple Machine Learning Research Model（apple-amlr）** | 同一 README；Apple 维护者 2025-07-21 在 `apple/MobileCLIP-S0` 讨论中确认 |
| 训练数据 | CC-BY-NC-ND | 同一 README |

apple-amlr 把使用限制在非商业的科研与学术开发，再分发必须带协议与署名，且不能用 Apple 商标背书衍生模型。Xenova 的 ONNX 是这份权重的导出件，跟着权重走，不因换文件格式变成 Apache-2.0。

**结论：W8 不能把 MobileCLIP 权重放进公开可下载的安装包。** 交付形态改为本机研究使用：权重留在已 gitignore 的 `models/raw/`，克隆仓库的人按研究许可自行下载。文本模型是 Apache-2.0，没有这一条限制。

### 决策 6：本包与 Flutter 的解耦程度

四层职责切分，**「纯 Dart 包」不等于「一切都用 Dart 做」，也不等于「没有原生依赖」**：

| 层 | 归属 | 约束 |
|---|---|---|
| 核心业务与接口 | **纯 Dart** | `dart test` 可跑、可算覆盖率；切块、输入构造、编排、错误处理都在这里 |
| 运行时适配 | FFI **或** 外部 engine，**选一个** | 藏在 `EmbeddingRuntime` 接口后；FFI 的绑定层再抽一层 `TfliteBindings`（见 A4） |
| 模型准备与转换 | 独立工具（`engine/`，Python） | 允许用独立工具，不要求 Dart 做 |
| Flutter | `apps/desktop`，UI 与应用装配 | W3 只加 path 依赖，不改 UI |

**测试分层**：`dart test` 测纯逻辑；原生集成测试（`integration` 标签）在有模型与运行库的环境跑真实推理；Flutter 测试测界面装配。**不要让每个单测都加载模型**，**也不要用 mock 通过代替真实推理验证**——后者靠 `integration` 标签与 A3 的转换等价性用例兜住。

---

## 5. 任务拆分（WBS）

工时单位：小时。依赖列写任务编号。

> **预算说明**：26h ＝ 原个人计划 24h ＋ 2h（D2 自建证据集）。若必须守住 24h，把 D2 拆成「W3 建 15 条最小集（1h）＋ W4 补到 30 条（1h）」。

### 阶段 A — 决策与可行性探针（Day 1，8h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **A1** | 冻结模型与运行时路线（决策 1/2/6） | `docs/architecture/adr/0003-embedding-model-and-runtime.md` | 含文本模型（含为什么不用 `bert-base-uncased`）、图像模型、运行时、双空间设计、兜底方案各一节，每节有 Alternatives | — | 1 |
| **A2** | 拉取/导出模型产物并按 8 字段登记 | `models/raw/` 落盘；`models/README.md` 写满决策 5 的 8 个字段 + 来源/许可证/sha256/字节数/张量签名；顺带纠正 `datasets/README.md` 的 rvlcdip 数量（32→16） | 两个模型各有一份可加载产物；`models/README.md` 不再是 0 字节；MobileCLIP 许可证给出**明确结论** | A1 | 2 |
| **A3** | **可行性探针 + 转换等价性（两个硬门槛）** | `engine/embed_spike.py`、`engine/convert_check.py` + `reports/week3/logs/{embed_spike,convert_check}.txt` | ① 对一句中文+一句英文、一张 COCO 图各跑出一次向量（维度、L2 范数、耗时）；② 同 3–5 句转换前后余弦 **≥ 0.999**。任一不过即触发决策 1 的降级分支 | A2 | 2.5 |
| **A4** | 端侧运行时接入 + 绑定层抽取 | `lib/src/spi/tflite_bindings.dart`；或在 ADR 写明走外部进程兜底 | `dlopen` 成功且**绑定层是接口、适配器分支可在默认套件里被假实现覆盖**；或兜底方案已在探针里验证 | A1 | 0.5 |
| **A5** | Q1 / Q7 结案 + Q3 冻结（含跨页移交说明） | TDD §4 的 Q1/Q3/Q7 更新为已结案；决策 3 写入 ADR | 三条都有结论与理由；Q1 引用 `pdf_stage_timing.txt` 数字；Q3 明确「跨页合并由 W4 邻域扩展承接」 | — | 1 |
| **A6** | 建包与冻结 public API | `packages/core_embedding/{pubspec.yaml,analysis_options.yaml,lib/core_embedding.dart}`、`lib/src/model/*`、`lib/src/spi/*` | `dart pub get --offline` 成功；`dart analyze` 0 issue；`TextChunk` 含 `textUnit` 与偏移字段 | A1 | 1 |

**阶段出口**：ADR 0003 定稿；探针日志证明文本与图像两条链路**都能出向量且转换未损坏模型**。这一步不过，后面全是白做。

> **实测**：`embed_spike.txt` → 中文 384 维 / 25.44 ms、英文 384 维 / 26.69 ms、COCO 图 512 维 / 35.26 ms，三份 `finite=1`，中文 `unk_tokens=0`。`convert_check.txt` → 三份 fp32→`ORT_ENABLE_ALL` 最低余弦 **1.000000**（通过）；文本 int8 **0.982951**、图像塔 int8 **0.045810**、CLIP 文本塔 int8 **0.768964**（全不通过，不加载）。

### 阶段 B — 文本向量（Day 2，6h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **B1** | 纯 Dart 分词器（按所选模型的词表方案 = **Unigram**） | `lib/src/text/unigram_tokenizer.dart`、`unigram_model.dart`、`precompiled_normalizer.dart` + `tokenizer.json` 路径约定 | 对已知句子输出与 Python `tokenizers` 参考实现**逐 id 一致**（含特殊标记、超长截断、空白与归一化）；夹具覆盖全部边界 | A6 | 2 |
| **B2** | 输入张量构造 + token 预算校验 | `lib/src/text/text_input_builder.dart` | 生成模型要求的输入张量，长度=模型 `maxLength`；**超长返回可重切信号，绝不静默截断** | B1 | 1 |
| **B3** | `TextEmbedder` + `EmbeddingRuntime` 适配器 | `lib/src/text/text_embedder.dart`、`lib/src/spi/embedding_runtime.dart`、`lib/src/spi/onnx_process_runtime.dart` | 假 runtime 下全分支可测（成功/维度不符/张量缺失/超时/运行时不具备）；输出 L2 归一化；**pooling 与归一化各有一条固定用例** | B1,A4 | 1.5 |
| **B4** | 文本向量 API 文档草案 | `docs/api/embedding-module-api.md`（文本部分） | 每个 public 符号有签名、参数、异常、示例；含 `textUnit` 与 `space` 语义 | B3 | 1 |
| **B5** | 文本链路单测补齐 | `test/text/*_test.dart` | 默认套件全绿；覆盖率 ≥45% | B1–B3 | 0.5 |

**阶段出口**：`dart test --exclude-tags integration` 全绿；`integration` 用例能对 NQ 的一句话出向量。

> **实测**：`text_tokenizer_ids.txt` → 44 句与 `tokenizers 0.23.2` 的 ids 与 tokens **全等**（含空串、空白、`##`、`<mask>`、代理对、全角、连字）。`text_tokenizer_truncation.txt` → `truncateTo:128` 三条对照全等并保住 `</s>`。`text_nq_vector.txt` → NQ 首句 384 维、`l2=1.000000`、`gate=pass`。覆盖率 **68.71%**（494/719，`text_coverage_b.txt`），高于 45% 门槛。

### 阶段 C — 切块、图像与统一接口（Day 3，6h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **C1** | `CascadeTextChunker`（决策 3 落地物） | `lib/src/text/text_chunker.dart` | 防御性级联 `\n\n→\n→句末→硬窗口` 全部可测；chunk 带 `chunkId`/`pageNumber`/`startOffset`/`endOffset`/`textUnit`/`chunkerVersion`；**给 DOCX 单换行歧义与 PDF 无段落两种输入各一条用例** | A6 | 1 |
| **C2** | 图像预处理（纯 Dart） | `lib/src/image/image_preprocess.dart` | resize（短边）+ center-crop + 归一化；尺寸/通道/异常输入有单测 | A6 | 1 |
| **C3** | `ImageEmbedder` | `lib/src/image/image_embedder.dart`、`image_decoder.dart` | COCO 一张图出一个向量；mean/std 与尺寸与模型卡一致并记入 ADR | C2,A3 | 1.5 |
| **C4** | 统一 `EmbeddingEngine`（决策 2） | `lib/src/engine/embedding_engine.dart`、`lib/src/text/clip_text_embedder.dart`、`clip_bpe_tokenizer.dart` | `embed(EmbeddingInput)` 同时接受文本与图像；返回值带 `space`/`dim`/`modelId`/`normalized`；**混用空间直接抛异常** | B3,C3 | 1.5 |
| **C5** | 批量 embedding 服务 | `lib/src/engine/embedding_service.dart` | 消费 `IngestionReport.indexable`；`onProgress` + `CancellationToken`；单条失败隔离并计入 `EmbeddingReport`；接口形状对齐 `IngestionService` | C4 | 0.5 |
| **C6** | 切块/图像/统一接口单测 | `test/text/text_chunker_test.dart`、`test/image/*_test.dart`、`test/engine/*_test.dart` | 默认套件全绿；覆盖率 ≥70% | C1–C5 | 0.5 |

**阶段出口**：五格式批量目录能整批出向量，可取消、有进度，坏文件不中断。

> **实测**：`embed_probe.txt` / `embed_probe_samples.txt` → `datasets/samples` 入库 3 条全 ok，向量 **97 条全 ok、0 失败**（文档文本 96 条 384 维 `documentText`，`sample.png` 1 条 512 维 `clipShared`）。`image_coco_vector.txt` → COCO 一张图 512 维，**手写双线性缩放对 Pillow 参考的余弦 0.999955**。覆盖率 **85.73%**（1250/1458，`text_coverage_c.txt`），高于 70% 门槛。

### 阶段 D — MVP、评测与收尾（Day 4，6h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **D1** | MVP 探针（个人计划要求） | `packages/core_embedding/bin/embed_probe.dart` | `--path <目录>` → 扫描 → 解析 → 切块 → 向量化 → 打印 `outcome/维度/耗时/向量前 3 维`；沿用 `probe_common.dart` 风格 | C5 | 1 |
| **D2** | **自建证据集（建集 + 冻结）** | `reports/week3/evidence_set.jsonl` + `reports/week3/证据集说明.md` | ≥20 条真实文档问题，字段见 §8.3；**dev/holdout 分离并记录冻结时间**；含跨页题；**W3 只建集，不据此调参** | D1 | 2 |
| **D3** | NQ-open 300 题评测（embedding 级） | `engine/eval_nq.py` + `reports/week3/logs/nq_eval.txt` | 按 §8.2 输出 recall@1/@5、MRR；报告章节**明确标注为代理指标** | B3 | 1 |
| **D4** | COCO 图像评测 | `engine/eval_coco.py` + `reports/week3/logs/coco_eval.txt` | 有 text tower → image→caption recall@1/@5；**无 text tower → 标「功能未完成」并把 image→image 健全性检查单列一栏**，不替换完成标准 | C4 | 0.5 |
| **D5** | 覆盖率 ≥85% | `reports/week3/coverage/lcov.info`、`覆盖率报告.md` | lcov 统计 ≥85.00%，证据落盘 | B5,C6 | 0.5 |
| **D6** | 报告与文档收尾 | `reports/week3/模型精度验证报告.md`、`W03_report.md`、`docs/api/embedding-module-api.md` 定稿、TDD 更新 | 三份交付物齐全；报告按 §8.4 的**四层分层**给数；含「用例 ID — 命令 — 期望 — 实际 — 判定 — 证据」 | 全部 | 1 |

**合计 26h**（A 8 + B 6 + C 6 + D 6）。

> 说明：报告与证据不是最后一天才开始写。A/B/C 每个任务完成时就把原始输出写进 `reports/week3/logs/`，D6 只做汇总与定稿。

> **实测**：`nq_eval.txt` → recall@1=0.110000（33/300）、recall@5=0.210000（63/300）、MRR=0.166034，首行 `metric_layer=embedding_proxy`。`coco_eval.txt` → 文本塔可用，image→caption recall@1=0.920000（46/50）、recall@5=1.000000（50/50）、`mean_rank=1.14`，`function_status=complete`；image→image 另列且标 `image_to_image_not_completion=1`。`evidence_freeze.txt` → 25 条、dev 15 / holdout 10、跨页 3 条、`scored=0`、冻结 `2026-10-16T13:12:33Z`。`coverage.txt` → **1250/1458 = 85.73%**，过 85.00% 门槛。

### 5.1 关键路径与并行机会

```text
A1 ─┬─ A2 ── A3 ─┬─ A4 ─┐
    ├─ A5         │      ├─ B1 ── B2 ── B3 ─┬─ B4 ─┐
    └─ A6 ────────┘      │                 └─ B5  │
         └─ C1 ──────────┴─ C2 ── C3 ── C4 ── C5 ── C6 ─┬─ D1 ── D2
                                                          ├─ D3/D4
                                                          └─ D5 ── D6
```

- **关键路径**：A1 → A2 → A3 → C3 → C4 → C5 → D1 → D2。A3 失败会阻塞一切，因此它排在 Day 1 且是硬门槛。
- **可并行**：A5（结案记录）、A6（建包）不依赖 A2/A3；B1（分词器）与 A3/A4 无耦合；C1（切块器）只依赖 A6，可与 B 阶段并行。
- **范围收缩顺序**（万一要砍）：先保 A1–A3 → B1–B3 → C1/C3/C4 → D1（文本链路 + 切块 + 图像向量 + MVP），把 C5 批量与 D3/D4 评测降级为简化版。**A3 的双硬门槛永远第一个做**。

---

## 6. 四天排期

| 日 | 上午 | 下午 | 当日出口 |
|---|---|---|---|
| **Day 1**（8h） | A1 选型冻结 → A2 模型落盘与 8 字段登记 | A3 双硬门槛探针 → A4 运行时与绑定层 → A5 结案 → A6 建包 | 探针证明两条链路都能出向量、转换未损坏模型；`dart analyze` 0 issue |
| **Day 2**（6h） | B1 分词器（与 Python 参考逐 id 对齐） | B2 输入张量与 token 校验 → B3 `TextEmbedder` → B4 API 草案 → B5 补测 | 默认套件全绿；覆盖率 ≥45% |
| **Day 3**（6h） | C1 `TextChunker` → C2 图像预处理 | C3 `ImageEmbedder` → C4 统一引擎（双空间）→ C5 批量服务 → C6 补测 | 五格式批次整批出向量，可取消；切块边界用例全绿 |
| **Day 4**（6h） | D1 MVP 探针 → D2 自建证据集（建集 + 冻结） | D3 NQ 评测 → D4 COCO 健全性 → D5 覆盖率 → D6 报告定稿 | 三份交付物齐全，覆盖率 ≥85%，证据集冻结 |

每天收工前把当天原始输出写进 `reports/week3/logs/`；每个阶段的出口判据不满足就不要进入下一阶段——W2 已经证明前置卡住时后补的代价更大。

---

## 7. 验收命令清单（逐条可复制）

```powershell
# 0) 前置：Java（PDF 路径）与 Python 评测环境
java -version
engine\.venv\Scripts\python.exe --version

# 1) 探针与转换等价性（A3 两个硬门槛）
engine\.venv\Scripts\python.exe engine\embed_spike.py   > reports\week3\logs\embed_spike.txt
engine\.venv\Scripts\python.exe engine\convert_check.py > reports\week3\logs\convert_check.txt

# 2) 包：静态检查 + 默认单测
cd packages\core_embedding
dart pub get --offline
dart analyze
dart test --exclude-tags integration

# 3) 真模型集成用例
dart test --tags integration

# 4) 覆盖率（G3 交付物）
dart test --coverage=coverage --exclude-tags integration
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --package=.

# 5) MVP 探针（G5 交付物）
cd ..\..
dart run packages\core_embedding\bin\embed_probe.dart --path datasets\samples
dart run packages\core_embedding\bin\embed_probe.dart --path datasets\coco\val_sample\images

# 6) 评测（G2 / G6 交付物）
engine\.venv\Scripts\python.exe engine\eval_nq.py   > reports\week3\logs\nq_eval.txt
engine\.venv\Scripts\python.exe engine\eval_coco.py > reports\week3\logs\coco_eval.txt

# 7) 桌面端仍能消费（分层未破）
cd apps\desktop
flutter pub get --offline
```

---

## 8. 评测口径设计（**必须在 Day 1 定死**）

### 8.1 四条纪律

1. **分层，不混**。四层指标各自单列，替代实验必须标明「它测的不是什么」。
2. **Hit@K ≠ Recall@K**。Hit@K 是「前 K 有没有至少一个相关」；Recall@K 是「所有相关证据找回了多少」。多证据时不可混用；单证据时 Recall@K ≡ Hit@K。
3. **不要用替代实验冒名顶替**。拿不到 text tower 就把功能标「未完成」，不要换个指标继续宣称完成。
4. **冻结后再调参**。证据集一旦用于调 chunk 大小／模型选型，数字必然虚高 → 必须 dev/holdout 分离并记录冻结时间。

### 8.2 NQ-open：这是 embedding 级代理指标，不是文档检索

仓库里是 **NQ-open 风格的整理版**，按构造只有问答对——**不是「NQ 没有 passage」**（官方 NQ 原始发布确实包含 Wikipedia 文档与标注，只是没进这个子集）。

实测：`nq_open_val50.jsonl` **50 行** ＋ `nq_open_val250_part2.jsonl` **250 行** = **300 题**（与 `datasets/README.md` 声明的 300 一致）。

```json
{"question": "when was the last time anyone was on the moon", "answers": ["14 December 1972 UTC", "December 1972"]}
```

| 方案 | 做法 | 取舍 |
|---|---|---|
| **NQ-A（采用）** | 查询 = 300 个 question；候选池 = 300 个 gold answer（取首个）＋ 300 个 question 作干扰 = **600 条**；指标 recall@1/@5、MRR | 离线、可复现、成本极低；**它测的是「能否从答案候选里排对」，不是「能否从知识库找到证据」**，报告必须写明 |
| NQ-B | 按答案字符串做相似度阈值二分类 | 指标更弱，不推荐 |
| NQ-C | 拉取 NQ 官方 passage 集 | 需联网且体积大，撞风险 R7，**不在 W3 范围** |

**实现细节（一条容易做错的地方）**：排序时去掉该题**自己的 question 行**。那一行就是查询本身，余弦恒为 1，留着会把 recall@1 钉死在 0。其余 299 个 question 仍作干扰，每题实际在 **599 条**里排序。相关项只有一条（配对的首个答案），所以这里的 recall@K ≡ Hit@K。同分时余弦高的在前，再按候选下标小的在前。

作用定位：**最便宜的 embedding 级回归信号**——能第一时间抓出「模型坏了／量化坏了／pooling 接错了」。**不当主指标**。

### 8.3 自建证据集：本项目真正对应的指标（W3 建、W4 起用）

从**实际导入的文档**里整理 20–30 个问题作为初始回归集（起步建议，不是统计充分性的保证）。每条字段：

```text
question
relevantDocumentId
evidenceLocation / evidenceText     ← 标原文证据位置，不只标 chunkId
referenceAnswer
answerable
split                                ← dev | holdout
```

实际落地的字段在此基础上扩了 `relevantDocumentIds`（多相关文件）、`evidenceLocations`（多位置）、`crossPage`、`modality`，见 `证据集说明.md` §2。

**为什么标原文位置而不是 chunkId**：一旦调整切块策略，chunkId 对应的内容就变了，只标 chunkId 的标签得整套重做。

**ID 与防泄漏**：dev/holdout 分离（15/10 起步），并记录**冻结时间**；冻结后不得按分数回头调切块参数或换模型——小样本评测最容易在这里自欺。集子一旦冻结，**调参只能看 dev**。

**指标**：

| 指标 | 定义 | 何时用 |
|---|---|---|
| **Hit@5** | 前 5 条里至少有一条相关 | **主指标**；直接对应 PRD MVP「Top 结果里能出现目标文件」 |
| **MRR@10** | 第一个相关结果的排名倒数的均值 | 主指标；衡量「排得够不够靠前」 |
| **Recall@5 / Recall@10** | 所有相关证据被找回的比例 | 仅在有**多证据**完整标注时；单证据时与 Hit@K 等价，不必单列 |
| 工程指标 | 索引耗时、查询耗时（必要时拆出 embedding 与解析耗时） | 性能基线，交 W6 |
| 跨页题 | 答案横跨两个 chunk 的题目 | **通过标准定在 W4**（邻域扩展），W3 只保证数据能支撑 |

**W3 交付的是「建集 + 冻结 + 口径定义」，不是分数**——检索流水线在 W4。

### 8.4 COCO：image→caption 检索，需要 text tower；拿不到就标未完成

`datasets/coco/val_sample/captions.jsonl` 实测 50 行，与 `images/` 下 50 张 jpg 一一对应：

```json
{"file_name": "000000397133.jpg", "caption": "A man is in a kitchen making pizzas."}
```

| 路径 | 做法 | 判定 |
|---|---|---|
| **主路径** | 图像向量 vs 50 条 caption 的**文本向量**（同一 CLIP 空间）做 image→caption 检索，报 recall@1/@5 与平均排名 | 需要 MobileCLIP **text tower** |
| **未完成** | 只拿到 image tower | **功能标「未完成」**；`image→image` 最近邻检查**单列一栏**作为健全性证据，不并入完成标准 |

**实际走的是主路径**：文本塔 fp32 已在，`function_status=complete`。

三条必须写进报告的边界：

1. **不要拿文本侧模型去编码 caption**——空间不同（决策 2）。
2. **COCO 分数不能用来证明「能理解 PDF 里的图表/截图」**，那是另一件事。
3. 可用图像素材只有 **coco 50 ＋ rvlcdip 16 = 66 张**，且 rvlcdip 无标签 → 图像侧评测**只能是健全性检查**，不可能给出有统计意义的精度，报告必须写明。

### 8.5 报告必须包含的数字

每个模型一行：模型名与 revision、维度、量化方式、文件大小、单条耗时（中位/最大）、**pooling 方式**、**是否归一化**、**query/document 前缀**、评测集与口径、recall@1/@5、MRR 或平均排名、转换等价性余弦值、**已知限制**。

---

## 9. W3 专项风险与应对

| 风险 | 触发信号 | 应对（W3 内可执行） | 结果 |
|---|---|---|---|
| **R1 模型转换/端侧推理失败（最高）** | A3 探针跑不出向量，或转换等价性 < 0.999 | 探针放 Day 1 且是硬门槛；失败立即降级：换更小/更匹配的模型、换 ONNX，运行时退到 W2 同款外部进程兜底 | 未触发。文本与图像两条链路 Day 1 即出向量 |
| **选错文本模型** | 中文检索效果明显差 | 决策 1 已排除纯英文词表的 `bert-base-uncased`；A3 探针**必须含一句中文**，中文不过就不算通过 | 中文探针 384 维、`unk_tokens=0` |
| **静默降质三件套** | 数字莫名偏低但不报错 | pooling 写错、前缀漏写、归一化与度量不一致——三者各有一条单测固定；转换等价性用例兜底 | pooling 与归一化各有固定用例；本模型无前缀需求，字段为 null |
| **本机无 torch / transformers** | 想加载 `.bin`/`.pt` 权重时 | 只走 TF 与 ONNX Runtime 两条已验证路径；不把「装 torch」当前提 | 未安装 torch，全链路跑通 |
| **拿不到 `libtensorflowlite_c-win.dll`** | `native/tflite/windows/` 仍为空 | 接口层已隔离 → 走外部进程兜底；**打包问题明确留给 W8**，在 ADR 里写清技术债 | 走兜底。`TfliteBindings` 只是接口，DLL 未放 |
| **FFI 适配器拖低覆盖率** | Day 3 结束覆盖率不达标 | 抽 `TfliteBindings` 接口，让适配器分支在默认套件里用假绑定覆盖（照抄 W2 `io_process_runner_test.dart` 的做法） | 达标 85.73% |
| **双空间被误当成一个空间** | 有人拿文本向量和 CLIP 向量直接算余弦 | 决策 2 写进 ADR，且在 `EmbeddingEngine` 里**抛异常**，用代码兜住 | `EmbeddingSpaceMismatchException` 已实现并有单测 |
| **小样本评测过拟合/泄漏** | dev 分数高、holdout 崩 | §8.1 纪律 4：dev/holdout 分离 + 记录冻结时间；冻结后只调 dev | 已冻结，`parameters_changed_after_freeze=0` |
| **生成范围膨胀** | 有人开始要求「回答 + 引用」 | §0.1 已声明为未规划；进入需单独评估本地 LLM 的体积/延迟/打包代价 | 未进入 |
| **许可证（R8）** | MobileCLIP 权重用途受限 | A2 必须给出结论；**越晚发现代价越大**，因为它直接决定 W8 能否公开可下载包 | 已结案：apple-amlr，W8 不得打进公开包（决策 5） |
| **覆盖率 85% 达不到** | Day 3 结束 <70% | 照抄 W2 打法：运行时、词表、文件系统全部经接口注入；适配器用假实现覆盖全分支 | 达标 85.73% |
| **登记与实际不符** | 报告里的 N 自相矛盾 | A2 顺带纠正 `datasets/README.md`（rvlcdip 32→16）；评测报告只引用**实测**行数 | 已纠正 |
| **PDF 5.1 s/文件拖慢批量** | 批量 embedding 吞吐不达标 | W3 只记录不优化（Q1 已结案）；批量服务设计成可取消 + 可断点续跑 | 仅记录。探针单条含进程启动与模型加载，中位 2016 ms |
| **异步断言漏 `await` 导致假绿** | 分支被删掉但测试仍全绿 | 异步用例一律 `await expectLater(...)`；改完必须做挖空复核，确认删掉分支测试会红 | 已修。`text_coverage_c.txt` 记录了这次重算 |

---

## 10. W3 明确不做（Scope Guard）

- ❌ Chroma 写入、索引、相似度查询、排序、混合打分（W4）
- ❌ 应用内检索闭环与邻域扩展（W4；W3 只保证 `pageNumber`+偏移可支撑）
- ❌ **生成闭环**：引用支撑的回答、无答案行为、答案正确性（§0.1，未规划）
- ❌ Flutter UI 与无障碍实现（W5）
- ❌ PDFium 落地改造（Q1 只结案；`process_wait` 99% 的问题留 W6 性能周）
- ❌ OCR / RVL-CDIP 标注（Q4，W6）
- ❌ worker isolate 化（Q6，W6）
- ❌ 多后端自动切换、复杂插件体系（只保留一个运行时后端 + 一个绑定接口）
- ❌ 把模型权重打进三平台发布包（W8）
- ❌ 重新训练、微调、蒸馏任何模型

---

## 11. 交付物清单（W3 仓库实际新增的文件）

```text
packages/core_embedding/
  pubspec.yaml  analysis_options.yaml  README.md  .gitignore  dart_test.yaml
  lib/core_embedding.dart
  lib/src/model/{embedding_vector,embedding_input,embedding_space,embedding_report,model_info,text_chunk}.dart
  lib/src/spi/{embedding_runtime,onnx_process_runtime,onnx_tensor_runtime,tflite_bindings}.dart
  lib/src/text/{unigram_tokenizer,unigram_model,precompiled_normalizer,text_input_builder,text_embedder,text_chunker}.dart
  lib/src/text/{clip_bpe_tokenizer,clip_text_embedder}.dart
  lib/src/text/wordpiece_tokenizer.dart      ← 计划路径上的再导出，不是第二种算法
  lib/src/image/{image_decoder,image_preprocess,image_embedder}.dart
  lib/src/engine/{embedding_engine,embedding_service}.dart
  bin/embed_probe.dart
  test/**（假 runtime、假绑定、词表夹具、切块边界、Pillow 对照、chunkChars 标定）
docs/
  api/embedding-module-api.md
  architecture/adr/0003-embedding-model-and-runtime.md
  tdd/technical-design-document.md            ← Q1/Q3/Q7 结案
engine/
  embed_spike.py   convert_check.py   eval_nq.py   eval_coco.py
  embed_text_hidden.py   embed_onnx_output.py   dump_token_ids.py
  w3_embed_lib.py   pillow_bilinear_ref.py   download_w3_models.py
models/
  README.md                                   ← 决策 5 的 8 个字段 + 来源/许可证/sha256/张量签名
  raw/**                                      （gitignore，本地存在）
  tflite/                                     （空；未产出 TFLite，ADR 决策 4 记兜底）
native/tflite/windows/                        （空；DLL 未放，见 ADR 0003 决策 4）
datasets/README.md                            ← 修正 rvlcdip 数量 32→16
reports/week3/
  W03_task_plan.md（本文件）  W03_report.md  模型精度验证报告.md  覆盖率报告.md
  evidence_set.jsonl  证据集说明.md           ← 自建证据集（G6）
  logs/                                       ← 每个任务的原始输出
  coverage/lcov.info                          ← G3 交付物
apps/desktop/pubspec.yaml                     ← 增加 core_embedding path 依赖
```

---

## 附录 A：接口骨架（Day 1 冻结，与实现一致）

```dart
/// 向量所处的空间。两个空间不可混用（决策 2）。
enum EmbeddingSpace {
  /// 文本空间：文档正文与文本查询。
  documentText,

  /// MobileCLIP 图文共享空间：图像检索与自然语言查图。
  clipShared,
}

/// 偏移量的索引单位。W3 冻结为 UTF-16 code unit，与 ParsedDocument 一致。
enum TextUnit { utf16CodeUnit }

/// 一个向量的自描述结果。
class EmbeddingVector {
  final List<double> values;
  final EmbeddingSpace space;
  final int dim;
  final String modelId;      // 例：'paraphrase-multilingual-MiniLM-L12-v2'
  final bool normalized;     // 归一化状态必须显式，向量库度量要据此选
  final String? chunkId;     // 文本分块时有值，W4 引用定位用
}

/// 文本分块产物（决策 3）。
class TextChunk {
  final String chunkId;      // documentId + chunkerVersion + 页码 + 块序号，见决策 3(d)
  final String text;
  final int? pageNumber;     // TXT/DOCX 无真实页码时为 null，UI 不得当真实页码展示
  final int startOffset;     // 相对该页提取文本，含首，单位见 textUnit
  final int endOffset;       // 不含尾
  final TextUnit textUnit;
  final String chunkerVersion;
}

/// 分块器：页=定位、段落=切分、长度上限才切窗口。
abstract interface class TextChunker {
  List<TextChunk> chunk(ParsedDocument document, {String? documentId});
}

/// 统一入口：文本与图像走同一个方法（原文 Key Task 3）。
abstract interface class EmbeddingEngine {
  Future<EmbeddingVector> embed(EmbeddingInput input, {CancellationToken? cancel});
  List<ModelInfo> get models;
}

/// 推理运行时：TFLite DLL 或外部进程，二者实现同一接口。
abstract interface class EmbeddingRuntime {
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs);
  bool get isAvailable;
}

/// FFI 绑定层：把 dlopen / tflite_interpreter_* 调用抽成接口，
/// 使适配器分支可在默认套件里用假绑定覆盖（覆盖率由它保住）。
abstract interface class TfliteBindings {
  int loadModel(List<int> bytes);
  List<TensorInfo> describe(int handle);
  void invoke(int handle, Map<String, Tensor> inputs, Map<String, Tensor> outputs);
  void close(int handle);
}

/// 批量：接口形状对齐 W2 的 IngestionService。
abstract interface class EmbeddingService {
  Future<EmbeddingReport> embedAll(
    IngestionReport ingestion, {
    void Function(EmbeddingProgress)? onProgress,
    CancellationToken? cancel,
  });
}
```

## 附录 B：与 W2 / W4 的接缝

| 接缝 | 约定 |
|---|---|
| W2 → W3 | 只消费 `IngestionReport.indexable`，**不重新读盘**；`ParsedDocument.pages` 是分块输入 |
| W3 → W4 | 交出 `EmbeddingVector`（含 `space`/`dim`/`modelId`/`normalized`/`chunkId`）＋ 元数据；**不做存储、不做排序**；`chunkId` **不是稳定主键**，W4 不得据此做增量更新 |
| W3 → W4（跨页） | W3 保证 `pageNumber` 与偏移被存下；**跨页答案的邻域扩展由 W4 承接**，W3 只提供数据 |
| W3 → W4（证据集） | W3 冻结 `evidence_set.jsonl` 与 dev/holdout 划分；W4 起用并按 §8.3 出 Hit@5 / MRR@10 |
| W3 → W5 | UI 只经检索层拿结果，不直接调 embedding；**虚拟页号不得当真实页码展示** |
| 测试约定 | 真模型用例一律带 `integration` 标签；默认套件不依赖 JDK、不依赖模型文件、不依赖数据集图片 |
| 证据约定 | 每个任务的原始输出落 `reports/week3/logs/`，报告体例沿用 `reports/week2/W02_report.md` |
