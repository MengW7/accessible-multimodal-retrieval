# Week 4 执行方案：向量库接入 + 核心检索逻辑，打通 MVP

| 项目 | 内容 |
|---|---|
| 周期 | W4 ｜ **2026-10-20（周二）– 10-25（周日）**，6 天 |
| 交付日 | **10/25（周日）** |
| 预算工时 | **40h**（Day 1 半天 5h ＋ Day 2–6 各 7h） |
| 主题 | 向量存储 + 混合检索 + 端到端 MVP |
| 上游依据 | `docs/tasks/Software Engineering Project … Retrieval System.pdf`（Week 4 章节） |
| 计划基线 | `reports/week1/个人计划.md`（W4 行）、`docs/tdd/technical-design-document.md`（Q2/Q5 本周结案） |
| 上游交付 | `packages/core_parsing`（覆盖率 90.99%）、`packages/core_embedding`（覆盖率 85.73%，双空间冻结）、`reports/week3/evidence_set.jsonl`（25 条，已冻结） |
| 下游衔接 | W5 只经检索层拿结果；W6 冲 ≥90% 覆盖率与性能；W8 打包不含 MobileCLIP 权重 |
| 落地目录 | `reports/week4/`（本计划、探针、日志、报告、覆盖率）＋ `packages/core_storage/`、`packages/core_retrieval/`、`packages/core_pipeline/` |

> 口径说明：W1–W3 的报告在 `reports/weekN/`，本周按任务要求集中在 `reports/week4/`。要并回总目录时整目录移动即可，文件名不变。

---

## 0. 一页速览

**一句话目标**：把 W3 已经能算出来的两个空间的向量，落到一个**离线、可过滤、带关键词通道**的本地索引里，用**三路召回 + RRF 融合 + 邻域扩展**把「一句不含文件名的中文问句」变成「Top-5 里出现目标文件 + 能定位到原文哪一页哪一段」，并给出可复现的精度数字。

**六天节奏**：

| 日 | 时长 | 主产出 | 出口判据 |
|---|---|---|---|
| Day 1（10/20 下午） | 5h | 决策冻结 + **存储等价门槛**（先证明两条存储路线给同一个排名） + 建包 | 同一批 97 条向量在 Chroma 与 Dart+SQLite 上 Top-5 一致率 ≥96% |
| Day 2（10/21） | 7h | `core_storage`：schema、批量写入、向量查询、关键词索引、代次表 | 10k 块写入 ≤0.6 s；单次 384 维查询 ≤60 ms；中文两字词能查到 |
| Day 3（10/22） | 7h | `core_retrieval`：三路召回、RRF 融合、过滤、Top-K、邻域扩展 | 融合结果在 dev 上不低于任一单通道；跨页题能扩到相邻块 |
| Day 4（10/23） | 7h | `core_pipeline` 编排 + `index_probe` / `search_probe`（MVP）+ 增量重建 | 一条命令完成 扫描→解析→向量化→入库；另一条完成 查询→返回出处 |
| Day 5（10/24） | 7h | E2E 用例集 + 精度基准（6 臂消融）+ 覆盖率 ≥85% + 离线自查 | E2E-01～E2E-12 全绿；ablation 表出数；覆盖率落盘 |
| Day 6（10/25） | 7h | `W04_report.md`、`检索精度基准报告.md`、API 与架构文档更新 | 四份 PDF 交付物齐全，证据索引可逐条点开 |

**红线**：W4 不做 UI、不做无障碍实现、不做生成（回答/引用）、不做 OCR、不做 ANN 索引、不做模型重训、不做多后端插件体系。

### 0.1 范围声明：本周把「检索闭环」闭合

| 列 | 内容 | 状态 | 依据 |
|---|---|---|---|
| **检索闭环** | 导入真实文件 → 索引 → 命中正确证据 → 展示出处与偏移 → 原文件路径可打开 → 断网可复现 | **本周闭合**（W3 承诺、W4 兑现） | PRD §6 MVP：「断网输入一句不含文件名的话，Top 结果里能出现目标文件」「结果可以打开原文件」 |
| **生成闭环** | 引用支撑的回答、资料不足时拒答、答案正确性 | **仍未规划** | PRD §2 与官方 Full Deliverables List 都没有生成；W3 计划 §0.1 已判定为范围扩张，W4 不重开 |

**这是本项目第一次能回答「检索到底行不行」**。W3 的证据集 `scored=0`，本周开始出分，且必须分通道、分臂报，不许合成一个数字。

### 0.2 工期对账（必须写明，否则后面每周都在补账）

个人计划里 W4 是 10/11–10/17 交付 10/16。实际 W3 的最后一次提交在 **10/17 10:08**，W3 报告 10/17 定稿——W4 的原定窗口已被 W3 吃掉。

| 周次 | 个人计划 | 实际 | 差 |
|---|---|---|---|
| W3 | 10/04–10/10，交付 10/10 | 10/15–10/17 实做，10/17 交付 | 晚 7 天 |
| **W4** | 10/11–10/17，40h | **10/20–10/25，40h（6 天）** | 顺延 6 天 |
| W5–W8 | 10/18–11/14（28 天） | 10/26–11/14（**20 天**） | 净少 8 天 |

**结论**：W4 仍是 40h，**不靠加班补**，靠两处结构压缩：Day 1 只做决策与对照（5h），报告在 Day 6 汇总而不重写。

W5 起**改为一周 5 天**，正好填满到 11/14，交付日不动：

| 周次 | 新窗口 | 天 |
|---|---|---|
| W5 | 10/26（周一）–10/30（周五） | 5 |
| W6 | 10/31（周六）–11/04（周三） | 5 |
| W7 | 11/05（周四）–11/09（周一） | 5 |
| W8 | 11/10（周二）–11/14（周六） | 5 |

这意味着 **W8 的三平台打包只有 5 天**，而它原本就要打三个平台 + 录 Demo + 整理作品集。**W5 起每周必须留半天给「打包与发布」的技术债偿还**，不接受把打包风险全压到 W8——这条写进 W5 计划的开头。

---

## 1. PDF 原文对 Week 4 的要求（照抄）

> **Week 4: Vector Database Integration & Core Retrieval Logic Implementation**
> Core Focus: Build the end-to-end semantic search pipeline, deliver a working minimum viable product (MVP)

**Key Tasks**

1. Integrate Chroma DB for local vector storage, indexing, and similarity search
2. Develop hybrid semantic retrieval logic: keyword + embedding-based similarity scoring, result ranking, and filter functionality
3. Build the end-to-end retrieval pipeline: file ingestion → parsing → embedding → storage → search → result return
4. Conduct end-to-end functional testing of the core pipeline
5. Benchmark retrieval accuracy using curated test datasets

**Weekly Deliverables**

1. Integrated vector storage and retrieval module
2. Working MVP of the full core retrieval pipeline
3. End-to-end functional test report
4. Retrieval accuracy benchmark report

**个人计划补充的 W4 目标**（`reports/week1/个人计划.md`）

- 本地 Chroma：写入、索引、相似度查询
- 混合检索：关键词 + 向量打分 + 排序 + 过滤
- 全链路 MVP：摄入 → 解析 → embedding → 存储 → 搜索 → 返回
- 端到端功能测试报告
- 检索准确率基准

### 1.1 与原文的一处必然偏差（决策 1 有完整论证）

| 原文 | 本周实际 | 原因 |
|---|---|---|
| Chroma DB 作为本地向量库，进入产品运行时 | **Chroma 只做评测侧基线**；产品运行时用 Dart + 系统 SQLite（`winsqlite3.dll`，FTS5） | pub.dev 上的 Dart `chromadb 2.0.0` 是 **HTTP 客户端**，必须另起一个 Chroma 服务进程；运行时要带 Python 或第二个进程，正好撞 TDD Q2 的结论（`engine/` 不进发布包）、风险 R7（体积）与 W8 三平台打包。系统 SQLite 零新增二进制，且本机已实测可用 |

**这条偏差不是「没做 Chroma」，而是「Chroma 做了、且被用来校准」**：两条路线在**同一批向量、同一批查询**上必须给出同一个排名（§3 的 H1 门槛）。Chroma 是**对照组**，不是被丢掉的选项。

---

## 2. 当前基线

