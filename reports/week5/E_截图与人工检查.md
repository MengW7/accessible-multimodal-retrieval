# 工作包 E：用户人工验收与截图清单

所有应用启动、窗口/键盘/鼠标操作、读屏、网络条件设置、截图和录像均由用户执行。
本轮只运行无界面自动测试，不启动 desktop.exe、原生选择器或系统查看器。
未填写实际结果前，下列人工项均未验证；B/C/D 清单继续保留，此文件作为 E 的统一执行入口。

## 1. 演示环境（由用户准备）

E 自动集成验证成功后，专用样本目录见 `logs/E_headless_acceptance.json` 的 fixtureRoot。
输入包含 notes/guide.txt、archive/old.txt、notes/sample.pdf、sample.png 和故意损坏的 bad.docx；
guide.txt 修改时间为 2026-10-29，其余为 2020 年。不是评测语料，不读 holdout。
在仓库根目录 PowerShell 中由用户执行：

```powershell
$env:AMR_DEV_ROOT = (Get-Location).Path
$eEvidence = Get-Content './reports/week5/logs/E_headless_acceptance.json' -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $eEvidence.ok) { throw 'E 自动集成验证未通过，请先查看其错误记录。' }
$eEvidence.fixtureRoot
$eDataDirectory = Join-Path $env:AMR_DEV_ROOT ('tmp/w05-e-manual-' + [guid]::NewGuid().ToString('N'))
$env:AMR_DATA_DIR = $eDataDirectory
& './apps/desktop/build/windows/x64/runner/Release/desktop.exe'
```

正常重启测试保留同一数据目录，只重复最后的启动命令；每位独立试用者从新的 GUID 数据目录开始。
保持整个 Release 目录完整，并满足开发运行时的模型、Python/ONNX、Java/Tika 前提。
禁止使用评测库 `reports/week5/.index/bench.sqlite`。如专用样本目录已清理，可重新运行 E 的无界面命令生成。
构建和环境标识见 `logs/E_build_manifest.json`、`logs/E_environment.json`。

## 2. 统一执行顺序

| ID / 对应矩阵 | 用户操作 | 预期与实际记录要求 | 状态 |
|---|---|---|---|
| E-M01 / BUILD-01 | 从非仓库工作目录启动同一 Release 程序，保持绝对路径环境变量；查看依赖诊断 | 能定位同一数据目录/资源；开发依赖说明准确。缺失依赖场景按 A 的已知配置检查，避免修改系统关联或权限 | 待用户验证 |
| E-M02 / UI-01、02 | 在空演示库导入 fixtureRoot；查看好/坏文件，重复增量，任务期间导航；用较多专用样本检查取消后再恢复 | 首次预期好文件 4、坏文件 1；未改变的 4 个文件复用；取消不回滚已提交数据。原生选择器、重复提交与窗口响应由实机确认 | 待用户验证 |
| E-M03 / UI-03、05 | Ctrl+L 搜索“离线检索”；类型 PDF；TXT+notes/+2026-10-25；路径 absent；日期 2026-02-30 后修正 | PDF 有实际页码；组合条件只留下 guide.txt；absent 是无命中，区别空库；无效日期提示可恢复。扩展边界情形见 C 清单 | 待用户验证 |
| E-M04 / UI-04、05 | 打开 TXT/PDF/图片原文件；退出应用后在专用样本中临时改名 guide.txt，重开旧索引并搜索/打开，恢复后重试 | 查看器实际打开正确来源；缺失与系统打开失败可区分。记录查看器名称、页定位限制和焦点。仅改专用样本并及时恢复 | 待用户验证 |
| E-M05 / A11Y-01 | 全程不用鼠标完成导入、查询、筛选、打开、设置与清除取消；Tab/Shift+Tab、Enter/Space、Ctrl+L、Esc；页面底部回导航 | 无陷阱；焦点可见且自动滚动；弹窗默认保留、关闭后回触发控件；原生选择器/查看器的焦点返回单列 | 待用户验证 |
| E-M06 / A11Y-02 | NVDA 重复 E-M02～05，尤其控件名称/角色/值、结果标题、含文件名的打开按钮、图片元数据及状态播报 | 记录逐字朗读与按键；滚到页面底部时也检查后台提示，无关键遗漏/持续重复。实际读屏不能由语义树或截图代替 | 待用户验证 |
| E-M07 / A11Y-03 | 明暗主题各自开/关高对比，查看四页和加载/错误/选中/焦点/禁用状态；按需检查系统高对比 | 关键内容/边界清楚，错误不只靠颜色；补足 28 个配置色对未覆盖的实际状态 | 待用户验证 |
| E-M08 / A11Y-04 | 同一窗口分别 100/150/200%，窄窗口重复长路径、片段、下拉框与弹窗；系统缩放+跟随系统/显式字号组合 | 全部核心操作可达，文字不遮挡导致功能丢失；标题增长，显式字号不重复乘系统/像素比例 | 待用户验证 |
| E-M09 / UI-01、05 | 更改显示设置并正常重启；恢复默认后再重启；在演示库确认/取消清除 | 设置恢复/重置正确；清除索引保留源文件和显示设置。设置损坏恢复按 D-13 操作 | 待用户验证 |
| E-M10 / UI-06 | 本地依赖齐全后，由用户自行提供断网条件，重复导入、检索和打开 | 记录隔离方式/开始结束时间/全部步骤及结果。自动测试没有隔离网络，不能作为此项通过证据 | 未执行 |
| E-M11 / UX-01 | 邀请 2–3 名独立试用者执行可用性报告的 T1～T5，至少一人熟悉键盘/读屏 | 按场记录成功/求助/失败、耗时、误操作、困难和证据；开发者走查另计 | 未执行 |
| E-M12 / 跨平台 | 有 macOS/VoiceOver、Linux 宿主和环境后重复适用流程；macOS 用 Command+L | 独立平台证据；没有环境时保留阻塞，不继承 Windows 结论 | 未验证，环境待补齐 |

## 3. 截图、记录与缺陷回填

建议用户保存到 `reports/week5/screenshots/`：

- `E-import-mixed.png`、`E-filter-results.png`、`E-source-viewer.png`：实际导入、筛选、打开。
- `E-keyboard-focus.png`、`E-dialog-focus.png`：焦点和弹窗。
- `E-contrast-light.png`、`E-contrast-dark.png`：两种高对比状态。
- `E-scale-100.png`、`E-scale-150.png`、`E-scale-200.png`、`E-scale-200-dialog.png`：同窗口字号比较。
- `E-error-recovery.png`、`E-settings-restored.png`：错误恢复和真实重启。

不是每步都必须截图；键盘与朗读结论必须另有操作记录，不能只凭静态图判定。
读屏/键盘日志可使用 `logs/screen_reader.md`、`logs/keyboard_walkthrough.md`，实际执行后再填写。
每项记录日期、构建标识、OS/工具版本、数据目录、窗口/缩放、步骤、期望、实际、判定和证据路径。

回填顺序：实际日志 → [E_验收矩阵.md](E_验收矩阵.md) 对应行 →
[E_问题与复测记录.md](E_问题与复测记录.md)（如有失败）→ 修复后同条件复测。
用例中的自动部分通过并不表示对应实机项目已经签收。

完整前序细节参见 [B 清单](B_截图与人工检查.md)、[C 清单](C_截图与人工检查.md)、[D 清单](D_截图与人工检查.md)。
