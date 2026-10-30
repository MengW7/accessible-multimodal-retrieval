# W05 工作包 A：应用骨架与运行时验证

日期：2026-10-29（Asia/Shanghai）。

**结论：A 的出口判据已满足。** 四个功能区可达，共享状态与应用服务接口已建立，
真实核心服务装配已通过 Windows release 程序验证，发布依赖清单与阻塞项已登记。
这不代表生产嵌入运行时、完整 UI 主流程或跨平台正式发布包已完成。
计划中 A 的 8h 是预算，本次未逐分钟跟踪实际工时，不将其直接登记为已耗 8h。

## 1. 逐项验收

| A 任务/出口 | 实际结果 | 证据 |
|---|---|---|
| 建立导航与四个功能区 | 通过；文件库、搜索、结果、设置均可到达，宽窗口侧栏/窄窗口底部导航 | `screenshots/A-library.jpg`、`A-search.jpg`、`A-results.jpg`、`A-settings.jpg`；Widget 测试 |
| 应用状态模型 | 通过；共享页面状态、查询草稿、筛选/结果容器和 checking/ready/blocked 启动状态；异步重试不被旧响应覆盖 | `apps/desktop/lib/src/application/app_controller.dart`；相关测试 |
| 应用服务接口 | 通过；可注入 `DesktopService`，后台 isolate 执行依赖检查/真实运行验证；Widget 不操作 SQLite 或启动探针 | `apps/desktop/lib/src/application/desktop_service.dart` |
| 真实服务接线方案明确 | 通过；纯 Dart 解析、Tika、三路嵌入、SQLite、索引管道与检索管道直接装配，无探针文本接口 | `apps/desktop/lib/src/runtime/runtime_session.dart`；真实冒烟 JSON |
| Windows 构建 | 通过；最终 release 构建成功 | `logs/A_windows_build.txt` |
| 模型与解析依赖定位 | 通过开发模式验证；显式资源根，检查分词器/模型/脚本/Python 模块/Java；PDF 实际解析成功 | `logs/A_runtime_development.json` |
| 数据库路径 | 通过；默认使用用户数据目录，演示/冒烟可显式覆盖，拒绝相对路径；检查 SQLite 与目录写入错误 | 配置单测、设置截图、冒烟报告 |
| 非仓库工作目录启动 | 通过；从 `C:\Users\11758\AppData\Local\Temp\` 启动 release 程序，资源/数据库均通过绝对路径定位 | `logs/A_build_smoke.json` |
| 依赖缺失有明确错误 | 通过；生产适配器缺失、缺资源、缺 Java 均输出阻塞检查与退出码 1；UI 仍可导航/查看详情 | 三份失败场景 JSON；设置截图；错误恢复测试 |
| 发布依赖清单与阻塞项 | 已登记，见第 4、5 节 | 本记录及桌面 README |

## 2. 实现范围与边界

- `main.dart` 为组合根，`RetrievalApp` 展示页面，`AppController` 持有共享状态。
- `RuntimeConfig` 从可执行文件位置和平台用户数据目录定位资源，不从工作目录向上找仓库。
  `AMR_DEV_ROOT` 显式启用仓库开发环境，`AMR_DATA_DIR` 独立控制索引目录，`AMR_JAVA`
  可指定 Java 的绝对路径。环境配置在启动时读取，修改环境需重启。
- `RuntimeSession` 装配 `IngestionIndexSource`、`DefaultIndexingPipeline`、
  `DefaultSearchPipeline`、`DefaultRetriever` 与 SQLite；调用真实核心包入口，不复写检索算法。
  会话关闭时释放 SQLite 和常驻 Python 嵌入进程。
- 启动诊断及显式工程冒烟放在后台 isolate；A 没有把同步解析/分词/数据库工作直接放进 Widget。
- 导入、查询提交、结果打开和显示设置尚未接入，相关按钮禁用并说明状态。
  当前输入框只保存查询草稿。真实查询证据来自同一 release 程序的工程冒烟入口，
  **不作为 UI-03/UI-04 或完整用户流程通过的证据**。
- 未实现或宣称 NVDA/VoiceOver 全流程、WCAG 合规、独立用户测试或断网隔离验证。

## 3. 本机验证与证据

工具链：Flutter 3.47.5、Dart 3.13.4、Windows 11，Visual Studio Build Tools 2022
17.14.41，Windows SDK 10.0.26100.0；Java Temurin 21.0.12.1；ONNX Runtime 1.30.0。
Android SDK 缺失不影响本次 Windows 目标；macOS/Linux 没有构建环境。

| 检查 | 最终结果 |
|---|---|
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub --reporter expanded` | 10 项通过 |
| `flutter build windows --release --no-pub` | 成功，`build/windows/x64/runner/Release/desktop.exe` |
| `tool/verify_runtime.ps1` | 四场景的退出码和 JSON 结果均符合预期 |
| 原生窗口走查 | 四区可达；默认发布模式缺运行时提示可见；截图与语义树已保存 |

