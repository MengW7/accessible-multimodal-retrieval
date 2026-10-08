# Week 2 执行方案：系统架构设计 + 核心文件解析模块

| 项目 | 内容 |
|---|---|
| 周期 | W2 ｜ 09/27（周日）– 10/03（周六） |
| 交付日 | **09/30（周三）** |
| 预算工时 | 16h |
| 主题 | 系统架构 + 文件解析模块方案 |
| 上游依据 | `docs/tasks/Software Engineering Project … Retrieval System.pdf`（Week 2 章节） |
| 下游衔接 | W3 多模态 Embedding 引擎（需要 W2 的 `ParsedDocument` 作为输入） |
| 计划基线 | `reports/week1/个人计划.md`、`reports/week1/W01_report.md`、`reports/week1/PRD.md` |

---

## 0. 一页速览

**一句话目标**：把「六层架构」从纸面落到仓库目录与接口契约上，并交付一个可跑、可测、离线、支持 TXT/PDF/DOCX/JPG/PNG 五格式的解析模块，单测覆盖率 ≥80%，同时产出架构文档、模块 API 文档、TDD 草稿三份文档。

**四天节奏**：

| 日期 | 时长 | 主产出 | 出口判据 |
|---|---|---|---|
| 09/27 周日 | 4h | 六层架构文档 + 目录骨架 + 接口冻结 | 架构文档含 Mermaid 六层图；`dart analyze` 干净 |
| 09/28 周一 | 4h | TXT / DOCX 解析器 + 单测 | 2 个解析器全部用例通过 |
| 09/29 周二 | 4h | PDF（Tika 适配）+ JPG/PNG 元数据 + 批量入库 | 5 格式端到端跑通 1 个真实目录 |
| 09/30 周三 | 4h | 覆盖率补到 ≥80% + API 文档 + TDD 草稿 + 验收留证 | 覆盖率报告 ≥80%，三份文档齐全，证据入 `reports/week2/` |

**红线**：W2 不做 embedding、不写向量库、不写 UI、不做 OCR、不编译 PDFium —— 只把「数据摄入管线」打穿。

---

## 1. PDF 原文对 Week 2 的要求（照抄，避免走偏）

> **Week 2: System Architecture Design & Core File Parsing Module Development**
> Core Focus: Design a modular, maintainable architecture aligned with Google's clean code principles, build the foundation of the data ingestion pipeline.

**Key Tasks**

1. Design full modular system architecture: File I/O Layer, Parsing Layer, Embedding Engine Layer, Vector Storage Layer, Retrieval Logic Layer, UI & Accessibility Layer
2. Develop and unit-test the file parsing module (support for TXT, PDF, DOCX, JPG, PNG formats)
3. Implement batch file ingestion and metadata extraction logic
4. Draft full technical design document (TDD) with architecture diagrams

**Weekly Deliverables**

1. Finalized System Architecture Design Document
2. Functional file parsing module with **≥80% unit test coverage**
3. Module API documentation

---

## 2. 当前基线（W1 结束时的真实仓库状态）

### 2.1 已经具备、W2 可直接复用的资产

| 资产 | 位置 / 证据 | 对 W2 的价值 |
|---|---|---|
| Flutter stable 3.47.5 / Dart 3.13.4 | `reports/week1/环境搭建验证报告.md` ENV-01/02/03 | UI 层与 `flutter test` 通路已通 |
| `apps/desktop` 模板工程可编译、可测 | ENV-04；`apps/desktop/lib/main.dart`、`test/widget_test.dart` | 后续接解析结果的宿主工程 |
| JDK 17 + **Apache Tika 4.0.0 已本地可离线抽 PDF 正文** | ENV-07；`tools/tika-app/tika-app-4.0.0.jar` + `lib/` | PDF/DOCX 抽文本的现成、已验证的兜底实现 |
| Python 3.13.2 venv + Chroma 1.5.9 + TensorFlow 2.21.0 | `engine/.venv`、`engine/requirements.txt`、`engine/smoke_tflite.py` | W3/W4 使用；W2 仅作为离线评测脚本环境 |
| 样本文件 | `datasets/samples/sample.pdf`（71 KB，**2 页**）、`sample.docx`（16.5 KB）、`sample.png`（1186×1137 PNG） | 解析模块真实输入 |
| 验证子集 | `datasets/nq/validation`（2 个 jsonl）、`datasets/coco/val_sample/images`（50 张 jpg）+ `captions.jsonl`、`datasets/rvlcdip/sample`（16 张 png） | 批量入库压测的批量文件来源 |
| Dart 依赖已在本地 pub 缓存 | `archive-3.6.1`、`xml-6.6.1`、`image-4.3.0`、`crypto-3.0.7`、`path-1.9.1`、`test-1.31.1`、`**coverage-1.15.1**`、`ffi-2.2.0` | **离线 `pub get` 可行**，覆盖率工具现成 |
| 预留的 native 目录 | `native/pdfium/{windows,include,tests}`、`native/gtest/`（空）、`native/tflite/windows/` | W3 之后 FFI 的位置，W2 只写接口不填实现 |
| `.gitignore` 已排除 `.venv/`、`chroma_data/`、模型权重、非 samples 的数据集图片 | 仓库根 `.gitignore` | 不会误提交大文件（R9） |