### 2.1 W3 已交付、W4 直接复用

| 资产 | 证据 | 对 W4 的价值 |
|---|---|---|
| `packages/core_embedding`：`EmbeddingEngine` / `DefaultEmbeddingService` / `CascadeTextChunker` | `reports/week3/W03_report.md`：默认套件 `+93` 全绿 | 向量与切块不用重做，W4 只消费 |
| `EmbeddingVector` 自带 `space`/`dim`/`modelId`/`normalized`/`chunkId` | `lib/src/model/embedding_vector.dart` | **索引必须按 `space` 分表**，这是存储层的建表输入 |
| 双空间 + `EmbeddingSpaceMismatchException` | `lib/src/engine/embedding_engine.dart:17` | 混算 384 与 512 在编译期/运行期都已被挡住；W4 不许退化成「一个索引」 |
| `chunkId` 组合式编号 | `lib/src/text/text_chunker.dart:339` | **不是稳定主键**，W4 的增量更新必须另建代次键（决策 4） |
| `pageNumber` + `startOffset`/`endOffset`（UTF-16 code unit） | `lib/src/model/text_chunk.dart:49` | 结果能回到原文哪一页哪一段；W5 高亮共用同一单位 |
| 自建证据集 25 条（dev 15 / holdout 10），sha256 冻结 | `reports/week3/证据集说明.md` §3 | **本周第一次出分**，且只能看 dev 调参 |
| `integration` 标签分离 | `packages/core_embedding/dart_test.yaml` | 真模型、真数据集不进默认套件，覆盖率口径可延续 |
| 探针体例 `probe_common.dart` / `embed_probe.dart` | `packages/*/bin/` | W4 的 `index_probe` / `search_probe` 沿用同一输出格式 |

### 2.2 W4 开工实测（本计划新增的探针，结论直接进决策）

三份原始输出在 `reports/week4/probes/`。**这三组数字是本周排期与选型的唯一依据，不是估算。**

#### （a）运行时常驻化：W3 的 2 s/向量不是模型的错

`reports/week4/probes/probe_persistent_runtime.txt`，同一批 24 条真实文本（取自 `docs/` + `reports/` 的 md，按 120 字符切）：

| 形态 | 每条中位 | p90 | 24 条合计 |
|---|---:|---:|---:|
| `one_shot`：每条一次 `python embed_text_hidden.py`（**W3 现状**） | **1382.4 ms** | 1436.9 ms | 33604 ms |
| `persistent`：一个进程加载一次模型，逐条前向 | **25.5 ms** | 27.3 ms | 618 ms |
| `batched`：同进程按批前向（size=8 / 16） | 21.9 / 24.0 ms | — | — |

**加速比 54.3×**，`session_load_ms=481`（另一次实测 905，模型 470 MB 冷读）。

含义：

- W3 的 2082 ms/条（`reports/week3/logs/embed_probe_samples.txt`，97 条 201993 ms）**几乎全是进程启动 + 模型加载**，不是推理。推理本身 25 ms。
- 全仓库 md 语料 20 文件 / 174519 字符 ≈ **1454 块**：按 W3 实测的 2082 ms/块要 **50 分钟**，按本探针的 `one_shot` 1382 ms/块要 **33.5 分钟**，按常驻形态 **37 秒**。
- 因此**常驻运行时是 W4 的前置条件，不是优化项**。批量（size=16）反而不如单条（24.0 vs 25.5 ms），本机 CPU 上没有 batch 收益，**不做 batch**。

#### （b）存储路线：系统 SQLite 实测可用

`reports/week4/probes/probe_sqlite_capacity.txt` + `reports/week4/probes/dart_store_probe.txt`：

| 项 | 实测 |
|---|---|
| `C:\Windows\System32\winsqlite3.dll` | SQLite **3.53.4**（2026-07-24 源码） |
| FTS5 / FTS4 / JSON1 / WAL | 全部可用 |
| `package:sqlite3` 2.9.4 在 Windows 的实际行为 | 先试 `sqlite3.dll`，失败**回退 `winsqlite3.dll`**；Dart 侧探针已跑通（`sqlite_version=3.53.4`） |

#### （c）关键词通道：**FTS5 的中文默认分词会让混合检索静默失效**

同一句「离线检索可以在没有网络的电脑上运行」，三种查法：

| 查询词 | `unicode61`（FTS5 默认） | `trigram` | `LIKE '%词%'` |
|---|---:|---:|---:|
| 离线（2 字） | **0** | **0** | 1 |
| 离线检索（4 字） | **0** | 1 | 1 |
| 键盘（2 字） | **0** | **0** | 1 |
| 整个流程（4 字） | 0 | 1 | 1 |
| 电脑上（3 字） | 0 | 1 | 1 |

`unicode61` 的词汇表实测只有两条：`离线检索可以在没有网络的电脑上运行` / `键盘操作必须能走完整个流程`——**整段中文被当成一个 token**。`trigram` 要 ≥3 字才命中。

**所以「关键词 + 向量」里的关键词通道，照默认配置做出来是 0 命中的**，而且不报错。这是本周最容易踩且最难发现的一个坑，处置见决策 3。

#### （d）暴力余弦够用，不需要 ANN

384 维 fp32 从 SQLite 读 BLOB 后逐条点积（纯 Dart，`dart_store_probe`）：

| 块数 | 索引写入 | 单次全量扫描（中位） |
|---:|---:|---:|
| 1500 | 103 ms | **13.6 ms** |
| 10000 | 528 ms | **51.9 ms** |

向量已 L2 归一化，余弦 = 点积。**本机 10k 块 52 ms，纳入 10 万块以内都不必上 ANN**，MVP 阶段用全量精确检索反而更好解释、更好复现。

### 2.3 开工缺口（W4 必须补上）

| W4 要求 | 开工现状 | 本周做什么 | 落点 |
|---|---|---|---|
| 向量存储与索引 | `packages/core_storage/` **不存在**；`engine/chroma_data/` 只有 W1 的 `week1_smoke`（1 条） | 建包 + schema + 写入/查询/删除 | `packages/core_storage/` |
| 检索逻辑 | `packages/core_retrieval/` **不存在** | 建包 + 三路召回 + 融合 + 过滤 + 邻域扩展 | `packages/core_retrieval/` |
| 端到端编排 | 架构写「在 `apps/desktop` 组合根」，但 W4 没有 UI，`dart test` 测不到 Flutter 组合根 | 抽 `packages/core_pipeline`（纯 Dart），桌面端只做装配（决策 6） | `packages/core_pipeline/` |
| 增量重建 | 无；`chunkId` 不稳定 | 代次键 `contentHash+parserVersion+chunkerVersion+modelId` | `core_storage` 的 `index_generation` |
| 关键词索引 | 无 | FTS5 `trigram` + **中文 bigram 预切** + `LIKE` 兜底（决策 3） | `core_storage` 的 `keyword_index` |
| 邻域扩展 | W3 明确移交 W4 | 命中块 → 同页相邻块 / 整页（决策 5） | `core_retrieval` |
| 评测集缺口 | 冻结集 25 条**全是 answerable，无 no-answer 题**；跨页 3 条在 `sample.pdf` 上是「同一证据出现在两页」而非断句 | **另建** W4 邻域验证集（10–15 条），**不并入冻结集**（决策 7） | `reports/week4/evidence_set_w4.jsonl` |
| Chroma 对照 | venv 里有 `chromadb 1.5.9`，但没有任何 W3 向量导出物 | 导出 97 条向量，建 Chroma 集合，跑 H1 等价门槛 | `reports/week4/vectors/`、`engine/chroma_baseline.py` |
| 覆盖率证据 | 只有 W2/W3 的 | 新三包落盘 | `reports/week4/coverage/` |

### 2.4 TDD 里本周要结案的未决问题

