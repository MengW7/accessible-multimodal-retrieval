# ADR 0004：向量存储、融合与编排落点

| 项目 | 内容 |
|---|---|
| 状态 | **Accepted**（已采纳） |
| 日期 | 2026-10-20 |
| 决策者 | Week 4 阶段 A |
| 影响范围 | 存储层、检索层、导入/检索编排；W5 只经检索层拿结果；W8 是否自带 `sqlite3.dll` |
| 相关文档 | `week4/W04_task_plan.md` 决策 1–8；`docs/tdd/technical-design-document.md` Q2、Q5 |

---

## Context（背景）

Week 4 要把已经算出来的两个空间的向量放进本地索引，并回答「一句不含文件名的话，能不能在 Top-5 里找到目标文件」。开工时的事实：

| 事实 | 证据 |
|---|---|
| 产品侧还没有向量库。`engine/chroma_data/` 只有 Week 1 的 `week1_smoke` | 仓库现状 |
| `chromadb 1.5.9` 已装在 `engine/.venv`。pub.dev 上的 Dart `chromadb 2.0.0` 是 HTTP 客户端，要另起一个服务进程 | `week4/W04_task_plan.md` §1.1 |
| 本机 `C:\Windows\System32\winsqlite3.dll` 是 SQLite 3.53.4，FTS5 / JSON1 / WAL 可用。`package:sqlite3` 2.9.4 在找不到 `sqlite3.dll` 时回退到 `winsqlite3.dll`，Dart 探针已跑通 | `week4/probes/probe_sqlite_capacity.txt`、`week4/probes/dart_store_probe.txt` |
| 384 维 fp32、1 万块的暴力余弦中位 51.9 ms，写入 528 ms | 同一份 Dart 探针 |
| FTS5 默认 `unicode61` 把整段中文当成一个 token。两字查询命中数是 0，而且不报错。`trigram` 要至少 3 个字 | 同一份探针的 token 表 |
| W3 的大约 2 秒/向量几乎全是进程启动和模型加载。常驻进程的前向中位是 25.5 ms，加速比 54.3 | `week4/probes/probe_persistent_runtime.txt` |
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
- H1：同一批向量、同一批查询，Chroma 与 Dart+SQLite 的 Top-5 一致率不低于 96%。2026-10-20 实测 121/125（96.8%），见 `week4/logs/storage_equivalence.txt`。4 处不一致都是第 5 名，落在 `sample.pdf` 两页重复排版的相邻块上，同一块分数差约 3.9e-7。不过此门，不做融合。
- 全量扫描在 1 万块量级是几十毫秒。本周不做 ANN。

---

## 决策 2：两个空间分路召回，用 RRF 合榜

**不用加权和。** `documentText` 的 384 维余弦、`clipShared` 的 512 维余弦、关键词覆盖率不是同一个量纲。把它们归一化后再加权，等于拿评测集调权重。

采用的公式是：

```text
score(d) = Σ_i  w_i / (k + rank_i(d))
```

`k=60`，这是 RRF 的常规取值，不是在 dev 上搜出来的最优值。权重初值按（文本向量，关键词，图像）= `(0.5, 0.3, 0.2)`。这是开工时定的一次选择，定完就冻结。dev 上如果要改，必须把 `parameters_changed_after_freeze` 加一，不能悄悄换。

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
- H2 的门槛是 dev 上融合臂的 Hit@5 和 MRR@10 不低于任一单通道。2026-10-25 实测 A4 与只开文本的 A1 相同：Hit@5 0.666667（10/15），MRR@10 0.622222。两者都高于只开关键词的 A0（0/15）和只开图像的 A2（2/15）。「不低于」成立，但对最好的单通道没有正增益。英文样本库 `keyword_terms=0`，关键词臂加不上名次，所以 A3 也等于 A1。图像臂单独命中的 ev-13（第 1 名）和 ev-15（第 3 名）在三路融合后掉出 Top-5，文本块占满了名单。权重仍是 `(0.5, 0.3, 0.2)`，`k=60`，`parameters_changed_after_freeze=0`。没有回头调权重。数字在 `week4/logs/retrieval_bench_dev.txt`。

---

## 决策 3：关键词通道自己切中文 bigram

