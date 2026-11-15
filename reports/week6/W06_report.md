# W06 report

1. [测试与覆盖率报告](#测试与覆盖率报告)
2. [缺陷修复与安全审查报告](#缺陷修复与安全审查报告)
3. [性能优化基准报告](#性能优化基准报告)

## 测试与覆盖率报告

原 D5 候选源码为 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e`。五包覆盖率、Flutter 集成及原生桌面实测均绑定该候选。11 月 15 日关键词优化的新增单测和生产 AOT 对照单独记录。无界面测试使用隔离库及合成夹具。 [构建与环境绑定](logs/D5_candidate_manifest.json) · [优化探针对照](benchmarks/D5_10k_probe_summary.json)

### 测试矩阵

| 编号与层级 | 输入、执行和实际证据 | 判定 |
|---|---|---|
| UT-01 核心单元测试 | 五包逐包分析、单测、LCOV。夹具覆盖坏文件、编码、分词、写入回滚、向量类型、索引复用、筛选和取消。 | 见下方单测汇总。 |
| IT-01 真实集成 | 独立生产资源根运行真实 ORT、Tika、SQLite 和 worker。固定 TXT/DOCX/PDF/PNG 走全链路，对照文本、图像、来源及跨进程重启。Flutter 集成另覆盖筛选、来源及打开请求。 | 通过。系统打开通道使用替身的范围单列。 |
| IT-02 故障恢复集成 | 真 worker 回归覆盖双写锁、主库锁、坏 DOCX 修复及关闭入口。另测缺 Java、缺资源和数据路径被占用。 | 自动项通过。建库中直接关窗、双窗口和 Windows ACL 按 D5-M04 待原生复验。 |
| E2E-01 原生桌面 | 10k 实测经原生选择器导入，并在退出重启后重查，Top-5 路径顺序一致。D1 M-04 主流程由操作者确认执行；M-05 恢复后通过 Acrobat 打开 PDF。 [桌面原始数据](benchmarks/D5_10k_desktop.json) · [M-05 实测](logs/M05.txt) | Windows 部分通过。D1 M-04 查看器截图和重查记录待回填，D5 生产模式的完整断网闭环待补同场证据。 |
| E2E-02 原生桌面 | M-05 实测 PDF 缺失与恢复、取消续建、清空和源文件哈希；原样增量沿用 M-04 证据。10k 原生测试另验证单文件增量、恢复原文及清空。 [M-05 实测](logs/M05.txt) · [桌面原始数据](benchmarks/D5_10k_desktop.json) | 已执行场景通过。D5 建库中直接关窗、双窗口冲突和 Windows ACL 恢复待原生实测。 |
| E2E-03 无障碍 | D5 候选 Flutter 语义、键盘与显示测试通过。Windows 人工部分沿用 W5 键盘、NVDA 及显示证据，含朗读原文和字号、高对比截图。 [W5 验收矩阵](../week5/E_验收矩阵.md) · [W5 NVDA 会话](../week5/logs/screen_reader_nvda_session.md) | Windows 人工范围沿用 W5 的部分验证判定。macOS VoiceOver 随目标机单独验证。 |
| E2E-04 跨平台 | Windows 有本机编译、生产无界面数据和部分原生实测。macOS/Linux 宿主和三平台 CI 工作流已配置。 | 三平台 CI、macOS/Linux 生产适配及目标机辅助技术验证暂缓。 |
| UX-01 独立试用 | W5 T1–T5 保留同一输入、计分及用时口径，D5 提供场次记录与候选绑定。 | 暂缓。独立试用 0 人、已执行任务 0 项。 |
| ST-01 压力 | D4 已测 1k／5k／10k。D5 桌面从 9,907 份夹具入库 9,906 份、10,000 块，完成取消续建、增量和清空，SQLite 检查与夹具哈希核对通过。全库和 TXT 各有 30 次桌面样本。 [桌面用例及内存采样](性能优化基准报告.md) | 已执行桌面场景通过。查询实际为 `0`，中文桌面计时仍待补，TXT 组后 9 次缺工作集采样。性能预算按性能报告逐项判定。 |
| SEC-01 离线安全 | D4 静态审查和 274 次无界面 TCP 采样。D1 M-06 断网主流程由操作者确认执行。 [安全审查](缺陷修复与安全审查报告.md) | 部分验证。隔离对照、应用及 Java 的 DNS／出站观察与系统查看器记录待补。 |

自动结果和候选入口见 [Flutter 测试](logs/D5_flutter_production.txt)、[真实集成 JSON](logs/D5_headless_production.json)、[D5 生产冒烟](logs/D5_runtime.json)、[跨进程重启](logs/D5_restart.json)、[故障恢复](logs/D5_library.json)。人工回填见 [D5 清单](D5_人工验证清单.md)。

### 平台证据

| 平台 | 本地构建 | 同 SHA CI | 真实运行时与原生 |
|---|---|---|---|
| Windows x64 | release 编译通过 | 未核实，暂缓 | 无界面生产链路通过。原生选目录、重启和恢复已执行。D1 断网主流程已确认，隔离与出站证据待补。读屏沿用 W5 部分实测。 |
| macOS | 待目标环境构建 | 未核实 | Windows 原生 ONNX 适配需移植。原生主流程和 VoiceOver 待补。 |
| Linux | 待目标环境构建 | 未核实 | Windows 原生 ONNX 适配需移植。原生主流程及桌面辅助技术待补。 |

GitHub Actions 的常规作业包括分析、Widget/单元测试和 release 构建。真实模型集成使用本机明确启用的独立测试。 [CI 配置](../../.github/workflows/ci.yml) · [CI 查询记录](logs/D5_ci_access.txt)

### 原 D5 候选的核心单测与覆盖率

排除 `integration` 标签，各包只统计 `lib/` 的 LCOV `LH/LF`。D5 重新生成分母和命中数。

| 包 | 通过 | 命中 / 总行数 | 行覆盖率 | LCOV 与单测 |
|---|---:|---:|---:|---|
| core_parsing | 99 | 987 / 1,091 | 90.47% | [LCOV](coverage/D5/core_parsing.lcov.info) · [单测](logs/D5_core_parsing_tests.txt) |
| core_embedding | 100 | 1,337 / 1,467 | 91.14% | [LCOV](coverage/D5/core_embedding.lcov.info) · [单测](logs/D5_core_embedding_tests.txt) |
| core_storage | 30 | 666 / 733 | 90.86% | [LCOV](coverage/D5/core_storage.lcov.info) · [单测](logs/D5_core_storage_tests.txt) |
| core_pipeline | 26 | 282 / 309 | 91.26% | [LCOV](coverage/D5/core_pipeline.lcov.info) · [单测](logs/D5_core_pipeline_tests.txt) |
| core_retrieval | 13 | 165 / 173 | 95.38% | [LCOV](coverage/D5/core_retrieval.lcov.info) · [单测](logs/D5_core_retrieval_tests.txt) |

共 268 项核心单测与 68 项 Flutter 测试通过。五个核心包及桌面静态分析均通过。Flutter 套件含真资源集成，桌面原生签收依第一个表格逐项补证。 [Flutter 分析](logs/D5_flutter_analyze.txt) · [Windows 构建](logs/D5_windows_build.txt)

### 关键词优化后的回归

在原 D5 源码上应用归档补丁，针对存储和检索两包复跑单测并按相同口径重采 LCOV。其余三包及 Flutter 的上节数据来自原 D5 候选。 [关键词补丁](benchmarks/D5_10k_keyword.patch) · [执行命令及退出码](logs/D5_10k_keyword_lcov.txt)

| 包 | 通过 | 命中 / 总行数 | 行覆盖率 | LCOV |
|---|---:|---:|---:|---|
| core_storage | 31 | 702 / 769 | 91.29% | [优化后 LCOV](coverage/D5_keyword/core_storage.lcov.info) |
| core_retrieval | 13 | 165 / 173 | 95.38% | [优化后 LCOV](coverage/D5_keyword/core_retrieval.lcov.info) |

另从独立源码副本构建含关键词优化的 Windows x64 release。仅运行专用生产冒烟入口，索引 4 份文档、98 个内容块并返回 5 条来源。该构建的中文桌面时延、故障恢复和断网原生场景仍待窗口实测。 [构建及哈希](logs/D5_10k_keyword_candidate.json) · [生产冒烟结果](logs/D5_10k_keyword_windows_smoke.json)

### 复跑方式

在各核心包目录执行，`$raw` 和 `$lcov` 指向新的覆盖率路径。

```powershell
dart analyze
dart test --exclude-tags integration "--coverage=$raw" --reporter expanded
dart run coverage:format_coverage --lcov "--in=$raw" "--out=$lcov" --report-on=lib --package=.
```

在 `apps/desktop` 执行，`$runtime` 为生产资源的绝对路径。

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --dart-define=AMR_E_REAL_RUNTIME=true `
  "--dart-define=AMR_E_RUNTIME_ROOT=$runtime" `
  --dart-define=AMR_E_REPORT_PATH=reports/week6/logs/D5_headless_recheck.json --reporter expanded
flutter build windows --release --no-pub
```

独立 Dart 进程的 `runtime`、`restart`、`library` 用同一生产资源和隔离数据目录，命令入口与参数见 [D2 复现说明](W06_D2_checkpoint.md)。D5 的原生命令保留在 [首次索引日志](logs/D5_runtime.txt)、[重启日志](logs/D5_restart.txt) 和 [worker 日志](logs/D5_library.txt)。

## 缺陷修复与安全审查报告

本报告汇总 D3 缺陷复现、D4 静态与动态安全审查及 D5 候选回归。Windows 原生离线验收处于部分验证状态。 [D3 阶段记录](W06_D3_checkpoint.md) · [D5 签收记录](W06_D5_checkpoint.md)

| 范围 | D4 源码审查结论 |
|---|---|
| 生产模型与遥测 | [运行配置](../../apps/desktop/lib/src/runtime/runtime_config.dart) 使用可执行程序旁或显式指定的绝对资源目录。没有模型获取逻辑。原生 DLL 在 [ONNX 桥](../../native/onnx/bridge.cpp) 初始化时关闭 ORT 遥测。开发 Python 模式需显式配置，另行验收。 |
| Java/Tika 与源文件 | [摄取](../../packages/core_parsing/lib/src/io/ingestion_service.dart) 默认不跟随扫描时遇到的符号链接。[Tika 调用](../../packages/core_parsing/lib/src/parsing/adapters/tika_cli_text_extractor.dart) 传递本地 classpath 和源文件绝对路径，参数分项，无 shell 或 Tika Server。PDF 正文从子进程 stdout 读取到应用，stderr 在失败分支可能进入诊断。Java 命令行包含源路径。 |
| SQLite 和设置 | [工作进程](../../apps/desktop/lib/src/runtime/library_worker.dart) 及 [显示设置](../../apps/desktop/lib/src/runtime/display_settings_store.dart) 写入应用数据目录；索引包含正文、来源、元数据、词项、向量和代次。包含 SQLite WAL/SHM 及写入锁数据库，目录和显示设置更新时使用同目录临时文件。清空是逻辑删除，不等于安全擦除，磁盘备份、WAL 与空闲页不在擦除保证内。 |
| 查询、诊断、导出 | 查询和片段用于本进程检索与显示。审查的生产入口未发现主动网络请求、查询日志或日志上传。诊断可包含机器绝对路径和错误详情；显式工程 smoke JSON 可包含绝对路径、查询和测试结果。项目证据只用合成数据；外发日志前应检查路径、文件名、片段及错误上下文。 |
| 系统查看器与路径范围 | [打开入口](../../apps/desktop/lib/src/runtime/file_opener.dart) 验证绝对路径和文件存在后交给系统关联应用。查看器可有独立网络行为。绝对路径检查不等同于本地卷限制，UNC、映射盘、同步盘和根目录重解析点不在本次本机普通卷证据内。 |
| 依赖与平台边界 | 审查覆盖仓库入口、进程调用和配置，并未穷举 ORT、Tika/JVM、系统及查看器的内部实现。Windows 有本地原生运行资源，macOS/Linux 的生产运行、平台网络审计待复验。 |

SEC-01 完整签收依赖 [D4-M03/M04](D4_人工验证清单.md) 的实际隔离、DNS/连接及查看器证据。

### Windows 无界面动态证据

在独立目录用原生 ORT、Java/Tika 和 10k 索引副本执行会话冷开、查询、修改一份夹具并取消、重开、续建、清空和退出。对本次探针及已识别的直接 Java 子进程做了 **274 次** Windows TCP 状态表采样，未观察到归属探针或其 Java 子进程的 TCP 端点。退出后未发现本次采到的 Java 子进程仍在运行。为该进程树设置独立 TEMP/TMP，归档探针报告后未见残留文件。清空后无检索结果，SQLite 完整性检查通过，目录中保留 `lifecycle.sqlite`（52,817,920 字节）。

覆盖 9,907 份合成或固定夹具的相对路径和内容 SHA-256 清单前后一致。生命周期主动改动过一个测试副本，测试结束时已恢复原字节。TCP 采样不记录 DNS、UDP、系统代理或短于采样间隔的连接，不能证明零外发；这轮未主动隔离网络、未启动桌面程序或系统查看器。

[生命周期结果](benchmarks/D4_lifecycle.json) · [工作集及 TCP 原始采样](benchmarks/D4_lifecycle.json.monitor.json) · [夹具核对前](benchmarks/D4_corpus_before.json) · [夹具核对后](benchmarks/D4_corpus_after.json)

### D5 候选回归

D5 Windows 候选对应源码 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e`。13 个构建文件 SHA-256 与 D4 清单一致。真实 Flutter 回归复测 D3-P1-01 双 worker 写冲突、锁释放重试、源数据保留、坏文件修复与建库关闭入口。存储单测复测 D3-P2-01 的损坏向量 BLOB 诊断。 [候选清单](logs/D5_candidate_manifest.json) · [真实 worker 回归](logs/D5_flutter_production.txt) · [存储单测](logs/D5_core_storage_tests.txt)

仓库外工作目录的 Dart 生产探针写入 4 份文档、98 个块，另一个进程复核了相同的五条结果及出处。独立 worker 探针验证增量复用、取消续建、清库与源文件内容保留。缺 Java、缺资源时退出 1，诊断与实际失败条件一致。 [生产链路](logs/D5_runtime.json) · [重启](logs/D5_restart.json) · [worker 恢复](logs/D5_library.json) · [缺 Java](logs/D5_missing_java.json) · [缺资源](logs/D5_missing_resources.json)

### 缺陷复测与签收状态

| 项目 | 修复版本及复测证据 | 当前状态 |
|---|---|---|
| D3-P1-01 双实例索引写入冲突 | D5 `04c22914a86f9` 已包含 D3 写入锁修复。两个真实 worker 使用同一数据目录，第二个 worker 在首个正在建库时收到拒绝，首个完成后可重试并复用 24 份。 [复现及修复](W06_D3_checkpoint.md) · [候选集成回归](logs/D5_flutter_production.txt) | 修复已通过 worker 回归，原生双窗口场景待关闭确认。 |
| D3-P2-01 损坏向量 BLOB | D5 `04c22914a86f9` 包含结构化错误诊断。存储回归覆盖持久化向量类型损坏。 [存储测试](logs/D5_core_storage_tests.txt) | 已修复并复测。 |
| 建库中关窗与恢复 | D5 worker 收尾入口已有回归；10k 场次验证了主动取消后退出重启及续建。 [候选集成回归](logs/D5_flutter_production.txt) · [10k 桌面数据](benchmarks/D5_10k_desktop.json) | 原生长任务中直接关窗并重启续建待实测。 |
| Windows ACL 拒绝与恢复 | D5 有主库锁和数据路径占用后的恢复证据。 [故障恢复](logs/D5_library.json) · [真实 worker 集成](W06_D3_checkpoint.md) | 实际 ACL 拒绝及恢复权限后重试待实测。 |

以上状态覆盖已登记的缺陷和相关待验场景。全局 P0/P1 关闭状态待核对。M-05 已验证 PDF 缺失与恢复、取消后续建和清空，清空前后 1,004 份源文件路径和 SHA-256 一致。后续 10k 桌面场次的两个隔离库均通过 SQLite `quick_check`，9,907 份夹具路径及 SHA-256 前后一致。 [M-05 实测](logs/M05.txt) · [10k 桌面证据](benchmarks/D5_10k_desktop.json)

### Windows 原生断网证据

| 验收项 | 当前可引用的证据及待补内容 |
|---|---|
| D1 M-06 主流程 | 操作者确认断网主流程已执行。待回填执行时间、隔离方式、隔离前后连通性对照及各操作实际结果。 [D1 人工验证清单](D1_人工验证清单.md) |
| 应用及 Java 子进程 | D4 仅有无界面 TCP 状态采样。原生场次待记录观察时间、进程归属、工具覆盖范围和 DNS、TCP、UDP 或阻止事件。缺现场采样的项目待补测。 [D4 采样](benchmarks/D4_lifecycle.json.monitor.json) |
| 系统查看器 | 待分别记录查看器进程、打开的文件和该进程的出站观察。D5 完整签收仍需同一 Windows 生产候选在隔离条件下的导入、查询、打开和重启证据。 [D5 实机步骤](D5_人工验证清单.md) |

## 性能优化基准报告

D4 在 Windows x64 上以原生 ONNX Runtime CPU 运行完整解析、嵌入、SQLite 和检索链路。预算在采样前固定，见 [D4 判据](benchmarks/D4_acceptance.md)。D1 的 Python 结果是历史参考，收益用 D4 的原生优化前后直接计算。

### 采样口径

- 使用同一台 Ryzen 7 5800H 主机、Windows 11 Pro 26300、Dart 3.13.4 AOT，探针在 Windows 系统目录启动。生产运行资源沿用 D2 的 ONNX Runtime 1.23.2 CPU、MiniLM、MobileCLIP、Java 21 / Tika 4.0.0 和本机 SQLite。
- 小夹具沿用 D1 的 TXT、DOCX、PDF、PNG。扩容使用确定性短 TXT，按固定 ID 加入 a/ 或 b/，外加一个故意损坏的 DOCX。1k、5k、10k 为同一库逐级扩容后关闭 SQLite 得到的快照。扩容耗时包含全目录扫描、解析、计算复用和写入新增内容，每档只跑一次扩容，分别报告实测耗时。
- 固定查询“离线检索”、Top-5 及默认文本、图像和关键词通道。大库测全库和 a/ 前缀，独立向量扫描使用固定 384 维单位向量及 Top-50，小夹具用 Top-5。会话冷态用 5 个新库，操作系统磁盘缓存未清；热态每组 30 次，大库先预热 3 次。p50/p95 用最近秩法。融合与管道子阶段沿用检索器的整数毫秒观测，0 表示不足 1 ms。
- 原生会话加载在桥调用边界计时。热前向含桥内 ORT 执行和输出拷贝，不含 Dart 分词、图像预处理及张量分配。运行时本身未更换模型、线程、精度或 ONNX 图。端到端热管道不含 Flutter 渲染、界面回传和系统查看器。
- 工作集约每 100 ms 采样，计入探针和其 Java 子进程。Dart RSS 另行记录。共享页可能重复计数，采样可能错过尖峰。出站采样另放生命周期运行，避免 netstat 查询影响前后性能基准。

### 优化机制

原实现先用 SQLite ResultSet 物化整批向量。达到候选阈值后，如果大量向量分数相同，每加入一行都可能对不断变长的列表重新排序。新实现用 SQLite 游标逐行读取 BLOB，只在积累足够多的严格高分时重算阈值。保留分数边界上的全部同分候选，分批读取路径、页码和偏移，并在每批后只保留当前 Top-K。最终按已选顺序回填展示字段。分数、路径、页码及偏移完全相同时，以行 ID 结束比较，避免分批大小左右并列结果。库表与向量格式未变。

普通查询与全同分压力分别报告。全同分对照只在隔离的 10k 索引副本中，把文本向量替换为同一个单位向量；真实语料快照不受影响。

### 实测结果

| 块数 | 扫描文件（含坏件） | 入库文档 | 新写入 / 复用 | 本档耗时（s） |
|---:|---:|---:|---:|---:|
| 1,000 | 907 | 906 | 906 / 0 | 39.61 |
| 5,000 | 4,907 | 4,906 | 4,000 / 906 | 213.43 |
| 10,000 | 9,907 | 9,906 | 5,000 / 4,906 | 422.39 |

每档的坏 DOCX 都被单列为解析失败，未阻塞其他文档。三档索引均通过 SQLite quick_check。10k 库取消在第一份修改提交后触发，取消请求至安全返回 **0.07 ms**。重开 SQLite 后 Top-5 一致，续建在 11.13 s 内复用 **9,906** 份文档。恢复源文件后只重写 1 份，回到原 Top-5；清空后无结果且 quick_check 通过。这一取消计时起于回调安全点，不能代表用户从任意进度点击取消的延迟。

热态表中每格为 **p50 / p95（ms）**，每配置 30 次：

| 内容块 / 筛选 | 向量扫描前 | 向量扫描后 | 热管道前 | 热管道后 |
|---|---:|---:|---:|---:|
| 98 / 全库 | 0.30 / 0.35 | 0.31 / 0.61 | 33.47 / 43.67 | 36.42 / 52.07 |
| 1,000 / 全库 | 6.82 / 7.29 | 6.73 / 7.17 | 56.60 / 65.15 | 62.72 / 71.64 |
| 1,000 / a/ 前缀 | 5.92 / 6.32 | 6.10 / 6.64 | 54.85 / 63.18 | 54.85 / 60.04 |
| 5,000 / 全库 | 32.24 / 33.66 | 31.93 / 33.37 | 200.21 / 213.29 | 200.84 / 213.79 |
| 5,000 / a/ 前缀 | 29.10 / 29.95 | 29.37 / 30.65 | 165.35 / 173.48 | 166.13 / 176.20 |
| 10,000 / 全库 | 64.62 / 65.87 | 64.83 / 65.85 | 354.59 / 368.39 | 363.56 / 416.24 |
| 10,000 / a/ 前缀 | 58.09 / 60.54 | 59.20 / 60.68 | 298.60 / 321.30 | 296.49 / 312.70 |

10k 全同分扫描从 **562.02 / 590.45 ms** 降到 **125.87 / 127.40 ms**，p95 下降 **78.4%**。普通 10k 全库的扫描 p95 为 **65.87 → 65.85 ms**。同一配置下前后 Top-5 与独立扫描结果完全一致，包括路径、页码、UTF-16 偏移、分数、通道及片段。10k 全库优化后管道子阶段的 p95 为编码 **54 ms**、存储及邻域 **360 ms**、融合 **0 ms**。这些分位值不可直接相加。

会话冷态与模型 **p50 / p95（ms）**。各 5 轮冷态，热前向每模型 30 条：

| 阶段 | 优化前 | 优化后 |
|---|---:|---:|
| 打开会话 / SQLite | 376.25 / 9903.06 | 360.61 / 9892.50 |
| 98 块冷建库 | 7070.75 / 7756.87 | 7358.83 / 7861.98 |
| 建库后首次查询 | 225.94 / 258.58 | 214.45 / 237.18 |
| MiniLM 会话加载 | 487.49 / 555.85 | 495.37 / 540.15 |
| MiniLM 热前向 | 21.73 / 27.90 | 23.87 / 35.80 |
| CLIP 文本 会话加载 | 197.52 / 221.58 | 185.90 / 200.97 |
| CLIP 文本 热前向 | 9.69 / 12.03 | 10.44 / 15.42 |
| CLIP 视觉 会话加载 | 117.59 / 140.12 | 116.03 / 119.15 |
| CLIP 视觉 热前向 | 14.48 / 19.35 | 19.04 / 23.01 |

| 运行 | 探针 + Java 采样峰值 | Dart 峰值 RSS |
|---|---:|---:|
| 三级建库 | 834.34 MiB | 957.70 MiB |
| 优化前冷热基准 | 908.18 MiB | 1023.01 MiB |
| 优化后冷热基准 | 923.01 MiB | 1023.80 MiB |
| 10k 生命周期 | 1134.23 MiB | 1010.09 MiB |

10k 全库热查及扫描完成后，Dart 的即时 RSS 为 **772.71 → 764.91 MiB**。该数值包含已经加载的会话和分配器保留页。峰值工作集也包含各轮 Java/Tika；单轮跨进程差异不作为模型内存优化收益。

优化后以下项目超出预算：10k 全同分扫描 127.40 ms（预算 60 ms）；5000 all 热管道 213.79 ms（预算 200 ms）；10000 all 扫描 65.85 ms（预算 60 ms）；10000 all 热管道 416.24 ms（预算 200 ms）；10000 a/ 扫描 60.68 ms（预算 60 ms）；10000 a/ 热管道 312.70 ms（预算 200 ms）。其余项目达标。推理实现保持相同，模型时延仅用于确认预算和识别瓶颈。两版首次打开会话约 9.9 秒，其余会话低于一秒，单独列出；尚未拆分首次加载 DLL、SQLite 初始化与系统冷启动开销。

真实 10k 普通向量扫描基本持平，全库热管道本轮 p95 从 368.39 ms 变为 416.24 ms，主要耗时在存储段。对同一快照只读复核，查询“离线检索”的中文 bigram 命中 **9,903** 个候选。D4 的关键词实现读取所有候选的正文和展示字段后才截取 Top-K。11 月 15 日已完成候选聚合和回填分段测量，并复测延后回填的改动。逐行精确向量扫描仍随块数增长。 [D4 候选核对](logs/D4_keyword_candidates.txt) · [11 月 15 日中文复测](#2026-11-15-中文关键词性能复测)

[扩容逐档](benchmarks/D4_growth.json) · [优化前原始样本](benchmarks/D4_before.json) · [优化后原始样本](benchmarks/D4_after.json) · [生命周期](benchmarks/D4_lifecycle.json) · [统计与排序对照](benchmarks/D4_summary.json) · [资源与快照绑定](benchmarks/D4_bindings.json)

### 复跑

在仓库根目录用 PowerShell 7.4 或以上。优化前探针可从 D3 基点 `8c69dff80c5684b60676f16f99b0cedb1fec30d1` 重建：带入 D4 的探针脚本和 `native_onnx.dart`、`runtime_session.dart` 的观测接口，保留基点的 `core_storage`。优化后从当前版本构建。两版均执行：

```powershell
dart compile exe apps/desktop/tool/week6_pressure.dart -o .dart_tool/w06-d4/probe.exe
```

把两个探针放到同一环境，确保已准备 D2 的本地生产资源；报告路径使用新文件，库路径使用新目录。先用优化前探针生成快照，再顺序运行两版测量和优化后的生命周期：

```powershell
$run = './apps/desktop/tool/week6_pressure.ps1'
$before = './.dart_tool/w06-d4/before.exe'
$after = './.dart_tool/w06-d4/after.exe'
$runtime = './.dart_tool/w06-d2-ort/local-runtime'
$work = './.dart_tool/w06-d4/recheck'
$out = './reports/week6/benchmarks/recheck'
New-Item -ItemType Directory -Force $out
& $run -Probe $before -Mode build -Scratch $work -RuntimeRoot $runtime -Report "$out/D4_growth.json"
& $run -Probe $before -Mode measure -Scratch $work -RuntimeRoot $runtime -Report "$out/D4_before.json"
& $run -Probe $after -Mode measure -Scratch $work -RuntimeRoot $runtime -Report "$out/D4_after.json"
python apps/desktop/tool/week6_pressure_summary.py snapshot $work "$out/corpus-before.json"
& $run -Probe $after -Mode lifecycle -Scratch $work -RuntimeRoot $runtime -Report "$out/D4_lifecycle.json" -ObserveTcp
python apps/desktop/tool/week6_pressure_summary.py snapshot $work "$out/corpus-after.json"
python apps/desktop/tool/week6_pressure_summary.py summary $out "$out/D4_summary.json"
```

原生桌面延迟、工作集、取消按钮和出站验证，见 [D4 人工验证清单](D4_人工验证清单.md)。


### D5 候选复测

候选源码 `04c22914a86f` 与 D4 合入版本的 Git tree 相同。重新编译 AOT 探针，从仓库外运行。三份真实索引取 D4 的 SHA-256 一致副本。小夹具重新建库五次，各热态配置测 30 次。D4 原始逐级扩容和 10k 生命周期保留为同一源码的历史证据。D5 本轮复测排序与查询性能。

| 块数 / 筛选 | D4 向量 | D5 向量 | D4 热管道 | D5 热管道 |
|---|---:|---:|---:|---:|
| 98 / 全库 | 0.61 | 0.67 | 52.07 | 96.94 |
| 1,000 / 全库 | 7.17 | 7.53 | 71.64 | 91.58 |
| 1,000 / a/ | 6.64 | 6.78 | 60.04 | 70.60 |
| 5,000 / 全库 | 33.37 | 33.39 | 213.79 | 225.32 |
| 5,000 / a/ | 30.65 | 31.36 | 176.20 | 192.26 |
| 10,000 / 全库 | 65.85 | 73.57 | 416.24 | 463.18 |
| 10,000 / a/ | 60.68 | 62.73 | 312.70 | 332.41 |

以上为 p95，单位 ms。各档 Top-5 管道结果和独立向量 Top-K 与 D4 精确一致，覆盖名次、分数、路径、页码、UTF-16 偏移、通道及片段。10k 全同分扫描 p95 为 **149.60 ms**。10k 普通全库热管道 **463.18 ms**，仍高于 200 ms 目标。D5 的 98 块冷建库 p95 为 9.59 秒。MiniLM、CLIP 文本、CLIP 视觉热前向 p95 分别为 57.72、38.49、21.66 ms。无界面探针加 Java 的采样峰值为 908.73 MiB。D4 与 D5 源码一致，两组时间差属于复测观察。

按 D4 冻结门槛，D5 的 5k 全库热管道、10k 两种热管道和两种普通向量扫描、10k 全同分扫描、CLIP 文本热前向超出预算。CLIP 文本在 D4 优化后为 15.42 ms，D5 为 38.49 ms，高于 30 ms 目标。11 月 15 日的复测记录了同一电源方案及两轮起始 CPU 负载。 [最新复测统计](benchmarks/D5_10k_probe_summary.json)

[候选原始样本](benchmarks/D5_measure.json) · [内存采样](benchmarks/D5_measure.json.monitor.json) · [同口径对照](benchmarks/D5_summary.json) · [候选绑定](logs/D5_candidate_manifest.json)

### 2026-11-15 Windows 10k 桌面实测

使用 D5 Windows x64 release 和生产 ORT CPU 资源。主机为 Windows 11 26H2（26300.9818）、Ryzen 7 5800H，沿用 D5 电源方案。将 D4 的 9,907 份夹具复制到独立目录，从原生选择器导入空库。另开一个空库测取消和恢复。测试后复算夹具的相对路径与逐文件 SHA-256，全部与操作前及 D4 夹具一致。两个测试库在退出后均通过 SQLite `quick_check`。

| 场景 | 观察结果 |
|---|---|
| 首次导入 | 644.61 秒完成写入，650.59 秒首次观察到桌面完成状态。写入 9,906 份文档、10,000 块。故意损坏的 `broken.docx` 单列，提示 `DOCX is not a valid zip container.` |
| 取消并搜索 | 从点击取消到辅助功能树出现“已取消”、增量按钮重新出现，耗时 574.94 ms。保留 1,579 份文档和 1,579 块，可查到 `a/02992.txt` 等已提交结果。 |
| 退出重启并续建 | 重启后仍可读到 1,579 份。续建 598.13 秒，复用 1,579 份并新增 8,327 份，恢复到 10,000 块。完整库另做一次退出重启和重查，Top-5 相对路径顺序一致。 |
| 修改一个 TXT | 17.91 秒，重写 1 份、复用 9,905 份，增加 1 个内容块。恢复原文后 16.95 秒，仍只重写该文件，回到 10,000 块。 |
| 清空隔离测试库 | 确认后文档、块、保存目录计数均归零，应用提示“索引及目录记录已清除，源文件保留”。首次导入的完整库保留。 |

桌面会话无法输入中文，本轮改用 `0`。全库和 TXT 各记录 30 次，均排除 3 次已记录的预热。TXT 组前 21 次与全库组同一进程，后 9 次在同一库重启并预热后测量。以提交按键前到 Windows UI Automation 首次观察到可激活结果按钮为边界，包含按键派发、界面回传和观察开销。分位数采用最近秩法。桌面 TXT 是文件类型筛选，探针 `a/` 是路径前缀筛选。`离线检索` 的中文查询保留在无界面探针。

| 桌面热查询 | p50 | p95 | 采样工作集峰值 |
|---|---:|---:|---:|
| 全库 | 696.27 ms | 776.15 ms | 965.17 MiB |
| TXT | 698.64 ms | 819.87 ms | 970.29 MiB，覆盖前 21 次 |

首次导入采样 2,862 次，中位间隔约 222 ms。桌面与 Java 子进程同一时刻合计峰值 787.95 MiB，Java 单独采样峰值 270.18 MiB。全库与 TXT 组内各 30 次的 Top-5 路径及界面可读出处一致。TXT 组最后 9 次缺工作集采样。实测流程中未观察到崩溃或界面失去响应。截图裁掉了光标所在区域。

[界面计时、Top-5 出处及索引结果](benchmarks/D5_10k_desktop.json) · [逐次工作集采样](benchmarks/D5_10k_desktop_memory.csv) · [导入](screenshots/D5-10k-import.png) · [全库](screenshots/D5-10k-all-results.png) · [TXT](screenshots/D5-10k-txt-results.png) · [取消](screenshots/D5-10k-cancel.png) · [续建](screenshots/D5-10k-resume.png) · [清空](screenshots/D5-10k-clear.png)

### 2026-11-15 中文关键词性能复测

同一台主机用 Dart 3.13.4 AOT、生产模型、校验过的 D4 三档 SQLite 快照和固定查询 `离线检索`。先跑 D5 基线探针，再跑从工作区编译的优化探针，均从系统目录启动。运行前 CPU 负载分别为 9% 和 16%，电源方案相同。各热查询与扫描组各 30 次，冷建库各 5 次。上节的 Windows 桌面数据来自原 D5 候选，关键词改动本轮通过 AOT 探针验证。

10k 快照的独立 SQL 对照命中 9,903 行。按 Python SQLite 3.45.3 计时，原查询投影完整展示字段后排序的 p95 为 399.38 ms。仅聚合 `keyword_term` 为 18.10 ms，合并元数据排序和选中正文回填为 108.47 ms，单独回填正文为 1.16 ms。30 次的 Top-50 行 ID 一致。这一对照与桌面续建并行，时间只用于定位热点。生产实现先聚合中文 bigram，再读取排序字段，排序截取后才取正文和其他展示字段。排名和回填使用同一 SQLite 读快照。包含额外 trigram 探测的混合查询继续走合并路径。

下表每格为 p50 / p95，单位 ms。完整热管道含编码、检索、融合和邻域片段。向量扫描为独立精确扫描。

| 内容块 / 筛选 | 热管道基线 | 热管道优化 | 向量基线 | 向量复测 |
|---|---:|---:|---:|---:|
| 98 / 全库 | 43.67 / 50.12 | 50.99 / 71.68 | 0.31 / 0.32 | 0.31 / 0.42 |
| 1,000 / 全库 | 69.59 / 81.86 | 64.12 / 79.96 | 6.95 / 7.25 | 8.17 / 9.33 |
| 1,000 / a/ | 65.67 / 79.66 | 62.58 / 79.45 | 6.66 / 8.53 | 6.79 / 8.57 |
| 5,000 / 全库 | 193.66 / 217.53 | 131.35 / 145.53 | 31.23 / 33.19 | 34.53 / 39.19 |
| 5,000 / a/ | 166.79 / 187.37 | 126.44 / 156.77 | 28.63 / 31.71 | 33.36 / 42.30 |
| 10,000 / 全库 | 343.43 / 357.97 | 224.92 / 245.16 | 62.95 / 65.01 | 76.92 / 103.73 |
| 10,000 / a/ | 307.09 / 402.15 | 183.42 / 207.58 | 59.54 / 65.42 | 60.70 / 65.79 |
| 10,000 / 全同分 | — | — | 128.26 / 137.29 | 128.08 / 131.33 |

10k 全库热管道 p95 降 31.5%，其中存储及邻域环节 p95 从 324 ms 降到 200 ms。5k 全库达到 200 ms，10k 全库和 `a/` 热管道仍超出 200 ms。10k 两种普通扫描及全同分扫描超出 60 ms。MiniLM、CLIP 文本、CLIP 视觉热前向 p95 为 43.43、32.66、25.88 ms，其中 CLIP 文本超过 30 ms，基线为 18.80 ms。探针加 Java 采样峰值为 1,002.52 / 937.91 MiB，冷建库 p95 为 9.12 / 9.50 s，两轮都在预算内。

各档全库和 `a/` 管道 Top-5、独立向量 Top-K、全同分扫描与原 D5 证据完全一致。管道对照包含路径、页码、UTF-16 偏移、分数、通道及片段。`core_storage` 31 项、`core_retrieval` 13 项测试通过，含关键词排序与回填、混合查询、去重、同路径替换和增量复用检查。`core_storage` 静态分析通过。

[原始基线](benchmarks/D5_10k_probe_baseline.json) · [优化原始样本](benchmarks/D5_10k_probe_optimized.json) · [统计与绑定](benchmarks/D5_10k_probe_summary.json) · [进程工作集](benchmarks/D5_10k_probe_memory.json) · [SQL 分段对照](benchmarks/D5_10k_keyword_diagnostic.json) · [存储测试](logs/D5_10k_core_storage_tests.txt) · [检索测试](logs/D5_10k_core_retrieval_tests.txt)

#### 复跑中文关键词对照

基线取 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e`。优化版在同一基线上应用归档补丁。两组探针的 SHA-256 和优化后的源文件 SHA-256 见统计文件。重新编译时使用 Flutter 3.47.5 所带的 Dart 3.13.4，并保留候选的依赖锁文件。用 PowerShell 7.4 或以上从仓库根目录执行，依赖需已缓存。命令使用独立源码副本和输出目录。 [关键词优化补丁](benchmarks/D5_10k_keyword.patch) · [探针统计与版本绑定](benchmarks/D5_10k_probe_summary.json)

```powershell
$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$head = '04c22914a86f9cd3d1d6cf9050b4e2e16055627e'
$runDir = '.dart_tool/w06-keyword-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory $runDir | Out-Null
$out = (Resolve-Path $runDir).Path
$src = "$runDir/src"
$archive = Join-Path $out 'baseline.zip'
$patch = Join-Path $repo 'reports/week6/benchmarks/D5_10k_keyword.patch'
git archive --format=zip "--output=$archive" $head
if ($LASTEXITCODE) { throw '无法导出 D5 基线源码' }
Expand-Archive -LiteralPath $archive -DestinationPath $src

Push-Location "$src/apps/desktop"
try {
    flutter pub get --offline --enforce-lockfile
    if ($LASTEXITCODE) { throw 'D5 依赖未就绪' }
    dart compile exe tool/week6_pressure.dart -o "$out/baseline.exe"
    if ($LASTEXITCODE) { throw '基线探针编译失败' }
} finally { Pop-Location }

git apply --no-index "--directory=$src" -- $patch
if ($LASTEXITCODE) { throw '关键词补丁应用失败' }
$summary = Get-Content -Raw 'reports/week6/benchmarks/D5_10k_probe_summary.json' |
    ConvertFrom-Json -AsHashtable
foreach ($item in $summary.optimizedCodeFileSha256.GetEnumerator()) {
    $file = "$src/packages/core_storage/lib/src/$($item.Key)"
    if ((Get-FileHash -LiteralPath $file).Hash -ne $item.Value) { throw "源码哈希不匹配 $file" }
}
Push-Location "$src/apps/desktop"
try {
    dart compile exe tool/week6_pressure.dart -o "$out/optimized.exe"
    if ($LASTEXITCODE) { throw '优化探针编译失败' }
} finally { Pop-Location }
```

沿用 D5 的 `tiny`、`image-only` 与三档 SQLite 快照。缺少本地快照时，先按 D4 复跑方式重建，将下方输入目录改为新快照所在位置并核对哈希。本次复验须使用 D4 清单绑定的运行库、模型、分词器和 Tika。脚本依次运行两版，每版对每个热态配置采 30 次，JSON 及工作集采样写到新目录。 [创建快照](#复跑) · [快照与资源 SHA-256 清单](benchmarks/D4_bindings.json)

```powershell
$binding = Get-Content -Raw 'reports/week6/benchmarks/D4_bindings.json' |
    ConvertFrom-Json -AsHashtable
$inputDir = (Resolve-Path '.dart_tool/w06-d5/pressure').Path
$runtime = (Resolve-Path '.dart_tool/w06-d2-ort/local-runtime').Path
$scratch = Join-Path $out 'snapshots'
New-Item -ItemType Directory $scratch | Out-Null
foreach ($name in 'tiny','image-only') {
    Copy-Item -LiteralPath (Join-Path $inputDir $name) -Destination $scratch -Recurse
}
foreach ($item in $binding.sqliteSnapshots.GetEnumerator()) {
    $file = Join-Path $inputDir $item.Key
    if ((Get-FileHash -LiteralPath $file).Hash -ne $item.Value) { throw "快照哈希不匹配 $file" }
    Copy-Item -LiteralPath $file -Destination $scratch
}
foreach ($item in $binding.runtimeResources.GetEnumerator()) {
    $file = Join-Path $runtime $item.Key
    if ((Get-FileHash -LiteralPath $file).Hash -ne $item.Value) { throw "资源哈希不匹配 $file" }
}
foreach ($tag in 'baseline','optimized') {
    powercfg /getactivescheme
    Get-CimInstance Win32_Processor | Select-Object Name,LoadPercentage
    & "$out/src/apps/desktop/tool/week6_pressure.ps1" -Mode measure -Probe "$out/$tag.exe" `
        -Scratch $scratch -RuntimeRoot $runtime -Report "$out/$tag.json"
    if ($LASTEXITCODE) { throw "$tag 探针复跑失败" }
}
```

复核每轮 `scales` 下各组的 `sources`、`vector.sources` 以及 `ties.sources`，前后应完全一致。用 `samples[].totalMs` 和 `vector.ms` 按最近秩法算 p50／p95，工作集取同名 `.monitor.json` 的 `peakWorkingSetBytes`。 [11 月 15 日原始样本及统计](benchmarks/D5_10k_probe_summary.json)

从独立源码副本复跑了两版探针，核对了三份 SQLite 快照和 125 个运行资源的 SHA-256。各档的管道 Top-5、独立向量 Top-K 及全同分结果均与原 D5 一致。本次起始 CPU 负载分别为 21% 和 46%，10k 全库热管道 p95 分别为 459.44 ms 和 280.84 ms。本轮用于核验复跑步骤和正确性，前文保留原基准数据。 [复跑核验结果](benchmarks/D5_10k_keyword_replay.json)

已在应用补丁的独立源码目录用 `flutter build windows --release --no-pub` 生成新的 Windows x64 候选，生产冒烟成功。原 D5 桌面压力数据仍绑定原构建。新构建的中文桌面查询待在窗口中另测。 [优化版构建清单](logs/D5_10k_keyword_candidate.json) · [生产冒烟](logs/D5_10k_keyword_windows_smoke.json)
