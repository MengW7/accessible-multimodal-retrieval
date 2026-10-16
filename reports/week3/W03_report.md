# W03 报告

---

## 1. 测试范围与环境

本周阶段 D 核对的是向量探针、NQ 代理评测、COCO 图像到 caption、证据集冻结，以及 `packages/core_embedding` 的默认单测和行覆盖率。带 `integration` 标签的 Dart 测试这次没有重跑。真模型的本次证据是探针和两份 Python 评测。

操作系统沿用本机已记录的 Windows 11 25H2。本次命令打出来的版本：

- Dart 3.13.4（stable）
- Flutter 3.47.5，`D:\flutter`
- Java 17.0.4，PDF 探针会用到
- `engine/.venv`：Python 3.13.2，onnxruntime 1.30.0，tokenizers 0.23.2，pillow 12.3.0，numpy 2.5.3（库版本见 `logs/embed_spike.txt`）

没有另做终端截屏。判定以本节命令写进 `reports/week3/logs/` 的文本为准。

---

## 2. 用例表

命令在仓库根目录执行，除非注明工作目录。

| 用例 ID | 命令 | 期望 | 实际 | 判定 | 证据 |
|---|---|---|---|---|---|
| EMB-01 | `packages\core_embedding` 下 `dart analyze` | 0 issue | `No issues found!` | 通过 | `logs/dart_analyze.txt` |
| EMB-02 | 同目录 `dart test --exclude-tags integration` | 默认套件全绿，不加载模型 | `00:01 +93: All tests passed!` | 通过 | `logs/dart_test.txt` |
| EMB-03 | 同目录覆盖率两条命令，`--report-on=lib` | 行覆盖率 ≥ 85.00% | 1250/1458 = 85.73%。带覆盖率的那次结束行是 `00:11 +93: All tests passed!` | 通过 | `logs/coverage.txt`；`coverage/lcov.info`；`覆盖率报告.md` |
| EMB-04 | `dart run packages\core_embedding\bin\embed_probe.dart --path datasets\samples` | 扫描、解析、切块、出向量；打印结果、维度、耗时和前 3 维 | 入库 3 条全 ok，7817 ms。向量 97 条全 ok，0 失败，201993 ms。文档文本 96 条、384 维；`sample.png` 1 条、512 维、`clipShared`。DOCX 22 条页码为空，PDF 第 1 页 37 条、第 2 页 37 条 | 通过 | `logs/embed_probe_samples.txt` |
| EMB-05 | `dart run packages\core_embedding\bin\embed_probe.dart --path datasets\coco\val_sample\images` | 50 张图各出一条图像向量 | 入库 50 条全 ok，1873 ms。向量 50 条全 ok，78466 ms，维度都是 512，空间都是 `clipShared` | 通过 | `logs/embed_probe_coco.txt` |
| EMB-06 | `engine\.venv\Scripts\python.exe engine\eval_nq.py` | 300 题打出 recall@1、recall@5、MRR，并标明是代理指标 | recall@1 = 0.110000（33/300），recall@5 = 0.210000（63/300），MRR = 0.166034。日志首行是 `metric_layer=embedding_proxy` | 通过 | `logs/nq_eval.txt`；`模型精度验证报告.md` 第 4 节 |
| EMB-07 | `engine\.venv\Scripts\python.exe engine\eval_coco.py` | 有文本塔则报 image→caption recall@1、recall@5 | 文本塔 fp32 存在。recall@1 = 0.920000（46/50），recall@5 = 1.000000（50/50），平均排名 1.14。`function_status=complete` | 通过 | `logs/coco_eval.txt`；`模型精度验证报告.md` 第 5 节 |
| EMB-08 | 证据集文件与说明 | ≥ 20 条，dev/holdout 分开，写下冻结时间，含跨页题，本周不算检索分 | 25 条，dev 15，holdout 10。冻结于 2026-10-16T13:12:33Z。`ev-08`、`ev-16`、`ev-17` 为跨页。`scored=0` | 通过 | `evidence_set.jsonl`；`证据集说明.md`；`logs/evidence_freeze.txt` |
| EMB-09 | `apps\desktop` 下 `flutter pub get --offline` | 桌面端仍能解析对 `core_embedding` 的 path 依赖 | 退出码 0。lock 新增传递依赖 `unorm_dart` 0.2.0 | 通过 | `logs/flutter_pub_get.txt` |

两份评测脚本先后单独运行，互不并行。探针每条的 `ms` 含进程启动和模型加载。样本目录 97 条的单条耗时最小 1447 ms、中位 2016 ms、最大 2734 ms。COCO 50 条最小 1326 ms、中位 1504.5 ms、最大 1816 ms。

`logs/embed_probe.txt` 是 EMB-04 和 EMB-05 两份输出接在一起，每段有一行 `# run=`。

---

## 3. 交付物

| 编号 | 文件 | 状态 |
|---|---|---|
| G1 / G5 | `packages/core_embedding/bin/embed_probe.dart` | EMB-04、EMB-05 已跑通 |
| G2 | `reports/week3/模型精度验证报告.md` | 四层分开 |
| G3 | `reports/week3/coverage/lcov.info`、`覆盖率报告.md` | 85.73% |
| G4 | `docs/api/embedding-module-api.md` | 公开符号仍是第 7 节那一份。探针是命令，不是库符号 |
| G6 | `evidence_set.jsonl`、`证据集说明.md` | 已冻结，未评分 |
| G7 | ADR 0003 阶段 D 后续项 | 已勾上。Q1、Q3、Q7 仍是 2026-10-15 的结案；TDD 补了证据集路径 |
| G8 | 本报告和 `logs/` | 上表 |

---

## 4. 范围

本阶段没有写向量库，没有做相似度排序，没有改桌面 UI，没有做 OCR，也没有做生成。PDF 仍走 Tika。`chunkChars` 仍是 120，模型仍是 ADR 0003 的三份 fp32。证据集冻结之后没有按分数改这些参数。
