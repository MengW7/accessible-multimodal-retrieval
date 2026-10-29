# 模型精度验证报告

## 1. 四层分别是什么

| 层 | 本周做了什么 | 数字说明 |
|---|---|---|
| 转换等价性 | Day 1 已测，本报告引用原日志 | 同一批输入，fp32 与 `ORT_ENABLE_ALL` 图的余弦。int8 未过 0.999，不加载 |
| embedding 代理 | `engine/eval_nq.py`，300 题 | 问题向量能否把对应答案排到候选前面。测的是答案候选，不是本地文件检索 |
| 检索 | 只建 `evidence_set.jsonl` 并冻结 | 不出 Hit@5、MRR@10。出分在 W4 |
| 生成 | 未做 | PRD 和官方交付清单都没有生成 |

COCO 另记一节。它是图像塔对文本塔的健全性检查，50 张图给不出有统计意义的精度，也不能用来说明系统读得懂 PDF 里的图。

## 2. 三个运行时模型

加载的都是 fp32。权重不进 Git。字段的全文在 `models/README.md`。

| 项 | 文档文本 | 图像塔 | CLIP 文本塔 |
|---|---|---|---|
| 模型 | paraphrase-multilingual-MiniLM-L12-v2 | MobileCLIP-S0 vision | MobileCLIP-S0 text |
| revision | `2c4055b12046f11709e9df2c122e59ffbdc2f900` | `757d59c9c6870a76a4b0306f05f5061bca15c39f` | 同上 |
| 文件 | `onnx/model.onnx` | `onnx/vision_model.onnx` | `onnx/text_model.onnx` |
| 字节 | 470268510 | 45543630 | 169807789 |
| 空间 / 维度 | `documentText` / 384 | `clipShared` / 512 | `clipShared` / 512 |
| pooling | mean，按 attention mask | none，`image_embeds` | none，`text_embeds` |
| 交出前 L2 | 是 | 是 | 是 |
| query / document 前缀 | 无 | 无 | 无。起止标记由分词器加 |
| 最大长度 | 128 token，含特殊标记，超长不截断 | 256×256，短边、双线性、中心裁剪、除以 255，无 mean/std | 77 token，不足用 `!` 补齐，超长不截断 |
| 运行时 | onnxruntime 1.30.0，图优化关闭 | 同上 | 同上。输入只有 `input_ids` |

Day 1 安静前向（warmup 一次后 3 次平均，不含加载模型）见 `reports/week3/logs/embed_spike.txt`：中文 25.44 ms，英文 26.69 ms，`000000397133.jpg` 35.26 ms。

本周批量前向是模型已经留在同一个进程里之后的单条耗时，不含加载。两份脚本先后单独运行。日志是 `nq_eval.txt` 和 `coco_eval.txt`。

| 运行 | 加载 | 单条中位 | 单条最大 | 计时里有什么 |
|---|---:|---:|---:|---|
| NQ，600 条文本 | 626.36 ms | 40.65 ms | 124.05 ms | 只计 MiniLM 前向 |
| COCO，50 张图 | 439.78 ms（两个模型一起） | 103.35 ms | 155.20 ms | Pillow 预处理加图像前向 |
| COCO，50 条 caption | 同上 | 39.63 ms | 73.89 ms | 只计文本塔前向 |

MVP 探针是另一条路径：每个向量单独起一次 Python，耗时含进程启动和模型加载。样本目录每条中位 2016 ms，COCO 图片每条中位 1504.5 ms。那不是上表的前向时间。见 `W03_report.md`。

## 3. 转换等价性

`reports/week3/logs/convert_check.txt`。门槛 0.999。采用 fp32。

| 模型 | `ORT_ENABLE_ALL` 最低余弦 | int8 最低余弦 | 装进运行时的文件 |
|---|---:|---:|---|
| MiniLM | 1.000000 | 0.982951 | fp32 |
| 图像塔 | 1.000000 | 0.045810 | fp32 |
| CLIP 文本塔 | 1.000000 | 0.768964 | fp32 |