| 编号 | 问题 | 现倾向 | W4 动作 | 出口 |
|---|---|---|---|---|
| **Q2** | `engine/`（Python + Chroma）是否进入发布包 | 不进入：只做离线评测，发布版存储由 Dart 侧实现 | **结案并写进 ADR 0004**：Chroma 只在评测侧做对照，产品侧 Dart + 系统 SQLite | 有结论 + H1 对照数字 |
| **Q5** | 图像-only 文档如何在结果列表里排序与展示 | 与文本同榜，展示缩略图 + 尺寸 | **结案**：`clipShared` 空间单独召回，经 RRF 与文本同榜；结果携带 `modality` 与 `imageAsset`，界面不参与打分 | 有结论 + 混合榜实测 |
| Q4 | 扫描件是否引入 OCR | 先走图像向量 | 本周只登记影响，仍留 W6 | 不动 |
| Q6 | 批量解析是否 worker isolate | W2 用 `ImmediateExecutor` | 本周只记录：全量索引 1454 块 37 s 已可接受，isolate 收益留 W6 实测后再定 | 不动 |

---

## 3. 完成定义（DoD）

| 编号 | 交付物（对应 PDF Deliverables） | 落地文件 | 验收方式 | 门槛 |
|---|---|---|---|---|
| **G1** | 集成向量存储与检索模块 | `packages/core_storage/`、`packages/core_retrieval/` | `dart analyze` 0 issue；默认套件全绿；两包各自覆盖率 ≥85% | 硬门 |
| **G2** | 端到端 MVP 可运行 | `packages/core_pipeline/bin/index_probe.dart`、`search_probe.dart` | 一条命令建库；另一条命令 `--query "…"` 出 Top-K，含文件、页/段、偏移、分数、通道 | 硬门 **H3** |
| **G3** | 端到端功能测试报告 | `reports/week4/W04_report.md` + `reports/week4/logs/` | 沿用 W2/W3 体例：用例 ID — 命令 — 期望 — 实际 — 判定 — 证据；E2E-01～E2E-12 齐备 | 硬门 |
| **G4** | 检索精度基准报告 | `reports/week4/检索精度基准报告.md` | 6 臂消融表 + Hit@5 / MRR@10 + **Wilson 95% 置信区间** + 逐题通过表；dev/holdout 分列；标明样本量限制 | 硬门 |
| **G5** | 存储等价门槛 | `reports/week4/logs/storage_equivalence.txt` | 同一批向量、同一批查询，Chroma 与 Dart+SQLite 的 **Top-5 一致率 ≥96%** | 硬门 **H1** |
| **G6** | 决策记录 | `docs/architecture/adr/0004-vector-storage-and-fusion.md` | 8 个决策各含 Decision / Alternatives / Consequences；写明与 PDF 原文的一处偏差 | 硬门 |
| **G7** | API 文档 | `docs/api/storage-module-api.md`、`docs/api/retrieval-module-api.md` | 每个 public 类型/方法有签名、参数、异常、示例；含 `space`、`filters`、`SearchResult` 语义 | 硬门 |
| **G8** | 覆盖率达 W6 可达性检查 | `reports/week4/coverage/*.lcov.info` + `覆盖率报告.md` | 三个新包 ≥85%，`core_parsing` 不回退到 80% 以下，`core_embedding` 不低于 85% | 硬门 |

**四个 PDF 交付物 → G 编号**：集成存储与检索模块 = G1；可用 MVP = G2；端到端功能测试报告 = G3；检索精度基准报告 = G4。

### 3.1 三个硬门槛（不过就不进下一阶段）

| 门槛 | 内容 | 不过怎么办 |
|---|---|---|
| **H1 存储等价** | 同一批向量、同一查询，两条存储路线 Top-5 一致率 ≥96%（25 题 × 5 位 = 125 个位置，允许浮点与 tie-break 差异） | 说明有一条路线的归一化/度量接错了（余弦 vs L2、是否归一化）。**先修，再谈融合**——喂错的排名上做融合等于白做 |
| **H2 融合有增益** | dev 上融合臂的 Hit@5 与 MRR@10 **不低于任一单通道臂** | 如实报「融合没有增益」，并给出原因分析。**不许只调 dev 硬凑**；holdout 只出最后一次数字 |
| **H3 端到端** | 断网 → 一条不含文件名的中文问句 → Top-5 出现目标文件 → 能给出页/段与偏移 → 原文件路径存在且可读 | 这是 PRD §6 的 MVP 原文。不过就是没打通，不许拿「模块单测全绿」代替 |

---

## 4. 开工前必须冻结的 8 个决策（Day 1 下午完成）

> 这 8 条不冻结就动手，等于把 W3 的已验证资产浪费掉。每条都写进 `ADR 0004`（决策 8 并进决策 1 的运行时一节，同一份 ADR）。

### 决策 1：存储分成两层——Chroma 做对照，系统 SQLite 做产品

事实约束（§2.2b）：系统自带 SQLite 3.53.4，FTS5/JSON1/WAL 齐全，`package:sqlite3` 2.9.4 在 Windows 自动回退到 `winsqlite3.dll` 并已跑通。

| 子问题 | 选项 | 选择 | 理由 |
|---|---|---|---|
| 产品运行时存储 | (a) Dart `chromadb 2.0.0` HTTP 客户端 + 本地 server<br>(b) 自带 `sqlite3` 原生编译<br>(c) 系统 SQLite（`winsqlite3.dll`）+ 自有向量表 | **(c)** | (a) 要第二个进程，撞 Q2/R7/W8；(b) 2.x 要 build hook，3.x 要 native toolchain，三平台打包成本高；(c) 零新增二进制，本机已验证 |
| 评测侧对照 | (a) 不做<br>(b) 用 venv 里的 `chromadb 1.5.9` 建集合，与产品路线对比排名 | **(b)** | 满足 PDF「Integrate Chroma DB … indexing and similarity search」的**可验证**含义，并给出 H1 等价门槛 |
| Chroma 的度量陷阱 | 默认 L2 vs 余弦 | **必须显式 `metadata={"hnsw:space": "cosine"}`** | 向量已 L2 归一化，用 L2 排序与余弦排序在近似并列处会翻转；不显式设置就是静默错排 |
| 向量存法 | (a) JSON 文本<br>(b) fp32 小端 BLOB | **(b)** | 1500 块写入 103 ms；JSON 体积约 3× 且要解析；fp32 BLOB 直接 `Float32List` 视图，无需拷贝 |
| 系统 DLL 的定位 | 直接写死 `C:\Windows\System32\winsqlite3.dll` | **写死是错的**：必须按平台名查找，且把「找不到」表达成结构化失败 | 换机器/换 Windows 版本就变；W8 打包可能要自带 `sqlite3.dll`。写成 `SqliteLibraryLocator` 接口，可注入假实现做覆盖率 |
| 已知限制 | — | `winsqlite3.dll` 是随系统分发的**未文档化**用途（`package:sqlite3` 源码注释亦如此标注） | 记入 ADR 与 §9 风险，W8 决定是否改为自带 `sqlite3.dll` |

**Alternatives（存储）**

| 方案 | 为什么不选 |
|---|---|
| **A. 坚持 Chroma 进运行时** | 需要 Python 或第二个进程常驻；Q2 已否；W8 三平台各打一份 Python 不现实 |
| **B. 纯内存索引，不落盘** | 每次启动重建 1454 块要 37 s，且断网重开就没了，违反「已建库后一次搜索尽快出结果」 |
| **C. 自研二进制索引文件** | 过滤、删除、事务、并发全要自己写；SQLite 已经把这些做完了 |

### 决策 2：两个空间三路召回，用 RRF 合榜，不用分数加权

**为什么不能用加权和**：`documentText` 的 384 维余弦与 `clipShared` 的 512 维余弦**分布不同**，且关键词分是另一套量纲。把三者归一化后加权，需要每路各自的校准，而校准本身要用标注数据——等于拿评测集调参。

| 方案 | 做法 | 取舍 |
|---|---|---|
| **A（采用）RRF** | `score(d) = Σ_i w_i / (k + rank_i(d))`，`k=60`，只依赖名次 | 无需跨空间校准；对量纲不敏感；单通道缺失时自然降权；**解释成本低，报告能讲清楚** |
| B 分数加权 | 各通道 min-max 或 z-score 后加权 | min-max 依赖候选集，Top-K 变了分数就变；需要调权重，撞决策 7 的冻结纪律 |
| C 只做向量 | 放弃关键词通道 | 文件名/路径/扩展名命中会丢；风险 R5 正面撞上（「演示时搜不到自己刚导入的文件」） |

**细则（这几条最容易做错）**：