FTS5 的默认分词会让混合检索静默变成 0 命中。索引和查询都按下面三层做：

```text
索引时：连续中文切成 bigram，写入 keyword_term(term, chunk_rowid)
        同时写 FTS5 trigram，给英文和不少于 3 字的片段
查询时：有中文 bigram → 按命中 term 的覆盖率给分（0–1）
        没有 bigram 且查询不少于 3 个字符 → FTS5 trigram
        更短，或切不出 bigram → LIKE，带 LIMIT
```

不引入 jieba 或别的词典。覆盖率只用于这一路内部的名次。进 RRF 之后只用名次。

### Alternatives（关键词）

| 方案 | 为什么没选 |
|---|---|
| **A. 只开 FTS5 默认 unicode61** | 两字中文查询命中数是 0，而且成功返回 |
| **B. 只开 trigram** | 两字查询仍然是 0。探针里「离线」「键盘」都是 0 |
| **C. 中文分词词典** | 新依赖和新的不确定性。bigram 不需要词典 |

### Consequences（关键词）

- 反例要留在 `week4/logs/keyword_probe.txt`：`unicode61=0`，bigram 对真实 Markdown 的两字查询命中数大于 0。
- 单测覆盖两字中文、三字中文、英文、过短查询这四类。

---

## 决策 4：`chunkId` 不是主键

能复用一条文档的条件是五项全等：`contentHash`、`parserName` + `parserVersion`、`chunkerVersion`、`modelId`、`vectorDim`。有一项不同，该文档的块和向量整组作废重写。不做块级 diff，因为窗口序号一变，块就对不齐。

`documentId` 用 `FileMetadata.contentHash ?? FileMetadata.id`，和 `DefaultEmbeddingService` 一致。

删除按 `document_id` 删向量行，再按 `chunk_rowid` 删关键词表和 FTS 行。默认走五项判等。整库重做留给以后的 `--force`，本决策不把每次启动都做成全量重建。

### Alternatives（代次）

| 方案 | 为什么没选 |
|---|---|
| **A. 用 `chunkId` 对齐** | ADR 0003 已经写明它不是稳定主键 |
| **B. 每次全量重建** | 可做强制通道，不适合作为默认。常驻推理下全库大约几十秒，但内容没变时不该重算 |

### Consequences（代次）

- 表是 `index_generation`。缺任何一项生成信息时不写代次行，调用方就不能把它当成可复用。
- ADR 0003 里交给 W4 的「不要把 `chunkId` 当主键」由此落地。

---

## 决策 5：邻域扩展在检索侧，先排序再扩展

`sample.pdf` 的两页是同一篇说明的重复排版，不是半句续到下一页。因此：

| 情形 | 处理 |
|---|---|
| 命中块在页中间 | 同页 `chunkIndex ± 1`，拼进 snippet |
| 页首或页尾 | 只扩同页还存在的那一侧。不跨页 |
| 顺序 | 先按块级分数取 Top-K，再扩展。扩展不改分数 |
| 页码 | `pageNumber == null` 时不得当成真实页码。TXT/DOCX 保持 null |

跨页断句的通过标准等有真实跨页文档再定。本周若要验证邻域，用长 Markdown 切出来的跨块样本，另建 `week4/evidence_set_w4.jsonl`，不并入已冻结的 25 条。

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

冻结集 `reports/week3/evidence_set.jsonl` 25 条，2026-10-16T13:12:33Z，本周不改不删。dev 15 条用来看臂和看已经冻结的权重，holdout 10 条只在最终报告出一次数，并写明被看过几次。

六个臂：A0 仅关键词，A1 仅文档向量，A2 仅图像向量，A3 文档向量加关键词，A4 三路（默认），A5 三路加邻域扩展。

每个 Hit@5 带 Wilson 95% 区间，写成 `0.80 [0.55, 0.93] (12/15)` 这种三件套。逐题保留名次。25 条里没有 no-answer 题，本周不报「查不到」。不把 COCO image→caption 或 NQ 代理分数写成检索精度。

邻域验证若加题，写入 `week4/evidence_set_w4.jsonl`，标记 `crossChunk: true`，不参与调参，也不并进冻结集。

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
