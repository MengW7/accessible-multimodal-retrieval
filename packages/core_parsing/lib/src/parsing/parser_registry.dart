import 'package:path/path.dart' as p;

import '../model/parsed_document.dart';
import '../spi/cancellation_token.dart';
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

/// Registry that dispatches on the lower-cased extension.
///
/// An unknown extension does not throw. [parse] returns
/// [ParseFailureKind.unsupportedFormat], which the report treats as skipped.
class StandardParserRegistry implements ParserRegistry {
  StandardParserRegistry(Iterable<DocumentParser> parsers)
    : _parsers = List<DocumentParser>.unmodifiable(parsers) {
    final Map<String, DocumentParser> map = <String, DocumentParser>{};
    for (final DocumentParser parser in _parsers) {
      for (final String extension in parser.supportedExtensions) {
        final String? key = normalizeParserExtension(extension);
        if (key == null) {
          continue;
        }
        map.putIfAbsent(key, () => parser);
      }
    }
    _byExtension = Map<String, DocumentParser>.unmodifiable(map);
  }

  final List<DocumentParser> _parsers;
  late final Map<String, DocumentParser> _byExtension;

  @override
  List<DocumentParser> get parsers => _parsers;

  @override
  Set<String> get supportedExtensions => _byExtension.keys.toSet();

  @override
  DocumentParser? resolveForExtension(String extension) {
    final String? key = normalizeParserExtension(extension);
    if (key == null) {
      return null;
    }
    return _byExtension[key];
  }

  @override
  DocumentParser? resolveForPath(String absolutePath) {
    return resolveForExtension(p.extension(absolutePath));
  }

  @override
  bool supports(String absolutePath) => resolveForPath(absolutePath) != null;

  /// Parse [absolutePath], or return `unsupportedFormat` when nothing matches.
  Future<ParseResult> parse(String absolutePath, {CancellationToken? cancel}) {
    final DocumentParser? parser = resolveForPath(absolutePath);
    if (parser == null) {
      final String extension = p.extension(absolutePath);
      return Future<ParseResult>.value(
        ParseResult.failure(
          ParseFailure(
            kind: ParseFailureKind.unsupportedFormat,
            message: 'No parser registered for "$extension".',
          ),
        ),
      );
    }
    return parser.parse(absolutePath, cancel: cancel);
  }
}

/// `.TXT`, `txt`, and `.txt` all become `.txt`. Empty input returns null.
String? normalizeParserExtension(String extension) {
  var value = extension.trim();
  if (value.isEmpty) {
    return null;
  }
  if (!value.startsWith('.')) {
    value = '.$value';
  }
  if (value == '.') {
    return null;
  }
  return value.toLowerCase();
}