1. **三路**：`documentText` 向量、`clipShared` 向量、关键词。**前两路分别召回、分别归一化名次，绝不跨空间算余弦**（决策在前，代码兜底：`space` 不符直接抛）。
2. **`k=60` 是 RRF 的常规取值，不是调出来的最优值**，报告里要这么写。
3. **过滤必须在存储层生效**，不许「先取 Top-50 再筛」——筛完可能空。每路查询都带 `filters`。
4. **同分 tie-break** 固定为：分数降序 → `relativePath` 升序 → `pageNumber` 升序（null 排后）→ `startOffset` 升序。写进 ADR，H1 的一致性判定靠它。
5. **图像通道没有命中时**（无图像文件、或图像塔不可用）不是错误，只降权；`SearchResult.modality` 如实标注。
6. 权重 `w` 初值 `(0.5, 0.3, 0.2)`（文本向量 / 关键词 / 图像），**在 dev 上只允许选一次**，然后冻结。
7. **过滤条件的类型归属**：`StorageFilter` 在 `core_storage`，`SearchFilters` 在 `core_retrieval`，后者转前者。反过来会让存储层 import 检索层，直接违 R1b。

### 决策 3：关键词通道必须自己处理中文——FTS5 默认分词是 0 命中

实测（§2.2c）：`unicode61` 把整段中文当一个 token，`trigram` 要 ≥3 字。**照默认配置做出来的关键词通道，两字中文查询全部 0 命中且不报错。**

**采用三层：索引时预切 bigram（主），FTS5 `trigram`（英文与长词），`LIKE` 兜底（短查询）。**

```text
索引时：body → 中文连续段切成 bigram（"离线检索" → "离线 线检 检索"）
              → 写 keyword_index(term, chunk_rowid)
查询时：中文查询 → 同样切 bigram → 逐 term 匹配，按命中 term 覆盖率给分
        英文查询 → 直接用 FTS5 trigram（≥3 字符）
        <3 字符或切不出 bigram → LIKE 兜底，限制候选数
```

| 子问题 | 选择 | 理由 |
|---|---|---|
| 主分词 | **bigram 预切 + 普通表 + 索引** | 实测 `LIKE '%离线%'` 必中；预切成 term 后可用普通 B-tree 索引，避免全表扫描。bigram 对中文检索是成熟做法，且**不需要词典** |
| FTS5 角色 | 英文与 ≥3 字中文的**补充**通道 | `trigram` 实测对「离线检索」「整个流程」「电脑上」有效，对英文单词有效 |
| 兜底 | `LIKE`，带 `LIMIT` | 实测 1500 块 0 ms、10k 块 <1 ms 量级；只在短查询用 |
| 不许做 | 引入中文分词库（jieba 等） | 新依赖 + 词典体积；且 W6 之前不该为关键词通道再加一个不确定性 |
| 打分 | 命中 bigram 覆盖率（0–1） | 与 RRF 配合时只用名次，此分数只用于同分排序与展示 |

**这条必须进 ADR，因为它是「配置默认值静默失效」的典型**——和 W3 里 int8 图像塔余弦掉到 0.0458 是同一类问题：不设门槛就发现不了。

### 决策 4：`chunkId` 不是主键，索引按代次键判断能否复用

ADR 0003 已警告「W4 不得把 `chunkId` 当主键」。落地方式：

```text
index_generation(document_id, content_hash, parser_name, parser_version,
                 chunker_version, model_id, vector_dim, embedded_at)
```

- **能复用**的条件：`contentHash`、`parserName+parserVersion`、`chunkerVersion`、`modelId`、`vectorDim` **五项全等**。
- 任一项变化 → 该文件的块与向量**整组作废重写**（不做块级 diff：`chunkId` 里含块序号，改一处窗口全变，块级对齐是伪精度）。
- `document_id` 用 `FileMetadata.contentHash ?? FileMetadata.id`（与 `DefaultEmbeddingService` 现有取值一致，见 `embedding_service.dart:143`）。
- 删除：`DELETE FROM ... WHERE document_id = ?` + 关键词表按 `rowid` 级联（FTS5 external content 或手动双写，二选一，ADR 里写死）。

**Alternatives**：块级 diff（省重算，但块边界一变全错）、文件级全量重建每次（最省心，1454 块 37 s，可作为 `--force` 通道保留）。**默认走五项判等，`--force` 强制重建。**

### 决策 5：邻域扩展只在检索侧做，扩到「同页相邻块」，必要时整页

W3 把跨页答案明确移交 W4（`证据集说明.md` §4），且记录了一个坏消息：`sample.pdf` 两页是**同一篇说明的重复排版**，`ev-08/16/17` 记的是「同一证据出现在两页」，不是「半句续到下一页」。所以：

| 情形 | 处理 |
|---|---|
| 命中块在页中间 | 扩到同页 `chunkIndex ± 1`，拼成「命中段 + 上下文」 |
| 命中块在页首/页尾 | 扩到同页首/尾块；**不跨页拼接**（没有可靠断句证据，拼错比不拼更糟） |
| 过滤/排序 | **扩展发生在排序之后、返回之前**：先用块级分数排 Top-K，再对前 K 条做扩展。反过来会让长页挤占榜单 |
| 页码 | TXT/DOCX 的 `pageNumber` 为 null，**界面与结果都不得当真实页码展示**（`text_chunk.dart:17` 的约定，W3 已冻结） |

**跨页断句的通过标准仍定在「有真实跨页文档」时**。本周新增的邻域验证集必须用**真的跨块**样本（长 md 文件按 120 字符切后天然跨块），而不是继续用 `sample.pdf` 的重复排版——这点写进报告的限制章节。

### 决策 6：编排落 `packages/core_pipeline`，桌面端只装配

架构 §5 R1a 原文是「导入编排在应用组合根，可以依次调用 File I/O、Parsing、Embedding、Storage」。W4 的现实：没有 UI，`dart test` 跑不了 Flutter 组合根，而 W6 要 ≥90% 核心覆盖率。

| 方案 | 取舍 |
|---|---|
| **A（采用）`packages/core_pipeline`（纯 Dart）** | `IndexingPipeline` / `SearchPipeline` 可 `dart test`、可算覆盖率、可被 `bin/*_probe.dart` 直接调用；`apps/desktop` 在 W5 只做依赖装配 |
| B 硬守「只写在 `apps/desktop`」 | E2E 要 `flutter test`，覆盖率口径分裂，W6 的 90% 要重做 |

**这修改了已冻结的架构文档，必须在 ADR 0004 与 `docs/architecture/system-architecture.md` 同步一行**（新增第 4.5 层说明与目录映射），不许只改代码不改文档。

依赖方向保持不变：`core_pipeline → {core_parsing, core_embedding, core_storage, core_retrieval}`，且 `core_storage` 与 `core_retrieval` **互不依赖**（R1b）；`core_embedding` 不 import 存储。

### 决策 7：评测口径——6 臂消融 + 置信区间 + 冻结纪律

**25 条不是统计充分的样本**，所以本周的数字必须带着不确定性一起报，并且**逐题可审**。

| 臂 | 配置 | 目的 |
|---|---|---|
| A0 | 仅关键词（决策 3 三层） | 建立「不用向量也能拿到多少」的下界 |
| A1 | 仅 `documentText` 向量 | 纯语义文本 |
| A2 | 仅 `clipShared` 向量 | 纯跨模态（只能命中图像题） |
| A3 | A1 + A0，RRF | 混合检索的主假设 |
| A4 | A1 + A2 + A0，RRF（**默认配置**） | 完整三路 |
| A5 | A4 + 邻域扩展 | 邻域扩展的增量 |

| 指标 | 定义 | 何时用 |
|---|---|---|
| **Hit@5** | 前 5 条里至少一条相关 | 主指标，对应 PRD「Top 结果里能出现目标文件」 |
| **MRR@10** | 首个相关结果排名倒数的均值 | 主指标，衡量「排得够不够靠前」 |
| Recall@5/@10 | 多证据时相关证据被找回的比例 | `evidence_set.jsonl` 里 12 条有双文件证据，可用 |
| **Wilson 95% 区间** | 二项比例的区间估计 | **每个 Hit@5 都必须带**，n=15/10 时区间很宽，这正是要给人看的 |
| 工程指标 | 建库耗时、单次查询耗时（拆 检索 + embedding 查询向量） | 交 W6 |

