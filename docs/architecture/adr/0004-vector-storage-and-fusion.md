# ADR 0004：向量存储、融合与编排落点

| 项目 | 内容 |
|---|---|
| 状态 | **Accepted**（已采纳） |
| 日期 | 2026-10-20 |
| 决策者 | Week 4 阶段 A |
| 影响范围 | 存储层、检索层、导入/检索编排；W5 只经检索层拿结果；W8 是否自带 `sqlite3.dll` |
| 相关文档 | `reports/week4/W04_task_plan.md` 决策 1–8；`docs/tdd/technical-design-document.md` Q2、Q5 |

---

## Context（背景）

Week 4 要把已经算出来的两个空间的向量放进本地索引，并回答「一句不含文件名的话，能不能在 Top-5 里找到目标文件」。开工时的事实：

| 事实 | 证据 |
|---|---|
| 产品侧还没有向量库。`engine/chroma_data/` 只有 Week 1 的 `week1_smoke` | 仓库现状 |
| `chromadb 1.5.9` 已装在 `engine/.venv`。pub.dev 上的 Dart `chromadb 2.0.0` 是 HTTP 客户端，要另起一个服务进程 | `reports/week4/W04_task_plan.md` §1.1 |
| 本机 `C:\Windows\System32\winsqlite3.dll` 是 SQLite 3.53.4，FTS5 / JSON1 / WAL 可用。`package:sqlite3` 2.9.4 在找不到 `sqlite3.dll` 时回退到 `winsqlite3.dll`，Dart 探针已跑通 | `reports/week4/probes/probe_sqlite_capacity.txt`、`reports/week4/probes/dart_store_probe.txt` |
| 384 维 fp32、1 万块的暴力余弦中位 51.9 ms，写入 528 ms | 同一份 Dart 探针 |
| FTS5 默认 `unicode61` 把整段中文当成一个 token。两字查询命中数是 0，而且不报错。`trigram` 要至少 3 个字 | 同一份探针的 token 表 |
| W3 的大约 2 秒/向量几乎全是进程启动和模型加载。常驻进程的前向中位是 25.5 ms，加速比 54.3 | `reports/week4/probes/probe_persistent_runtime.txt` |
| `chunkId` 含块序号和窗口参数，不是稳定主键 | ADR 0003，`text_chunker.dart` |
| 发布包不能带 `engine/`，也不能把 MobileCLIP 权重打进公开安装包 | TDD Q2 的原倾向；ADR 0003 决策 5 |

官方 Week 4 原文写的是 “Integrate Chroma DB”。下面各节说明产品运行时为什么不把 Chroma 进程放进去，以及 Chroma 仍然要做的那一件事。

---

## 决策 1：产品用系统 SQLite，Chroma 只做对照

**产品运行时用 Dart + 系统 SQLite。Chroma 留在 `engine/`，用同一批向量做排名对照。`engine/` 不进发布包。**

| 子问题 | 选择 |
|---|---|
| 产品存储 | 系统 SQLite（Windows 上由 `package:sqlite3` 2.x 回退到 `winsqlite3.dll`）加自有向量表。不采用 Dart `chromadb` HTTP 客户端，也不在本周自带一份编译出来的 `sqlite3.dll` |
| 评测对照 | `engine/.venv` 里的 `chromadb 1.5.9` 建集合，和产品路线比 Top-5 |
| 度量 | 集合必须显式 `hnsw:space=cosine`。向量已经 L2 归一化，用默认 L2 会在近似并列处把名次翻掉 |
| 向量存法 | fp32 小端 BLOB。不用 JSON 文本 |
| 动态库定位 | `SqliteLibraryLocator` 接口。默认实现走 `package:sqlite3` 的加载顺序，不把 `C:\Windows\System32\winsqlite3.dll` 写死。找不到库时返回结构化失败 |
| 依赖版本 | `sqlite3: ^2.9.0`。3.x 要 build hook 和 `native_toolchain_c`，三平台打包成本留到 W8 再决定 |

`winsqlite3.dll` 是随系统分发的未文档化用途，`package:sqlite3` 自己的注释也这么写。这条记入风险。W8 决定公开包是继续用系统库，还是改成自带 `sqlite3.dll`。

