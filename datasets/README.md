## 1.基准数据集来源

- **Natural Questions (NQ)**：用于开放域问答与文本检索评测。
  - 官方地址：https://ai.google.com/research/NaturalQuestions
- **MS COCO**：用于多模态跨模态图像-文本检索与特征评测。
  - 官方地址：https://cocodataset.org/#download
- **RVL-CDIP**：用于文档级扫描件分类与复杂版面/PDF 检索评测。
  - 官方地址：https://www.cs.cmu.edu/~aharley/rvl-cdip/
- **Wikipedia Dumps**：用于大规模知识库稠密/稀疏向量检索构建语料。
  - 官方地址：https://dumps.wikimedia.org/

## 2.样本和数据集验证集
本目录只存放验证子集，用于后续 embedding / retrieval 评测，不包含官方全集。

## Samples 
| File | Format | Used by |
|---|---|---|
| samples/sample.pdf | PDF | Tika + PDFium smoke test |
| samples/sample.docx | DOCX | Tika |
| samples/sample.png | PNG | image pipeline placeholder |

## Validation subsets 
| Path | Source | License | Sampling rule | Count |
|---|---|---|---|---|
| nq/validation | Natural Questions | 见官网 | validation 随机抽样 | 300 |
| coco/val_sample | COCO val2017 | CC | 前 N 张 + captions | 50 |
| rvlcdip/sample | RVL-CDIP | 见官网 | 每类 1–2 张 | 32 |
| wiki/ | Wikimedia dump | GFDL/CC | Week 6 | 0 |