**纪律**：

1. **dev 只用于选臂与选权重，holdout 只在最终报告出一次数**；报告里必须写明「holdout 被看过几次」。
2. 证据集已冻结（`2026-10-16T13:12:33Z`，sha256 有记录）。**本周不得改动这 25 条**。要加题就新建 `reports/week4/evidence_set_w4.jsonl`，单独标注用途（邻域扩展验证），**不并入冻结集、不参与调参**。
3. 25 条里**没有 no-answer 题**（`answerable` 全为 true）。所以「查不到时怎么办」本周**不出数**，只在报告的限制里写明——不许用 Hit@5 冒充「能判断无答案」。
4. **不许拿 COCO 的 image→caption 分数冒充检索精度**（W3 已划清），也不许拿 NQ 代理指标当检索完成度。

**Alternatives**：扩到 100+ 条（需要真实文档集，本周没有）、用官方 NQ passage 集（联网 + 体积，W3 已否）。

### 决策 8（并入决策 1 执行）：常驻运行时是前置条件

`engine/` 侧把「每向量一个进程」改成**一个进程服务多次前向**（`engine/embed_server.py`，stdin/stdout 行协议，或直接由 `core_pipeline` 的 `EmbeddingRuntime` 实现复用同一子进程）。约束：

- 仍走 `EmbeddingRuntime` 接口，单测注入假实现，**默认套件不加载模型**（延续 W3 覆盖率打法）。
- 协议要有**请求 id + 长度前缀**，避免半包；错误以结构化 JSON 回，不以 stderr 文案判断。
- 进程崩溃要能重启并**保留已完成记录**（对齐 `EmbeddingReport.cancelled` 的语义）。
- `session_load_ms` 计入**首次调用**，不计入每条；报告里两个数分列。

---

## 5. 任务拆分（WBS）

工时单位：小时。依赖列写任务编号。

### 阶段 A — 决策、对照基线与建包（Day 1 下午，5h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **A1** | 冻结存储与融合路线（决策 1/2/6/8） | `docs/architecture/adr/0004-vector-storage-and-fusion.md` 前四节 | 每节含 Decision / Alternatives / Consequences；显式写出与 PDF「Chroma 进运行时」的偏差及理由 | — | 1 |
| **A2** | W3 向量导出 + **Chroma 对照基线** | `reports/week4/vectors/w3_samples.jsonl`（97 条：space/dim/modelId/chunkId/values）、`engine/chroma_baseline.py`、`reports/week4/logs/chroma_baseline.txt` | Chroma 集合必须 `hnsw:space=cosine`；25 题跑出 Hit@5/MRR@10，并记录 `chromadb` 版本 | — | 1.5 |
| **A3** | 关键词通道方案定稿 + 最小验证（决策 3） | `reports/week4/logs/keyword_probe.txt` | bigram 预切在真实 md 语料上：两字中文查询命中率 >0；记录 `unicode61=0` 的反例 | — | 0.5 |
| **A4** | 建三个包并冻结 public API | `packages/core_{storage,retrieval,pipeline}/{pubspec.yaml,analysis_options.yaml}` | `dart pub get --offline` 成功、`dart analyze` 0 issue；`core_storage` 只依赖 `sqlite3` 与 `ffi`/`path` | — | 1 |
| **A5** | Q2 / Q5 结案 + 架构文档同步（决策 6 的目录与分层） | TDD §4 的 Q2/Q5 更新；`docs/architecture/system-architecture.md` 增加 `core_pipeline` 说明 | 两条都有结论与理由；架构文档的目录映射与依赖规则同步 | — | 0.5 |
| **A6** | 常驻运行时落地（决策 8） | `engine/embed_server.py` + `core_pipeline` 侧的 `PersistentOnnxRuntime` | 同一批 24 条文本，中位 ≤30 ms/条；进程崩溃可重启并保留已完成记录 | — | 0.5 |

**阶段出口**：**H1 存储等价门槛通过**——同一批向量、同一批查询，Chroma 与 Dart+SQLite 的 Top-5 一致率 ≥96%。这一步不过，后面所有精度数字都是在错排名上算的。

### 阶段 B — 向量存储（Day 2，7h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **B1** | schema + 迁移 + WAL + 库定位接口 | `lib/src/schema.dart`、`lib/src/sqlite_library_locator.dart`、`lib/src/store_opener.dart` | 建表幂等；`journal_mode=wal` 生效；找不到 DLL 时返回结构化失败而非崩溃；schema 版本号可迁移 | A4 | 1.5 |
| **B2** | 批量写入（事务 + fp32 BLOB） | `lib/src/vector_writer.dart` | 10k 块 ≤0.6 s（实测基线 103 ms@1.5k、528 ms@10k）；写入中途失败可整体回滚 | B1 | 1.5 |
| **B3** | 向量查询（暴力余弦 + filters + Top-K） | `lib/src/vector_query.dart` | 384 维 10k 块 ≤60 ms；`filters` 在 SQL 层生效（`EXPLAIN QUERY PLAN` 有证据）；`space` 不符抛异常 | B2 | 1.5 |
| **B4** | 关键词索引（bigram + FTS5 trigram + LIKE 兜底） | `lib/src/keyword_index.dart` | 两字中文、三字中文、英文、混合查询四类各有用例；`LIKE` 路径有 `LIMIT` | B1 | 1.5 |
| **B5** | 删除 / 清空 / 统计 / 代次表（决策 4） | `lib/src/maintenance.dart`、`lib/src/index_generation.dart` | 五项判等可复用判定；`--force` 路径可整组重建；删除后 FTS 与向量表一致（有用例） | B2,B4 | 1 |

**阶段出口**：`core_storage` 单测全绿、覆盖率 ≥85%；10k 块写入与查询达标。

### 阶段 C — 混合检索（Day 3，7h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **C1** | 查询向量构造（两空间各一次） | `lib/src/query_encoder.dart` | 一次 `search` 只调两次 `embed`（`documentText` + `clipShared`）；图像塔不可用时降级而非报错 | A6,B3 | 1 |
| **C2** | 三路召回 + RRF 融合（决策 2） | `lib/src/rrf_fusion.dart`、`lib/src/retriever.dart` | `k=60` 可配置；单路缺失自动降权；tie-break 与 ADR 一致且有用例 | C1 | 2 |
| **C3** | filters + Top-K + `SearchResult` 值对象 | `lib/src/model/search_result.dart`、`lib/src/model/search_filters.dart`（内部转成 `StorageFilter` 传给存储层） | `SearchResult` 含 `relativePath`/`fileName`/`mimeType`/`pageNumber`/`startOffset`/`endOffset`/`textUnit`/`snippet`/`score`/`channels`/`modality`；**不含颜色语义**（架构 §12 第 3 条） | C2 | 1.5 |
| **C4** | 邻域扩展（决策 5） | `lib/src/neighborhood.dart` | 页中扩 ±1 块、页首页尾只扩同侧、不跨页；扩展在排序之后；有跨块真实样本用例 | C3 | 1.5 |
| **C5** | 单测补齐 | `test/**` | 覆盖率 ≥70%（阶段门槛），配假 store 与假 runtime | C1–C4 | 1 |

**阶段出口**：dev 上融合臂不低于任一单通道（**H2**）；跨块题能扩出上下文。

### 阶段 D — 端到端与 MVP（Day 4，7h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **D1** | `IndexingPipeline` / `SearchPipeline` | `lib/src/indexing_pipeline.dart`、`lib/src/search_pipeline.dart` | 只消费 `IngestionReport.indexable`，不重新读盘（R2）；两段都可取消、有 `processed/total` 进度 | B5,C4 | 2 |
| **D2** | 增量重建（代次键） | `lib/src/incremental.dart` | 内容不变的文件第二次建库 `skipped`；改一个文件只重算该文件（有计时对比） | D1 | 1.5 |
| **D3** | MVP 命令行 | `bin/index_probe.dart`、`bin/search_probe.dart` | `--path <目录> --db <路径>` 建库；`--query "…" --top 10` 出结果，逐条打印出处与偏移；沿用 `probe_common.dart` 风格 | D1 | 1.5 |
| **D4** | 真实语料联调 | `reports/week4/logs/e2e_samples.txt`、`reports/week4/logs/e2e_docs.txt` | `datasets/samples` 3 文件 + 仓库 20 份 md 都能建库并检索；记录建库总耗时与单次查询耗时 | D3 | 1.5 |
| **D5** | 取消 / 断点 / 坏文件隔离 | `reports/week4/logs/e2e_cancel.txt` | 建库中途取消，已写入记录保留且索引自洽（可继续查）；坏文件不中断整批 | D4 | 0.5 |