### 运行时（决策 8）

常驻推理是本周的前置条件，不是事后优化。`engine/embed_server.py` 一个进程加载一次模型，用长度前缀加请求 id 的帧协议服务多次前向。错误是结构化 JSON，不靠 stderr 的文案判断。进程退出后，下一次调用重新拉起；已经返回给调用方的向量保留，不因为重启被清掉。模型加载时间算在第一次调用上，不摊进每一条。

单测注入假连接，默认套件不加载 `model.onnx`。`engine/embed_text_hidden.py` 保留，作为每向量一次进程的对照，不删。

#### Alternatives（运行时）

| 方案 | 为什么没选 |
|---|---|
| **A. 每个向量起一次进程**（W3 现状，`embed_text_hidden.py`） | 实测每条 1382 ms，其中推理只有 25 ms，其余是进程启动与 470 MB 模型加载。全仓库 1454 块要 33.5 分钟，建库不可用。保留为对照，不作主路径 |
| **B. 常驻进程 + 逐条前向**（采用） | 实测中位 25.5 ms/条，加速 54.3×；1454 块约 37 秒。协议要自带请求 id 与长度前缀，否则半包无法定位 |
| **C. 常驻进程 + 批前向** | 实测 batch=8 为 21.9 ms/条、batch=16 为 24.0 ms/条，**反而不如单条 25.5 ms**。本机 CPU 上没有批收益，且批会拉高首字节延迟、恶化取消粒度。不做 |
| **D. Dart 进程内 TFLite（`libtensorflowlite_c`）** | 通过 0.999 门槛的产物是 ONNX fp32，DLL 加载不了；`native/tflite/windows/` 至今为空。ADR 0003 决策 4 已把进程内推理推到 W8 |

#### Consequences（运行时）

- 建库从「几十分钟」回到「几十秒」量级，W4 的增量重建与反复回归才有可行性。
- 代价一：产品路径依赖 `engine/.venv` 里的 Python 与 onnxruntime。**这不是发布形态**，Q2 已结案 `engine/` 不进发布包；W8 要换成进程内运行时，届时 `EmbeddingRuntime` 接口不变。
- 代价二：多一层 IPC（长度前缀 + base64 隐藏态），e2e 中位 30.5 ms，比纯前向 28.0 ms 多约 2.5 ms。这条开销记在 `logs/embed_server_median.txt`。
- 代价三：常驻进程是有状态服务，必须处理崩溃重启。重启后已返回给调用方的向量保留，未完成的那一条由调用方重试；这条语义与 `EmbeddingReport.cancelled` 一致。
- 约束：**默认套件不得加载模型**。凡需要真模型的用例一律打 `integration` 标签，否则换机器即红。

### Alternatives（存储）

| 方案 | 为什么没选 |
|---|---|
| **A. Chroma 进产品运行时** | 要 Python 或第二个常驻进程。Q2 已经否定把 `engine/` 打进发布包。W8 还要打三个桌面平台 |
| **B. 纯内存索引** | 大约 1454 块的常驻重建要几十秒，进程一关索引就没了 |
| **C. 自研二进制索引文件** | 过滤、删除、事务都要重写。SQLite 已经提供这些 |
| **D. 自带编译的 `sqlite3` 3.x** | 本机系统库已经够用。原生编译链留到 W8 的打包决策 |

### Consequences（存储）

- 存储层依赖 `sqlite3` 2.x、`ffi`、`path`，以及 `EmbeddingVector` 这个值类型。它调用不了嵌入器。
- 两个空间分表查询。维度或 `normalized == false` 直接拒绝，因为余弦被实现成点积。
- H1：同一批向量、同一批查询，Chroma 与 Dart+SQLite 的 Top-5 一致率不低于 96%。2026-10-26 用当前两份 jsonl 重跑 `engine/compare_ranking.py`：125 个位置全部一致（`agreement=1.000000`），见 `reports/week4/logs/storage_equivalence.txt`。此前那份 121/125（0.968）由更早的 Chroma 输出算出，与已提交的 jsonl 不一致，已作废。此门已过，融合继续。
- 全量扫描在 1 万块量级是几十毫秒（向量查询三段式：打分、候选回表、展示回表；10k 块写入 449 ms / 查询中位 44 ms）。本周不做 ANN。

