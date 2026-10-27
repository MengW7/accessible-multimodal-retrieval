# core_storage

本地向量和关键词索引。产品运行时用系统 SQLite（`package:sqlite3` 2.x，Windows 上回退到 `winsqlite3.dll`）。Chroma 只在 `engine/` 里做对照，不是这个包的依赖。

公开入口是 `package:core_storage/core_storage.dart`。`lib/src/` 不是稳定 API。

两个空间分开查。查询向量的 `space` 或维度和库里不一致时抛异常。向量按 fp32 小端 BLOB 存放，调用方必须已经做完 L2，余弦就是点积。

关键词通道不使用 FTS5 的默认分词。连续中文在写入时切成 bigram。查询有中文 bigram 时走词表覆盖率，并把长度不少于 3 的拉丁串和离线英文词再各查一次 FTS5 `trigram`，同一块保留较高分。整句中文不送进 trigram。没有 bigram、且不少于 3 个字符的查询整句走 trigram。更短的查询走带 `LIMIT` 的 `LIKE`。

`chunkId` 只回指切块结果。一个文档能不能跳过重嵌，看 `IndexGeneration.sameRecipe` 的 6 个字段是否和库里的代次行一致：`contentHash`、`parserName`、`parserVersion`、`chunkerVersion`、`modelId`、`vectorDim`。ADR 0004 决策 4 把解析器名和版本合成一项，连同其余四项称作五项。`documentId` 只用来找行。

动态库从 `SqliteLibraryLocator` 来。单测可以注入一个直接返回失败的定位器，不需要把系统路径写死。

```text
dart test --exclude-tags integration
```

API 说明随本周实现补在 `docs/api/storage-module-api.md`。决策见 ADR 0004。
