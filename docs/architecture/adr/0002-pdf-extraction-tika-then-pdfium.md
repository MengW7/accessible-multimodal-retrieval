# ADR 0002：PDF 文本抽取先用 Apache Tika CLI，PDFium FFI 后续替换

| 项目 | 内容 |
|---|---|
| 状态 | **Accepted**（已采纳，带明确的迁移触发条件） |
| 日期 | 2026-09-27 |
| 决策者 | Week 2 架构设计 |
| 影响范围 | Parsing Layer 的 PDF 分支；W6 性能预算；W8 打包 |
| 相关文档 | `docs/architecture/system-architecture.md` §6、§9、§10 |

---

## Context（背景）

PRD 的 P0 要求是「PDF 抽文本层并记下页码」，官方技术栈同时列了 **PDFium** 与 **Apache Tika**。必须决定 W2 用哪条路先把 PDF 跑通，以及什么时候换成 PDFium。

实测到的事实：

| 事实 | 证据 |
|---|---|
| Apache Tika 4.0.0 已在本仓库、可完全离线运行 | `tools/tika-app/tika-app-4.0.0.jar` + `lib/`；W1 报告 ENV-07 用同一命令抽出 `sample.pdf` 正文，退出码 0 |
| Tika 的 XHTML 输出保留分页，可满足"记下页码" | 本机实测 `TikaCLI -x datasets/samples/sample.pdf` 输出含 **2 个** `<div class="page">`，与 `sample.pdf` 的 2 页一致 |
| Tika 会把 INFO 日志写到 **stderr** | ENV-07 与本机实测均观察到 `INFO [main] ... org.apache.tika.cli.TikaCLI` 噪声 |
| 运行 Tika 需要 JDK | 本机 `java 17.0.4`，`JAVA_HOME=C:\Program Files\Java\jdk-17.0.4` |
| 本地 pub 缓存**没有**任何 PDF 解析包 | 缓存中不存在 `pdfrx` / `pdfium_dart` / `syncfusion_*`（已逐一核对） |
| `native/pdfium/` 是空占位 | 只有 `windows/`、`include/`、`tests/` 三个空目录 + README，没有 `pdfium.dll`，也没有构建脚本 |
| 本机网络可用性不稳定 | 对 `pub.dev` DNS/TCP 可通，但 HTTPS 请求在当前 Shell 下反复握手失败 → 不能把"新增未缓存依赖"当作计划前提 |

风险 R2（PDF/DOCX 难以对接 Flutter 桌面，等级：高）给出的缓解方向是：**先保证能跑通，解析失败的文件跳过并记原因**。

## Decision（决策）

**W2 的 PDF 文本抽取走 `TikaCliTextExtractor`：以子进程方式调用仓库内已有的 Tika 发行版，用 `-x`（XHTML）提取并按 `<div class="page">` 切页，`-t` 作为回退。PDFium 作为 W3+ 的替换实现，接口不变。**

约束条件（同时写进架构文档 §6.3 契约）：

1. 抽取逻辑藏在 `TextExtractor` 接口后面，`PdfParser` 只依赖接口，**不认识 Tika**；
2. 子进程调用统一经 `ProcessRunner`（全包唯一允许 spawn 的位置），因此单测可注入假实现，覆盖率不依赖真 JVM；
3. 命令行 classpath 分隔符按平台分支（Windows `;`，macOS/Linux `:`）；
4. **stdout 才是正文，stderr 只作诊断**；
5. `java` 不存在时抛 `ProcessStartException` → 映射为 `ParseFailure(kind: dependencyUnavailable)`，该文件计 `failed` 并单列在报告里，**绝不崩溃整批**；
6. 外部进程必须带超时，超时 → `ParseFailureKind.timeout`。

**迁移触发条件**（满足任意一条即启动 PDFium 替换，且必须新写一份 ADR）：

- T1：`native/pdfium/windows/pdfium.dll` 能拿到可信来源的预编译产物，且 `dart:ffi` 绑定在 Windows 上抽文本正确；
- T2：W6 实测中，JVM 启动成为 PDF 解析耗时的主导项（例如单文件 > 2 s 且批量占比显著）；
- T3：W8 三平台打包发现"随包分发 JRE"不可接受（体积/许可证/签名任一受限）。

## Consequences（后果）

**正面**

