# NVDA 实机会话记录与补充确认

已保留操作者填写的实际朗读原文，并依据用户于 2026-11-03 提供的补充确认更新审阅结果。
本文区分“原文可见信息”与“用户补充确认”；不是自动测试或维护者重新实测。整场为部分验证；此前 PDF 打开异常已由用户确认是 Acrobat 卡住，现已能正常打开，E-OPEN-01 按查看器环境事件关闭。
操作步骤见 [NVDA 分阶段清单](../NVDA实机验收清单.md)。第二次测试另建文件，保留本场记录。

## 开场信息

- 会话编号：
- 日期、开始/结束时间：
- 操作者及参与者类型（开发者走查 / 独立试用者）：
- NVDA 版本：2026.2.0.57664（用户确认）。语音语言/合成器、键盘布局及修饰键：未登记。
- 输入方式：用户确认全程使用键盘；是否有他人提示未说明。
- Windows 版本：
- 源码提交、未提交修改说明：
- 实际 desktop.exe SHA256：
- 实际 data/app.so SHA256：
- 本场 AMR_DATA_DIR 绝对路径：
- 输入目录与样本检查：
- 窗口尺寸、系统显示/文字缩放、应用字号、主题：
- 其他取证方式（可选录屏/截图）：

## 阶段 0：准备工具与样本

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：工具已使用；准备过程未单独记录
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
【阶段0朗读粘贴处】

## 阶段 1：启动与本场数据

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：首屏原文为空，版本绑定待补
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：


## 阶段 2：四页导航

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：名称/角色有原文，完整顺序及选中状态待确认
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```
文件库  button
搜索  button
目录的绝对路径
选择文件夹，或直接输入完整路径  edit
结果  button
设置  button
选择目录  button
建立 / 增量更新索引  button
grouping  支持 TXT、Markdown、PDF、DOCX、JPG、PNG。增量更新会复用未改变的内容。相同内容共用一份索引文档；源文件不会被修改。
清除全部索引  button
```

## 阶段 3：选择目录与首次导入

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：目录字段及入口可读，原生选择/进度完整性待确认
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```文件库  button
搜索  button
目录的绝对路径
选择文件夹，或直接输入完整路径  edit
E:\Project\accessible-multimodal-retrieval\tmp\w05-acceptance-1ca1c8c4\fixtures
目录的绝对路径
结果  button
设置  button
选择目录  button
建立 / 增量更新索引  button
设置  button
```

## 阶段 4：增量复用

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：原文记录写入 0、复用 4、失败 1
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```文件库  button
搜索  button
结果  button
设置  button
部分失败 · 新写入 4 · 复用 0 · 失败 1 · 跳过 0 · 警告 0
最近处理：2026-11-03 14:43:32.600894  grouping
增量重建目录 E:\Project\accessible-multimodal-retrieval\tmp\w05-acceptance-1ca1c8c4\fixtures  button
查看目录 E:\Project\accessible-multimodal-retrieval\tmp\w05-acceptance-1ca1c8c4\fixtures 的上次文件状态
目录的绝对路径  edit  E:\Project\accessible-multimodal-retrieval\tmp\w05-acceptance-1ca1c8c4\fixtures
选择目录  button
建立 / 增量更新索引  button
部分失败：新写入 0，复用 4，失败 1，跳过 0。
支持 TXT、Markdown、PDF、DOCX、JPG、PNG。增量更新会复用未改变的内容。相同内容共用一份索引文档；源文件不会被修改。
```

## 阶段 5：搜索与来源阅读

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：原文有结果；用户确认正文/完整来源路径可读
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```搜索  button
搜索本地内容
输入关键词或自然语言描述  edit
搜索本地内容  edit  离线检索
离线检索
结果  grouping  开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。
文件库  button
grouping  找到 20 条结果。
修改搜索条件  button
搜索  button
结果  button
设置  button
1. old.txt
类型：text/plain
此结果无物理页码。
命中块字符偏移：0–21（UTF-16，含首不含尾）。片段可包含相邻上下文，偏移仅对应命中块。
系统查看器可能无法直接定位到上述页或片段。  grouping
打开原文件：old.txt  button
```

## 阶段 6：PDF 筛选、打开与返回

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：PDF 筛选可读、TXT/Notepad 打开成功；PDF 已由用户确认恢复，精确返回焦点待补
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```
文件库  button
grouping  找到 20 条结果。
修改搜索条件  button
搜索本地内容  edit  离线检索
文件库  button
搜索  button
文件类型
所有类型  button  collapsed
弹出菜单  grouping
所有类型  button
TXT  button
Markdown  button
PDF  button
文件类型
PDF  button  collapsed
结果  button
相对目录或文件路径  edit
设置  button
修改时间晚于日期
YYYY-MM-DD（可留空）  edit
修改时间晚于日期
开始搜索  button
结果  grouping  开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。
文件库  button
grouping  找到 20 条结果。
修改搜索条件  button
搜索  button
结果  button
设置  button
1. sample.pdf
类型：application/pdf
出处：第 1 页
命中块字符偏移：1318–1328（UTF-16，含首不含尾）。片段可包含相邻上下文，偏移仅对应命中块。
系统查看器可能无法直接定位到上述页或片段。  grouping
打开原文件：sample.pdf  button
```

