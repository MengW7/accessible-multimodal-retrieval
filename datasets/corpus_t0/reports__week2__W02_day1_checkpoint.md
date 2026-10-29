# W02 Day 1 检查点：架构落地 + 接口冻结

| 项目 | 内容 |
|---|---|
| 日期 | 2026-09-27（计划 W2 Day 1） |
| 计划工时 / 实际 | 4h / 4h |
| 对应方案 | `docs/tasks/week2_task.md` §6 Day 1（步骤 1.1 – 1.7） |
| 结论 | **Day 1 全部步骤完成，验收命令全部通过**；可进入 Day 2（TXT + DOCX 解析器） |

---

## 1. 步骤完成情况

| 步 | 计划内容 | 实际产出 | 计划判据 | 实测结果 |
|---|---|---|---|---|
| 1.1 | 建包骨架 | `packages/core_parsing/{pubspec.yaml, analysis_options.yaml, README.md, .gitignore, lib/, test/, tool/}` | `dart pub get` 成功、`dart analyze` 0 issue | ✅ 离线解析 52 个依赖；`No issues found!` |
| 1.2 | `apps/desktop` 以 path 依赖接入 | `apps/desktop/pubspec.yaml` + `pubspec.lock` | `flutter pub get` 成功 | ✅ `+ core_parsing 0.1.0 from path ..\..\packages\core_parsing`，退出码 0 |
| 1.3 | 冻结核心模型 | `lib/src/model/` 六个文件，10 个 `@immutable` 值对象，全部含 `==/hashCode/toJson()` | 类型不可变、含 `toJson()` | ✅ |
| 1.4 | 冻结接口 | `lib/src/parsing/{parser,parser_registry}.dart`、`lib/src/spi/{cancellation_token,executor,process_runner,text_extractor}.dart` | 均为 `abstract interface class`；`dart analyze` 干净 | ✅ 并有契约条款 P1–P8（架构文档 §6.3） |
| 1.5 | 建测试夹具 | `test/fixtures/` 15 个文件 + 可重跑生成器 `tool/make_fixtures.py` | 夹具齐备、总体积 < 200 KB | ✅ **2 060 B**（预算 204 800 B） |
| 1.6 | 架构设计文档 | `docs/architecture/system-architecture.md`（23.6 KB，18 节，含 2 张 Mermaid 图） | 含六层架构图；能回答「新增格式改哪几个文件」 | ✅ 见文档 §3、§4.1 |
| 1.7 | ADR | `docs/architecture/adr/0001-…dart-package.md`、`0002-…tika-then-pdfium.md` | 每份含 Context / Decision / Consequences / Alternatives | ✅ |

### 1.1 冻结的公开接口（`lib/core_parsing.dart`）

值对象：`ParseOutcome`、`DocumentPage`、`ImageAsset`、`ParsedDocument`、`ParseFailure`、`ParseResult`、`FileMetadata`、`IngestRecord`、`IngestionReport`、`IngestProgress`。

接口：`DocumentParser`、`ParserRegistry`、`TextExtractor`、`ProcessRunner`、`Executor`、`CancellationToken` / `CancellationTokenSource`。

### 1.5 夹具清单

| 夹具 | 用途 |
|---|---|
| `hello.txt`（CRLF）、`hello_utf8_bom.txt`、`hello_gbk.txt`、`hello_utf16le.txt` | TXT 编码矩阵（含中文 GBK / UTF-16） |
| `UPPER.TXT` | 扩展名大小写不敏感 |
| `empty.txt`、`zero.pdf` | 0 字节边界 |
| `nested/a.txt` | 递归扫描 |
| `.hidden.txt`、`~$temp.docx` | 扫描必须跳过 |
| `truncated.pdf`（声明长度 > 实际字节） | 损坏 PDF 的降级路径 |
| `corrupt.docx`、`fake.png` | 伪装扩展名的非目标格式 |
| `docx_minimal.docx`（真实 OOXML，含 `word/document.xml` + `docProps/core.xml`，段落跨多个 `w:r`） | Day 2 DOCX 解析主用例 |
| `tiny.png`（真实 8×8 RGB PNG） | Day 3 图像元数据 |

---

## 2. 验收命令与结果

```powershell
cd packages\core_parsing
dart pub get --offline      # ✅ Changed 52 dependencies!（全部命中本地 pub 缓存，零联网）
dart analyze .              # ✅ No issues found!                      exit=0
dart test                   # ✅ All tests passed! 28 个契约测试         exit=0

cd apps\desktop
flutter pub get --offline   # ✅ Changed 7 dependencies!（含 core_parsing 0.1.0） exit=0
```

### 契约测试覆盖（28 个用例）