1. **零新增依赖、零网络风险**：Tika 与 JDK 已在 W1 验证可用，W2 不必赌 pub 包能不能拉下来（对应风险 R7）。
2. **不偏离官方技术栈**：Tika 本来就在官方技术栈清单里，这是"用哪一个先"的顺序问题，不是取舍。
3. **页码需求当场满足**：`-x` 的 `<div class="page">` 已实测可分页，PRD 的 P0 条款不需要额外工作。
4. **可测性没有被牺牲**：因为走 `ProcessRunner`，PDF 分支的单元测试不需要 JVM，覆盖率门槛不受影响。
5. **换来一次干净的架构演示**：W3 换成 PDFium 时只改 `lib/src/parsing/adapters/` 下的一个文件，正好验证 §4.1「新增/替换实现要改几个文件」的设计承诺。

**代价 / 需要接受的事**

1. **开发期引入 JVM 依赖**：PDF 解析需要 `java` 在 `PATH` 上。此约束必须写进 README 与用户手册的"运行前置条件"，并在缺失时优雅降级。
2. **每文件一次进程启动**：原先估计单文件 1–2.5 s，且预计由 JVM 启动主导。实测总时间高于这个估计：Day 3 为 4857 ms，Day 4 为 5215 ms。2026-10-10 三次分段（`reports/week3/logs/pdf_stage_timing.txt`）的 `total_ms` 中位是 5101，其中 `process_wait` 中位 5050。`process_wait` 含 JVM 启动、扫描 classpath 和 Tika 抽取，三者还没有分开。W2 按「每个 PDF 一次进程」实现。常驻 JVM 或 PDFium 仍留作后续优化选项。
3. **发布包问题被推迟而不是解决**：如果最终仍靠 Tika，W8 需要决定 JRE 的处理方式。因此设置了触发条件 T3，不允许它无声地拖到打包日。
4. **能力边界**：Tika 抽不出文本层的扫描件只能得到空文本 + 元数据（`outcome: partial`），OCR 不在 W2 范围（TDD 的 Q4）。

## Alternatives considered（考虑过的其他方案）

| 方案 | 为什么没选（当前） |
|---|---|
| **A. 立刻用 PDFium 预编译 DLL + `dart:ffi`** | 与官方技术栈最贴合，但要先解决 DLL 来源可信性、头文件、`ffi`/`ffigen` 绑定与三平台产物；`native/pdfium/` 目前是空目录，W2 的 16h 不足以同时做完"五格式解析 + ≥80% 覆盖率"和"原生集成"。**保留为 T1 触发后的目标实现。** |
| **B. 引入 `pdfrx` / `pdfium_dart` 等 pub 包** | 底层同样是 PDFium，集成成本最低；但这些包**不在本地 pub 缓存里**，需要联网解析（本机 HTTPS 不稳定），且 Flutter 插件在纯 `dart test` 下不可跑，会把 PDF 分支的覆盖率推向"只能靠集成测试"。 |
| **C. 自己实现 PDF 解析（解析 xref / 解压 FlateDecode / 抽 Tj 文本）** | 工作量与正确性风险都不可接受（字体编码、CJK、加密 PDF 等），且与"用成熟开源组件"的工程原则相悖。 |
| **D. W2 直接放弃 PDF，只做 TXT/DOCX/图片** | 违反 PDF 原文 Week 2 的明确要求（support for TXT, PDF, DOCX, JPG, PNG）与 PRD 的 P0；且会让 W3/W4 的检索基准缺少最主要的一类真实文件。 |
| **E. 用常驻 Tika server（HTTP 本机端口）代替每文件一次 CLI** | 省掉重复 JVM 启动，但增加一个本机监听端口，与"完全离线、无外传"的 C1 表述容易被误读为网络通信；也提高了生命周期管理复杂度。**作为 W6 的备选优化，需先实测收益再决定。** |

## Follow-up（后续动作）

- [x] W2 Day 1：在架构文档中冻结 `TextExtractor` / `ProcessRunner` 契约与降级策略。
- [x] W2 Day 2：实现 `TikaCliTextExtractor`（含平台 classpath 分支、stderr 分离、超时、缺 Java 分支），并用假 `ProcessRunner` 覆盖全部分支。
- [x] W2 Day 3：跑通 `datasets/samples/sample.pdf`（期望 2 页），单文件耗时记入 `reports/week2/logs/day3_jvm_single_file.txt`。
- [ ] W3：评估触发条件 T1/T2；若满足，新增 ADR 并实现 `PdfiumTextExtractor`。2026-10-10 已做评估，两条都未满足，所以这里不换实现。T1：`native/pdfium/windows/` 里没有 `pdfium.dll`。T2：单文件总时间高于 2 s，`process_wait` 约占 99%，但这一段还没有拆出 JVM 启动本身，也没有新的批量占比。
- [ ] W8：若届时仍依赖 Tika，必须先解决 JRE 分发问题（触发条件 T3）。