### 2.2 W2 必须补上的缺口

| W2 要求 | 现状 | W2 要做什么 |
|---|---|---|
| 六层架构设计文档 | 只有一句技术栈描述（`README.md`），无分层、无目录映射、无接口契约 | 新建 `docs/architecture/system-architecture.md` |
| TXT 解析 | 不存在 | 新建 `TxtParser` |
| PDF 解析（正文 + 页码） | 只有一条人工验证过的 Tika 命令，未代码化 | 新建 `TikaCliTextExtractor` + `PdfParser` |
| DOCX 解析 | 仅人工跑过 Tika | 新建纯 Dart `DocxParser`（`archive` + `xml`）+ Tika 兜底 |
| JPG/PNG 处理 | 无 | 新建 `ImageParser`（元数据，不 OCR） |
| 批量入库 + 元数据提取 | 无 | 新建 `IngestionService`、`FileMetadata` |
| 解析模块单测 ≥80% | 只有 Flutter 模板计数器测试（ENV-04，非业务） | 新建 `packages/core_parsing/test/**` + 覆盖率报告 |
| 模块 API 文档 | 无 | 新建 `docs/api/parsing-module-api.md` |
| TDD 草稿（含架构图） | 无 | 新建 `docs/tdd/technical-design-document.md` |
| W2 测试/验收证据目录 | `reports/week1/` 已成形 | 新建 `reports/week2/`（报告 + 原始日志 + 截图） |

**其他已知事实（写进架构文档的约束）**：

- `apps/desktop/lib/` 目前是 Flutter 计数器模板，与检索业务无关，W2 不动 UI，但要把 `core_parsing` 以 path 依赖接进去证明可被 UI 层消费。
- `datasets/samples/` **没有 `.txt` 和 `.jpg` 样本**，W2 必须自己补测试夹具。
- `.gitignore` 只保留 `datasets/samples/**` 下的 jpg/png，其余数据集图片不入库 → 测试夹具要放在包内 `test/fixtures/`。
- 本机对 `pub.dev` 的 TCP 443 可通、DNS 可解析，但 HTTPS 请求在当前 Shell 下握手不稳定 → **不把「新增未缓存 pub 包」当作 W2 的前提**。

---

## 3. 完成定义（DoD）

| 编号 | 交付物 | 落地文件 | 验收方式（可复制执行） |
|---|---|---|---|
| **D1** | 系统架构设计文档（定稿） | `docs/architecture/system-architecture.md` | 含六层 Mermaid 图、六层→目录映射表、跨层接口契约、进程/线程模型、错误分层、W2 范围边界 |
| **D2** | 可用的文件解析模块（TXT/PDF/DOCX/JPG/PNG） | `packages/core_parsing/` | `dart analyze` 0 issue；`dart test` 全绿；对 `datasets/samples/` 实跑能输出正文与元数据 |
| **D3** | 单测覆盖率 ≥80% | `reports/week2/coverage/lcov.info` + `reports/week2/覆盖率报告.md` | 脚本统计 LF/LH ≥ 80.00% |
| **D4** | 批量入库与元数据提取 | `lib/src/io/ingestion_service.dart`、`lib/src/model/file_metadata.dart` | 对 `datasets/coco/val_sample/images`（50 张）与 `datasets/rvlcdip/sample`（16 张）批量扫描，产出 66 条元数据、0 崩溃、坏样本被记录 |
| **D5** | 模块 API 文档 | `docs/api/parsing-module-api.md` | 每个 public 类型/方法有签名、参数、异常、示例 |
| **D6** | TDD 草稿（含架构图） | `docs/tdd/technical-design-document.md` | 含数据流时序图 + 解析层详细设计 + 未决问题清单 |
| **D7** | W2 验收留证 | `reports/week2/` | 报告 + `dart test` / 覆盖率原始日志 + 截图索引（沿用 W1 报告体例） |

