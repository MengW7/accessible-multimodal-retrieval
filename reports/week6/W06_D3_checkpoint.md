# W06 D3 阶段记录

执行日为 2026-11-06。按 [W06 任务计划](W06_task_plan.md) 补测五个核心包，复现并修复阻断问题，执行真实生产 worker 的 SQLite 与失败恢复验证。代码基点为 `17f29f3e00d239541f36b4c4a87540842bacf25d`，包含工作区 D1–D3 改动。Windows x64 验证沿用 D2 的 ONNX Runtime 1.23.2、三个本地模型、Java/Tika 与 SQLite。测试只在独立临时目录创建夹具和索引。

## 五包覆盖率

排除 `integration` 标签，只统计各包 `lib/` 的 LCOV 行覆盖率。五个包的静态分析均通过，共 **267** 项单测通过，五包分别达到 90%。D1 的 LCOV 作为原始基线保留。

| 包 | 通过用例 | D1 | D3 命中 / 总行 | D3 |
|---|---:|---:|---:|---:|
| `core_parsing` | 99 | 89.73% | 987 / 1091 | **90.47%** |
| `core_embedding` | 100 | 85.89% | 1337 / 1467 | **91.14%** |
| `core_storage` | 29 | 87.38% | 662 / 729 | **90.81%** |
| `core_pipeline` | 26 | 91.26% | 282 / 309 | 91.26% |
| `core_retrieval` | 13 | 95.38% | 165 / 173 | 95.38% |

新增覆盖包括 PDF 标题与计时元数据、分词器配置损坏、CLIP 特殊标记和 Unicode 边界、模型及向量元数据、非有限向量触发回滚、损坏索引数据与旧图像元数据，以及拒绝未知 schema 时保留原库。存储首轮有效覆盖为 656/729，精确值低于门槛，补了未知 schema 的只读验证后重新采集。[五份 LCOV](coverage/D3/) · [命令输出](logs/)

## 缺陷与复测

| ID | 复现和原因 | 修复与判定 |
|---|---|---|
| D3-P1-01 多实例索引写入冲突 | 用两个真实 worker 指向同一数据目录。A 已进入建库，B 的清库请求仍成功返回。SQLite 只保护单次事务，A 的建库会分批提交，目录记录另存于 JSON，因此 B 可在 A 的任务中途清库或覆盖记录。[修复前日志](logs/D3_recovery_before.txt) | 用同数据目录的独立 SQLite 文件持有写入保留锁，覆盖一次完整建库或清库和目录记录更新。冲突时提示等待另一实例完成，取消、异常或正常结束都会释放锁。原用例复测覆盖 B 建库和清库被拒、A 完成后 B 重试并复用 24 份，目录记录仍唯一。原生双窗口待 D3-M01。 |
| D3-P2-01 持久化向量类型损坏 | 将临时索引中的 `vec` 改为文本。原扫描用强制转换，搜索抛出 Dart 类型错误。[修复前日志](logs/D3_storage_before.txt) | 复用存储层 BLOB 校验，损坏类型与长度返回结构化错误。重新写入原文档后能搜索。该回归也保留了旧图像元数据的读取覆盖。[存储回归](logs/D3_core_storage_coverage.txt) |

写入锁覆盖文件库的建库、清库和目录记录。它使用独立锁文件 `library-write-lock.sqlite`，沿用现有索引 schema 和目录记录格式。窗口间读取仍可进行，显示可能要在另一实例写完后刷新。已锁定的 SQLite 主索引仍按现有事务语义失败并可重试。

W5 的 Acrobat 环境事件已由用户确认恢复。当前清单中的原生交互、ACL、读屏和断网仍按各自证据判定。

## 真实 worker 集成

| 场景 | 通过条件与实测 |
|---|---|
| 双实例冲突 | 真实 worker A 建库时，B 的清库和建库均被拒。A 结束后 B 可重试并复用 24 份，目录记录只有一条。 |
| SQLite 主库写锁 | 单独连接持有 `BEGIN IMMEDIATE`。同一路径修订内容未写入，已提交旧文本仍可搜索。释放锁后同一 worker 重试，替换为新文本且文档总数仍为 1。 |
| 数据路径与坏 DOCX | 用目录占据 SQLite 文件路径可复现打开失败。移开测试障碍后，同一 worker 可建库。混合批次首次写入 1、失败 1。将坏 DOCX 替换为有效文档后，增量复用 1、补写 1、失败 0。 |
| 建库中关闭 | 等待至少一个文件提交，再调用应用正常关闭使用的 worker 收尾入口。索引返回已取消，关闭后用新的 worker 打开同一数据目录，复用已提交文件并补齐 24 份。 |

完整 Flutter 复跑 **68 项通过**，含真实生产模式界面、worker、SQLite 和故障回归。首轮并发测试触及测试框架默认 30 秒上限。最终真模型套件按文件串行，长流程测试各有独立上限。桌面静态分析和 Windows release 编译均退出 0。自动验证记录到系统打开通道请求，Windows 原生关闭、双窗口和 ACL 由用户补证。[Flutter 输出](logs/D3_flutter_production.txt) · [分析](logs/D3_analyze_final.txt) · [构建](logs/D3_windows_build.txt) · [构建哈希](logs/D3_windows_build_sha256.txt) · [原生复测清单](D3_人工验证清单.md)

## 复跑方式

各核心包目录下运行，`$raw`、`$lcov` 指向本次独立的覆盖率路径。

```powershell
dart analyze
dart test --exclude-tags integration "--coverage=$raw" --reporter expanded
dart run coverage:format_coverage --lcov "--in=$raw" "--out=$lcov" --report-on=lib --package=.
```

在 `apps/desktop` 运行。将 `$runtime` 指向按 D2 准备的本机生产资源绝对路径。

```powershell
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --dart-define=AMR_E_REAL_RUNTIME=true `
  "--dart-define=AMR_E_RUNTIME_ROOT=$runtime" `
  --dart-define=AMR_E_REPORT_PATH=reports/week6/logs/D3_headless_recheck.json --reporter expanded
flutter build windows --release --no-pub
```
