# W03 报告

---

## 1. 测试范围与环境

本文核对的是向量探针、NQ 代理评测、COCO 图像到 caption，以及 `packages/core_embedding` 的默认单测和行覆盖率。

系统环境：

- Dart 3.13.4（stable）
- Flutter 3.47.5，`D:\flutter`
- Java 17.0.4
- Python 3.13.2，onnxruntime 1.30.0，tokenizers 0.23.2，pillow 12.3.0，numpy 2.5.3


---

## 2. 用例表

| 用例 ID | 命令 | 期望 | 实际 | 判定 | 证据 |
|---|---|---|---|---|---|
| EMB-01 | `packages\core_embedding` 下 `dart analyze` | 0 issue | `No issues found!` | 通过 | `logs/dart_analyze.txt`；`screenshots/EMB-01-dart-analyze.png` |
| EMB-02 | 同目录 `dart test --exclude-tags integration` | 默认套件全绿，不加载模型 | `00:03 +93: All tests passed!` | 通过 | `logs/dart_test.txt`；`screenshots/EMB-02-dart-test.png` |
| EMB-03 | 同目录覆盖率两条命令，`--report-on=lib` | 行覆盖率 ≥ 85.00% | 1250/1458 = 85.73%。带覆盖率的那次结束行是 `00:15 +93: All tests passed!` | 通过 | `logs/coverage.txt`；`coverage/lcov.info`；`覆盖率报告.md`；`screenshots/EMB-03-coverage.png` |
| EMB-04 | `dart run packages\core_embedding\bin\embed_probe.dart --path datasets\samples` | 扫描、解析、切块、出向量；打印结果、维度、耗时和前 3 维 | 入库 3 条全 ok，7690 ms。向量 97 条全 ok，0 失败，212987 ms。文档文本 96 条、384 维；`sample.png` 1 条、512 维、`clipShared`。DOCX 22 条页码为空，PDF 第 1 页 37 条、第 2 页 37 条 | 通过 | `logs/embed_probe_samples.txt`；`screenshots/EMB-04-embed-probe-samples.png` |
| EMB-05 | `dart run packages\core_embedding\bin\embed_probe.dart --path datasets\coco\val_sample\images` | 50 张图各出一条图像向量 | 入库 50 条全 ok，1848 ms。向量 50 条全 ok，78466 ms，维度都是 512，空间都是 `clipShared` | 通过 | `logs/embed_probe_coco.txt`；`screenshots/EMB-05-embed-probe-coco.png` |
| EMB-06 | `engine\.venv\Scripts\python.exe engine\eval_nq.py` | 300 题打出 recall@1、recall@5、MRR，并标明是代理指标 | recall@1 = 0.110000（33/300），recall@5 = 0.210000（63/300），MRR = 0.166034。日志首行是 `metric_layer=embedding_proxy` | 通过 | `logs/nq_eval.txt`；`模型精度验证报告.md` 第 4 节；`screenshots/EMB-06-nq-eval.png` |
| EMB-07 | `engine\.venv\Scripts\python.exe engine\eval_coco.py` | 有文本塔则报 image→caption recall@1、recall@5 | 文本塔 fp32 存在。recall@1 = 0.920000（46/50），recall@5 = 1.000000（50/50），平均排名 1.14。`function_status=complete` | 通过 | `logs/coco_eval.txt`；`模型精度验证报告.md` 第 5 节；`screenshots/EMB-07-coco-eval.png` |
| EMB-08 | 证据集文件与说明 | ≥ 20 条，dev/holdout 分开，写下冻结时间，含跨页题，本周不算检索分 | 25 条，dev 15，holdout 10。冻结于 2026-10-16T13:12:33Z。`ev-08`、`ev-16`、`ev-17` 为跨页。`scored=0` | 通过 | `evidence_set.jsonl`；`证据集说明.md`；`logs/evidence_freeze.txt` |
| EMB-09 | `apps\desktop` 下 `flutter pub get --offline` | 桌面端仍能解析对 `core_embedding` 的 path 依赖 | 退出码 0。lock 新增传递依赖 `unorm_dart` 0.2.0 | 通过 | `logs/flutter_pub_get.txt` |
| INT-01 | `packages\core_embedding` 下 `dart test --tags integration` | 真模型套件全绿（加载 tokenizer.json、fp32 ONNX、数据集图片） | `00:15 +7: All tests passed!` | 通过 | `screenshots/INT-01-dart-test-integration.png` |
| A3-01 | `engine\.venv\Scripts\python.exe engine\embed_spike.py` | 一句中文、一句英文、一张 COCO 图各出一次向量 | 中文 384 维 52.86 ms、英文 384 维 55.54 ms、COCO 图 512 维 60.10 ms，`finite=1`，中文 `unk_tokens=0` | 通过 | `logs/embed_spike.txt`；`screenshots/A3-embed-spike.png` |
| A3-02 | `engine\.venv\Scripts\python.exe engine\convert_check.py` | 转换前后余弦 ≥ 0.999 | 三份 fp32 → `ORT_ENABLE_ALL` 最低余弦 1.000000；三份 int8 为 0.982951 / 0.045810 / 0.768964，均不采用 | 通过 | `logs/convert_check.txt`；`ADR 0003` 决策 5；`screenshots/A3-convert-check.png` |