> **D3 口径说明**：覆盖率只统计 `packages/core_parsing/lib/`，`lib/src/parsing/adapters/` 中调外部进程的部分必须通过注入 `ProcessRunner` 假实现来覆盖；不靠「跑真 Java」来凑行数。

---

## 4. 开工前必须冻结的 5 个决策

> 这 5 条在 Day 1 的前 30 分钟内定完并写进架构文档，避免后面反复返工。

### 决策 1：解析模块的宿主 —— 独立纯 Dart 包 `packages/core_parsing`

- **推荐**：独立 pure-Dart 包（`dart test` 可跑，不依赖 Flutter 引擎），`apps/desktop` 通过 path 依赖引用。
- **理由**：① 解析是纯逻辑，`dart test` 比 `flutter test` 快、无关 Flutter 绑定；② 强制「UI 层不得直接读文件」的分层纪律；③ W3 的 embedding 引擎同构复用；④ 对应风险 R4「FFI/原生/文件对话框用接口包一层，测试打 Mock」。
- **落地**：`environment: sdk: ^3.13.0`；`dependencies: archive ^3.6.1, xml ^6.6.1, image ^4.3.0, path ^1.9.1, crypto ^3.0.7, meta`；`dev_dependencies: test ^1.31.1, lints ^6.1.0, coverage ^1.15.1`。**全部已在本地 pub 缓存**。

### 决策 2：五种格式的抽取路线（分层 + 可替换）

| 格式 | W2 实现 | 理由 | W3+ 演进 |
|---|---|---|---|
| TXT | 纯 Dart：`dart:io` 读取 + BOM/编码嗅探（UTF-8 / UTF-8 BOM / **GBK 中文** / UTF-16） | 零依赖，中文文件最容易踩坑，必须早测 | 不变 |
| DOCX | **主**：纯 Dart（`archive` 解压 `word/document.xml`，`xml` 取 `w:p`/`w:t`，`docProps/core.xml` 取 title/creator）；**备**：Tika CLI | 已验证 `sample.docx` 内含 `word/document.xml` + `docProps/core.xml`；纯 Dart 路径可被单测完全覆盖 | 不变 |
| PDF | **W2 主**：Tika CLI 适配器（`TikaCliTextExtractor`），用 `-x`（XHTML）保留 `<div class="page">` 页码，回退 `-t` 纯文本 | Tika 4.0.0 已本地、离线、ENV-07 已验证；`sample.pdf` 实测解析出 **2 个 page div**，满足 PRD「抽文本层并记下页码」 | W3/W4 增加 `PdfiumTextExtractor`（`native/pdfium/windows/pdfium.dll` + `dart:ffi`），**接口不变**，去掉 JVM 依赖（对应风险 R2 降级路线） |
| JPG/PNG | 纯 Dart `image` 包读尺寸/格式/色彩模式，产出 `ImageAsset` 记录（**不 OCR**） | 图像语义由 W3 的 MobileCLIP 负责，W2 只做元数据与登记 | W3 接 MobileCLIP 时补 `imageEmbedding` 字段 |

> **关键设计**：PDF/DOCX 的外部进程调用一律藏在 `TextExtractor` 接口后面（依赖倒置），因此 (a) 单测注入假 `ProcessRunner` 即可达覆盖率；(b) 换 PDFium 不动上层。

### 决策 3：PDF 用「每文件一个 JVM 进程」，但把耗时记进报告

- 命令（注意 Windows 用 `;`、macOS/Linux 用 `:` 作为 classpath 分隔符，代码里用 `Platform.isWindows` 分支）：

```powershell
java -cp "tools\tika-app\tika-app-4.0.0.jar;tools\tika-app\lib\*" org.apache.tika.cli.TikaCLI -x "<file>"
```

- **只取 stdout 作为正文**，stderr 收作诊断日志（Tika 会往 stderr 打 INFO 噪声，ENV-07 已观察到）。
- Java 不可用时不得崩溃：解析器返回 `ParserUnavailableError`，入库把该文件标记为 `skipped` 并记录原因。
- Day 3 记录「单文件 JVM 启动耗时」，作为 W3 是否改常驻 JVM / PDFium FFI 的依据。

### 决策 4：批量入库先同步可测，接口预留 Isolate

- W2 的 `IngestionService` 用可注入的 `Executor`（默认 `ImmediateExecutor`），保证单测可确定性执行；并发度、取消令牌（`CancellationToken`）、进度回调（`onProgress`）在 W2 就定进接口签名。
- 真正跑在 Isolate 上交给 W5/W6（性能周），但**接口不改**——避免 W6 再动架构。

### 决策 5：`engine/`（Python + Chroma）在架构中的定位必须在架构文档里写清

