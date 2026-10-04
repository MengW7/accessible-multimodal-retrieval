import 'parser.dart';

/// 把文件分派给其扩展名对应的解析器。
///
/// 注册表是唯一知道「扩展名 → 解析器」映射的地方，因此新增第六种格式
/// 只需加一个解析器和一行注册（对应架构文档中「新增格式要改哪几个文件」）。
abstract interface class ParserRegistry {
  /// 已注册的解析器，按注册顺序排列。
  List<DocumentParser> get parsers;

  /// 所有已注册解析器扩展名的并集。
  Set<String> get supportedExtensions;

  /// [extension] 对应的解析器（点可有可无、忽略大小写）；不支持时为 `null`。
  DocumentParser? resolveForExtension(String extension);

  /// 应当处理 [absolutePath] 的解析器；没有则为 `null`。
  DocumentParser? resolveForPath(String absolutePath);

  /// [absolutePath] 是否有已注册的解析器。
  bool supports(String absolutePath);
}
