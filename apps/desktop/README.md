# 本地内容检索桌面应用

W5 工作包 A/B 提供应用骨架、共享状态、运行依赖诊断、真实服务装配和文件库管理。
文件库、搜索、结果、设置四个功能区均可导航；查询草稿在切换页面后保留。
文件库已支持目录选择、进度、逐文件状态、取消、增量重建与清除确认。
查询提交、结果打开和显示设置仍由后续 C/D 接入，相应按钮保持禁用。

## 本机开发启动

需要 Flutter Windows 工具链、仓库的模型文件、`engine/.venv`、Tika 与 Java。
在本目录运行：

```powershell
$env:AMR_DEV_ROOT = (Resolve-Path '../..').Path
# 可选：使用独立演示索引。目录必须是绝对路径。
$env:AMR_DATA_DIR = Join-Path $env:AMR_DEV_ROOT 'tmp/desktop-demo'
# 可选：AMR_JAVA 指定 java.exe 的绝对路径；默认从 PATH 找 java。
flutter pub get --offline
flutter run -d windows
```

开发模式显式使用 Python/ONNX；不会自动向父目录查找仓库。不要将 `AMR_DATA_DIR`
设为评测索引目录。默认数据库是用户数据目录下的
`AccessibleMultimodalRetrieval/library.sqlite`，与工作目录无关：

| 平台 | 默认用户数据根 |
|---|---|
| Windows | `LOCALAPPDATA`，缺省时 `USERPROFILE/AppData/Local` |
| macOS | `HOME/Library/Application Support` |
| Linux | `XDG_DATA_HOME`，缺省时 `HOME/.local/share` |

相对路径覆盖会被拒绝，避免换工作目录后误建另一个索引。修正进程环境后需重启应用；
“重新检查依赖”可用于修复同一路径下的缺失文件或目录权限后重试。

## 文件库操作

1. 点击“选择目录”打开 Windows 原生文件夹对话框，或直接输入目录的绝对路径。
2. 点击“建立 / 增量更新索引”。扫描与解析、嵌入与建库、保存记录分别显示进度；
   成功、复用、解析/建库失败、跳过和取消后的未处理文件有独立状态。
3. 点击“取消索引任务”会协作式取消：等待当前安全点，不回滚之前已提交的文件。
   取消后再次增量更新可以复用已提交内容。第一次模型加载期间也可能需要等待。
4. “已添加目录”保留最近一次结果，重启后仍可查看；“增量重建此目录”复用未改变的
   内容，并替换同一路径已修改的文档版本。文件明细每页 30 条，可翻页查看。
5. “清除全部索引”需要确认，说明当前数据库位置及源文件保留；它只清空应用索引和
   `library-roots.json` 中的目录记录，不删除或修改源文件。

任务期间禁用重复导入和清除，页面导航仍可使用。正常关闭 Windows 窗口会先取消并结束
后台 worker、关闭 SQLite 与嵌入进程，再退出窗口。

相同内容哈希共用一份文档，结果路径沿用最初写入的来源；目录统计与文档统计可能不同。
增量更新不会自动删除已从磁盘移除或改名的旧文件记录，需要时可清除应用索引后重新导入。
这与 C 中“源文件丢失”的可恢复提示分别处理，不把缺失路径包装成可打开的文件。