- **推荐定位**：`engine/` 只做**离线评测/数据集抽样/精度基准**，**不进入发布包**；发布版向量库由 Dart 侧（`core_storage`，W4 决策：Chroma Dart FFI 或 SQLite+近邻）实现。
- 理由：避免把一个 Python 运行时塞进 Windows/macOS/Linux 桌面发布包（体积 + 打包复杂度，风险 R2/R7）。
- W2 只需在架构文档给出结论与 ADR 链接，具体选型归 W4。

---

## 5. 六层 → 仓库目录映射

| PDF 要求的层 | 仓库落地位置 | W2 是否落地 | 责任周次 |
|---|---|---|---|
| File I/O Layer | `packages/core_parsing/lib/src/io/`（`file_scanner.dart`、`ingestion_service.dart`、`file_reader.dart`） | ✅ 实现 | W2 |
| Parsing Layer | `packages/core_parsing/lib/src/parsing/`（`parser_registry.dart` + `parsers/` + `adapters/`） | ✅ 实现 | W2 |
| Embedding Engine Layer | `packages/core_embedding/`（W2 只在架构文档与接口文件中冻结 `EmbeddingEngine` 契约） | ⬜ 仅接口 | W3 |
| Vector Storage Layer | `packages/core_storage/`（W2 仅冻结 `VectorStore` 契约） | ⬜ 仅接口 | W4 |
| Retrieval Logic Layer | `packages/core_retrieval/`（W2 仅冻结 `Retriever` 契约） | ⬜ 仅接口 | W4 |
| UI & Accessibility Layer | `apps/desktop/lib/`（W2 只改 `pubspec.yaml` 加 path 依赖，证明可消费解析层） | 🔶 最小接入 | W5 |
| 离线评测 / 基准脚本（非产品层） | `engine/`（Python，`.venv` 不入库） | 🔶 定位澄清 | W3/W4 |

**依赖方向（单向，禁止反向）**：

```
UI & Accessibility  →  Retrieval  →  Vector Storage  →  Embedding  →  Parsing  →  File I/O
                                     ↑ 跨层只经接口，不跨层 import 实现
```

---

## 6. 分步执行计划（4 天 / 16h，每步都有完成判据）

### Day 1｜09/27（周日）· 4h — 架构落地 + 接口冻结

| 步 | 动作 | 产出 | 完成判据 |
|---|---|---|---|
| 1.1 | 建包骨架：`packages/core_parsing/{pubspec.yaml,analysis_options.yaml,lib/core_parsing.dart,lib/src/...,test/}` | 包可解析 | `cd packages/core_parsing; dart pub get; dart analyze` → 0 issue（**离线可完成，依赖全在 pub 缓存**） |
| 1.2 | `apps/desktop/pubspec.yaml` 增加 `core_parsing: {path: ../../packages/core_parsing}` | 依赖接通 | `cd apps/desktop; flutter pub get` 成功 |
| 1.3 | 定义并冻结核心模型：`FileMetadata`、`ParsedDocument`、`DocumentPage`、`ImageAsset`、`ParseOutcome`（ok/partial/skipped/failed）、`IngestionReport` | `lib/src/model/*.dart` | 类型全部 `final`/不可变，含 `toJson()`（W4 入库要用） |
| 1.4 | 定义并冻结接口：`DocumentParser`、`ParserRegistry`、`TextExtractor`、`ProcessRunner`、`CancellationToken`、`Executor` | `lib/src/parsing/parser.dart`、`lib/src/spi/*.dart` | 接口均为 `abstract interface class`；`dart analyze` 干净 |
| 1.5 | 建测试夹具：`test/fixtures/`（`hello.txt`、`hello_utf8_bom.txt`、`hello_gbk.txt`、`empty.txt`、`truncated.pdf`、`docx_minimal.docx`、`nested/a.txt`；并复制 `datasets/samples/sample.pdf|docx|png` 作为集成夹具并注明来源） | 夹具齐备 | 夹具总体积 < 200 KB（大样本只在集成测里引用 `datasets/`） |
| 1.6 | 写架构文档 `docs/architecture/system-architecture.md`：六层 Mermaid 图、目录映射、接口契约、数据流、线程/进程模型、错误分层、W2 范围边界、5 条决策记录 | D1 | 文档含 Mermaid 六层架构图；能回答「新增一种格式要改哪几个文件」 |
| 1.7 | 写 ADR：`docs/architecture/adr/0001-parsing-runtime-dart-package.md`、`0002-pdf-extraction-tika-then-pdfium.md` | 2 份 ADR | 每个 ADR 含 Context / Decision / Consequences / Alternatives |

