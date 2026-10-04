# core_parsing

无障碍多模态检索项目的第 2 周交付物 **D2**：六层架构中的**文件 I/O 层（File I/O Layer）**与**解析层（Parsing Layer）**。

刻意采用纯 Dart 实现（不依赖任何 Flutter 框架）：

- 该层级可以直接通过 `dart test` 进行测试，这是达成第 2 周要求的 ≥80% 单元测试覆盖率的最快途径；
- 强制落实架构文档中“UI 层绝不直接读取文件”的设计规范；
- 同一个包后续还会被嵌入引擎（Embedding Engine，第 3 周）和检索流水线（Retrieval Pipeline，第 4 周）共用复用。

## 目录结构

```text
lib/core_parsing.dart              公共导出文件（外部引用的唯一入口）
lib/src/model/                     跨层交互使用的不可变值对象（Value Objects）
lib/src/spi/                       依赖注入切入点（进程、执行器、任务取消）
lib/src/parsing/                   解析器契约（接口规范）与注册中心
lib/src/parsing/parsers/           每种受支持的格式对应一个实现文件
lib/src/parsing/adapters/          调用外部进程提取文本的适配器
lib/src/io/                        文件扫描、元数据提取、摄取服务
test/                              单元测试 + 测试夹具
```

## 常用命令
```
dart pub get --offline
dart analyze
dart test
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
```
