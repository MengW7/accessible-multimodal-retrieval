# W07 周报

1. [技术文档](#技术文档)
2. [用户手册](#用户手册)
3. [开源合规报告](#开源合规报告)
4. [演示脚本](#演示脚本)

## 技术文档

源码基线为 `14b3abeefcea15b7b3ed5f93956c7658eab52121`。D2 启动示例采用含关键词优化的 Windows x64 候选，由原 D5 提交 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e` 加归档补丁构建。原 D5 的窗口证据随原构建引用。 [源码与候选核对](D1_缺口表.md) · [优化候选及哈希](../week6/logs/D5_10k_keyword_candidate.json)

### 1. 阅读顺序

维护者按这个顺序读，不必把旧文档抄进本文。

| 顺序 | 文档 | 用它回答的问题 |
|---|---|---|
| 1 | [系统架构](../../docs/architecture/system-architecture.md) | 六层边界、依赖方向、失败如何隔离 |
| 2 | [ADR 0003](../../docs/architecture/adr/0003-embedding-model-and-runtime.md)、[ADR 0004](../../docs/architecture/adr/0004-vector-storage-and-fusion.md) | 为什么是 ONNX 与系统 SQLite，权重能否公开分发 |
| 3 | [ADR 0002](../../docs/architecture/adr/0002-pdf-extraction-tika-then-pdfium.md) 与 [TDD](../../docs/tdd/technical-design-document.md) 的 Q1 | PDF 继续 Tika，PDFium 未接入 |
| 4 | [解析](../../docs/api/parsing-module-api.md)、[嵌入](../../docs/api/embedding-module-api.md)、[存储](../../docs/api/storage-module-api.md)、[检索](../../docs/api/retrieval-module-api.md) | 公开类型、参数和异常 |
| 5 | [桌面 README](../../apps/desktop/README.md) 的 Windows x64 生产运行时 | 如何准备 `runtime/` |
| 6 | 本文第 3 节 | 启动、数据目录、取消、增量、锁、清库和日志 |

桌面 `NativeOnnxModel` 实现嵌入包的 `EmbeddingRuntime`。当前存储 API 已补 `ScoredId.compareRank` 及中文 bigram 的分段读取行为。 [嵌入 API](../../docs/api/embedding-module-api.md) · [存储 API](../../docs/api/storage-module-api.md)

### 2. 本周回写的事实

- 文本模型是 `paraphrase-multilingual-MiniLM-L12-v2` 的 fp32 ONNX，维度 384。图像与查图文本塔是 MobileCLIP-S0 fp32 ONNX，维度 512。生产推理在 Windows x64 上使用 ONNX Runtime CPU 1.23.2 和本仓库的 `amr_onnx.dll`。
- 桌面文件库 worker 在单独 isolate 中持有 SQLite 和嵌入运行时。开发模式的 `OnnxProcessEmbeddingRuntime` 使用 `engine/` 的 Python 进程。Chroma 用于开发期评测对照。
- PDF 文本由外部 `java` 调用 Apache Tika 4.0.0。没有换成 PDFium。
- 公开安装包不携带 MobileCLIP 权重。桥接在创建运行环境时关闭遥测事件。

### 3. 维护步骤

下列步骤基于 Windows x64 候选和本机生产资源。原 D5 窗口实测覆盖原生选目录、导入、退出重启、取消续建、增量和清空。M-05 另有 PDF 缺失与恢复后由 Acrobat 打开的证据。D2 的命令行证据见第 4 节。 [运行时配置](../../apps/desktop/lib/src/runtime/runtime_config.dart) · [W6 原生桌面数据](../week6/benchmarks/D5_10k_desktop.json) · [M-05 恢复记录](../week6/logs/M05.txt)

#### 3.1 生产模式与开发模式

两条路径只配一个资源根。

| 模式 | 环境变量 | 资源从哪里来 | 嵌入怎么跑 |
|---|---|---|---|
| 生产 | 不设置 `AMR_DEV_ROOT`。可选绝对路径 `AMR_RUNTIME_ROOT` | 未设置覆盖时，用可执行文件所在目录下的 `runtime/` | `onnxruntime.dll` 与 `amr_onnx.dll` |
| 开发 | 绝对路径 `AMR_DEV_ROOT` 指向仓库根 | 仓库里的 `models/`、`engine/`、`tools/tika-app/` | 仓库的 Python 与 `engine/embed_server.py` |

两个变量同时有非空值时，启动检查报“AMR_DEV_ROOT 和 AMR_RUNTIME_ROOT 只能配置一项。”开发模式的检查会提示当前不能当作独立发布包验收。

生产资源根至少要有这些文件：

- `bin/onnxruntime.dll`
- `bin/amr_onnx.dll`
- `models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json`
- `models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/onnx/model.onnx`
- `models/raw/image/mobileclip-s0/tokenizer.json`
- `models/raw/image/mobileclip-s0/onnx/vision_model.onnx`
- `models/raw/image/mobileclip-s0/onnx/text_model.onnx`
- `tools/tika-app/tika-app-4.0.0.jar`
- `tools/tika-app/lib/tika-parser-pdf-module-4.0.0.jar`

缺任何一项时，设置页的“本地运行依赖”把该项标为阻塞，并写出完整路径。非 Windows 的生产模式会阻塞，并说明生产推理适配当前支持 Windows x64。

`AMR_JAVA` 接受 Java 可执行文件的绝对路径或字面值 `java`。省略时也从 PATH 查找 `java`。PDF 解析使用完整的 Tika `lib/` 依赖目录，候选使用本机 Temurin 21.0.12.1。Windows x64 的 SQLite 来自系统 `winsqlite3.dll`。 [Java 标识](logs/java_identity.txt) · [SQLite 查找规则](../../docs/api/storage-module-api.md#systemsqlitelibrarylocator)

#### 3.2 准备生产资源并启动

在 PowerShell 7.4 或以上从仓库根目录执行。先按桌面 README 准备桥接和生产资源根。本地资源已准备时，下面的命令从清单定位候选、核对 `desktop.exe` 和 `data/app.so`，并创建独立测试数据和临时目录。换用其他构建时，使用该构建的完整 Release 目录及其哈希。 [生产资源准备](../../apps/desktop/README.md#windows-x64-生产运行时) · [优化候选清单](../week6/logs/D5_10k_keyword_candidate.json)

```powershell
$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$manifest = Get-Content -Raw 'reports/week6/logs/D5_10k_keyword_candidate.json' |
    ConvertFrom-Json -AsHashtable
$release = (Resolve-Path -LiteralPath (Join-Path $repo $manifest.releaseDirectory)).Path
foreach ($name in 'desktop.exe','data/app.so') {
    $actual = (Get-FileHash -LiteralPath (Join-Path $release $name)).Hash
    if ($actual -ne $manifest.releaseFilesSha256[$name]) { throw "候选文件哈希不符 $name" }
}
$desktop = Join-Path $release 'desktop.exe'
$work = Join-Path $repo ('.dart_tool/w07-d2/manual-' + [guid]::NewGuid().ToString('N'))
$isolatedTemp = Join-Path $work 'temp'
New-Item -ItemType Directory -Path $isolatedTemp -Force | Out-Null
Remove-Item Env:AMR_DEV_ROOT -ErrorAction SilentlyContinue
$env:AMR_RUNTIME_ROOT = (Resolve-Path -LiteralPath '.dart_tool/w06-d2-ort/local-runtime').Path
$env:AMR_DATA_DIR = Join-Path $work 'desktop-data'
$env:AMR_JAVA = (Get-Command java.exe -CommandType Application | Select-Object -First 1).Source
$env:TEMP = $isolatedTemp
$env:TMP = $isolatedTemp
Start-Process -FilePath $desktop -WorkingDirectory $env:SystemRoot -Wait
```

不设置 `AMR_RUNTIME_ROOT` 时，使用可执行文件旁的 `runtime/`。不设置 `AMR_DATA_DIR` 时，Windows 依次使用 `%LOCALAPPDATA%\AccessibleMultimodalRetrieval` 和 `%USERPROFILE%\AppData\Local\AccessibleMultimodalRetrieval`。macOS 的默认目录是 `~/Library/Application Support/AccessibleMultimodalRetrieval`，其他系统使用 `$XDG_DATA_HOME/AccessibleMultimodalRetrieval` 或 `~/.local/share/AccessibleMultimodalRetrieval`。这些数据路径规则与平台生产推理支持独立，当前生产适配为 Windows x64。无法定位用户数据目录时，显式设置可写的绝对 `AMR_DATA_DIR`。

PATH 上有多个 Java 时，`AMR_JAVA` 只填写一个可执行文件路径。上例选 PATH 的第一项。若诊断仍显示 Java 阻塞，可在 PowerShell 用 `& $env:AMR_JAVA -version` 核对所选版本。

开发模式改为设置 `AMR_DEV_ROOT` 为仓库根的绝对路径，并去掉 `AMR_RUNTIME_ROOT`。设置页会出现“开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。”

#### 3.3 数据目录里有什么

| 文件 | 作用 |
|---|---|
| `library.sqlite` | 文档、切块、向量和关键词。切块文本保存在库里，供片段和检索使用 |
| `library-write-lock.sqlite` | 一次建库或清库期间的写入保留锁 |
| `library-roots.json` | 已添加目录和最近一次处理计数，版本字段为 1 |
| `display-settings.json` | 主题、高对比和字号 |

源文件留在用户原来的目录，不会被复制成可编辑原件。

#### 3.4 导入、取消、重启与增量

1. 在设置页检查“本地运行依赖”，确认资源状态就绪。文件库用“选择目录”选一个夹具副本，激活“建立 / 增量更新索引”，记录写入、复用和失败数。
2. 在搜索页提交 `离线检索`，用结果页核对路径、页码和偏移。打开原文件可检查系统查看器。查看器能否定位到所示页或片段视系统关联应用而定，当前打开通道传递文件路径。
3. 在建库中点击“取消索引任务”，等待“已取消”并记录已提交数。用同一目录再次增量以复用已提交文件并补齐其余文件。
4. 退出，在同一 PowerShell 中用上一节的 `Start-Process` 命令重启，沿用原 `$env:AMR_DATA_DIR`。核对目录记录、索引统计、显示设置，并用相同查询和筛选复查出处。

增量复用比较 6 个字段：`contentHash`、`parserName`、`parserVersion`、`chunkerVersion`、`modelId`、`vectorDim`。任一不同就重新嵌入。文件改名或删除后，旧记录不会只靠增量自动消失。

原 D5 的窗口重启记录核对了五条 Top-5 路径的顺序。独立 Dart 进程可从同一 SQLite 复核页码、偏移和通道。 [窗口重查](../week6/benchmarks/D5_10k_desktop.json) · [独立进程重查](../week6/logs/D5_restart.json)

#### 3.5 第二实例、损坏向量、移动文件与清库

建库或清库会在 `library-write-lock.sqlite` 上执行 `BEGIN IMMEDIATE`。另一实例同时写入或清库时得到：“另一个实例正在修改此文件库，请等待其完成后重试。”锁在任务结束、取消或异常时释放。这是 worker 级复测，见 [W6 D3 记录](../week6/W06_D3_checkpoint.md)。两个原生窗口同时打开还没有人工记录。

打开索引失败时，先确认 Java 与模型诊断是否已就绪，再检查应用指向的数据目录、目录可写性、SQLite 系统库和其他实例。可在新数据目录重试启动，以区分环境问题与已有库故障。向量字段类型或 BLOB 长度异常时，存储层返回结构化错误。保留诊断，在测试副本重建对应文档后重查。 [存储故障回归](../week6/logs/D5_core_storage_tests.txt)

打开结果时使用索引里的绝对路径。文件不存在时界面提示检查路径和权限。能恢复原路径时，恢复后从同一结果重试。文件已迁移时，在新路径重新索引后重查，并核对旧结果的路径。系统打开失败时检查文件权限和默认查看器。 [PDF 缺失与恢复](../week6/logs/M05.txt)

“清除全部索引”清掉当前数据目录中的索引表，并把 `library-roots.json` 写成空目录列表。源文件不删。显示设置不在这次清除里。确认框的默认按钮是“保留索引”。

目录记录损坏时，错误写明 `library-roots.json` 的路径，并说明可以备份后修复，或通过清除索引重置。源文件不受影响。

#### 3.6 诊断与评测输出

普通运行日志遵守正文约束。`--runtime-smoke` 导出启动检查、计数、查询、来源路径、页码、偏移和通道，失败时可能含错误和堆栈。`--library-smoke` 记录进度和逐文件状态。工程性能探针显式导出 `hit.snippet`，SQLite 保存切块正文。维护证据用合成或固定样本。共享诊断前检查绝对路径、错误详情和片段。 [日志与导出字段抽查](logs/log_field_check.txt)

#### 3.7 尚未在本周操作的项目

| 项目 | 现有证据 | 本周状态 |
|---|---|---|
| 原生导入、查看器和重启 | 原 D5 已有 10k 选择器导入与窗口重启，M-05 恢复后由 Acrobat 打开 PDF | D1 M-04 查看器截图及重查细节待回填。优化候选的中文桌面查询待测 |
| 建库中直接关窗、双原生窗口和 ACL | worker 关闭入口与锁有自动回归，原 D5 有主动取消后重启的实测 | 三个原生故障场景仍待实测 |
| 断网时的 DNS 与出站，含外部查看器 | W6 有受限 TCP 采样及操作者确认的断网主流程 | 隔离方式、覆盖范围、DNS／出站和查看器证据待补 |
| 10k 普通热管道 | 原 D5 p95 463.18 ms，同轮关键词优化对照 357.97 → 245.16 ms | 优化后仍超过 200 ms。按原快照与查询在 W8 复验。 [性能报告](../week6/性能优化基准报告.md) |

### 4. 命令行验证与复跑

2026-11-15 从 `C:\Windows` 运行，核对了 12 个候选文件和 125 个本地资源的 SHA-256，以下四个用例复跑均退出 0。三个测试库均通过只读 SQLite `quick_check`。首次运行时 `Get-Command` 返回两个 Java 路径，合并后的值导致 Java 诊断阻塞。改成选择单个路径后，从新目录重试通过。 [D2 复跑原始数据](logs/D2_maintenance_verification.json)

| 用例 | 实际结果 |
|---|---|
| 优化候选的 `--runtime-smoke` | 生产依赖就绪，TXT、DOCX、PDF、PNG 共 4 份入库，包含 97 个文本块和 1 个图像块。返回 5 条来源 |
| 独立 Dart 进程 `runtime` → `restart` | PID 38560 首次索引，PID 36908 重开同一 SQLite。Top-5 路径、页码、UTF-16 偏移及通道一致，也与优化候选冒烟的来源一致 |
| worker `library` | 好坏文件分别计数，原样复用 1 份，修改后替换 1 份。取消保留 2 份新提交，续建复用 2 份并新增 18 份，合计 21 份。清空后文档、内容块、目录均为空，22 个源文件在清空前后内容一致 |

在新 PowerShell 窗口中执行 §3.2 的配置，执行到设置 `$env:TMP` 为止。以下命令先通过候选的隐藏冒烟入口检查启动、混合导入和检索，再用独立 Dart 进程完成索引重开与 worker 恢复验证。先在 `apps/desktop` 准备 Flutter 依赖，确保 `.dart_tool/package_config.json` 存在。`runtime` 与 `restart` 复用同一测试数据目录，`library` 使用另一空目录。`library` 会改写它的 `good.txt` 并在同级生成取消用例，因此用专用夹具。

```powershell
$fixtures = Join-Path $work 'mixed'
$workerFixtures = Join-Path $work 'worker-fixtures'
New-Item -ItemType Directory -Path $fixtures,$workerFixtures | Out-Null
foreach ($name in 'sample.pdf','sample.docx','sample.png') {
    Copy-Item -LiteralPath (Join-Path $repo "datasets/samples/$name") -Destination $fixtures
}
Set-Content -Encoding utf8 -LiteralPath "$fixtures/smoke.txt" -Value '离线检索验证：文件在本机建立索引。'
Set-Content -Encoding utf8 -LiteralPath "$workerFixtures/good.txt" -Value '离线检索验证：本地索引应保存已提交的文件。'
Set-Content -Encoding utf8 -LiteralPath "$workerFixtures/bad.docx" -Value 'deliberately invalid DOCX archive'

$env:AMR_DATA_DIR = Join-Path $work 'release-data'
$env:AMR_SMOKE_FIXTURES = $fixtures
$env:AMR_SMOKE_OUTPUT = Join-Path $work 'release.json'
$proc = Start-Process -FilePath $desktop -ArgumentList '--runtime-smoke' `
    -WorkingDirectory $env:SystemRoot -WindowStyle Hidden -PassThru
if (!$proc.WaitForExit(120000)) {
    Stop-Process -Id $proc.Id
    throw '候选冒烟超时'
}
if ($proc.ExitCode -ne 0) { throw "候选冒烟失败，检查 $env:AMR_SMOKE_OUTPUT" }

$config = Join-Path $repo 'apps/desktop/.dart_tool/package_config.json'
$probe = Join-Path $repo 'apps/desktop/tool/verify_runtime.dart'
$env:AMR_DATA_DIR = Join-Path $work 'runtime-data'
Push-Location $env:SystemRoot
try {
    dart "--packages=$config" $probe runtime $fixtures "$work/runtime.json"
    if ($LASTEXITCODE) { throw '首次索引失败' }
    dart "--packages=$config" $probe restart "$work/runtime.json" "$work/restart.json"
    if ($LASTEXITCODE) { throw '独立进程重查失败' }
    $env:AMR_DATA_DIR = Join-Path $work 'worker-data'
    dart "--packages=$config" $probe library $workerFixtures "$work/library.json"
    if ($LASTEXITCODE) { throw '文件库恢复验证失败' }
} finally { Pop-Location }
```

核对各 JSON 的 `ok` 和实际索引计数。`restart` 比较相同查询的 Top-5 来源路径、页码、偏移和通道。`library` 核对原样复用、修改替换、取消保留、续建、坏文件提示、清空和清空前后源文件内容。窗口选择器、查看器和辅助技术按上节所列证据单独签收。

## 用户手册

编写日期 2026-11-15。界面用词按源码 `14b3abeefcea15b7b3ed5f93956c7658eab52121` 核对。启动步骤使用含关键词优化的 Windows x64 候选，窗口示例引用原 D5 候选 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e` 及 W5 实机记录。 [优化候选清单](../week6/logs/D5_10k_keyword_candidate.json) · [D2 启动验证](logs/D2_maintenance_verification.json)

当前可使用 Windows x64 的 Release 目录和本地生产资源。三平台安装器尚未交付。其他平台及辅助技术的验证范围见第 9 节。

### 1. 安装与启动

本地内容检索可以为 TXT、Markdown（`.md`）、PDF、DOCX、JPG／JPEG 和 PNG 建立索引，再用文字查询、筛选和打开原文件。

1. 将完整的 Windows x64 Release 目录解压或复制到本机，确保 `desktop.exe` 与同目录的 `data/`、Flutter DLL 一起保留。
2. 准备本地生产资源，包含 ONNX Runtime CPU、桥接 DLL、文本与图文模型、分词器和 Tika。Java 安装在本机并加入 PATH，或通过 `AMR_JAVA` 指定一个 `java.exe` 的绝对路径。MobileCLIP 权重按项目研究资源配置准备。 [资源布局与 Java 配置](#31-生产模式与开发模式) · [资源分发范围](#开源合规报告)
3. 将资源目录命名为 `runtime` 并放在 `desktop.exe` 旁边，即可从 Release 目录启动 `desktop.exe`。若资源保存在其他位置，用 PowerShell 的 `AMR_RUNTIME_ROOT` 指定该目录的绝对路径，再从同一窗口启动程序。 [PowerShell 启动示例](#32-准备生产资源并启动)
4. 打开“设置”，找到“本地运行依赖”。核对各项状态与“索引位置”。资源补齐后按“重新检查依赖”。若更改了资源根、Java 路径或数据目录，先关闭应用，再从设置了这些变量的 PowerShell 窗口重新启动。

Windows 默认数据目录是 `%LOCALAPPDATA%\AccessibleMultimodalRetrieval`。`LOCALAPPDATA` 未设置时，应用使用 `%USERPROFILE%\AppData\Local\AccessibleMultimodalRetrieval`。试用可用 `AMR_DATA_DIR` 指定一个新的绝对路径，与评测库分开。同一数据目录会保留索引与显示设置，源文件留在原处。 [数据目录与重启](#33-数据目录里有什么)

### 2. 四个功能区

宽窗口左侧是“文件库”“搜索”“结果”“设置”。窗口变窄时导航会改换布局。内容超出窗口时向下滚动，键盘继续按 Tab。

| 功能区 | 你可以做什么 |
|---|---|
| 文件库 | 选择目录、建立或增量更新索引、看每个文件的结果、取消、清除全部索引 |
| 搜索 | 输入查询，并按类型、相对路径和修改日期筛选 |
| 结果 | 看本次条件、片段和出处，请求系统打开原文件 |
| 设置 | 主题、高对比、文字大小，以及本地运行依赖 |

### 3. 建立文件库

1. 准备一个你有权读取的文件夹。试用时用单独的样本目录。
2. 打开“文件库”。按“选择目录”，在系统窗口里选定文件夹。也可将文件夹的绝对路径填入“目录的绝对路径”。
3. 按“建立 / 增量更新索引”，等待阶段和计数结束。模型第一次加载会更久。
4. 查看本次文件状态中的新写入、复用和失败计数。部分失败时，展开或翻页查看具体文件和原因。已写入的文件可以继续搜索。 [原 D5 导入示例](../week6/screenshots/D5-10k-import.png)

同一内容可能共用一条索引，所以文件数和索引文档数可以不同。

文件有改动时，对同一目录再按一次“建立 / 增量更新索引”。未改动的内容会复用。需要暂停时按“取消索引任务”，等待已取消状态。已经提交的文件会保留，再对同一目录执行一次增量即可续建。 [原 D5 取消与续建](../week6/benchmarks/D5_10k_desktop.json)

文件改名或删除后，旧索引可能还在。增量不会保证清掉这些旧记录。需要整库重来时，用第 7 节的清除，再重新添加目录。

### 4. 搜索与筛选

1. 打开“搜索”。在 Windows 上也可按 Ctrl+L 聚焦查询框。
2. 在“搜索本地内容”输入一个关键词或一句话。导入仓库样本后，可用 `tika` 试搜。
3. 第一次先保持“所有类型”，路径和日期留空，按 Enter 或“开始搜索”。
4. 到结果页核对“本次查询”和筛选条件。要缩小范围时按“修改搜索条件”，设置一个或多个筛选项后重新提交。例如，把“文件类型”设为 `PDF`，再次搜索并查看 `sample.pdf` 的出处。 [PDF 筛选示例](../week6/screenshots/M04-results.png)

| 筛选项 | 规则 |
|---|---|
| 文件类型 | 所有类型、TXT、Markdown、PDF、DOCX、图片（JPG / PNG） |
| 相对目录或文件路径 | 从导入目录算起，例如 `notes` 或 `notes/file.pdf`。目录包含其子目录，输入中省略盘符、起始斜线和 `..` |
| 修改时间晚于日期 | 使用实际存在的 `YYYY-MM-DD`，例如 `2026-10-30`。只匹配晚于该日本地时间零点的文件 |
| 清除筛选 | 重置类型、路径和日期，保留查询文字。再次按“开始搜索”才会应用这些设置 |

每次最多显示前 20 条。文件库还在建索引时，搜索会提示等待或先取消建库。搜索过程中可以按“取消当前搜索”。

### 5. 阅读结果与打开原文件

结果按相关性排列。界面写明排序分值不代表正确概率。

- 每条结果显示“来源路径”和“相对路径”。来源路径是系统打开时使用的本地绝对路径，相对路径从导入目录计算。
- 文本结果显示片段和命中块字符偏移。偏移按 UTF-16 计算，起点包含在范围内，终点在范围之外。片段可能包含相邻上下文。
- 有页码的结果显示“出处：第 N 页”。没有物理页码的结果会直接说明无页码。
- 图片结果显示文件名和元数据，并说明没有生成图像内容描述。
- 按“打开原文件”。系统接收请求后，在默认查看器里确认实际打开的是所示文件。应用传递文件路径，查看器可能无法自动定位到页或片段。

看到源文件不存在或不可访问的提示时，先检查“来源路径”和读取权限。如果能恢复到原路径，从同一条结果再次按“打开原文件”。文件已迁移时，对新位置重新建立或更新索引，再搜索并检查新的来源路径。增量可能保留旧路径，重新索引后要核对结果指向哪个文件。索引更新或清除后，重新提交查询。当前平台缺少系统打开功能时，按提示复制来源路径并手动打开。 [PDF 原路径恢复实测](../week6/logs/M05.txt)

从系统查看器回到本程序时，用系统自己的窗口切换。焦点落在哪个控件上，还没有对所有查看器做完记录。

### 6. 键盘、读屏和显示

| 按键 | 作用 |
|---|---|
| Tab / Shift+Tab | 在控件间移动 |
| Enter | 在搜索框提交；在按钮上执行 |
| Space | 激活按钮或开关。在搜索文字里它是空格，不是提交 |
| 方向键、Enter | 在打开的下拉项里移动并确认 |
| Esc | 关闭当前程序弹窗。系统窗口按系统自己的规则 |
| Ctrl+L | 在 Windows 上进入搜索并聚焦输入框。有弹窗时先关闭弹窗 |

使用键盘时，按 Tab 移到“文件库”，按 Enter 进入，再用 Tab 到“选择目录”或“目录的绝对路径”。建库结束后按 Ctrl+L 搜索，按 Tab 移到结果的“打开原文件”。清空确认框默认聚焦“保留索引”，Tab 在框内循环。按 Esc 或“保留索引”关闭后，应用将焦点还给“清除全部索引”。系统目录对话框和查看器的焦点由 Windows 及相应应用管理。 [W5 键盘验收范围](../week5/E_验收矩阵.md)

配合 NVDA 操作时，先启动 NVDA，再打开应用。用 Tab 进入控件，听到“搜索本地内容”后输入并提交。在结果中阅读文件名、正文片段、来源路径和页码，再激活读作“打开原文件：文件名”的按钮。等待期间可阅读“正在检索本地索引”等状态。W5 的 NVDA 2026.2.0.57664 实机记录覆盖键盘、来源阅读和文件打开的部分场景。自动播报是否完整、各系统查看器返回后的精确焦点仍待实机验证。 [NVDA 实机原文](../week5/logs/screen_reader_nvda_session.md)

打开“设置”，用 Tab 到主题和字号下拉框，通过方向键选项并按 Enter 确认。焦点在“高对比模式”开关时可按 Space 切换。

| 设置 | 选项 |
|---|---|
| 明暗主题 | 跟随系统、浅色、深色 |
| 高对比模式 | 可手动打开。系统要求高对比时也会自动启用 |
| 文字大小 | 跟随系统、100%、150%、200% |
| 恢复默认显示设置 | 恢复上述三项的默认值，不清除索引 |

选择“跟随系统”时采用系统文字缩放。选择 100%、150% 或 200% 时使用所选的应用字号，系统文字比例不会再次叠乘。按钮在窗口外时，向下滚动或继续按 Tab。同一数据目录再次启动会恢复已保存的设置。 [W5 高对比示例](../week5/screenshots/07-high-contrast-light.png) · [100%](../week5/screenshots/09-text-scale-100.png) · [150%](../week5/screenshots/10-text-scale-150.png) · [200%](../week5/screenshots/11-text-scale-200.png)

课程 PDF 点名的 Accessibility Scanner 面向 Android，WAVE 面向网页。本程序是桌面界面，这两项工具没有对它出报告。替代记录在 [无障碍合规验证报告](../week5/无障碍合规验证报告.md)。

### 7. 清除索引与退出

“清除全部索引”清除的是当前数据目录里的全部索引和已保存目录，不是输入框里的某一个文件夹。源文件保留。清除后要重新添加目录。

1. 先看设置页或确认框里的索引位置。
2. 按“清除全部索引”，读完说明。
3. 不想清除时按 Esc 或“保留索引”。
4. 确定要清除整个索引时，才按“确认清除索引”。

关闭窗口时，若显示后台仍在收尾，等待任务结束。要重启后继续使用同一索引和显示设置，沿用相同的 `AMR_DATA_DIR`。第二个实例遇到同一索引的写锁时，等待首个实例完成或取消，再重试。

### 8. 常见提示

| 提示 | 可以怎么做 |
|---|---|
| 依赖项为阻塞，并给出缺少的文件 | 把文件放到提示的路径，或让维护者设置资源根，然后“重新检查依赖” |
| 索引库为空 | 先添加目录并完成建库 |
| 当前条件下没有检索结果 | 放宽类型、路径或日期筛选，再提交同一查询 |
| 日期或路径不被接受 | 日期用真实的 `YYYY-MM-DD`，路径用相对路径 |
| 源文件不存在、不可访问或不是文件 | 核对来源路径和权限。恢复到原路径后重试，或为新路径建立索引后重新搜索 |
| 系统未能打开文件 | 检查权限和默认查看器，或复用来源路径自行打开 |
| 另一个实例正在修改此文件库 | 等对方结束、取消或退出后再试 |

### 9. 平台与验证范围

| 平台或方式 | 记录 |
|---|---|
| Windows x64 | D2 用优化候选通过生产冒烟和无界面维护验证。原 D5 已实测原生选目录、重启及索引恢复，M-05 有 Acrobat 打开恢复后的 PDF 记录。优化候选的完整窗口流程及中文桌面计时待补测。 [D2 维护证据](logs/D2_maintenance_verification.json) · [原 D5 窗口证据](../week6/benchmarks/D5_10k_desktop.json) |
| Windows 键盘、NVDA 和显示 | 沿用 W5 部分实机验证。完整自动朗读、查看器返回焦点和全部显示组合仍待补测。 [W5 验收矩阵](../week5/E_验收矩阵.md) |
| D3 Flutter 自动验证 | 68 项通过。覆盖键盘顺序、弹窗焦点、显示设置及真实生产资源下的导入、组合筛选、出处和重启。系统打开请求通过通道替身验证，NVDA 使用 W5 实机证据。 [测试日志](logs/D3_flutter_tests.txt) · [无界面集成结果](logs/D3_headless_acceptance.json) |
| macOS | 未验证。设置页提示使用 Command+L，需在目标机核对快捷键及完整原生流程 |
| macOS VoiceOver | 未验证。需要单独记录实际读屏、焦点和操作结果 |
| Linux | 未验证。设置页提示使用 Ctrl+L，需在目标机核对快捷键、原生流程及辅助技术 |

独立试用暂缓，当前记录为 0 人。 [独立试用记录与任务](../week5/UI可用性测试报告.md)

## 开源合规报告

核对日期 2026-11-15，源码为 `14b3abeefcea15b7b3ed5f93956c7658eab52121`。构建检查使用原 D5 提交 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e` 加关键词补丁的 Windows x64 Release，以及同机独立的生产资源根。实际 Release 的 12 个文件与候选清单一致，125 个生产资源文件与 W6 哈希清单一致。正式安装包的合规签收随 W8 实际打包检查。 [候选构建清单](../week6/logs/D5_10k_keyword_candidate.json) · [依赖、许可文件与哈希盘点](logs/D4_dependency_inventory.json)

### 1. 源码与运行组件

仓库根 [LICENSE](../../LICENSE) 为 Apache-2.0，覆盖本项目源码、五个本地 Dart 包及 `native/onnx` 桥接实现。随源码或构建交付保留相应许可证和第三方声明。 [Apache-2.0 原文](https://www.apache.org/licenses/LICENSE-2.0)

| 组件 | 版本及取得位置 | 许可或声明来源 | 公开交付范围 |
|---|---|---|---|
| 项目源码与 `amr_onnx.dll` | 当前源码，桥接来自 `native/onnx` | 仓库 `LICENSE`。桥调用的 ORT 动态库有独立声明 | 源码及桥接构建按项目许可公开，随附 ORT 时带其声明 |
| Flutter、Dart 及 Flutter Windows 引擎 | Flutter 3.47.5、Dart 3.13.4，本机 SDK 与候选 Release | SDK 为 BSD-3-Clause，`NOTICES.Z` 汇集引擎、ICU 和包的声明。字体的独立声明见第 2 节 | 交付 Flutter 二进制时保留 `NOTICES.Z` 与适用附带声明。 [Flutter SDK LICENSE](https://github.com/flutter/flutter/blob/3.47.5/LICENSE) |
| `sqlite3` 与系统 SQLite | Dart `sqlite3` 2.9.4，Windows 系统 `winsqlite3.dll` 实测为 3.53.4 | Dart 包 MIT。SQLite 上游代码为公有领域，Windows 系统二进制从系统加载 | 随应用带 Dart 包声明。当前包不复制系统 DLL，W8 若改为自带 SQLite，应绑定具体来源并复验加载。 [SQLite 上游声明](https://sqlite.org/copyright.html) |
| ONNX Runtime CPU | Microsoft Windows x64 SDK 1.23.2，资源根 `bin/` | MIT，随 SDK 的 `LICENSE` 和 `ThirdPartyNotices.txt` | 随运行资源提供 DLL 时带两份原声明。 [版本许可](https://github.com/microsoft/onnxruntime/blob/v1.23.2/LICENSE) · [第三方声明](https://github.com/microsoft/onnxruntime/blob/v1.23.2/ThirdPartyNotices.txt) |
| Apache Tika | 4.0.0，发布 zip 的启动 JAR 与 `lib/` | Apache-2.0，发行版 `LICENSE`、`NOTICE` 和 JAR 内声明。第三方依赖各有条款 | Tika 独立运行资源保持发行版结构。W8 以实际包含的 JAR 为准核对其许可文本、署名和分发条件。 [Tika 4.0.0 发行说明](https://tika.apache.org/4.0.0/index.html) |
| Eclipse Temurin | 本机 21.0.12.1+1，由应用调用 `java` | 发行版 GPL v2 与 Classpath Exception，另有 `NOTICE`、`legal/`、`ASSEMBLY_EXCEPTION` 和附加声明 | 目前作为外部安装的前提。W8 如携带 JRE，按选定发行版的实际产物和条款核对。 [Adoptium 许可说明](https://adoptium.net/docs/faq/) · [本机 Java 标识](logs/java_identity.txt) |
| MiniLM 文本权重及分词器 | 上游 Sentence Transformers，Xenova ONNX 导出 `2c4055b12046f11709e9df2c122e59ffbdc2f900` | 上游模型卡标为 Apache-2.0。固定 Xenova 文件树提供 ONNX 和分词器，未列单独 `LICENSE`。仓库登记了来源与哈希 | W8 随包提供时绑定上游许可、导出 revision、署名及转换说明。 [上游模型卡](https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2) · [导出文件树](https://huggingface.co/Xenova/paraphrase-multilingual-MiniLM-L12-v2/tree/2c4055b12046f11709e9df2c122e59ffbdc2f900) |
| MobileCLIP-S0 双塔及分词器 | 上游 Apple，Xenova ONNX 导出 `757d59c9c6870a76a4b0306f05f5061bca15c39f` | 官方权重标为 `apple-amlr`。Apple 将代码、模型和其发布的数据分别列为 MIT、Apple ML Research Model TOU、CC-BY-NC-ND | 项目按 ADR 0003 将 ONNX 双塔和对应分词器留在本机研究资源，公开安装包排除该资源组。 [Apple 模型卡](https://huggingface.co/apple/MobileCLIP-S0) · [Apple 模型条款](https://github.com/apple-aiml-research/ml-mobileclip/blob/main/LICENSE_MODELS) · [ADR 0003](../../docs/architecture/adr/0003-embedding-model-and-runtime.md) |

Apple 模型条款限定研究用途，并对研究范围内的再分发、署名和衍生修改有要求。固定 Xenova 导出仓的 `LICENSE` 写的是软件许可，权重判断采用 Apple 官方模型条款。使用者可按研究条款自行准备资源。若将来换用可分发图像模型，W8 需登记新模型和许可，并复验图像检索及缺件启动。当前版本在图像资源缺失时显示阻塞。 [Apple 项目许可分类](https://github.com/apple-aiml-research/ml-mobileclip#license) · [Xenova 固定版本的许可文件](https://huggingface.co/Xenova/mobileclip_s0/blob/757d59c9c6870a76a4b0306f05f5061bca15c39f/LICENSE) · [模型登记](../../models/README.md)

### 2. Dart 依赖、Flutter 声明和字体

共核对桌面及五个核心包的 6 份 `pubspec.lock`，得到 78 个去重后的托管包与版本组合。逐个定位 pub 缓存中对应的 `LICENSE` 并记录哈希，按许可文本识别出 BSD-3-Clause 65 项、MIT 10 项、Apache-2.0 3 项。桌面版本以桌面锁文件和与之匹配的依赖图为准。核心包各自的锁文件与缓存开发图差异单独登记。 [六份锁文件与托管包清单](logs/D4_dependency_inventory.json)

从桌面包沿 `dependencies` 递归得到 19 个托管依赖，包括直接依赖 `cupertino_icons`、`ffi`、`path`、`sqlite3`，以及各本地核心包和 Flutter 引入的传递依赖。19 个包都能在优化构建的 `data/flutter_assets/NOTICES.Z` 中找到声明名称。开发工具与测试依赖保留在锁文件清单中。该压缩声明是 Flutter 编译产物的一部分，外部 ONNX Runtime、Tika、Temurin 及模型各自带声明。 [Flutter 构建与锁文件证据](logs/D4_dependency_inventory.json)

| 实际字体资产 | 文件来源与许可 | 本次观察及交付动作 |
|---|---|---|
| `MaterialIcons-Regular.otf` | Flutter 3.47.5 的 `material_fonts` 缓存，构建依赖表指向其 `materialicons-regular.otf`。随该缓存提供的 `materialicons_license.txt` 为 CC-BY-4.0 | 候选中的字体是 2,784 字节的构建子集。其许可原文在 `NOTICES.Z` 中未检出。W8 随该字体附缓存中的许可文本、来源、署名及子集化说明，并在成包后复核。 [实际字体与许可哈希](logs/D4_dependency_inventory.json) · [CC BY 4.0 原文](https://creativecommons.org/licenses/by/4.0/legalcode) |
| `CupertinoIcons.ttf` | `cupertino_icons` 1.0.9，包内 MIT `LICENSE` | 构建包含字体资产，包名出现在 `NOTICES.Z` 中。交付时保留该声明。 [版本许可](https://pub.dev/packages/cupertino_icons/versions/1.0.9/license) |

### 3. Tika 与本地开发资源

本机 Tika 目录有 121 个 JAR，其中启动 JAR 和 `lib/` 里的 116 个 JAR 在 W6 运行哈希清单内，另有展开的 Tika 插件目录中的 4 个 JAR。D4 逐个索引 JAR 的哈希、内置许可与 NOTICE 文件路径、可用的 `Bundle-License` 和 POM 许可声明，并标明各自是否在 W6 绑定中。资源根的顶层 `LICENSE` 和 `NOTICE` 与仓库归档逐字节一致。 [Tika 原始 LICENSE](../../tools/tika-app/LICENSE) · [Tika NOTICE](../../tools/tika-app/NOTICE) · [逐 JAR 索引](logs/D4_dependency_inventory.json)

Tika 发行版 `LICENSE` 单列 JHighlight 2.0.0 的 CDDL 1.0／LGPL 2.1-or-later 双许可及 JUnRAR 的 UnRAR 条款。`boilerpipe` 1.1.0、`parso` 2.0.14、`pf4j` 3.15.0 和 `picocli` 4.7.7 的本地 JAR 未找到对应的许可文本或许可元数据。Parso、PF4J 与 Picocli 的上游标注 Apache-2.0，Boilerpipe 的固定版本原文仍待补。W8 若随包提供这些 JAR，需把所附声明与实际版本对齐。 [Tika 发行版条款](../../tools/tika-app/LICENSE) · [Boilerpipe 项目档案](https://code.google.com/archive/p/boilerpipe/) · [Parso 上游](https://github.com/epam/Parso) · [PF4J 上游](https://github.com/pf4j/pf4j) · [Picocli 4.7.7 LICENSE](https://github.com/remkop/picocli/blob/v4.7.7/LICENSE)

`engine/requirements.txt` 中的 Chroma、TensorFlow、NumPy、Pillow 等为开发和评测依赖。生产候选从本地 DLL 加载 ONNX Runtime。已检查的 Flutter Release 文件表中没有 Python、JRE、Tika JAR 或模型权重，生产测试通过独立资源根加载所需文件。 [开发依赖锁定值](../../engine/requirements.txt) · [实测候选哈希及资源](logs/D4_dependency_inventory.json)

### 4. 第三方声明索引与发布核对

| 随包内容 | 声明原件位置与复验条件 |
|---|---|
| 项目源码、桥接 | 根 `LICENSE`，绑定实际发布提交 |
| Flutter、Dart 包、ICU | `data/flutter_assets/NOTICES.Z`。改依赖或重建后重新检查声明 |
| Material Icons 字体 | Flutter SDK 的 `bin/cache/artifacts/material_fonts/materialicons_license.txt`，附字体来源、署名和子集说明 |
| ONNX Runtime | 运行资源根的 `bin/LICENSE`、`bin/ThirdPartyNotices.txt`，核对 SDK 版本和哈希 |
| Apache Tika | `tools/tika-app/LICENSE`、`NOTICE` 与各实际随包 JAR 的声明，单独核对拟交付的插件及第三方条款 |
| Java | 当前指向外部 Temurin。若改随包，核对实际发行版 `NOTICE`、`legal/` 和提供对应源码的条件 |
| 模型资源 | MiniLM 保留上游 Apache-2.0 与导出来源。按 ADR 0003 从公开包排除 MobileCLIP-S0 模型资源，并检查缺件提示。 [模型登记](../../models/README.md) |

### 5. D4 打磨记录

复核 D3 的键盘、清空弹窗焦点、缺资源提示和显示设置结果。当前自动范围通过，未发现本轮可稳定复现且可按相同条件复测的小缺陷。D4 交付合规文档与清单，正式包检查和候选原生复验已有待办。 [D3 测试日志](logs/D3_flutter_tests.txt) · [W8 移交](W08_移交.md)

## 演示脚本

供 W8 录像，成片目标 **05:00**。文档和演示预检的源码基线为 `14b3abeefcea15b7b3ed5f93956c7658eab52121`。开场字幕填写实际出镜构建的标识。插用归档画面时，角标注明原构建及场次。 [源码核对](D1_缺口表.md) · [W07 交付状态](W07_report.md)

| 证据或画面 | 构建归属 |
|---|---|
| 计划录制的新画面 | Windows x64 关键词优化候选，由 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e` 加归档补丁构建。`desktop.exe` SHA-256 为 `e0af370dad83c60edb5cc03f35d7fd8d4c12237f9c16304f71e2f98bf3e1baa9`，`data/app.so` 为 `41c36aa3c372d6fcba4701a322f3f6185d9172d2b5b90a3e39d1d480c16ad0a3`。 [构建清单](../week6/logs/D5_10k_keyword_candidate.json) · [D2 生产冒烟](logs/D2_maintenance_verification.json) |
| W6 D5 或 M-05 窗口素材 | 原候选 `04c22914a86f9cd3d1d6cf9050b4e2e16055627e`，`desktop.exe` SHA-256 为 `159a7f0294655b9b55d6ae781c56827b3fa9045283feeccf60e42cfc12dbce27`。M-04 开发模式截图单独标注。 [原候选清单](../week6/logs/D5_candidate_manifest.json) · [M-05 记录](../week6/logs/M05.txt) |
| W5 读屏与显示素材 | Windows 开发版的部分实机记录。使用原注释所述的实测范围。 [W5 验收矩阵](../week5/E_验收矩阵.md) · [NVDA 原始记录](../week5/logs/screen_reader_nvda_session.md) |

### 录制前准备

按 [技术文档 §3.2](#32-准备生产资源并启动) 在仓库根配置 `$repo`、`$desktop`、`$work` 和运行环境，先执行到设置 `$env:TMP`。下方命令创建专用演示索引和夹具。录制时用“选择目录”导入命令打印的 `$fixtures`。先在独立目录预演，再用全新的 `$work` 正式录制。

```powershell
$fixtures = Join-Path $work 'demo-fixtures'
$notes = Join-Path $fixtures 'notes'
New-Item -ItemType Directory -Path $notes -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'datasets/samples/sample.pdf') -Destination $notes
foreach ($name in 'sample.docx','sample.png') {
    Copy-Item -LiteralPath (Join-Path $repo "datasets/samples/$name") -Destination $fixtures
}
Set-Content -Encoding utf8 -LiteralPath "$notes/guide.txt" -Value '离线检索演示指南。Tika 在本机抽取 PDF 文字。'
Set-Content -Encoding utf8 -LiteralPath "$fixtures/bad.docx" -Value 'deliberately invalid DOCX archive'
$env:AMR_DATA_DIR = Join-Path $work 'demo-data'
$fixtures
Start-Process -FilePath $desktop -WorkingDirectory $env:SystemRoot
```

预期入库 4 份，`bad.docx` 单列失败。统一用 `tika` 作为演示查询。PDF 筛选和 `notes` 路径条件下，核对 `notes/sample.pdf` 及其出处页码。把系统查看器准备好，正式录制时以实际打开文件为准。冷启动和索引等待可剪辑，保留索引开始及结果，并标明剪去了等待。若要展示真实断网，在 W8 场次登记隔离方式和连通性检查。 [M-05 的 `tika`／PDF 实测](../week6/logs/M05.txt) · [离线实机取证步骤](../week6/D5_人工验证清单.md)

D5 按上述命令生成夹具并用生产 worker 预检。写入 4 份、98 个内容块，坏 DOCX 独立失败。组合筛选的 20 条结果均来自 `notes/sample.pdf`，首条为第 1 页，UTF-16 偏移 1318–1328。再次建库复用 4 份。查看器画面留待 W8 录制。 [D5 交付检查](logs/D5_delivery_check.json)

### 00:00–00:45 离线与本机资源

| 项 | 分镜 |
|---|---|
| 画面与操作 | 片头放构建标识和哈希。切到“设置”的“本地运行依赖”，展示 ONNX Runtime、Java 和索引位置。用演示目录的名称标示资源与数据分别放在哪 |
| 旁白 | “这是 Windows x64 研究候选。模型和 Tika 资源预先放在本机。生产模式用 ONNX Runtime CPU，解析和 SQLite 索引也在本机完成。这里配置的是本次演示专用的索引目录。” |
| 证据与替代画面 | 新开场按优化候选台账。若当次无法录到诊断页，使用标注为“W7 D2 无界面冒烟”的结果摘要。 [候选清单](../week6/logs/D5_10k_keyword_candidate.json) · [D2 启动结果](logs/D2_maintenance_verification.json) |
| 演示边界 | 这一段介绍本地资源布局。网络隔离和出站观察引用各自的实测场次。其他两平台的生产适配仍待验证 |

### 00:45–01:55 选择目录并建库

| 项 | 分镜 |
|---|---|
| 画面与操作 | 打开“文件库”，点击“选择目录”选中演示夹具，按“建立 / 增量更新索引”。显示进度，完成后停在计数及 `bad.docx` 的错误描述 |
| 旁白 | “这个目录里有文本、PDF、DOCX 和图片。四份正常文件写入索引。故意损坏的 DOCX 有自己的失败记录，其余文件仍可搜索。再次更新同一目录时会复用未改动的内容。” |
| 证据与替代画面 | 如需插入素材，可用角标为“W6 原 D5 10k 导入”的候选截图，按该图实际计数旁白。坏件提示可用注明“W5 开发版混合导入”的单独画面。 [原 D5 导入](../week6/screenshots/D5-10k-import.png) · [W5 坏件画面](../week5/screenshots/02-library-incremental.png) |
| 演示边界 | 原 D5 10k 截图的计数来自大夹具。新画面中的 4 份正常文件来自上面的演示目录 |

### 01:55–03:10 查询、筛选、出处与查看器

| 项 | 分镜 |
|---|---|
| 画面与操作 | 在“搜索本地内容”输入 `tika`，选择 `PDF`，在“相对目录或文件路径”填 `notes`，按“开始搜索”。停留在 `sample.pdf` 的片段、相对路径、页码和偏移。按“打开原文件”，展示系统查看器中打开的实际文件 |
| 旁白 | “类型和目录条件一起缩小搜索范围。结果给出片段、来源路径和页码，可以据此在原件中核对。打开按钮把文件交给系统的默认查看器。需要核对具体页时，可以根据结果页给出的页码手动定位。” |
| 证据与替代画面 | 可插用注明“M-04 开发模式 PDF 结果”的截图。查看器画面取不到时，在结果画面上说明 M-05 曾由 Acrobat 打开同一样本的恢复实例。 [M-04 PDF 结果](../week6/screenshots/M04-results.png) · [M-05 查看器记录](../week6/logs/M05.txt) |
| 演示边界 | 排序分值表示相关性。系统打开入口传递文件路径，页码和片段定位由查看器决定 |

### 03:10–04:10 键盘操作与显示

| 项 | 分镜 |
|---|---|
| 画面与操作 | 返回应用，按 Ctrl+L 聚焦查询框，输入或确认 `tika`，按 Enter 提交。用 Tab 移到结果的“打开原文件”。进入设置，选 150% 文字并展示焦点，或切换高对比 |
| 旁白 | “Ctrl+L 将焦点移到查询框，Enter 提交，Tab 可继续到结果的打开按钮。设定 150% 后可用 Tab 或滚动继续操作。W5 的 Windows 实机记录还覆盖了 NVDA 读取来源和打开文件的部分场景。” |
| 证据与替代画面 | 若新场次录到 NVDA，则同时标出实际版本和构建，并保留原声。没有新读屏录音时，引用 W5 原文，或使用明确标注的 W5 150%／高对比截图。 [NVDA 原文](../week5/logs/screen_reader_nvda_session.md) · [W5 150%](../week5/screenshots/10-text-scale-150.png) · [W5 高对比](../week5/screenshots/07-high-contrast-light.png) |
| 演示边界 | 完整自动朗读、系统查看器返回后的精确焦点及 VoiceOver／Linux 仍待验证。独立试用记录为 0 人 |

### 04:10–05:00 技术路径与交付范围

| 项 | 分镜 |
|---|---|
| 画面与操作 | 放架构图中的解析、嵌入、SQLite 与检索部分，随后回到结果页。字幕注明 10k 中文探针 p95 **357.97 → 245.16 ms**、预算 **200 ms** |
| 旁白 | “PDF 仍由 Tika 解析，文本和图像通过 ONNX 嵌入。SQLite 保存索引，检索融合关键词、文本向量和图像向量。中文关键词优化后，10k 全库探针 p95 降至 245.16 毫秒，仍高于 200 毫秒预算。公开安装包的项目方案排除 MobileCLIP 权重。” |
| 证据与替代画面 | 以同轮探针对照显示数据，标为“生产 AOT 探针”。架构与许可画面来自项目文档。 [系统架构](../../docs/architecture/system-architecture.md) · [10k 中文探针对照](../week6/benchmarks/D5_10k_probe_summary.json) · [模型分发范围](#开源合规报告) |
| 演示边界 | 该时延属于固定快照的中文探针。优化候选的中文桌面时延、图像问句召回限制及安装包验收按各自证据记录 |