> **Day 1 结束必须能回答**：解析模块的 public API 长什么样？（Day 2 起只做实现，不再改签名。）

### Day 2｜09/28（周一）· 4h — TXT + DOCX

| 步 | 动作 | 产出 | 完成判据 |
|---|---|---|---|
| 2.1 | `TxtParser`：编码嗅探（UTF-8 / UTF-8 BOM / UTF-16 LE/BE / GBK 兜底）、换行归一（`\r\n`→`\n`）、超大文件截断（默认 10 MB 上限并记 `partial`） | `parsers/txt_parser.dart` | 4 个编码夹具都读出正确中文；空文件返回空正文 + `ok` |
| 2.2 | `ParserRegistry`：按扩展名分派、未知扩展名返回 `UnsupportedFormat`（不抛异常） | `parsing/parser_registry.dart` | 大小写扩展名（`.TXT`/`.Pdf`）都能命中 |
| 2.3 | `DocxParser`：`archive` 解压 → `xml` 解析 `word/document.xml`，按 `w:p` 切段、`w:t` 取文本；`w:tab`/`w:br` 处理；`docProps/core.xml` 取 `dc:title`/`dc:creator`/`dcterms:created` | `parsers/docx_parser.dart` | 对 `datasets/samples/sample.docx` 输出非空正文与 title/creator；损坏 zip 返回 `failed` + 原因 |
| 2.4 | `TikaCliTextExtractor`（`ProcessRunner` 注入）：组装 classpath（平台分支）、执行 `-x`、解析 `class="page"` 切页、失败回退 `-t` | `adapters/tika_cli_text_extractor.dart` | 假 `ProcessRunner` 下 100% 分支可测；真 Java 下 `sample.pdf` 得到 2 页 |
| 2.5 | 单测：TXT 4 编码 + 空/超大 + DOCX 正常/损坏/无 `document.xml` + Registry 分派 + Extractor 成功/超时/Java 缺失 | `test/**` | `dart test --exclude-tags integration` 全绿；真 Java 的 `sample.pdf` 用 `dart test --tags integration`；此日结束覆盖率应 ≥55% |

### Day 3｜09/29（周二）· 4h — PDF + 图像 + 批量入库

| 步 | 动作 | 产出 | 完成判据 |
|---|---|---|---|
| 3.1 | `PdfParser` 接上 `TikaCliTextExtractor`：组装 `DocumentPage` 列表、`pageCount`、`metadata.pageCount` | `parsers/pdf_parser.dart` | `sample.pdf` → 2 页、正文非空、`parseOutcome=ok` |
| 3.2 | `ImageParser`：`image` 包读取 format/width/height/colorMode；产出 `ImageAsset`（无文本）；`exif` 缺失不报错 | `parsers/image_parser.dart` | `sample.png` → 1186×1137 / PNG / RGB；`.jpg` 同样可得 |
| 3.3 | `FileScanner`：递归扫描、扩展名白名单（`.txt .pdf .docx .jpg .jpeg .png`）、跳过隐藏文件/系统目录/`~$` 临时文件、`followLinks=false`、`maxDepth`、结果按路径排序 | `io/file_scanner.dart` | 对 `datasets/rvlcdip/sample` 得 16 条；对含 `nested/` 的夹具得包含子目录文件 |
| 3.4 | `FileMetadata` 提取：`relativePath`、`fileName`、`extension`、`mimeType`、`sizeBytes`、`createdAt/modifiedAt/accessedAt`、`contentHash`（sha256）、`indexedAt`、`parserName`、`durationMs`、`status`、`errorMessage` | `model/file_metadata.dart`（+`crypto`） | 同一文件二次扫描 `contentHash` 一致；权限不足只记 `skipped` 不中断 |
| 3.5 | `IngestionService`：目录入口 → 扫描 → 逐文件「解析 + 元数据」→ 汇总 `IngestionReport`；单文件异常隔离；`onProgress`、`CancellationToken`、`concurrency` | `io/ingestion_service.dart` | 对 `datasets/coco/val_sample/images`(50) + `datasets/rvlcdip/sample`(16) 跑出 **66 条**记录、0 崩溃、报告含 skipped/failed 分类 |
| 3.6 | 单测：PDF/图像/扫描/元数据/入库（含坏文件、空目录、重复文件去重、取消中断） | `test/**` | `dart test` 全绿；覆盖率 ≥70% |

### Day 4｜09/30（周三）· 4h — 覆盖率、文档、验收（**交付日**）

