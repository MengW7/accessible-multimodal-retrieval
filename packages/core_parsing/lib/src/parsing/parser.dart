import '../model/parsed_document.dart';
import '../spi/cancellation_token.dart';

/// 每种格式的解析器都要实现的契约。
///
/// 解析器是「磁盘字节 → 内容或失败」的纯函数：文件本身的问题（内容损坏、
/// 变体不支持、运行时不具备）一律以 [ParseFailure] 返回而不抛异常，
/// 以免一个坏文件中断上万文件的批次（对应风险 R2/R3）。
///
/// 签名已在 W2 冻结，见 `docs/architecture/system-architecture.md`。
abstract interface class DocumentParser {
  /// 解析器的稳定标识，如 `txt`、`docx`、`pdf`、`image`。
  String get name;

  /// 解析器版本；抽取行为变化时递增，保证检索基准可跨版本比较。
  String get version;

  /// 本解析器负责的小写扩展名（含前导点），如 `{'.txt'}`、`{'.jpg', '.jpeg', '.png'}`。
  Set<String> get supportedExtensions;

  /// 解析 [absolutePath]。
  ///
  /// 实现需在安全点调用 [CancellationToken.throwIfCancelled]，
  /// 并把耗时写入 `ParseResult.duration`。
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  });
}
