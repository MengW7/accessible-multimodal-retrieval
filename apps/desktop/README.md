# 本地内容检索桌面应用

W5 工作包 A/B/C/D 提供应用骨架、共享状态、运行依赖诊断、真实服务装配、文件库管理、搜索闭环与无障碍设置。
文件库、搜索、结果、设置四个功能区均可导航；查询草稿在切换页面后保留。
文件库已支持目录选择、进度、逐文件状态、取消、增量重建与清除确认。
文本查询、筛选、出处展示与打开原文件已接入；D 已实现读屏语义、键盘焦点、显示设置与持久化。
NVDA/VoiceOver 与实际纯键盘全流程仍需用户按 D 清单验收。

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
后台 worker、关闭 SQLite 与嵌入进程，等待显示设置保存后再退出窗口。

相同内容哈希共用一份文档，结果路径沿用最初写入的来源；目录统计与文档统计可能不同。
增量更新不会自动删除已从磁盘移除或改名的旧文件记录，需要时可清除应用索引后重新导入。
这与 C 中“源文件丢失”的可恢复提示分别处理，不把缺失路径包装成可打开的文件。

## 搜索与打开原文件

1. 在搜索页输入文本，按 Enter 或点击“开始搜索”。第一次查询可能需要加载本地模型。
2. 可按 TXT、Markdown、PDF、DOCX、图片筛选。路径条件使用导入目录内的相对目录或完整
   相对文件路径，例如 `notes`、`notes/` 或 `notes/recent.txt`。目录条件包含子目录；它不是任意字符串前缀匹配。
3. 修改日期格式为 `YYYY-MM-DD`，含义是严格晚于该日期的本地零点。错误日期、绝对路径条件
   和空查询会显示修正提示。“清除筛选”仅清空输入条件，需要重新提交才能应用。
4. 每次最多展示前 20 条结果；结果页显示本次实际提交的查询和条件，避免将后续草稿误认为已应用。
   连续提交只保留最新查询，旧查询的成功或失败都不会覆盖新结果。
5. 结果展示文件名、类型、路径、片段、实际页码（若有）与命中块偏移。片段可含相邻上下文，
   UTF-16 偏移仅描述命中块，不作为扩展片段的起点。图片只显示文件名和已有尺寸/格式等元数据，不生成图像描述。
6. “打开原文件”将索引的真实绝对路径交给 Windows 的系统查看器。界面只报告系统接受了打开请求，
   不保证查看器已显示文件或自动跳到指定页/段。文件丢失、权限/默认查看器失败会分别给出可恢复提示。
   较早的探针索引若只保存相对来源键，需要经桌面端重新导入后再打开。

空库提示先建库；实际空结果提示修改查询/条件，不根据低分推断“资料不存在”。没有可靠的无答案阈值。
取消查询在后台安全点完成；用户可立即提交新查询，索引写入/清除需等旧查询收尾后再执行。
索引变更会使现有结果失效，需重新查询。系统打开文件功能目前只实现 Windows；其他平台给出明确说明。

## 无障碍与显示设置

- `Ctrl+L` 聚焦搜索，macOS 对应 `Command+L`；Tab / Shift+Tab 移动焦点，按钮用 Enter / Space 激活。
  清除确认弹窗默认聚焦“保留索引”，Esc 关闭，关闭后返回清除按钮。快捷键在弹窗打开时不切换页面。
- 主要输入和操作控件显示 3px 焦点边框，获得焦点时滚动到可见位置；窄窗口导航可滚动，保留在焦点顺序中。
  目录选择器、系统查看器和读屏软件的实际焦点行为须人工验证。
- 设置支持跟随系统 / 浅色 / 深色、高对比、跟随系统字号 / 100% / 150% / 200%。系统高对比启用时也使用高对比主题。
  跟随系统保留系统 TextScaler；显式字号直接替代系统文字比例，不再乘屏幕像素比例。标题工具栏随字号增长。
- `display-settings.json` 与 `library.sqlite` 位于同一数据目录，保存明暗、高对比和字号；正常重启自动恢复。
  更改立即生效并排队写入，使用临时文件替换；保存失败显示文字提示。损坏记录加载时保留原文件，
  可用“恢复默认显示设置”保存默认值。该操作只重置显示设置。