| 步 | 动作 | 产出 | 完成判据 |
|---|---|---|---|
| 4.1 | 补齐未覆盖分支（错误路径优先：Java 缺失、超时、编码非法、超大文件、权限拒绝、取消） | `test/**` | 统计 **≥80.00%** |
| 4.2 | 生成覆盖率证据：`dart test --coverage=coverage` → `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib` | `reports/week2/coverage/lcov.info` + 百分比截图 | 附录 C 脚本输出 ≥80% |
| 4.3 | 写 `docs/api/parsing-module-api.md`（D5）：每个 public 类型/方法给签名、参数语义、异常、示例、线程安全性 | D5 | 每个 public 符号都被文档覆盖（`grep` 对照 `lib/core_parsing.dart` 导出清单） |
| 4.4 | 写 `docs/tdd/technical-design-document.md` v0.1（D6）：数据流时序图、解析层详细设计、性能预估（单文件耗时）、未决问题清单（PDFium 替换、PDF 页码策略、OCR、大文件分块） | D6 | 含至少 2 张 Mermaid 图；未决问题带 Owner 与解决周次 |
| 4.5 | 写 `reports/week2/W02_report.md`（沿用 W1 体例：范围/环境/用例统计表/详细用例/证据索引/结论/限制） | D7 | 表格含「用例 ID—命令—期望—实际—判定—证据」 |
| 4.6 | 原始日志与截图归位：`reports/week2/logs/{dart_analyze.txt,dart_test.txt,coverage.txt,ingest_samples.txt}`、`reports/week2/screenshots/*.png` | D7 | 每个用例都有对应证据文件 |
| 4.7 | 提交：`git add packages/core_parsing docs reports/week2 apps/desktop/pubspec.yaml`；提交前 `git status` 复核无 `.tflite`/`.venv`/`chroma_data` | Git | 单一提交信息：`feat: week2 architecture design and file parsing module` |

---

## 7. 验收命令清单（逐条可复制）

```powershell
# 1) 解析包：静态检查 + 单测（不启动 JVM）
cd packages\core_parsing
dart pub get
dart analyze
dart test --exclude-tags integration

# 2) 覆盖率（D3；不把真 Java 算进行覆盖率）
dart test --coverage=coverage --exclude-tags integration
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
# 见附录 C 计算百分比

# 2b) 真 Java、真样本冒烟（架构 §13；需要 JDK 与 tools\tika-app）
java -version
dart test --tags integration

# 3) 五格式端到端冒烟（D2）
cd ..\..
dart run packages\core_parsing\bin\parse_probe.dart --path datasets\samples
# 期望：sample.pdf → 2 页 / ok；sample.docx → 非空正文；sample.png → 1186x1137 PNG

# 4) 批量入库压测（D4）
dart run packages\core_parsing\bin\ingest_probe.dart --path datasets\coco\val_sample\images
dart run packages\core_parsing\bin\ingest_probe.dart --path datasets\rvlcdip\sample
# 期望：50 + 16 = 66 条元数据，0 崩溃，报告列出 skipped/failed

# 5) UI 层能消费解析层（分层纪律，D1 的证明）
cd apps\desktop
flutter pub get
flutter analyze

# 6) 提交前复核
cd ..\..
git status --short
```

---

## 8. 测试用例矩阵（覆盖率 ≥80% 的来源）

| 用例 ID | 归属 | 场景 | 判定 |
|---|---|---|---|
| PAR-01..04 | TxtParser | UTF-8 / UTF-8 BOM / UTF-16 / GBK 中文 | 正文与预期完全一致 |
| PAR-05..07 | TxtParser | 空文件 / 无换行大单行 / 超过上限的大文件 | `ok` / `ok` / `partial` + 截断标记 |
| PAR-08..10 | ParserRegistry | 已知扩展名 / 未知扩展名 / 大写扩展名 | 命中对应解析器 / `UnsupportedFormat` / 命中 |
| PAR-11..14 | DocxParser | 正常 docx / 缺 `word/document.xml` / 损坏 zip / `docProps` 缺失 | 正文非空 / `failed` / `failed` / 正文可用且 title 为 null |
| PAR-15..18 | TikaCliTextExtractor | `-x` 多页成功 / 无 page div 回退 `-t` / 进程非 0 退出 / Java 缺失 | 页数正确 / 单页 / `failed`+stderr / `ParserUnavailable` |
| PAR-19..21 | PdfParser | `sample.pdf` 集成 / 加密 PDF / 0 字节 pdf | 2 页 / `failed`（记明原因）/ `failed` |
| PAR-22..24 | ImageParser | PNG / JPG / 伪装扩展名的非图片 | 尺寸+格式 / 尺寸+格式 / `failed` |
| ING-01..03 | FileScanner | 递归含子目录 / 隐藏与临时文件被跳过 / 扩展名白名单 | 数量正确 / 不含 `~$`、`.` 开头 / 只留白名单 |
| ING-04..06 | FileMetadata | sha256 稳定 / 时间字段 / 中文与长路径 | 两次一致 / 非空 / 不抛异常 |
| ING-07..10 | IngestionService | 66 文件批量 / 坏文件隔离 / 空目录 / 取消中断 | 报告计数正确 / 其余文件仍成功 / 空报告 / 及时停止且报告 `cancelled` |

