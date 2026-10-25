import 'package:core_parsing/core_parsing.dart';

/// 建库要读的文件从这里来。
///
/// 生产实现包一层 [IngestionService]。测试注入假实现，避免为了编排去读盘。
abstract interface class IndexSource {
  Future<IngestionReport> load(String rootPath, {CancellationToken? cancel});
}

/// 把具体的入库服务收成 [IndexSource]。
final class IngestionIndexSource implements IndexSource {
  const IngestionIndexSource(this.service, {this.extensions});

  final IngestionService service;

  /// 为 null 时用解析包的默认白名单。Markdown 建库传入额外的 `.md`。
  final Set<String>? extensions;

  @override
  Future<IngestionReport> load(String rootPath, {CancellationToken? cancel}) {
    final Set<String>? allowed = extensions;
    if (allowed == null) {
      return service.ingestDirectory(rootPath, cancel: cancel);
    }
    return service.ingestDirectory(
      rootPath,
      extensions: allowed,
      cancel: cancel,
    );
  }
}