**阶段出口**：**H3 通过**——断网、中文问句、Top-5 命中目标文件、给出页/段与偏移、原文件路径存在。

### 阶段 E — 测试与精度基准（Day 5，7h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **E1** | E2E 功能用例集（E2E-01～E2E-12） | `reports/week4/logs/e2e_*.txt`、`reports/week4/screenshots/` | 12 条用例覆盖：建库、重建、增量跳过、单查询、多查询、过滤（扩展名/路径/时间）、图像题、跨块邻域、取消、坏文件、空库查询、清库 | D5 | 2 |
| **E2** | 精度基准 6 臂消融（决策 7） | `engine/eval_retrieval.py`、`reports/week4/logs/retrieval_bench_dev.txt` 与 `reports/week4/logs/retrieval_bench_holdout.txt` | A0–A5 各出 Hit@5 / MRR@10 + Wilson 区间；dev/holdout 分列；`parameters_changed_after_freeze` 计数为 0 | D4 | 2 |
| **E3** | 邻域验证集（新建，独立于冻结集） | `reports/week4/evidence_set_w4.jsonl`、`reports/week4/证据集说明_w4.md` | 10–15 条，**必须含真实跨块样本**（长 md 切块后跨块），标 `crossChunk: true`；与冻结集分开统计 | D4 | 1.5 |
| **E4** | 覆盖率 ≥85% 落盘 | `reports/week4/coverage/*.lcov.info`、`reports/week4/覆盖率报告.md` | 三个新包各自 ≥85%；`core_parsing` 不回退、`core_embedding` 不低于 85% | E1 | 1 |
| **E5** | 离线自查 | `reports/week4/logs/offline_check.txt` | `lib/` 下无 `HttpClient`/`Socket`/`http` 引用（grep 门禁 + 用例）；断网跑一遍建库与检索 | E1 | 0.5 |

**阶段出口**：ablation 表出数；覆盖率证据落盘；离线自查可复现。

### 阶段 F — 报告与收尾（Day 6，7h）

| 编号 | 任务 | 具体产出 | 完成判据 | 依赖 | 工时 |
|---|---|---|---|---|---|
| **F1** | 端到端功能测试报告 | `reports/week4/W04_report.md` | 沿用 W2/W3 体例：用例 ID — 命令 — 期望 — 实际 — 判定 — 证据；含环境、用例统计表、交付物表、证据索引、截屏 | E1–E5 | 2 |
| **F2** | 检索精度基准报告 | `reports/week4/检索精度基准报告.md` | 6 臂表 + 置信区间 + 逐题通过表 + 已知限制（n=25/无 no-answer 题/跨页样本性质） | E2,E3 | 2 |
| **F3** | API 文档 + ADR 定稿 + 架构同步 | `docs/api/storage-module-api.md`、`docs/api/retrieval-module-api.md`、ADR 0004 全文 | 每个 public 符号有签名/参数/异常/示例；ADR 八节齐备 | A1–E5 | 1.5 |
| **F4** | 交付物自检 | 本文件 §11 的清单逐条打勾 | 四份 PDF 交付物可逐条点开；`git status` 无意外文件 | F1–F3 | 1.5 |

**合计 40h**（A 5 + B 7 + C 7 + D 7 + E 7 + F 7）。

> 说明：报告不是最后一天才开始写。A–E 每个任务完成时就把原始输出写进 `reports/week4/logs/`，F 只做汇总与定稿。

### 5.1 关键路径与并行机会

```text
A1 ─┬─ A2 ──(H1)──┐
    ├─ A3 ────────┤
    └─ A4 ── B1 ──┴─ B2 ─┬─ B3 ─┐
                          └─ B4 ─┴─ B5 ── D1 ─┬─ D2
                                               ├─ D3 ── D4 ─┬─ E1 ─┬─ E4
    A6 ────────────────────────── C1 ── C2 ── C3 ── C4 ── C5 ──┘     ├─ E2 ── F2
                                                                    └─ E5
    A5 ── F3（文档可提前起草）
```

- **关键路径**：A1 → A2/H1 → B1 → B2 → B3 → C2 → C3 → C4 → D1 → D3 → D4 → E2 → F2。
- **可并行**：A3（关键词探针）与 A2 无耦合；A6（常驻运行时）与 B 阶段无耦合，但 C1 依赖它；`core_retrieval` 的 C1–C5 在 `core_storage` 的 B3 落地后即可用假 store 并行开工。
- **范围收缩顺序**（万一要砍）：先保 A1–A2/H1 → B1–B4 → C1–C3 → D1/D3/D4（H3）→ E1/E2。把 C4（邻域扩展）、E3（邻域验证集）、A3（关键词探针改为直接照决策 3 实现）降级。**H1 与 H3 永远最先做**。

---

## 6. 六天排期

| 日 | 上午 | 下午 | 当日出口 |
|---|---|---|---|
| **Day 1**（10/20 下午，5h） | — | A1 决策冻结 → A2 向量导出与 Chroma 对照 → A3 关键词探针 → A4 建包 → A5 结案 → A6 常驻运行时 | **H1 通过**：两条存储路线 Top-5 一致率 ≥96% |
| **Day 2**（10/21，7h） | B1 schema/定位 → B2 批量写入 | B3 向量查询 → B4 关键词索引 → B5 维护与代次表 | 10k 块 ≤0.6 s 写入、≤60 ms 查询；两字中文可命中 |
| **Day 3**（10/22，7h） | C1 查询编码 → C2 RRF 融合 | C3 filters 与 `SearchResult` → C4 邻域扩展 → C5 补测 | **H2 通过**：融合臂不低于任一单通道 |
| **Day 4**（10/23，7h） | D1 编排 → D2 增量重建 | D3 MVP 命令行 → D4 真实语料联调 → D5 取消与坏文件 | **H3 通过**：中文问句 Top-5 命中目标文件并给出出处 |
| **Day 5**（10/24，7h） | E1 E2E 用例 → E3 邻域验证集 | E2 六臂消融 → E4 覆盖率 → E5 离线自查 | 12 条 E2E 全绿；ablation 出数；覆盖率 ≥85% |
| **Day 6**（10/25，7h） | F1 端到端报告 | F2 精度基准报告 → F3 API/ADR/架构 → F4 自检 | 四份交付物齐全、可逐条点开 |

每天收工前把当天原始输出写进 `reports/week4/logs/`；**每个阶段的出口判据不满足就不要进下一阶段**——W2/W3 都证明了前置卡住时后补的代价更大。

---

## 7. 验收命令清单（逐条可复制）