> **合计 24 + 若干**用例；`lib/` 中除 `dart:io` 直读与进程调用外，**全部逻辑可被上述用例覆盖**。

---

## 9. W2 专项风险与应对

| 风险 | 触发信号 | 应对（W2 内可执行） |
|---|---|---|
| R2 PDF/DOCX 难接（**最高**） | PDFium 编译或新 pub 包拉不下来 | 按决策 2 走 Tika 兜底，PDFium 推迟到 W3；接口不变，切换只改一个 adapter 文件 |
| R4 覆盖率不达标（**高**） | Day 3 结束 <70% | 错误分支优先补测；进程/文件系统一律经 `ProcessRunner`/`FileSystem` 注入；Day 4 上午必须见 80% |
| Java/JVM 缺失导致 PDF 全挂 | `java -version` 失败 | 解析器返回 `ParserUnavailable`，入库记 `skipped`，报告单列；架构文档写明 PDF 解析的运行前置条件 |
| 中文 TXT 乱码 | GBK 文件读出乱码 | Day 2 就把 GBK/UTF-16 纳入夹具与用例（PAR-03/04） |
| 大文件 / 大目录把内存打爆（R3 前兆） | 内存飙升、耗时线性爆炸 | 单文件 10 MB 上限 + `partial` 标记；入库按文件流式处理，不一次性载入整目录 |
| Tika stderr 噪声污染正文 | 正文里混入 `INFO [main]` | 只取 stdout 作正文，stderr 存诊断字段（决策 3） |
| Windows 路径长度 / 中文路径 | 长路径解析失败 | 用例 ING-06 覆盖；失败只记 `skipped`，不中断整批 |
| 误提交大文件或环境产物（R9） | `git status` 出现 `.tflite`/`.venv`/`chroma_data` | 提交前跑清单第 6 条；夹具体积 < 200 KB 硬约束 |
| 范围膨胀（W2 只有 16h） | 开始写 UI / 接 embedding | 守住第 0 节「红线」与第 10 节「不做清单」 |

---

## 10. W2 明确不做（Scope Guard）

- ❌ BERT / MobileCLIP 接入与向量化（W3）
- ❌ Chroma 写入、检索排序、混合打分（W4）
- ❌ Flutter UI 界面开发、无障碍实现（W5）
- ❌ OCR（扫描件先只登记元数据）
- ❌ PDFium 编译与 FFI 落地（W3 之后替换 `PdfParser` 的实现，接口不动）
- ❌ 把 Python/`engine/` 打进发布包
- ❌ 全量数据集下载（继续只保留验证子集）

---

## 11. 衔接：W2 出口条件 → W3 入口

**W2 出口条件（09/30 全部满足才算完成）**

1. `docs/architecture/system-architecture.md` 定稿，六层图 + 目录映射 + 接口契约齐全。
2. `packages/core_parsing` 对 TXT/PDF/DOCX/JPG/PNG 五格式可用，`dart analyze` 0 issue，`dart test` 全绿。
3. 覆盖率 ≥80%，报告与 `lcov.info` 落在 `reports/week2/`。
4. 批量入库对 66 个真实文件产出正确元数据，坏文件被隔离记录。
5. `docs/api/parsing-module-api.md` + `docs/tdd/technical-design-document.md` v0.1 完成。
6. `reports/week2/W02_report.md` 含用例统计与证据索引；提交入库。

**给 W3 的输入契约（W2 冻结，W3 不得改）**

```dart
// W3 只需消费这一个函数签名即可接入 embedding 引擎
Future<IngestionReport> ingestDirectory(String rootPath, { ... });
// 其中每条记录：FileMetadata + ParsedDocument（text / pages / imageAsset）
```

---

## 附录 A：接口骨架（Day 1 冻结，供评审）

