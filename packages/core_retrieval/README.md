# core_retrieval

离线检索层。三路分别召回：文档文本向量、关键词、图像共享空间。合榜用 RRF，`k=60`，权重是文本 0.5、关键词 0.3、图像 0.49。图像权重开工时是 0.2。

过滤条件是本包的 `SearchFilters`，查询前转成存储层的 `StorageFilter`。邻域扩展发生在排序之后，只拼同页 `chunkIndex ± 1`，不改分数，也不跨页。

`pageNumber == null` 的结果保持 null，不能当成真实页码。本包不读文件，也不调用嵌入运行时以外的 `EmbeddingEngine`。

默认测试不打开数据库、不加载模型：

```powershell
dart test --exclude-tags integration
```
