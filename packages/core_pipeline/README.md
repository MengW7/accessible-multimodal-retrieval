# core_pipeline

建库和查询的编排。桌面端只装配这个包，不直接调用解析、嵌入或存储。

建库按五项代次判断能否跳过。一项不符就整份文件重写。新向量全部算完才写入，写入本身在存储层的一个事务里替换旧行。坏文件记入失败数，不打断后面的文件。取消停在下一份文件之前，已经提交的写入保留。

查询只转给 `Retriever`。

常驻嵌入进程走长度前缀的 JSON 帧。文本模型要回 `last_hidden_state`，pooling 仍在 `TextEmbedder`。默认测试用假进程，不加载 ONNX。

```powershell
dart test --exclude-tags integration
```

`sqlite3` 仍由 `core_storage` 固定在 2.9，因为 3.x 需要本机编译工具链。