```dart
// lib/src/model/parse_outcome.dart
enum ParseOutcome { ok, partial, skipped, failed }

// lib/src/parsing/parser.dart
abstract interface class DocumentParser {
  String get name;
  String get version;
  Set<String> get supportedExtensions; // 小写，含点，如 {'.pdf'}
  Future<ParseResult> parse(String absolutePath, {CancellationToken? cancel});
}

// lib/src/spi/text_extractor.dart —— PDF/DOCX 的外部进程抽取藏在接口后
abstract interface class TextExtractor {
  Future<ExtractedText> extract(String absolutePath, {CancellationToken? cancel});
}

// lib/src/spi/process_runner.dart —— 单测注入假实现，覆盖率的关键
abstract interface class ProcessRunner {
  Future<ProcessResultLike> run(String exe, List<String> args,
      {String? workingDirectory, Duration? timeout});
}

// lib/src/io/ingestion_service.dart
class IngestionService {
  IngestionService({
    required ParserRegistry registry,
    required MetadataExtractor metadata,
    Executor executor = const ImmediateExecutor(),
    int concurrency = 2,
    int maxFileSizeBytes = 10 * 1024 * 1024,
  });

  Future<IngestionReport> ingestDirectory(
    String rootPath, {
    Set<String> extensions = const {'.txt', '.pdf', '.docx', '.jpg', '.jpeg', '.png'},
    bool followLinks = false,
    int maxDepth = 32,
    void Function(IngestProgress)? onProgress,
    CancellationToken? cancel,
  });
}

// lib/src/model/parsed_document.dart
class ParsedDocument {
  final String fullText;              // 归一化换行，UTF-8
  final List<DocumentPage> pages;     // PDF 多页；单页格式长度为 1
  final ImageAsset? imageAsset;       // 仅 JPG/PNG
  final ParseOutcome outcome;
  final List<String> warnings;        // 例如 encoding-fallback:gbk
}
```

## 附录 B：Tika 命令参考（W2 已验证）

```powershell
# 纯文本（无页码）
java -cp "tools\tika-app\tika-app-4.0.0.jar;tools\tika-app\lib\*" org.apache.tika.cli.TikaCLI -t "datasets\samples\sample.pdf"

# XHTML（保留 <div class="page">，可切页码；sample.pdf 实测 2 个 page div）
java -cp "tools\tika-app\tika-app-4.0.0.jar;tools\tika-app\lib\*" org.apache.tika.cli.TikaCLI -x "datasets\samples\sample.pdf"

# 元数据
java -cp "tools\tika-app\tika-app-4.0.0.jar;tools\tika-app\lib\*" org.apache.tika.cli.TikaCLI --metadata "datasets\samples\sample.pdf"
```

- classpath 分隔符：Windows `;`，macOS/Linux `:`。
- 正文只取 stdout；stderr 为诊断。

## 附录 C：覆盖率百分比计算脚本

```powershell
# 在 packages\core_parsing 下执行，读取 coverage\lcov.info
$lf = 0; $lh = 0
Get-Content coverage\lcov.info | ForEach-Object {
  if ($_ -match '^LF:(\d+)') { $lf += [int]$Matches[1] }
  if ($_ -match '^LH:(\d+)') { $lh += [int]$Matches[1] }
}
$pct = [math]::Round(100.0 * $lh / $lf, 2)
"lines hit $lh / $lf = $pct%"
if ($pct -lt 80) { throw "W2 覆盖率门槛未达标：$pct% < 80%" }
```

---

## 附录 D：W2 结束时仓库应新增的文件树

```text
docs/
  tasks/week2_task.md                     ← 本文件
  architecture/system-architecture.md      ← D1
  architecture/adr/0001-parsing-runtime-dart-package.md
  architecture/adr/0002-pdf-extraction-tika-then-pdfium.md
  api/parsing-module-api.md                ← D5
  tdd/technical-design-document.md         ← D6
packages/core_parsing/
  pubspec.yaml  analysis_options.yaml  README.md
  lib/core_parsing.dart
  lib/src/model/{file_metadata,parsed_document,document_page,image_asset,parse_result,ingestion_report}.dart
  lib/src/parsing/{parser,parser_registry}.dart
  lib/src/parsing/parsers/{txt_parser,pdf_parser,docx_parser,image_parser}.dart
  lib/src/parsing/adapters/tika_cli_text_extractor.dart
  lib/src/spi/{text_extractor,process_runner,cancellation_token,executor}.dart
  lib/src/io/{file_scanner,file_reader,metadata_extractor,ingestion_service}.dart
  bin/{parse_probe,ingest_probe}.dart
  test/**（含 fixtures/ 与 24+ 用例）
reports/week2/
  W02_report.md  覆盖率报告.md
  coverage/lcov.info
  logs/{dart_analyze.txt,dart_test.txt,coverage.txt,ingest_samples.txt}
  screenshots/*.png
apps/desktop/pubspec.yaml                 ← 增加 core_parsing path 依赖
```