## 构建与复现验证

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
./tool/verify_runtime.ps1
./tool/verify_library.ps1
```

Windows 输出位于 `build/windows/x64/runner/Release/`。启动和分发时保留整个目录，
包括 `flutter_windows.dll` 和 `data/`，不能只复制 `desktop.exe`。
验证脚本从系统临时目录启动 release 程序，复制四个专用样本到新的 `tmp/w05-runtime-*`
目录；每次使用新数据库，不清理或重嵌已有索引。它验证：

- 开发运行时的 TXT/DOCX/PDF/PNG 解析、文本/图像嵌入、SQLite 建库与真实混合查询；
- 未配置生产适配器、缺少资源、缺少 Java 时的可处理错误；
- 程序退出码及 JSON 报告与预期一致。

结果保存在 `reports/week5/logs/A_*.json`。脚本结束会恢复它修改的进程环境变量。
该验证是工程冒烟，不是独立用户可用性测试，也未执行断网隔离验证。

`verify_library.ps1` 另建 `tmp/w05-library-*` 的专用输入与数据库，验证好/坏文件分别记录、
未改动内容复用、修改替换、目录记录持久化、即时取消、提交后取消及恢复、缺失目录、
清除后源文件保留。结果写入 `reports/week5/logs/B_library_smoke.json`，并通过主 isolate
定时心跳检查后台工作没有阻断主 isolate；它不代表已经完成大库压力或真实 UI 帧率测试。
B 不自动采集截图；截图与人工显示检查由用户完成，步骤见 `reports/week5/B_截图与人工检查.md`。

## 结构与下一步接线

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 组合根，读取配置，装配服务与控制器，启动 UI/显式冒烟模式 |
| `lib/src/app.dart` | 可响应窗口宽度的导航和四个页面；不访问数据库或启动进程 |
| `lib/src/application/app_controller.dart` | 页面、查询草稿、筛选/结果状态、启动状态及重试；丢弃过期启动响应 |
| `lib/src/application/desktop_service.dart` | 可替换的应用服务接口；诊断/冒烟经 `Isolate.run` 在后台执行 |
| `lib/src/application/library_service.dart` | 文件库的 load/index/cancel/clear/close 与目录选择接口 |
| `lib/src/application/library_models.dart` | 可跨 isolate 发送的进度、逐文件结果、目录历史及统计 |
| `lib/src/library_page.dart` | 目录输入、进度、取消、确认弹窗和文件状态分页 |
| `lib/src/runtime/library_worker.dart` | 常驻 worker、取消协议、目录记录持久化及资源释放 |
| `lib/src/runtime/directory_picker.dart` | Windows 原生文件夹对话框的 MethodChannel 适配；其他平台可输入路径 |
| `lib/src/runtime/window_lifecycle.dart` | Windows 正常关闭时等待后台收尾 |
| `lib/src/runtime/runtime_config.dart` | 可执行文件位置、资源根、用户数据目录与配置校验 |
| `lib/src/runtime/runtime_diagnostics.dart` | 资源、Python 模块、Java、SQLite/目录权限检查 |
| `lib/src/runtime/runtime_session.dart` | 真实解析器、嵌入引擎、索引管道、查询管道的装配及资源释放 |

真实接线为带进度回调的 `IngestionService / IndexSource → DefaultIndexingPipeline → SqliteVectorStore`，
查询为 `DefaultSearchPipeline → DefaultRetriever → QueryEncoder/VectorStore`。
不调用 `bin/` 探针，不解析终端文字，不复制打分算法。会话持有 SQLite 和常驻嵌入进程，
在 `finally` 或 worker 关闭时释放；B 的常驻 worker 传递进度、取消和结果，数据库句柄不传给 UI。
后续 C 应沿用 worker 的服务边界增加真实搜索命令。
现有 `IndexingPipeline` 接受 `IndexProgress` 回调与 `CancellationToken`；
`SearchPipeline` 接受 `SearchFilters`、取消令牌和 Top-K。B 将解析失败记录与建库结果合并，
不单独依赖 `IndexReport.failed`（它只统计嵌入/写库阶段失败）。
`IndexProgress` 新增可选源路径、逐文件结果、错误信息及新写入/复用/失败累计计数；
每份文件完成后让出一个事件循环，以便快速复用时也能接收取消消息。

结果以真实绝对路径写入 `documentKey` 供应用打开源文件；`relativePath` 保持核心契约，
筛选仍针对它。页码为空时不编造页码，偏移继续按 UTF-16 code unit 解释。
多目录相同内容仍沿用核心库按内容标识文档的语义，未引入多副本索引或调整检索打分。

## 发布缺口

没有 `AMR_DEV_ROOT` 时进入发布模式，资源根定位到可执行文件旁的 `runtime/`，
但生产推理适配器尚未实现，应用明确显示阻塞，不悄悄回退到仓库 Python。
这符合 TDD 中 `engine/` 不进入发布包的决定。模型/分词器如何随包安装、
原生 ONNX/TFLite 推理方案、Java/Tika 的分发及 SQLite 动态库策略仍需后续解决。

移除了模板中未使用的 `tflite_flutter` 依赖与 MobileNet 示例模型的打包声明，
示例模型文件仍保留。本机首次构建因该插件要求 Windows 符号链接支持而失败；
移除未使用插件后构建通过，没有修改 Windows 开发者模式。

当前只有 Windows 宿主工程且已验证构建与运行。macOS/Linux 的宿主工程、各平台
本地运行时、构建机器与读屏环境均需补齐；共享 Dart UI 不代表这些平台已经通过验证。