---

## 决策 2：两个空间分路召回，用 RRF 合榜

**不用加权和。** `documentText` 的 384 维余弦、`clipShared` 的 512 维余弦、关键词覆盖率不是同一个量纲。把它们归一化后再加权，等于拿评测集调权重。

采用的公式是：

```text
score(d) = Σ_i  w_i / (k + rank_i(d))
```

`k=60`，这是 RRF 的常规取值，不是在 dev 上搜出来的最优值。权重初值按（文本向量，关键词，图像）= `(0.5, 0.3, 0.2)`。这是开工时定的一次选择，定完就冻结。dev 上如果要改，必须把 `parameters_changed_after_freeze` 加一，不能悄悄换。2026-10-27 已把图像权重改为 0.49，文本权重和 `k` 未改，计数为 1。记录在本节 Consequences。

细则：

1. 三路分开召回。两条向量路各自排序，禁止跨空间算余弦。`space` 或维度不符时存储层抛异常。
2. 过滤条件在存储层生效，不先取 Top-50 再筛。
3. 同分时：分数降序，`relativePath` 升序，`pageNumber` 升序且 null 在后，`startOffset` 升序。
4. 图像路没有命中不是错误，这一路的权重自然不起作用。
5. `StorageFilter` 在 `core_storage`。`SearchFilters` 在 `core_retrieval`，由它转成 `StorageFilter`。存储层不 import 检索层。

### Alternatives（融合）

| 方案 | 为什么没选 |
|---|---|
| **B. 分数加权** | min-max 随候选集变化。调权重会动用冻结的评测集 |
| **C. 只做向量** | 文件名和原词命中会丢。风险 R5 就是演示时搜不到刚导入的文件 |

### Consequences（融合）

- 融合结果只依赖名次。单路缺失时那一项不加入求和。
- H2 的门槛是 dev 上融合臂的 Hit@5 和 MRR@10 不低于任一单通道。2026-10-25 实测 A4 与只开文本的 A1 相同：Hit@5 0.666667（10/15），MRR@10 0.622222。两者都高于只开关键词的 A0（0/15）和只开图像的 A2（2/15）。「不低于」成立，但对最好的单通道没有正增益。英文样本库 `keyword_terms=0`，关键词臂加不上名次，所以 A3 也等于 A1。图像臂单独命中的 ev-13（第 1 名）和 ev-15（第 3 名）在三路融合后掉出 Top-5，文本块占满了名单。当时权重是 `(0.5, 0.3, 0.2)`，`k=60`，`parameters_changed_after_freeze=0`。数字在 `reports/week4/logs/retrieval_bench_dev.txt`，这张表不改。
- 2026-10-27：图像权重改为 0.49。文本权重和 `k` 不变，所以 `parameters_changed_after_freeze=1`。在文本权重 0.5、`k=60` 下，图像单独第 2 名要进 Top-5，权重得大于 `0.5 * 62 / 64`；权重大于或等于 0.5 时，文本单独第 3 名会在同分路径序下掉出 Top-5。0.49 取在这个区间里，没有用 dev 的标签搜索。关键词仍打不中空正文的图像行。两路都命中的文本块（例如标题问句上的 `sample.pdf`）分数仍高于只在图像路出现的文件。新测量在 `reports/week4/logs/retrieval_bench_reweight_dev.txt` 和 `reports/week4/logs/retrieval_bench_reweight_holdout.txt`。

---

## 决策 3：关键词通道自己切中文 bigram

FTS5 的默认分词会让混合检索静默变成 0 命中。索引和查询都按下面三层做：

```text
索引时：连续中文切成 bigram，写入 keyword_term(term, chunk_rowid)
        同时写 FTS5 trigram，给英文和不少于 3 字的片段
查询时：有中文 bigram → 词表覆盖率（0–1）
        同时把长度不少于 3 的拉丁串，以及离线词表给出的英文词，
        各自再查一次 FTS5 trigram。不把整句中文送进 trigram。
        同一块保留较高的分数，不重复占一行。
        没有 bigram 且查询不少于 3 个字符 → 整句 FTS5 trigram
        更短，或切不出 bigram → LIKE，带 LIMIT
```