---

## 3. 交付物

| 编号 | 文件 | 状态 |
|---|---|---|
| G1 / G5 | `packages/core_embedding/bin/embed_probe.dart` | 已完成。EMB-04 出向量 97 条、EMB-05 出向量 50 条，失败 0 |
| G2 | `reports/week3/模型精度验证报告.md` | 已完成。7 节，四层指标分列 |
| G3 | `reports/week3/coverage/lcov.info`、`覆盖率报告.md` | 已完成。1250/1458 = 85.73%，门槛 85.00% |
| G4 | `docs/api/embedding-module-api.md` | 已完成。53 个 public 符号小节 |
| G6 | `evidence_set.jsonl`、`证据集说明.md` | 已完成。25 条，dev 15 / holdout 10，`scored=0` |
| G7 | ADR 0003、TDD Q1/Q3/Q7 | 已完成。三条均标记已结案 |
| G8 | 本报告、`logs/`、`screenshots/` | 已完成。12 条用例 |

---

## 4. 证据索引

| 路径 | 对应内容 |
|---|---|
| `reports/week3/logs/dart_analyze.txt` | EMB-01 |
| `reports/week3/logs/dart_test.txt` | EMB-02 |
| `reports/week3/logs/dart_test_coverage_run.txt` | EMB-03 带 `--coverage` 的那次套件输出 |
| `reports/week3/logs/coverage.txt` | EMB-03 命令、行命中与分文件数字 |
| `reports/week3/logs/embed_probe_samples.txt` | EMB-04 |
| `reports/week3/logs/embed_probe_coco.txt` | EMB-05 |
| `reports/week3/logs/embed_probe.txt` | EMB-04 与 EMB-05 接在一起的副本，每段有 `# run=` |
| `reports/week3/logs/nq_eval.txt` | EMB-06 |
| `reports/week3/logs/coco_eval.txt` | EMB-07 |
| `reports/week3/logs/evidence_freeze.txt` | EMB-08 冻结记录 |
| `reports/week3/logs/flutter_pub_get.txt` | EMB-09 |
| `reports/week3/logs/embed_spike.txt` | A3-01 |
| `reports/week3/logs/convert_check.txt` | A3-02 |
| `reports/week3/logs/text_coverage_b.txt` | 阶段 B 的覆盖率（494/719 = 68.71%） |
| `reports/week3/logs/text_coverage_c.txt` | 阶段 C 与 D 的覆盖率（1250/1458 = 85.73%） |
| `reports/week3/logs/chunk_chars_calibration.txt` | `chunkChars=120` 在 `datasets/samples` 上的标定 |
| `reports/week3/logs/image_preprocess_pillow.txt` | 纯 Dart 双线性缩放对 Pillow 参考的对照 |
| `reports/week3/coverage/lcov.info` | G3 交付物 |
| `reports/week3/evidence_set.jsonl` | G6 自建证据集 |
| `reports/week3/screenshots/*.png` | 第 2 节各条命令的终端截屏 |
| `docs/api/embedding-module-api.md` | G4 |
| `docs/architecture/adr/0003-embedding-model-and-runtime.md` | G7 |


---

## 5. 截屏

按第 2 节的用例 ID 排列。

![EMB-01 dart analyze](screenshots/EMB-01-dart-analyze.png)

![EMB-02 dart test](screenshots/EMB-02-dart-test.png)

![EMB-03 覆盖率](screenshots/EMB-03-coverage.png)

![EMB-04 samples 探针](screenshots/EMB-04-embed-probe-samples.png)

![EMB-05 coco 探针](screenshots/EMB-05-embed-probe-coco.png)

![EMB-06 NQ 评测](screenshots/EMB-06-nq-eval.png)

![EMB-07 COCO 评测](screenshots/EMB-07-coco-eval.png)

![INT-01 integration 套件](screenshots/INT-01-dart-test-integration.png)

![A3-01 可行性探针](screenshots/A3-embed-spike.png)

![A3-02 转换等价性](screenshots/A3-convert-check.png)

