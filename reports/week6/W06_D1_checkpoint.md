# W06 D1 阶段记录

执行日为 2026-11-06。按 [W06 任务计划](W06_task_plan.md) 固定基线、采集覆盖率和开发运行时数据、排查发布依赖。D1 的 8 小时为计划预算，实际工时由项目开发者登记。

## 1. 基线绑定

- 代码基点为 `17f29f3e00d239541f36b4c4a87540842bacf25d`。核心包与该提交一致。桌面运行会话新增可选的基准观测入口，默认仍使用原有 Python 宿主；集成测试新增报告路径覆盖，W6 证据单独保存。两处改动和基准脚本的 SHA-256 均已登记。
- 本机 Windows x64 10.0.26300、Ryzen 7 5800H、16 个逻辑处理器、约 31.9 GiB RAM，电源方案为“野兽模式”。Flutter 3.47.5、Dart 3.13.4、Python 3.13.2、ONNX Runtime 1.30.0 CPU、Temurin 21.0.12.1、Tika 4.0.0、SQLite 3.53.4。
- 夹具为仓库样本 DOCX、PDF、PNG 和脚本生成的 UTF-8 TXT，修改时间固定为 2020-01-01 UTC。每轮创建新库，共 4 文档 / 98 块（97 文本、1 图像）；固定查询“离线检索”，Top-5，无筛选。样本、模型、分词器、运行脚本和构建文件均可按哈希核对。[环境及输入哈希](logs/D1_environment.txt) · [Windows 构建文件哈希](logs/D1_windows_build_sha256.txt)

## 2. 单测、覆盖率和全链路

覆盖率口径与 W4 相同。按包排除 `integration` 标签，只统计 LCOV 中 `lib/` 的 `LH/LF`。五包共 256 项单测通过，静态分析均无问题。

| 核心包 | 通过用例 | 命中/总行数 | 行覆盖率 | W06 ≥90% |
|---|---:|---:|---:|---|
| `core_parsing` | 98 | 979/1091 | 89.73% | 未达 |
| `core_embedding` | 95 | 1260/1467 | 85.89% | 未达 |
| `core_pipeline` | 26 | 282/309 | 91.26% | 达标 |
| `core_storage` | 24 | 637/729 | 87.38% | 未达 |
| `core_retrieval` | 13 | 165/173 | 95.38% | 达标 |

证据在 [覆盖率目录](coverage/) 与 [测试命令日志](logs/)（`D1_*_coverage.txt`）。初次受限运行的 Dart VM Service 本机连接失败，改用允许回环连接的无界面环境后，五包测试和 LCOV 转换均退出 0。Flutter 初次运行也遇到 SDK 缓存不可写，随后在可写环境完成测试和构建。

D3 在分母不变时还需命中至少 3 行解析、61 行嵌入及 20 行存储。LCOV 的可检查入口包括解析进程及坏图像/PDF 分支、两类 tokenizer 和嵌入服务，以及 SQLite 的行映射、向量 BLOB 和查询分支。

| 验证项 | 实际结果 | 证据 |
|---|---|---|
| Flutter 静态分析 | 修正基准工具的格式提示后复跑，退出 0 | [分析输出](logs/D1_flutter_analyze_final.txt) |
| Flutter 无界面测试 | 62 项通过。真实 worker、模型、SQLite 和设置持久化覆盖混合导入、PDF/图片筛选、错误恢复、增量复用及清除；打开通道使用替身 | [测试输出](logs/D1_flutter_test_local.txt) · [集成 JSON](logs/D1_headless_acceptance.json) |
| Windows release 编译 | 命令退出 0，构建目录为 `apps/desktop/build/windows/x64/runner/Release/`；已记录整目录文件哈希 | [构建输出](logs/D1_flutter_windows_build_local.txt) · [文件哈希](logs/D1_windows_build_sha256.txt) |
| Windows 开发资源链路 | 从 `C:\Windows` 的工作目录以纯 Dart 运行。TXT、DOCX、PDF、PNG 解析并写入 SQLite。库内有 97 个 384 维 MiniLM 文本向量和 1 个 512 维 MobileCLIP 图像向量。查询返回 5 条，含 PDF 第 1、2 页的 UTF-16 命中偏移和 PNG 的图像通道结果 | [基准 JSON 的 runtimeSmoke](benchmarks/D1_windows_development.json) |
| 原生可执行程序、独立生产包 | 原生程序冒烟待 M-01。生产适配器诊断已确认阻塞，见下一节 | [人工清单](D1_人工验证清单.md) |

## 3. 发布依赖与诊断

下表的负责人按角色指定，均由项目开发者执行对应工作。D2 处理接线和运行条件，W7 记录分发与安装，W8 验收正式包。