```powershell
# 0) 前置：Java（PDF 路径）、Python 评测环境、系统 SQLite
java -version
engine\.venv\Scripts\python.exe --version
Test-Path C:\Windows\System32\winsqlite3.dll

# 1) 计划阶段的探针（已跑，产物在 reports/week4/probes/）
engine\.venv\Scripts\python.exe reports\week4\probes\probe_persistent_runtime.py > reports\week4\probes\probe_persistent_runtime.txt
engine\.venv\Scripts\python.exe reports\week4\probes\probe_sqlite_capacity.py  > reports\week4\probes\probe_sqlite_capacity.txt
cd reports\week4\probes\dart_store_probe; dart pub get; dart run bin\probe.dart > ..\dart_store_probe.txt; cd ..\..\..\..

# 2) 三个新包：静态检查 + 默认单测
foreach ($p in 'core_storage','core_retrieval','core_pipeline') {
  Push-Location "packages\$p"
  dart pub get --offline
  dart analyze
  dart test --exclude-tags integration
  Pop-Location
}

# 3) 存储等价门槛（H1）
engine\.venv\Scripts\python.exe engine\export_vectors.py --path datasets\samples --out reports\week4\vectors\w3_samples.jsonl
engine\.venv\Scripts\python.exe engine\chroma_baseline.py > reports\week4\logs\chroma_baseline.txt
dart run packages\core_pipeline\bin\search_probe.dart --db reports\week4\.index\samples.sqlite --query "这份说明在能够被完全信任之前，还要求人做什么？" --top 5 --json > reports\week4\logs\dart_top5.json
engine\.venv\Scripts\python.exe engine\compare_ranking.py reports\week4\logs\dart_top5.json > reports\week4\logs\storage_equivalence.txt

# 4) MVP：建库 + 检索（G2）
dart run packages\core_pipeline\bin\index_probe.dart  --path datasets\samples --db reports\week4\.index\samples.sqlite
dart run packages\core_pipeline\bin\search_probe.dart --db reports\week4\.index\samples.sqlite --query "工具靠什么判断文件类型？" --top 10
dart run packages\core_pipeline\bin\index_probe.dart  --path docs --db reports\week4\.index\docs.sqlite
dart run packages\core_pipeline\bin\index_probe.dart  --path docs --db reports\week4\.index\docs.sqlite   # 第二次应全 skipped

# 5) 覆盖率（G8）
foreach ($p in 'core_storage','core_retrieval','core_pipeline') {
  Push-Location "packages\$p"
  dart test --coverage=coverage --exclude-tags integration
  dart run coverage:format_coverage --lcov --in=coverage --out=coverage\lcov.info --report-on=lib --package=.
  Pop-Location
}

# 6) 精度基准（G4）
engine\.venv\Scripts\python.exe engine\eval_retrieval.py --arms A0,A1,A2,A3,A4,A5 --split dev     > reports\week4\logs\retrieval_bench_dev.txt
engine\.venv\Scripts\python.exe engine\eval_retrieval.py --arms A4 --split holdout                > reports\week4\logs\retrieval_bench_holdout.txt

# 7) 离线自查（E5）
Get-ChildItem packages\core_storage\lib,packages\core_retrieval\lib,packages\core_pipeline\lib -Recurse -Include *.dart |
  Select-String -Pattern 'HttpClient|Socket|import .http|package:http' | Out-File reports\week4\logs\offline_check.txt
```

---

## 8. 评测口径设计

### 8.1 四条纪律（延续 W3，本周第一次真正用上）

1. **分层，不混**。检索级指标（Hit@5/MRR@10）与工程指标（建库/查询耗时）单列；W3 的 embedding 级与转换等价性不重跑、不冒充。
2. **Hit@K ≠ Recall@K**。`evidence_set.jsonl` 里 12 条有双文件证据，多证据题必须报 Recall，单证据题才可只报 Hit。
3. **不要用替代实验冒名顶替**。只有 25 条就报 25 条 + 置信区间；不许拿 COCO image→caption 或 NQ 代理分数当检索精度。
4. **冻结后再调参**。dev 选臂与选权重，holdout 只出最后一次数，并记录被看过几次。

### 8.2 为什么必须带 Wilson 区间

n=15（dev）时，Hit@5=0.80 的 95% Wilson 区间约 **[0.55, 0.93]**；n=10（holdout）时约 **[0.49, 0.94]**。**区间这么宽，正是必须写出来的理由**——否则「Hit@5 从 0.73 提到 0.80」会被读成进步，而它可能只是抽样噪声。

报告里每个比例都要写成 `0.80 [0.55, 0.93] (12/15)` 这种三件套。

### 8.3 逐题可审

`reports/week4/logs/retrieval_bench_*.txt` 每题一行：

```text
ev-01 split=dev hit@5=1 rank=2 channels=docvec,keyword top5=[ev-01@2, ev-03@1, ev-07@4, ...]
```

出错时能立刻看出是「没召回」还是「召回但排太后」，而不是只有一个总数。

### 8.4 检索精度报告必须包含的数字

每个臂一行：配置、dev Hit@5（含区间）、dev MRR@10、holdout Hit@5（含区间）、holdout MRR@10、建库耗时、单次查询耗时（拆 向量化 + 存储查询 + 融合）、**已知限制**（样本量、无 no-answer 题、跨页样本性质、图像题只有 10 条）。

### 8.5 与 W3 四层指标的关系（不许混账）

| 层 | 指标 | W3 | W4 |
|---|---|---|---|
| 转换等价性 | 余弦 ≥0.999 | 已出数 | 不重跑 |
| embedding 级 | NQ 300 题 recall@1/@5、MRR（代理） | 已出数 | 不重跑 |
| **检索级** | **冻结集 Hit@5、MRR@10；多证据 Recall@5/10** | 只建集 | **本周出数（主交付）** |
| 生成级 | 答案正确性、引用支撑 | 未规划 | 仍未规划 |

---

## 9. W4 专项风险与应对

| 风险 | 触发信号 | 应对（本周内可执行） |
|---|---|---|
| **R2 存储接不进（原「高」，本周降级）** | Chroma 需要常驻服务、或 `sqlite3` 原生编译失败 | 决策 1 已改为「系统 SQLite + Chroma 只做对照」，本机已实测通过，风险降为**低**；残余风险是 `winsqlite3.dll` 属未文档化用途 |
| **词法通道静默 0 命中（本周最大坑）** | 中文两字查询关键词通道无结果、且不报错 | 决策 3 三层方案；**A3 必须先跑出反例日志**（`unicode61=0`）再实现；单测固定四类查询 |
| **两条存储路线排名不一致** | H1 一致率 <96% | 先查三处：Chroma 是否设 `hnsw:space=cosine`、向量是否真的 L2 归一化、tie-break 是否一致。**H1 不过不许做融合** |
| **跨空间分数被硬比** | 有人把 384 与 512 的余弦放一个数组排序 | 决策 2 用 RRF（只用名次）；`space` 不符时 `EmbeddingEngine` 已抛异常，存储层再抛一次 |
| **融合没有增益（H2 不过）** | A3/A4 ≤ max(A1, A0) | **如实报**并分析：可能是关键词通道太弱、或语料本身语义稀薄。不许只调 dev 硬凑；结论写进 ADR |
| **25 条样本太小被过度解读** | 报告只写「Hit@5 = 0.80」 | 每个比例强制带 Wilson 区间 + 逐题表；限制章节明写「不构成统计充分性」 |
| **无 no-answer 题** | 有人问「查不到时会怎样」 | 本周**不出数**，写进限制；W5 的 UI 不得承诺「会告诉你没找到」 |
| **`chunkId` 被当主键** | 增量更新按 `chunkId` 对齐 | 决策 4 五项代次键；ADR 0003 的 Follow-up 已挂账，本周勾掉 |
| **邻域扩展把榜单挤坏** | 长页文件占据 Top-K | 决策 5：**先排序后扩展**，扩展不参与打分 |
| **W3 的 2 s/向量拖垮建库** | 全量建库 >10 min | A6 常驻运行时（实测 54×）；建库计时必须拆「模型加载 / 单条推理 / 存储写入」三段 |
| **系统 DLL 换机器就没了** | 另一台 Windows 或 CI 上找不到 `winsqlite3.dll` | `SqliteLibraryLocator` 接口 + 结构化失败；W8 决定是否自带 `sqlite3.dll`，本周只记录 |
| **`package:sqlite3` 大版本升级破坏性** | 有人 `pub upgrade` 到 3.x | `pubspec.yaml` 锁 `^2.9.0`（3.x 需 build hook 与 `native_toolchain_c`）；`.gitignore` 已忽略 `pubspec.lock`，故**在 README 与 ADR 里写死版本理由** |
| **离线承诺被依赖破坏** | 某个包引入了网络代码 | E5 grep 门禁 + 断网实跑；`core_storage`/`core_retrieval`/`core_pipeline` 的 pubspec 依赖白名单写进 ADR |
| **编排落点改动被当成违规** | 有人指出 R1a 写的是「组合根」 | 决策 6 已有 Alternatives 与理由；**同步改架构文档**，不留「代码与文档不一致」 |
| **覆盖率掉到 85% 以下** | Day 3 结束 <70% | 延续 W2/W3 打法：DLL 定位、进程、存储全部经接口注入，适配器用假实现覆盖；`sqlite3` 用内存库做真实用例（不需要文件系统） |
| **MobileCLIP 权重不能进公开包** | W8 打包时发现图像通道依赖受限权重 | ADR 0003 决策 5 已定；W4 的图像通道只在**本机研究用途**验证，报告注明，W8 再决定公开版的图像能力 |