## 阶段 7：日期错误与恢复

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：错误提示可读；用户确认修正后搜索成功
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```搜索  button
文件类型
PDF  button  collapsed
结果  button
相对目录或文件路径  edit
设置  button
修改时间晚于日期
YYYY-MM-DD（可留空）  edit
修改时间晚于日期
2026-02-30
开始搜索  button
grouping  修改日期不存在，请检查年月日。
清除筛选  button
搜索本地内容  edit  离线检索
文件类型
PDF
相对目录或文件路径
修改时间晚于日期 2026-02-30
清除筛选
修改日期不存在，请检查年月日。
```

## 阶段 8：主题、高对比与字号

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：开关、明暗、200% 有原文；全布局矩阵待补
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```文件库  button
文件类型
PDF  button  collapsed
相对目录或文件路径  edit
设置  button
设置  grouping  开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。
明暗主题
跟随系统  button  collapsed
高对比模式
系统要求高对比时也会自动启用。
文件库  button
高对比模式
系统要求高对比时也会自动启用。  check box  not selected  not checked
checked
搜索  button
结果  button
grouping  默认保留系统文字缩放；选择 100% / 150% / 200% 时使用该应用字号，不会再乘一次系统文字比例或屏幕像素比例。
文字大小
跟随系统  button  collapsed
设置  button
grouping  提示 · 开发运行时
重新检查依赖  button
明暗主题
跟随系统  button  collapsed
弹出菜单  grouping
跟随系统  button
浅色  button
明暗主题
浅色  button  collapsed
文件库  button
高对比模式
系统要求高对比时也会自动启用。  check box  not selected  checked
结果  button
设置  button
恢复默认显示设置  button
明暗主题
浅色  button  collapsed
弹出菜单  grouping
浅色  button
深色  button
明暗主题
深色  button  collapsed
文件库  button
高对比模式
系统要求高对比时也会自动启用。  check box  not selected  checked
搜索  button
结果  button
grouping  默认保留系统文字缩放；选择 100% / 150% / 200% 时使用该应用字号，不会再乘一次系统文字比例或屏幕像素比例。
文字大小
跟随系统  button  collapsed
弹出菜单  grouping
跟随系统  button
100%  button
150%  button
200%  button
grouping  默认保留系统文字缩放；选择 100% / 150% / 200% 时使用该应用字号，不会再乘一次系统文字比例或屏幕像素比例。
文字大小
200%  button  collapsed
```

## 阶段 9：确认弹窗与焦点

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：部分验证：按钮/焦点有原文；默认时机、循环/Esc 细节待确认
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```desktop
文件库  grouping  开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。
目录的绝对路径  edit  E:\Project\accessible-multimodal-retrieval\tmp\w05-acceptance-1ca1c8c4\fixtures
文件库  button
搜索  button
选择目录  button
建立 / 增量更新索引  button
grouping  支持 TXT、Markdown、PDF、DOCX、JPG、PNG。增量更新会复用未改变的内容。相同内容共用一份索引文档；源文件不会被修改。
清除全部索引  button
提醒  grouping
保留索引  button
确认清除索引  button
保留索引  button
保留索引  button  focused
确认清除索引  button
grouping  支持 TXT、Markdown、PDF、DOCX、JPG、PNG。增量更新会复用未改变的内容。相同内容共用一份索引文档；源文件不会被修改。
清除全部索引  button
```

## 阶段 10：正常退出、重启与汇总

- 开始/结束时间：
- 实际按键与操作顺序：
- 实际结果及需要分别判断的子项：
- 自动听到的状态 / 主动查询或阅读到的信息：
- 阶段结束时焦点：
- 输入方式：用户确认全程使用键盘；具体按键序列和提示情况未登记。
- 实际计数、来源文件、设置值或恢复结果（按本阶段填写）：
- 审阅判定：用户确认索引及显示设置重启恢复；具体值与精确焦点待补
- 未完成内容、问题编号及补救/复测：
- 证据文件（有则填）：

