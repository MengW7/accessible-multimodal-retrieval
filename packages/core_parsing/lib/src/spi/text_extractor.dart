import 'package:meta/meta.dart';

import '../model/document_page.dart';
import 'cancellation_token.dart';

/// 抽取后端产出的文本，保留分页边界。
@immutable
class ExtractedText {
  const ExtractedText({
    required this.pages,
    required this.extractorName,
    this.title,
    this.attributes = const <String, Object?>{},
  });

  /// 按文档顺序排列的页；页码从 1 开始且连续。
  final List<DocumentPage> pages;

  /// 产出该结果的后端名称，用于报告。
  final String extractorName;

  /// 后端能提供时的文档标题。
  final String? title;

  /// 后端特有的附加信息（作者、生成器等）。
  final Map<String, Object?> attributes;

  /// 所有页以空行连接。
  String get fullText =>
      pages.map((DocumentPage page) => page.text).join('\n\n');

  /// 是否有任意一页含文本。
  bool get hasText => fullText.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ExtractedText &&
      other.extractorName == extractorName &&
      other.title == title &&
      _listEquals(other.pages, pages);

  @override
  int get hashCode =>
      Object.hash(extractorName, title, Object.hashAll(pages));

  @override
  String toString() =>
      'ExtractedText($extractorName, pages: ${pages.length})';
}

/// 把二进制或结构化文档转成文本的后端。
///
/// W2 只提供一个实现 `TikaCliTextExtractor`，它调用仓库内的 Apache Tika
/// 发行版。ADR 0002 计划在 W3+ 用 PDFium FFI 实现替换；因为解析器依赖本接口
/// 而不依赖具体实现，替换不会影响解析层。
abstract interface class TextExtractor {
  /// 后端标识，如 `tika-cli`。
  String get name;

  /// 后端版本；记录下来以保证基准数字可比。
  String get version;

  /// 从 [absolutePath] 抽取文本。
  ///
  /// 实现不得因*文档*问题抛异常：损坏的文件或不可用的运行时，
  /// 只能抛出调用方已声明的异常，由解析器转成 `ParseFailure`。
  Future<ExtractedText> extract(
    String absolutePath, {
    CancellationToken? cancel,
  });
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
