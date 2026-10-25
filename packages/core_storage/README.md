# core_storage

本地向量和关键词索引。产品运行时用系统 SQLite（`package:sqlite3` 2.x，Windows 上回退到 `winsqlite3.dll`）。Chroma 只在 `engine/` 里做对照，不是这个包的依赖。

公开入口是 `package:core_storage/core_storage.dart`。`lib/src/` 不是稳定 API。

两个空间分开查。查询向量的 `space` 或维度和库里不一致时抛异常。向量按 fp32 小端 BLOB 存放，调用方必须已经做完 L2，余弦就是点积。

关键词通道不使用 FTS5 的默认分词。连续中文在写入时切成 bigram。英文和不少于 3 个字符、且没有中文 bigram 的查询走 FTS5 `trigram`。更短的查询走带 `LIMIT` 的 `LIKE`。

`chunkId` 只回指切块结果。一个文档能不能跳过重嵌，看 `IndexGeneration` 的五项是否和库里的代次行一致。

动态库从 `SqliteLibraryLocator` 来。单测可以注入一个直接返回失败的定位器，不需要把系统路径写死。

```text
dart test --exclude-tags integration
```

API 说明随本周实现补在 `docs/api/storage-module-api.md`。决策见 ADR 0004。