---

## 10. W4 明确不做（Scope Guard）

- ❌ Flutter UI、四个界面、`Semantics`、焦点顺序、高对比、字号（W5）
- ❌ 无障碍扫描（Accessibility Scanner / WAVE）与可用性测试（W5）
- ❌ **生成闭环**：回答、引用支撑、拒答行为（PRD 与交付清单都没有，W3 §0.1 已判为范围扩张）
- ❌ OCR 与 RVL-CDIP 标注（Q4，W6）
- ❌ ANN / HNSW / IVF 索引（10k 块 52 ms 已够，MVP 用精确检索更好解释）
- ❌ 多后端向量库插件体系（只保留系统 SQLite 一个实现 + 一个 `SqliteLibraryLocator` 注入缝）
- ❌ 中文分词词典（jieba 等），只用 bigram
- ❌ 把 `engine/` 或 Python 解释器带进发布包（Q2 已结案）
- ❌ 模型重训、微调、量化二次尝试（W3 的 fp32 已过 0.999 门槛）
- ❌ 全量数据集（NQ passage / COCO 全集 / Wikipedia dump）
- ❌ worker isolate 化（Q6，W6）
- ❌ PDFium 替换 Tika（Q1 已结案，`process_wait` 99% 的问题留 W6 性能周）

---

## 11. 交付物清单（W4 仓库预计新增的文件）

```text
packages/core_storage/
  pubspec.yaml  analysis_options.yaml  README.md  dart_test.yaml
  lib/core_storage.dart
  lib/src/{schema,store_opener,sqlite_library_locator,vector_writer,vector_query,
            keyword_index,maintenance,index_generation}.dart
  lib/src/model/{stored_vector,stored_chunk,index_stats,storage_failure,storage_filter}.dart
  test/**（内存库真实用例 + 假 locator）

packages/core_retrieval/
  pubspec.yaml  analysis_options.yaml  README.md  dart_test.yaml
  lib/core_retrieval.dart
  lib/src/{query_encoder,rrf_fusion,retriever,neighborhood}.dart
  lib/src/model/{search_result,search_filters,search_channel}.dart
  test/**

packages/core_pipeline/
  pubspec.yaml  analysis_options.yaml  README.md  dart_test.yaml
  lib/core_pipeline.dart
  lib/src/{indexing_pipeline,search_pipeline,incremental,persistent_onnx_runtime}.dart
  bin/{index_probe,search_probe,probe_common}.dart
  test/**

engine/
  chroma_baseline.py   export_vectors.py   compare_ranking.py   eval_retrieval.py
  embed_server.py      （常驻推理进程，W3 的 embed_text_hidden.py 保留作单次对照）

docs/
  architecture/adr/0004-vector-storage-and-fusion.md
  architecture/system-architecture.md          ← 增加 core_pipeline 的目录与分层说明
  api/storage-module-api.md
  api/retrieval-module-api.md
  tdd/technical-design-document.md             ← Q2/Q5 结案

reports/week4/
  W04_task_plan.md（本文件）      W04_report.md        检索精度基准报告.md
  覆盖率报告.md                   evidence_set_w4.jsonl  证据集说明_w4.md
  probes/（三个探针 + 原始输出；dart_store_probe/ 是独立的探针包）
  vectors/w3_samples.jsonl        logs/                coverage/       screenshots/

apps/desktop/pubspec.yaml                       ← 增加 core_pipeline 的 path 依赖（仍未接 UI）
```

---

## 附录 A：接口骨架（Day 1 冻结，与实现一致）

```dart
/// 向量与正文在本地索引里的一条记录。`chunkId` 只作回指，不是主键。
@immutable
class StoredChunk {
  final String documentId;      // contentHash ?? FileMetadata.id
  final String chunkId;         // 来自 TextChunk，不稳定
  final String relativePath;
  final String fileName;
  final String? mimeType;
  final int? pageNumber;        // TXT/DOCX 为 null，界面不得当真实页码
  final int startOffset;        // UTF-16 code unit，含首
  final int endOffset;          // 不含尾
  final String body;
  final Object? imageAsset;     // Modality == image 时有值
  final Modality modality;      // text | image
}

/// 存储层的唯一注入缝：sqlite3 动态库从哪来。
/// 单测注入内存实现；`winsqlite3.dll` 只是默认实现之一。
abstract interface class SqliteLibraryLocator {
  /// 找不到时返回结构化失败，不抛未捕获异常。
  SqliteOpenResult open(String databasePath);
}

/// 存储层的过滤条件。**必须是存储层自己的类型**——检索层的 `SearchFilters`
/// 可以由它派生，但反过来不行，否则 core_storage 就要 import core_retrieval（违 R1b）。
@immutable
class StorageFilter {
  final Set<String>? extensions;      // {'.pdf', '.md'}
  final String? pathPrefix;           // relativePath 前缀
  final DateTime? modifiedAfter;
  final Modality? modality;
  const StorageFilter({this.extensions, this.pathPrefix, this.modifiedAfter, this.modality});
}

/// 向量存储：写入、查询、删除、统计。不打分、不融合（R1b）。
abstract interface class VectorStore {
  Future<WriteOutcome> write(Iterable<StoredChunk> chunks, Iterable<EmbeddingVector> vectors);
  Future<List<ScoredId>> search(
    EmbeddingVector query, {          // space 决定落到哪张表
    StorageFilter? filter,
    int topK = 50,
  });
  Future<List<ScoredId>> keyword(String query, {StorageFilter? filter, int topK = 50});
  Future<void> deleteDocument(String documentId);
  Future<void> clear();
  Future<IndexStats> stats();
}

/// 检索层：三路召回 + RRF 融合 + 邻域扩展。不碰文件系统。
abstract interface class Retriever {
  Future<List<SearchResult>> search(
    String query, {
    SearchFilters? filters,
    int topK = 10,
    CancellationToken? cancel,
  });
}

/// 一条结果。字段足够读屏直接播报，不需要再访问文件系统（架构 §12 第 4 条）。
@immutable
class SearchResult {
  final String relativePath;
  final String fileName;
  final String? mimeType;
  final int? pageNumber;
  final int startOffset;
  final int endOffset;
  final TextUnit textUnit;
  final String snippet;
  final double score;
  final Set<SearchChannel> channels;   // 命中来自哪几路，可文本化
  final Modality modality;
}

/// 端到端编排（决策 6）：只在组合根装配，内部按层调用。
abstract interface class IndexingPipeline {
  Future<IndexReport> index(
    String rootPath, {
    void Function(IndexProgress)? onProgress,
    CancellationToken? cancel,
    bool force = false,
  });
}

abstract interface class SearchPipeline {
  Future<List<SearchResult>> search(String query, {int topK = 10});
}
```

## 附录 B：与 W3 / W5 / W6 的接缝

| 接缝 | 约定 |
|---|---|
| W3 → W4 | 只消费 `IngestionReport.indexable` 与 `EmbeddingReport`；**不重新解析、不重新切块** |
| W3 → W4（空间） | 两个空间两张表，`space` 不符抛异常；**禁止跨空间算余弦** |
| W3 → W4（`chunkId`） | 只作回指；增量判定用五项代次键 |
| W3 → W4（证据集） | 冻结的 25 条**原样使用、不改不删**；新增题另建文件 |
| W4 → W5 | UI 只经 `Retriever` 拿 `SearchResult`，不直接调 embedding/存储；`pageNumber == null` 时不得显示页码；进度同时带 `processed` 与 `total` |
| W4 → W6 | 交出建库/查询三段计时基线；覆盖率口径与假实现打法延续；Q6（isolate）由 W6 用真数据定 |
| W4 → W7 | API 文档已定稿，W7 只做「架构深潜 + 维护手册」的汇编 |
| W4 → W8 | 系统 SQLite 的依赖形态（自带 `sqlite3.dll` 与否）与 MobileCLIP 权重的分发方式，W8 定 |
| 测试约定 | 真模型、真数据集用例一律带 `integration` 标签；默认套件不依赖 JDK、不依赖模型文件、不依赖 DLL 以外的网络 |
| 证据约定 | 每个任务的原始输出落 `reports/week4/logs/`，报告体例沿用 `reports/week2/W02_report.md` |
