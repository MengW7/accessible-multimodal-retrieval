# W06 D2 阶段记录

按 [W06 任务计划](W06_task_plan.md) 联调桌面和生产适配，验证真实索引、增量、重启及取消恢复。代码基点为 `17f29f3e00d239541f36b4c4a87540842bacf25d`，含工作区 D1/D2 改动。候选构建、适配源码和关键资源以 SHA-256 绑定。[候选清单](logs/D2_candidate_sha256.txt)

## Windows x64 生产适配

桌面 worker 经 Dart FFI 调用 C++ 桥接库和 ONNX Runtime CPU 1.23.2。三个 fp32 ONNX 图复用原来的 Dart 分词、图像预处理、归一化、模型标识、SQLite schema 和检索算法。桥接层在推理前关闭 ONNX Runtime 遥测，按会话复用三路模型，随 worker 收尾释放。生产资源从可执行文件旁的 `runtime/` 解析，也支持绝对路径 `AMR_RUNTIME_ROOT`。生产和开发根同时配置时拒绝启动。Python/ONNX 1.30.0 开发模式仍可用作对照。[ONNX Runtime C++ 文档](https://onnxruntime.ai/docs/get-started/with-cpp)

本机候选使用单独准备的模型、分词器、Java 21、Tika 4.0.0 和系统 SQLite。资源包没有 `engine/` 或 Python。启动检查逐项报告所需资源，并探测 DLL 的 C API 与 Java。公开安装包仍需处理模型供应、Java 和 SQLite 的分发，按 ADR 0003 准备 MobileCLIP 权重。macOS 和 Linux 生产适配单列待做。[资源准备说明](../../apps/desktop/README.md)

## 实测与证据

| 场景 | 判定与实测 | 证据 |
|---|---|---|
| 构建与静态检查 | 原生桥接库、Windows release 编译和 Flutter 静态分析通过 | [桥接构建](logs/D2_native_build.txt) · [桌面构建](logs/D2_windows_build.txt) · [分析](logs/D2_analyze.txt) |
| 生产首次索引和召回 | 从 `C:\Windows` 工作目录运行无界面生产模式。四个样本入库，写入 97 个 384 维文本块和 1 个 512 维图像块。Top-5 含 PDF 页码、UTF-16 命中偏移和 PNG 图像通道 | [生产烟测](logs/D2_production.json) |
| 新进程重启 | 首次 PID 19828、重开 PID 40760。重开原 SQLite 文件并重新编码查询，Top-5 路径、页码、偏移和通道一致 | [重启证据](logs/D2_restart.json) |
| 增量、取消和续建 | 真实生产 worker 区分好坏样本，原样增量复用，修改后替换。早取消保留 0 份新提交，中途取消保留 2 份新提交，续建复用 2 份、补写 18 份，最后总计 21 文档。清除索引前后 22 个源文件内容一致 | [worker 证据](logs/D2_library.json) |
| 缺依赖诊断 | 缺少资源和 Java 均阻塞并退出 1。初次受限运行把退出码 1 映射为 Windows `0xC0000008`，最小 Dart 退出脚本复现，同一用例在普通命令环境退出 1 | [进程复核](logs/D2_process_checks.txt) · [资源诊断](logs/D2_missing_resources.json) · [Java 诊断](logs/D2_missing_java.json) |
| Flutter 无界面集成 | 生产模式全套 64 项通过，含真实 worker、模型、SQLite、筛选和持久化；开发模式真实集成单独复跑。系统打开通道用替身记录传入的实际路径 | [生产测试](logs/D2_flutter_production.txt) · [开发测试](logs/D2_flutter_development.txt) · [生产集成记录](logs/D2_headless_production.json) |
| 原生选择目录、系统查看器、断网 | 待手工执行。现有证据覆盖生产代码路径和独立 SQLite 数据，原生交互、真正的系统打开及外网隔离另行记录 | [人工清单](D2_人工验证清单.md) |

### 后端一致性

两个后端使用同一 TXT、DOCX、PDF、PNG 夹具、固定查询“离线检索”和 Top-5。按 `space,model_id,chunk_id` 对齐 SQLite 数据，逐向量比较有限性、维度、余弦和最大绝对差。门槛沿用 ADR 0003 的余弦 ≥0.999，另要求 Top-5 顺序、出处和通道一致。

| 空间 | 向量 | 最小余弦 | 最大分量绝对差 |
|---|---:|---:|---:|
| MiniLM 文本 | 97 | 0.9999999999997904 | 1.19e-7 |
| MobileCLIP 图像 | 1 | 0.9999999999940943 | 5.51e-7 |

夹具内达标，Top-5 完全一致。当前对照包含单条查询和单张图像，冻结评测结果按原口径保留。[开发烟测](logs/D2_development.json) · [等价性记录](logs/D2_backend_parity.json)

## 复跑

按桌面 README 准备本地生产资源。以下从仓库根目录执行。设 `$runtime` 为资源根，`$fixtures` 为含 TXT、DOCX、PDF、PNG 的独立绝对路径，`$output` 为新建证据目录。首次索引和重启两条命令分别启动 Dart 进程。

```powershell
$repo = (Get-Location).Path
$env:AMR_DEV_ROOT = ''
$env:AMR_RUNTIME_ROOT = $runtime
$env:AMR_DATA_DIR = Join-Path $output 'index'
$config = Join-Path $repo 'apps/desktop/.dart_tool/package_config.json'
$probe = Join-Path $repo 'apps/desktop/tool/verify_runtime.dart'
Push-Location $env:SystemRoot
try {
    dart "--packages=$config" $probe runtime $fixtures "$output/production.json"
    dart "--packages=$config" $probe restart "$output/production.json" "$output/restart.json"
} finally { Pop-Location }
```

复跑 worker 时换一个新 `AMR_DATA_DIR`，以 `library` 模式传入只有 `good.txt` 与损坏的 `bad.docx` 的独立夹具目录。此验证会改写该目录下的 `good.txt`。开发对照清空 `AMR_RUNTIME_ROOT` 并将 `AMR_DEV_ROOT` 设为仓库绝对路径，使用同一组 smoke 夹具和另一新索引。

在 `apps/desktop` 运行 Flutter 静态分析、release 编译和生产集成测试。

```powershell
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --dart-define=AMR_E_REAL_RUNTIME=true `
  "--dart-define=AMR_E_RUNTIME_ROOT=$runtime" `
  --dart-define=AMR_E_REPORT_PATH=reports/week6/logs/D2_headless_recheck.json
flutter build windows --release --no-pub
```

**G1 部分完成。** Windows x64 生产适配和真数据自动联调已有证据。待补原生桌面与断网实测、其他平台生产路径和最终安装包。D3 接续验证 SQLite 权限、锁冲突、并发写入和关闭时索引任务，D4 补网络监测和性能复测。