最终真实冒烟为 4 份专用样本：临时 `smoke.txt` 加复制的 `sample.docx`、`sample.pdf`、
`sample.png`。四份解析均为 `ok`，PDF 2 页/4358 字符，DOCX 1499 字符；
写入 4 份文档、98 个内容块（97 个文本、1 个图像），失败数 0。
实际完成 100 次嵌入进程请求，查询“离线检索”返回 5 条结果，包含文本和图像通道。
最终运行耗时 31207 ms，仅为这次小样本冒烟计时，不作为通用性能指标或准确率指标。

每次脚本都建立新临时目录和新数据库；没有加载 W5 题集，没有重跑 holdout，
没有清理或重嵌 `reports/week5/.index/bench.sqlite`。临时索引保留在
`tmp/w05-runtime-*/`，已加入针对性的 Git 忽略规则，日志与截图正常保留。

最终可执行文件 SHA-256：
`7669BB7F43DB1256605B83EBA0A7EF940A497905BEAEEF34EAD6D6BC94A81B24`。
需连同同目录的 `flutter_windows.dll` 与 `data/` 使用；这只是开发验证产物。
Runner 的哈希不能单独标识 Dart 代码版本；包含 `data/app.so`、引擎 DLL 与 ICU
资源的构建哈希清单另存于 `logs/A_build_manifest.json`。

测试覆盖四区导航、草稿保留、依赖失败后的重试、过期检查响应、控制器提前销毁、
资源/数据库路径分离、拒绝相对路径、缺 Java/资源以及发布适配器阻塞。
替身只用于 Widget/状态测试，真实模型证据单独列于 `A_runtime_development.json`。

初次构建失败原因：模板的未使用 `tflite_flutter` 插件需要本机符号链接支持。
已确认项目中没有该插件调用，且既有 ADR 没有选它作为核心包运行时，随后移除依赖
及不相关 MobileNet 示例模型的打包声明，模型原文件保留。未修改 Windows 开发者模式。

## 4. 发布依赖清单

| 依赖 | 当前定位/验证 | 正式发布处理 |
|---|---|---|
| Flutter 桌面引擎/资源 | release 目录的 DLL、`data/`，本机非仓库工作目录启动通过 | 保留完整目录；安装包/干净机器验证留待后续 |
| 文本模型与分词器 | 资源根下 `models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/` | 安装布局、许可证、完整性与升级策略待确定 |
| MobileCLIP 图像塔/文本塔与分词器 | `models/raw/image/mobileclip-s0/`，真实推理通过 | 同上；生产推理适配器待接通 |
| 开发嵌入进程 | 显式开发模式使用 `engine/.venv`、`embed_server.py`、`w3_embed_lib.py`，依赖 numpy/onnxruntime/Pillow/tokenizers | TDD 规定 `engine/` 不进入产品包，不能照搬开发 Python 环境作为发布解决方案 |
| PDF 解析 | `tools/tika-app/tika-app-4.0.0.jar`、配套 lib、PATH/显式 Java；实际 PDF 解析通过 | Java/Tika 的随包分发、许可证、版本与资源布局仍待确认 |
| TXT/DOCX/图片解析 | 现有 Dart 核心解析包；本次样本均成功 | 保留核心包契约；大文件/坏文件处理由 B/E 验证 |
| SQLite 动态库 | 通过 `SystemSqliteLibraryLocator` 调用核心存储包；本机实际建库/查询通过 | Windows 系统库策略仍有 TDD 已登记风险；macOS/Linux 的动态库与干净机器验证未完成 |
| 用户数据目录 | 各平台用户目录规则，Windows 已验证；允许绝对路径覆盖 | 安装、迁移、权限及卸载保留策略后续补齐 |

## 5. 阻塞与后续移交

| 项目 | 当前状态 | 下一步 |
|---|---|---|
| 生产嵌入运行时 | 阻塞；无开发变量时明确显示缺适配器，未偷偷退回仓库 Python | W6 确定并实现生产推理适配器、模型安装布局与依赖检查，W8 验证发布包 |
| macOS | 未验证，当前仓库没有 macOS 宿主工程，本机不是 macOS | 补宿主工程；准备 macOS + Xcode/CLI、模型运行时、Java/Tika/SQLite；构建、VoiceOver 和打开文件实测 |
| Linux | 未验证，当前仓库没有 Linux 宿主工程，本机不是 Linux | 补宿主工程；准备 Linux + clang/CMake/Ninja/pkg-config/GTK 开发环境、运行依赖；构建及键盘/读屏实测 |
| 文件库后台通信 | B 待接入；A 只验证后台短会话 | 加持久 worker 的进度/取消/错误消息与生命周期管理；不要传 SQLite 句柄到 UI |
| 索引统计 | B 待处理 | 同时展示解析失败和嵌入/写库失败，不能只看 `IndexReport.failed`；明确同内容多路径规则 |
| 查询与出处打开 | C 待接入 | 转交真实筛选；过期请求保护；用真实路径打开文件；页码/UTF-16 偏移保持原语义 |
| 无障碍 | D/E 待验收 | 读屏、键盘、高对比、大字号及人工证据；当前语义树截图不等于完整无障碍验证 |

启动、构建、复现脚本与目录说明见 `apps/desktop/README.md`。
本次没有提交 Git commit，没有修改既有核心包算法、评测题集或历史评测结论。