实际朗读原文：
```
搜索  button
Native input
NVDA实机验收清单.md - accessible-multimodal-retrieval - Visual Studio Code  window
NVDA实机验收清单.md - accessible-multimodal-retrieval - Visual Studio Code  document
application
main landmark
The editor is not accessible at this time. To enable screen reader optimized mode, use Shift+Alt+F1  editor  has auto complete  multi line  blank
Native input
desktop
搜索  button
Microsoft Pinyin
NVDA实机验收清单.md - accessible-multimodal-retrieval - Visual Studio Code  window
NVDA实机验收清单.md - accessible-multimodal-retrieval - Visual Studio Code  document
application
main landmark
The editor is not accessible at this time. To enable screen reader optimized mode, use Shift+Alt+F1  editor  has auto complete  multi line  blank
Weixin  row 1  column 2  2 of 16
Native input
Weixin
NVDA实机验收清单.md - accessible-multimodal-retrieval - Visual Studio Code  window
NVDA实机验收清单.md - accessible-multimodal-retrieval - Visual Studio Code  document
application
main landmark
The editor is not accessible at this time. To enable screen reader optimized mode, use Shift+Alt+F1  editor  has auto complete  multi line  blank
Terminal 4, desktop Run the command: Toggle Screen Reader Accessibility Mode for an optimized screen reader experience Use Alt+F1 for terminal accessibility help  edit  blank
blank
Terminal 4, pwsh Run the command: Toggle Screen Reader Accessibility Mode for an optimized screen reader experience Use Alt+F1 for terminal accessibility help
Terminal 4, desktop Run the command: Toggle Screen Reader Accessibility Mode for an optimized screen reader experience Use Alt+F1 for terminal accessibility help
desktop
Alpha numeric input
文件库  button
```

## 用户补充确认及证据口径

补充归档日期：2026-11-03；实际测试起止时间、OS 版本、受测构建哈希及显示条件仍未登记，不从旧日志或当前二进制反填。

1. 用户原话：“NVDA 版本：2026.2.0.57664，全程使用键盘”。
2. 用户原话：“实测txt会用notepad打开，pdf未能成功打开”。这是初次失败反馈。后续用户明确说明此前是 Acrobat 卡住，现 PDF 能正常打开；TXT/Notepad 和 PDF 打开子项按用户确认记录通过，返回后的精确焦点仍未确认。
3. 对“错误日期修正后是否重新搜索成功”，用户答“可以”：错误恢复子项按用户确认通过。
4. 对“重启后索引和显示设置是否恢复”，用户答“是的”：恢复子项按用户确认通过，具体文档数和设置值尚未登记。
5. 对“正文片段和完整来源路径是否可读”，用户答“可以”：这两项按用户确认通过；不将这句话补造为逐字朗读。

后续确认归档日期：2026-11-03。用户原话：“之前是acrobat卡住了，现在pdf能正常打开了”。问题现象已解除，无应用代码修复；不据此补造按键、查看器焦点或具体处理动作。

原始朗读保持原样。PDF 事件的初次失败和后续恢复见 [E-OPEN-01](../E_问题与复测记录.md#e-open-01pdf-原文件未能打开)。未记录不等于未执行；阶段判定按已有证据范围填写，不直接签收完整无障碍或独立用户试用。

## 本场汇总

| 阶段 | 内容 | 判定 | 证据/问题 |
|---|---|---|---|
| 0 | 准备工具与样本 | 工具已使用；准备过程未单独记录 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 1 | 启动与本场数据 | 首屏原文为空，版本绑定待补 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 2 | 四页导航 | 部分验证：名称/角色有原文，完整顺序及选中状态待确认 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 3 | 选择目录与首次导入 | 部分验证：目录字段及入口可读，原生选择/进度完整性待确认 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 4 | 增量复用 | 部分验证：原文记录写入 0、复用 4、失败 1 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 5 | 搜索与来源阅读 | 部分验证：原文有结果；用户确认正文/完整来源路径可读 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 6 | PDF 筛选、打开与返回 | 部分验证：PDF 筛选可读、TXT/Notepad 打开成功；PDF 已由用户确认恢复，精确返回焦点待补 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 7 | 日期错误与恢复 | 错误提示可读；用户确认修正后搜索成功 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 8 | 主题、高对比与字号 | 部分验证：开关、明暗、200% 有原文；全布局矩阵待补 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 9 | 确认弹窗与焦点 | 部分验证：按钮/焦点有原文；默认时机、循环/Esc 细节待确认 | 原文及用户补充；阶段6另见 E-OPEN-01 |
| 10 | 正常退出、重启与汇总 | 用户确认索引及显示设置重启恢复；具体值与精确焦点待补 | 原文及用户补充；阶段6另见 E-OPEN-01 |

- 纯键盘完成的实际范围：
- 使用了鼠标或辅助操作的阶段：
- 读屏名称/角色/值/状态实际覆盖范围：
- 仍未测、失败或环境受限项：
- 问题登记与复测安排：
- 实际回填验收矩阵的子项：
- 保存确认、结束时间：

未执行协作式取消、TXT/图片系统查看器、真实权限、断网或跨平台等项目时保持未测；
本场不能自动计入独立用户样本。不要仅因本汇总模板存在而修改验收矩阵为通过。