不引入 jieba，也不下载分词词典。覆盖率只用于这一路内部的名次。进 RRF 之后只用名次。2026-10-27 起仓库里有一份固定的视觉词表：命中时改写送给 MobileCLIP 文本塔的字符串，并给上面的 bigram 查询补 trigram 探针。它不切分中文。文档文本塔仍用原问句。这次改词表没有改权重；图像权重的改动记在融合后果里。

### Alternatives（关键词）

| 方案 | 为什么没选 |
|---|---|
| **A. 只开 FTS5 默认 unicode61** | 两字中文查询命中数是 0，而且成功返回 |
| **B. 只开 trigram** | 两字查询仍然是 0。探针里「离线」「键盘」都是 0 |
| **C. 中文分词词典** | 新依赖和新的不确定性。bigram 不需要词典。固定视觉词表不是这个方案：它不切词，也不引入新包 |

### Consequences（关键词）

- 反例要留在 `reports/week4/logs/keyword_probe.txt`：`unicode61=0`，bigram 对真实 Markdown 的两字查询命中数大于 0。
- 单测覆盖两字中文、三字中文、英文、过短查询这四类。
- 2026-10-27：原先「有中文 bigram 就不再走 trigram」。英文库上中文问句因此整路为空，A0 的 0/15 记的是那次冻结运行。查询侧现在在 bigram 之外补拉丁串和离线英文词的 trigram，同一块取较高分。整句中文仍不送进 trigram。图像块正文是空的，这条补查打不中图像行。新测量写在 `reports/week4/logs/query_rewrite_probe.txt`，不替换 `retrieval_bench_dev.txt` 的六臂表，也不把 E2E-07 改成通过。

---

## 决策 4：`chunkId` 不是主键

能复用一条文档的条件在本决策里称作五项全等：`contentHash`、解析器名加版本、`chunkerVersion`、`modelId`、`vectorDim`。`sameRecipe` 把解析器名和版本分成 `parserName`、`parserVersion` 两个字段来比，所以实际比较 6 个字段。有一个字段不同，该文档的块和向量整组作废重写。不做块级 diff，因为窗口序号一变，块就对不齐。

`documentId` 用 `FileMetadata.contentHash ?? FileMetadata.id`，和 `DefaultEmbeddingService` 一致。

删除按 `document_id` 删向量行，再按 `chunk_rowid` 删关键词表和 FTS 行。默认走 `sameRecipe` 的六字段判等，也就是上面的五项。整库重做留给以后的 `--force`，本决策不把每次启动都做成全量重建。

### Alternatives（代次）

| 方案 | 为什么没选 |
|---|---|
| **A. 用 `chunkId` 对齐** | ADR 0003 已经写明它不是稳定主键 |
| **B. 每次全量重建** | 可做强制通道，不适合作为默认。常驻推理下全库大约几十秒，但内容没变时不该重算 |

### Consequences（代次）

- 表是 `index_generation`。缺任何一项生成信息时不写代次行，调用方就不能把它当成可复用。
- ADR 0003 里交给 W4 的「不要把 `chunkId` 当主键」由此落地。
- 2026-10-28：默认窗口仍写 `w3-cascade-1`，已入库的代次继续对得上。窗口或 token 上限离开 120/128 时，版本串写成 `w3-cascade-1-c<窗口>-t<上限>`。`sameRecipe` 仍是上面这 6 个字段，不把窗口单列成第 7 项。管道在切块器是 `CascadeTextChunker` 时，传入的版本串必须等于切块器自己的串。

---

## 决策 5：邻域扩展在检索侧，先排序再扩展

`sample.pdf` 的两页是同一篇说明的重复排版，不是半句续到下一页。因此：

| 情形 | 处理 |
|---|---|
| 命中块在页中间 | 同页 `chunkIndex ± 1`，拼进 snippet |
| 页首或页尾 | 只扩同页还存在的那一侧。不跨页 |
| 顺序 | 先按块级分数取 Top-K，再扩展。扩展不改分数 |
| 页码 | `pageNumber == null` 时不得当成真实页码。TXT/DOCX 保持 null |