| 分组 | 用例数 | 验的东西 |
|---|---|---|
| `ParseOutcome` 词汇表 | 2 | 枚举值顺序/名称冻结；`isUsable` 语义 |
| `ParseFailure` 降级映射 | 3 | 7 个 `kind` → `outcome` 全覆盖；新增 kind 会让测试失败 |
| `ParsedDocument` | 4 | 页数回退规则、空白文本为 0 页、显式分页优先、图像-only 判定 |
| `ParseResult` | 2 | 成功/失败两侧的 `outcome` 推导 |
| `FileMetadata` | 4 | `isIndexable`、`copyWith`、`toJson` 字段完整性、值相等 |
| `IngestionReport` / `IngestProgress` | 5 | 分类计数、`indexable`、失败清单、取消不 clean、进度分数边界 |
| `CancellationToken` | 4 | 协作式取消、幂等、监听器、`whenCancelled` |
| 注入缝 | 4 | `ImmediateExecutor`、`ProcessRunResult`、接口可从包外实现 |

> 其中「接口可从包外实现」这个用例是刻意加的：`abstract interface class` 若被误写成不可实现的形态，Day 2 的解析器就会编译不过，这里提前暴露。

### Day 1 发现并修掉的两个真实缺陷

1. **`ParsedDocument.pageCount`**：原实现按 `fullText.isEmpty` 判断，导致「只有空白字符」的文档被算作 1 页。已改为按 `hasText` 判断（空白 → 0 页），与「无可供嵌入的内容」的语义一致。
2. **测试替身 `_FakeRegistry.resolveForPath`**：把整条路径当扩展名传下去，`resolveForExtension` 因此永远返回 `null`。已改为先取 `lastIndexOf('.')` 再分派 —— 这条同时也固化了 registry 的调用约定。

---

## 3. 证据文件

| 文件 | 内容 |
|---|---|
| `reports/week2/logs/day1_dart_analyze.txt` | `No issues found!` |
| `reports/week2/logs/day1_dart_test.txt` | 28 个用例逐条通过记录 |
| `reports/week2/logs/day1_flutter_pub_get.txt` | `core_parsing 0.1.0 from path` 解析结果 |

---

## 4. 与计划的偏差（及理由）

| 偏差 | 理由 |
|---|---|
| 测试夹具**不复制** `datasets/samples/` 的 pdf/docx/png，改为合成小型夹具 | 原计划允许"复制并注明来源"，但三份样本合计 281 KB，会突破自设的 200 KB 夹具预算（`sample.png` 单文件 193 KB）。改为：合成夹具保证包自包含且体积可控，Day 2/Day 3 的**集成测试**直接读 `datasets/samples/`，避免同一份二进制在仓库里存两份。 |
| 新增 `packages/core_parsing/tool/make_fixtures.py` | 夹具里的 GBK/UTF-16 字节与被故意截断的 PDF 都是"契约的一部分"，脚本化后意图可评审、可重跑。已注明 Python **不是** Dart 包的构建依赖。 |
| 新增 `packages/core_parsing/.gitignore`（忽略本包 `pubspec.lock`） | Dart 约定：包不提交 lockfile，由消费方 `apps/desktop/pubspec.lock` 作为版本唯一来源，避免两份锁文件漂移。 |
| 架构文档把第三~五层的接口写成**文档契约**而非代码 | 计划里写的是"只在架构文档与接口文件中冻结契约"；W2 不建空包，避免仓库里出现没有实现、没有测试的 `core_embedding/` 等占位包。 |

---

## 5. 环境注意事项（供后续周次复用）

1. **沙箱模式下 `dart analyze` / `dart test` / `flutter pub get` 无法运行**：这三个命令都会启动 Dart 子进程（分析服务器、测试 VM），在受限沙箱下直接 `Access denied`；且 `dart pub get` 在出错时会尝试写 `%LOCALAPPDATA%\Pub\Cache\log`。本次 Day 1 的验收命令是在放宽权限后执行的，属预期内的例外，不是命令本身的问题。
2. **离线可用性已证实**：`dart pub get --offline` 全部命中本地 pub 缓存；`flutter pub get --offline` 同样成功。这消除了风险 R7 中"依赖拉不下来"的担忧。
3. **PDF 解析依赖 `java`**：`C:\Program Files\Common Files\Oracle\Java\javapath\java.exe`（JDK 17.0.4）。缺失时必须走 `ParseFailureKind.dependencyUnavailable` 降级（ADR 0002）。

---

## 6. 下一步（Day 2：TXT + DOCX）

1. `TxtParser`：UTF-8 / UTF-8 BOM / UTF-16 LE / GBK + 换行归一 + 超大文件截断，逐个夹具跑通。
2. `ParserRegistry` 具体实现（`DefaultParserRegistry`），大小写与未知扩展名行为按 Day 1 冻结的约定。
3. `DocxParser`：`archive` + `xml` 解 `word/document.xml`，段落按 `w:p` 切、run 按 `w:t` 合；`docProps/core.xml` 取 title/creator。
4. `TikaCliTextExtractor`：平台 classpath 分支、stderr 分离、超时、缺 Java 分支，**全部用假 `ProcessRunner` 覆盖**。
5. Day 2 出口：`dart test` 全绿，覆盖率估算 ≥55%。
