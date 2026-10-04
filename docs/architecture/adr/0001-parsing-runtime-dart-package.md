# ADR 0001：解析模块以独立纯 Dart 包落地

| 项目 | 内容 |
|---|---|
| 状态 | **Accepted**（已采纳） |
| 日期 | 2026-09-27 |
| 决策者 | Week 2 架构设计 |
| 影响范围 | File I/O Layer、Parsing Layer；后续 W3/W4/W5 的消费方式 |
| 相关文档 | `docs/architecture/system-architecture.md` §4、§5、§14 |

---

## Context（背景）

Week 2 要交付「支持 TXT/PDF/DOCX/JPG/PNG 的文件解析模块」，并达到 **≥80% 单元测试覆盖率**。在动手前必须回答一个会长期影响仓库结构的问题：**这段逻辑住在哪里、用什么语言写？**

当时可用的既有条件：

- `apps/desktop` 是 Flutter 桌面工程（Dart 3.13.4 / Flutter 3.47.5），`flutter test` 通路已在 W1 验证（ENV-04）。
- `engine/` 已有一个 Python 3.13.2 虚拟环境，内含 `chromadb 1.5.9`、`tensorflow 2.21.0`，并被 W3/W4 的 Chroma 计划引用。
- `native/` 已预留 `pdfium/`、`tflite/`、`gtest/` 目录，但**全为空**，没有任何 C++ 构建产物或 CMake 工程。
- `tools/tika-app/` 已有可离线运行的 Apache Tika 4.0.0 发行版（ENV-07 验证过 PDF 抽文本）。
- 本地 pub 缓存已存在 `archive 3.6.1`、`xml 6.6.1`、`image 4.3.0`、`crypto 3.0.7`、`path 1.9.1`、`test 1.31.1`、`coverage 1.15.1`，即**离线 `pub get` 可行**。

约束：C1 完全离线、C2 跨平台、C5 可测性（风险 R4 明确要求"FFI、模型推理、文件对话框用接口包一层，测试打 Mock"）、以及发布包不能拖进一个 Python 运行时（风险 R7 体积）。

## Decision（决策）

**把 File I/O Layer 与 Parsing Layer 实现为一个独立、纯 Dart、无 Flutter 依赖的包：`packages/core_parsing`。**

- 对外只暴露 `lib/core_parsing.dart` 一个 barrel 入口，`lib/src/` 全为实现细节；
- `apps/desktop` 通过 path 依赖消费它（W2 已接入，用于验证分层纪律）；
- 副作用（外部进程）统一收口到 `lib/src/spi/`，解析器只依赖接口；
- 该包**不依赖 Flutter**，用 `dart test` 直接测试。

## Consequences（后果）

**正面**

1. **覆盖率门槛可达且便宜**：`dart test` 不需要 Flutter 引擎绑定，跑得快、失败信息干净，直接对应 W2 的 ≥80% 硬指标。
2. **分层由机制保证，而不是靠自觉**：`packages/` 与 `apps/` 的物理隔离，使"UI 层不得直接读文件"这条规则无法被偷偷绕过。
3. **复用面更大**：W3 的 embedding 引擎与 W4 的检索流水线都以 `ParsedDocument` 为输入，同一个包直接复用，不需要跨进程/跨语言搬运。
4. **发布包干净**：Dart 代码编译进 Flutter 产物，不引入 Python 运行时、不需要 C++ 工具链即可完成 W2 交付。
5. **测试替身有地方放**：`ProcessRunner` / `Executor` / `CancellationToken` 有了天然归属，对应风险 R4 的缓解措施。

**代价 / 需要接受的事**

1. 仓库多一个包，W4 起会变成 `core_embedding` / `core_storage` / `core_retrieval` 多包结构，需要遵守 §5 的单向依赖规则（已写入架构文档，并在 `analysis_options.yaml` 里启用严格分析）。
2. Dart 生态里没有已缓存的 PDF 解析包（见 ADR 0002），PDF 这一条路必须绕道外部进程。
3. 纯 Dart 的性能天花板低于原生，长文档的 CPU 解码在 W6 可能需要 worker isolate（已预留 `Executor`）。

**不变的部分**

`native/` 与 Google Test 并未被取消：它们负责的是 **FFI 边界与原生依赖**（PDFium、TFLite 动态库），属于 W3+ 的实现替换，而不是解析业务逻辑的落点。解析*逻辑*留在 Dart，解析*引擎*可以是原生。

## Alternatives considered（考虑过的其他方案）

| 方案 | 为什么没选 |
|---|---|
| **A. 放进 `engine/`，用 Python 实现解析** | 已有 venv 且能跑 Tika/Chroma，看似最省事；但产品运行时会依赖 Python 解释器与整包依赖，直接撞上风险 R7（体积）与 W8 三平台打包；且 Flutter 侧要么跨进程 IPC、要么嵌解释器，复杂度远超收益。最终只保留 `engine/` 做**离线评测**（见架构文档 Q2）。 |
| **B. 写成 C++ 核心库 + FFI，用 Google Test 测** | 与官方技术栈（PDFium、Google Test）最贴合，但 W2 只有 16h，需要先搭 CMake + Google Test 拉取 + 三平台构建，尚未有任何既有产物（`native/gtest/` 为空）；而且覆盖率会花在 C++ 工具链上而不是解析逻辑上。**推迟到 W3+，只用于 FFI 边界**。 |
| **C. 直接写在 `apps/desktop/lib/`（甚至塞进 widget 层）** | 起步最快，但没有强制边界，测试要拖 Flutter 测试框架，且无法被 W3/W4 的纯 Dart 消费方复用；长期会把 UI 与 I/O 缠在一起。 |
| **D. 用 `freezed` / `json_serializable` 生成值对象** | 会引入 `build_runner` 与代码生成步骤，离线解析与派生文件管理成本上升；W2 值对象数量有限，手写 `==/hashCode/toJson` 更可控，也更容易在评审时逐条对照契约。 |

## Follow-up（后续动作）

- [x] W2 Day 1：创建包骨架、冻结 §6 接口、`dart analyze` 零问题。
- [ ] W2 Day 2–3：填充 5 个解析器与 `IngestionService`。
- [ ] W2 Day 4：`coverage/lcov.info` 证明 ≥80%，证据入 `reports/week2/`。
- [ ] W3：新增 `packages/core_embedding`，消费 `ParsedDocument`；届时复查本条 ADR 的依赖方向是否仍然成立。
