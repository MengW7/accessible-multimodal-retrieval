import 'package:meta/meta.dart';

/// 提取出的单页文本（或单块逻辑文本块）。
///
/// 对于没有物理分页概念的格式（TXT、DOCX），只会生成唯一一页，
/// 且其 [pageNumber] 为 1；PDF 则会为每一页生成一个条目。
@immutable
class DocumentPage {
  const DocumentPage({required this.pageNumber, required this.text});

  /// 页码，从 1 开始。
  final int pageNumber;

  /// 提取出的文本，换行符已归一为 `\n`。
  final String text;

  /// 该页是否没有可用文本。
  bool get isEmpty => text.trim().isEmpty;

  /// [text] 的字符数。
  int get charCount => text.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'pageNumber': pageNumber,
    'text': text,
    'charCount': charCount,
  };

  @override
  bool operator ==(Object other) =>
      other is DocumentPage &&
      other.pageNumber == pageNumber &&
      other.text == text;

  @override
  int get hashCode => Object.hash(pageNumber, text);

  @override
  String toString() => 'DocumentPage(pageNumber: $pageNumber, chars: $charCount)';
}