跨页断句的通过标准等有真实跨页文档再定。本周若要验证邻域，用长 Markdown 切出来的跨块样本，另建 `reports/week4/evidence_set_w4.jsonl`，不并入已冻结的 25 条。

### Alternatives（邻域）

| 方案 | 为什么没选 |
|---|---|
| **A. 扩展后再排序** | 长页会占满 Top-K |
| **B. 跨页拼接** | 现有 PDF 样本不支持这个判断，拼错比不拼更差 |

### Consequences（邻域）

- 存储层提供按文档读出块的能力。扩展逻辑不在存储层打分。
- `SearchResult.startOffset` / `endOffset` 仍是命中块自己的范围。上下文只放在 `snippet`。

---

## 决策 6：编排放在 `packages/core_pipeline`

架构原文把导入编排放在 `apps/desktop` 的组合根。W4 没有界面，`dart test` 也覆盖不了 Flutter 组合根，而 W6 的覆盖率要算核心库。

**编排实现放在纯 Dart 包 `packages/core_pipeline`。桌面端只装配依赖，不把流程写进 Widget。**

依赖方向：

```text
core_pipeline → core_parsing, core_embedding, core_storage, core_retrieval
core_retrieval → core_embedding, core_storage
core_storage → core_embedding（只用 EmbeddingVector 这个值，不调用 embed）
core_embedding 不 import 存储或检索
core_storage 不 import 检索
```

这修改了架构文档里的 R1a，必须和本文一起生效。见 `docs/architecture/system-architecture.md` 的目录映射和依赖规则。

### Alternatives（编排）

| 方案 | 为什么没选 |
|---|---|
| **B. 只写在 `apps/desktop`** | 端到端要走 `flutter test`，覆盖率口径会裂开 |

### Consequences（编排）

- `IndexingPipeline` / `SearchPipeline` 是后续探针和 W5 的调用面。
- 常驻运行时 `PersistentOnnxRuntime` 放在这个包里，实现 `EmbeddingRuntime`。

---

## 决策 7：评测口径

冻结集 `reports/week3/evidence_set.jsonl` 25 条，2026-10-16T13:12:33Z，本周不改不删。dev 15 条用来看臂和看已经冻结的权重，holdout 10 条原先定的是只在最终报告出一次数，并写明被看过几次。2026-10-27 改了查询与图像权重后又打了一次，因此 holdout 实际被看过 2 次：0.500 是冻结系统的那次，0.900 是改后的重测，两者不能并列成提升，0.900 也不再是无偏估计。记录在 `reports/week4/检索精度基准报告.md` 第 10 节末段。

六个臂：A0 仅关键词，A1 仅文档向量，A2 仅图像向量，A3 文档向量加关键词，A4 三路（默认），A5 三路加邻域扩展。

每个 Hit@5 带 Wilson 95% 区间，写成 `0.80 [0.55, 0.93] (12/15)` 这种三件套。逐题保留名次。25 条里没有 no-answer 题，本周不报「查不到」。不把 COCO image→caption 或 NQ 代理分数写成检索精度。

邻域验证若加题，写入 `reports/week4/evidence_set_w4.jsonl`，标记 `crossChunk: true`，不参与调参，也不并进冻结集。

### Alternatives（评测）

| 方案 | 为什么没选 |
|---|---|
| **A. 扩到 100 条以上** | 本周没有另一套真实文档标注 |
| **B. 用官方 NQ passage** | W3 已经因为体积和联网否掉 |

### Consequences（评测）

- 样本小是结论的一部分，不是脚注可选项。
- 图像题的目标文件不在 `datasets/samples` 里时，对照索引要单独带上这些图像向量，不能把「库里没有这张图」算成存储实现错误。

---

## 与 PDF 原文的偏差

原文要求把 Chroma DB 集成进本地向量存储。本决策的做法是：Chroma 建集合、做余弦检索、和产品索引比 Top-5。产品进程里没有 Chroma 服务。偏差的原因是 HTTP 客户端方案和「`engine/` 不进发布包」冲突，而系统 SQLite 已经在本机测通。没有测过的存储实现不能拿来替代这次对照。