- 控件保留名称、角色和状态，标题有 heading 语义，打开按钮包含来源文件名；图片只朗读真实元数据。
  单个 live region 提供任务、查询和错误状态，索引进度按阶段及约 10% 区间更新，减少重复播报。

D 的自动证据与 WCAG 检查范围见 `reports/week5/W05_D_checkpoint.md`。
所有桌面交互、截图和读屏测试由用户执行，见 `reports/week5/D_截图与人工检查.md`；语义测试不等于实际读屏通过。

## 构建与复现验证

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
./tool/verify_runtime.ps1
./tool/verify_library.ps1
dart run tool/verify_search.dart
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

`verify_search.dart` 是无界面的纯 Dart 验证命令，不启动 Flutter 窗口、系统文件选择器或查看器。
它在 `tmp/w05-search-*` 的新库内建 6 个独立样本，检查 9 组搜索/筛选与直接核心调用一致、
空库、无命中、连续查询替换，以及先搜索再增量建库的回归。结果写入 `reports/week5/logs/C_search_smoke.json`。
打开文件适配器在测试中用替身/通道模拟；真正的导入到系统查看器闭环、截图、断网与读屏操作由用户执行，
见 `reports/week5/C_截图与人工检查.md`，不能由无界面验证推断全部通过。

## 结构与下一步接线

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 组合根，读取配置，装配服务与控制器，启动 UI/显式冒烟模式 |
| `lib/src/app.dart` | 可响应窗口宽度的导航和四个页面；不访问数据库或启动进程 |
| `lib/src/application/app_controller.dart` | 页面、查询草稿、筛选/结果状态、启动状态及重试；丢弃过期启动响应 |
| `lib/src/application/desktop_service.dart` | 可替换的应用服务接口；诊断/冒烟经 `Isolate.run` 在后台执行 |
| `lib/src/application/library_service.dart` | 文件库的 load/index/cancel/clear/close 与目录选择接口 |
| `lib/src/application/library_models.dart` | 可跨 isolate 发送的进度、逐文件结果、目录历史及统计 |
| `lib/src/application/search_models.dart` | 查询快照、筛选校验、结果状态和文件打开契约 |
| `lib/src/search_page.dart` / `lib/src/results_page.dart` | 搜索表单、已应用条件、结果出处与可恢复错误 |
| `lib/src/library_page.dart` | 目录输入、进度、取消、确认弹窗和文件状态分页 |
| `lib/src/accessibility_widgets.dart` / `lib/src/app_theme.dart` | 语义边界、可见焦点、状态区域及共享明暗/高对比主题 |
| `lib/src/settings_page.dart` / `lib/src/application/display_settings.dart` | 显示设置界面、快捷键说明与设置格式 |
| `lib/src/runtime/display_settings_store.dart` | 数据目录内的显示设置读取、写入与错误恢复 |
| `lib/src/runtime/library_worker.dart` | 常驻 worker、取消协议、目录记录持久化及资源释放 |
| `lib/src/runtime/directory_picker.dart` | Windows 原生文件夹对话框的 MethodChannel 适配；其他平台可输入路径 |
| `lib/src/runtime/window_lifecycle.dart` | Windows 正常关闭时等待后台收尾 |
| `lib/src/runtime/file_opener.dart` | 验证来源文件并通过 Windows MethodChannel 交给系统查看器 |
| `lib/src/runtime/runtime_config.dart` | 可执行文件位置、资源根、用户数据目录与配置校验 |
| `lib/src/runtime/runtime_diagnostics.dart` | 资源、Python 模块、Java、SQLite/目录权限检查 |
| `lib/src/runtime/runtime_session.dart` | 真实解析器、嵌入引擎、索引管道、查询管道的装配及资源释放 |

真实接线为带进度回调的 `IngestionService / IndexSource → DefaultIndexingPipeline → SqliteVectorStore`，
查询为 `DefaultSearchPipeline → DefaultRetriever → QueryEncoder/VectorStore`。
不调用 `bin/` 探针，不解析终端文字，不复制打分算法。会话持有 SQLite 和常驻嵌入进程，
在 `finally` 或 worker 关闭时释放；B 的常驻 worker 传递进度、取消和结果，数据库句柄不传给 UI。
C 复用同一个 worker 的真实搜索会话，后台只保留一个待执行的新查询；新请求会取消旧请求和过期排队项。
控制器另用请求代次阻止旧结果/错误以及过期打开反馈覆盖新页面。索引命令与查询命令串行执行。
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