| 依赖 | D1 验证与实际诊断 | 负责人及复验条件 |
|---|---|---|
| 推理宿主 | 设 `AMR_DEV_ROOT` 后加载 `engine/.venv` 和常驻 ONNX 服务。清除该配置进入生产模式，资源根解析为可执行文件旁的 `runtime/`；诊断明确报生产推理适配器尚未接通 | D2 桌面/推理开发。使用无 `engine/` 的发布布局从仓库外启动，真实完成文本与图片检索 |
| 权重和分词器 | MiniLM fp32 及 MobileCLIP 视觉、文本塔，配套两个 tokenizer。空资源根使三模型、两个分词器和解析器逐项显示缺失。实际加载和 SHA-256 已记录 | D2 推理开发锁定配对与部署清单；W7 开源审查按 ADR 0003 复核 MobileCLIP 权重供应；W8 验证目标主机离线资源齐备 |
| Java/Tika | 真实 PDF 解析成功。Java 路径缺失时诊断给出不可执行路径。空资源根下 Tika JAR 单列缺失 | D2 解析开发验证显式 Java、Tika JAR 与 PDF；W7/W8 明确离线安装或分发方式 |
| SQLite / 用户数据目录 | SQLite 实测 3.53.4，SQLite 在生产适配器阻塞时仍可独立打开。模拟 `LOCALAPPDATA` 可创建默认用户库；绝对覆盖成功；现有文件占据目录时报告 SQLite/数据目录不可用；相对覆盖被拒绝 | D2 存储开发补权限、锁及重启；W8 逐平台验证目标 SQLite 动态库与可写用户目录 |
| 三平台宿主 | 本轮有 Windows 本机编译证据。其余平台与对应提交的 CI 结果待 M-02 核对 | D1 项目开发者登记设备，D2/D5 记录原生操作及 VoiceOver，W8 复验正式包 |

开发链路可以进入 D2。生产模式仍缺推理适配器，独立发布验收保留阻塞。实机启动、截图、读屏、断网与试用安排由项目开发者按 [人工清单](D1_人工验证清单.md) 回填。

## 4. 性能基线

同一主机先做 5 轮会话冷启动，每轮用新的 SQLite 库和 Python worker，OS 文件缓存保持系统自然状态。最后一轮按固定顺序做 30 次热查询、30 次固定单位向量扫描与 30 次同一图像的热前向。p50/p95 用最近秩法，5 样本时 p95 等于该组最大值。冷、热查询的 Top-5 文件顺序、页码和偏移均一致，热扫描的块 ID 顺序一致。[逐次原始样本](benchmarks/D1_windows_development.json)

| 指标 | 样本数 | p50（ms） | p95（ms） |
|---|---:|---:|---:|
| 打开会话与 SQLite（模型延迟加载） | 5 | 437.51 | 464.18 |
| 冷建库（解析、模型加载、推理及写入） | 5 | 9258.76 | 9736.37 |
| 建库后首查（首次加载 CLIP 文本塔） | 5 | 244.05 | 292.60 |
| 热查询（Dart 搜索管道端到端） | 30 | 60.64 | 82.20 |
| SQLite 热向量扫描及回表（97 个文本块） | 30 | 0.60 | 1.02 |
| MiniLM / CLIP 文本 / CLIP 视觉会话加载 | 各 5 | 517.34 / 191.99 / 55.99 | 532.72 / 220.47 / 70.28 |
| MiniLM / CLIP 文本 / CLIP 视觉热前向 | 各 30 | 33.33 / 14.37 / 33.02 | 52.20 / 23.81 / 37.10 |

工作集按约 100 ms 间隔采样，含 Dart 启动器、Dart VM、Python worker 和 Java。543 个非空快照的工作集之和峰值 **1,278.33 MiB**，Dart VM 自报峰值 RSS 为 **567.63 MiB**。进程工作集相加可能重复计入共享页，采样也可能略过短尖峰。Flutter GUI 的内存、UI 提交至结果可操作的延迟、单独的融合耗时和大库压力留待后续实测。[进程采样](benchmarks/D1_windows_process_memory.json)

D4 同配置复跑的初始回归预算为热前向 p95 分别 ≤60/30/45 ms，热管道搜索 ≤100 ms，97 块扫描 ≤1.5 ms，冷建库 ≤11 s，采样进程树峰值 ≤1.35 GiB。预算仅适用于该主机和上述夹具。替换模型或调整索引规模时需另立基线，并保留排名与出处对照。

## 5. 复现命令

从仓库根目录在 PowerShell 7 运行基准。脚本从 Windows 系统目录启动 Dart，探针的工作数据在仓库内忽略目录，每次使用新夹具和数据库。复跑若要保留本次 JSON，传入新的 `-OutputDirectory`。若命令提示缺少 Python 或 Java 进程采样，检查该 shell 的进程查询权限后再采内存。

```powershell
./apps/desktop/tool/week6_baseline.ps1 -OutputDirectory ./reports/week6/benchmarks/recheck
```

在每个核心包目录执行，`$raw` 指向新目录，`$lcov` 指向该包独立的报告路径。

```powershell
dart analyze
dart test --exclude-tags integration "--coverage=$raw" --reporter expanded
dart run coverage:format_coverage --lcov "--in=$raw" "--out=$lcov" --report-on=lib --package=.
```

在 `apps/desktop` 执行。复跑前按需把报告路径改到新的证据文件。

```powershell
flutter analyze --no-pub
flutter test --no-pub --dart-define=AMR_E_REAL_RUNTIME=true `
  --dart-define=AMR_E_REPORT_PATH=reports/week6/logs/D1_headless_acceptance.json --reporter expanded
flutter build windows --release --no-pub
```