`*_ort.onnx` 只是本机对照，不外带。int8 三份都不用。

![转换等价性](screenshots/A3-convert-check.png)

## 4. NQ-open 代理指标

数据是 `nq_open_val50.jsonl` 50 行加 `nq_open_val250_part2.jsonl` 250 行，共 300 题。查询按这个文件顺序。候选池 600 条：每题的第一个 gold answer，再加 300 个 question 作干扰。

排序时去掉该题自己的 question 行。那一行就是查询本身，余弦是 1，留着会把 recall@1 固定成 0。其余 299 个 question 仍是干扰。每题实际在 599 条里排序。相关项只有一条，就是配对该题的那个 answer 行，所以这里的 recall@K 等于 Hit@K。同分时余弦高的在前，再按候选下标小的在前。

分词用 tokenizers 0.23.2，关闭截断，再按 Dart 的方式补到 128。mean pooling 用 attention mask，然后 L2。超长会中止脚本，这次 600 条都没有超长。

| 指标 | 值 |
|---|---|
| recall@1 | 33/300 = 0.110000 |
| recall@5 | 63/300 = 0.210000 |
| MRR | 0.166034 |
| 排名最小 / 中位 / 最大 | 1 / 47 / 526 |
| 随机 recall@1 / recall@5 | 0.001669 / 0.008347 |

随机基线按 599 条里碰对 1 条或 5 条来算。0.110 和 0.210 高于这个基线。它只说明向量没有坏到随机。它不说明系统能从本地文档里找到证据。第一题 “when was the last time anyone was on the moon” 的 gold answer 排在第 11，不在前 5。

日志：`reports/week3/logs/nq_eval.txt`。

![NQ 代理评测](screenshots/EMB-06-nq-eval.png)

## 5. COCO 图像到 caption

50 行 `captions.jsonl` 与 50 张 jpg 按 `file_name` 配对。图像走视觉塔，caption 走 CLIP 文本塔，都在 `clipShared`。没有用 MiniLM 去编码 caption。文本塔文件存在，这一项的状态是完成。

| 指标 | 值 |
|---|---|
| image→caption recall@1 | 46/50 = 0.920000 |
| image→caption recall@5 | 50/50 = 1.000000 |
| 平均排名 | 1.14 |
| 排名最小 / 中位 / 最大 | 1 / 1 / 4 |
| 随机 recall@1 / recall@5 | 0.020000 / 0.100000 |

`000000397133.jpg` 的配对 caption 排第 1。

image→image 另记，不计入上面的完成数字：自身余弦最小 0.999999、最大 1.000000；去掉自身后，最近邻余弦中位 0.510716、最大 0.826031。RVL-CDIP 的 16 张无标题图没有进这次运行。

日志：`reports/week3/logs/coco_eval.txt`。

![COCO 图像到 caption](screenshots/EMB-07-coco-eval.png)

## 6. 自建证据集

25 条，dev 15，holdout 10。冻结时间 2026-10-16T13:12:33Z，sha256 `82c080c0c91e29551d7e3ee4a67f4ae3e421d424a2b2fb5a5d8079b23e4eb9d6`。本周没有对它计算检索分数。说明见 `reports/week3/证据集说明.md`。

## 7. 已知限制

- 官方任务书写的是 TFLite。本机没有 `libtensorflowlite_c-win.dll`，int8 又未过余弦门槛，所以运行时仍是 ADR 0003 里的 ONNX Runtime 外部进程，加载 fp32。
- MobileCLIP 权重是研究用途，不能放进公开安装包。
- NQ 子集只有问答对。代理指标抓得到模型或 pooling 坏了，抓不到「一句话能否搜到本地文件」。
- COCO 只有 50 对。分数高只说明这两只塔在这 50 张上对得上 caption。
- 证据集里 PDF 两页是同一篇说明的重复排版。跨页题记的是两页都有同一句，不是半句续到下一页。通过标准在 W4。
- 生成式回答不在本周范围。
