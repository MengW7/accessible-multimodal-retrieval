import 'package:core_parsing/core_parsing.dart';
import 'package:meta/meta.dart';

/// 偏移量的索引单位。
///
/// W3 冻结为 UTF-16 code unit，与 Dart 的 `String.length` / `String.substring`
/// 以及 [DocumentPage.charCount] 相同。BMP 内的汉字一个字符占一个 code unit；
/// emoji 等代理对一个字符占两个。高亮、切片、引用必须共用这一单位。
enum TextUnit {
  utf16CodeUnit,
}

/// 切块产物。
///
/// [startOffset] 含首、[endOffset] 不含尾，都相对该页的提取文本，单位见
/// [textUnit]。因此 `pageText.substring(startOffset, endOffset)` 就是 [text]
/// 在原文里的跨度。TXT 和 DOCX 没有真实页码时 [pageNumber] 为 null，界面不得
/// 把它显示成真实页码。
///
/// [chunkId] 由 `contentHash`、[chunkerVersion]、页码和块序号组成。同一
/// 内容哈希、同一分块器版本、同一配置才能复现。它不是稳定主键。
@immutable
class TextChunk {
  const TextChunk({
    required this.chunkId,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.textUnit,
    required this.chunkerVersion,
    this.pageNumber,
  }) : assert(chunkId != '', 'chunkId must not be empty'),
       assert(chunkerVersion != '', 'chunkerVersion must not be empty'),
       assert(startOffset >= 0, 'startOffset must be >= 0'),
       assert(
         endOffset >= startOffset,
         'endOffset must be >= startOffset',
       ),
       assert(
         pageNumber == null || pageNumber > 0,
         'pageNumber is 1-based when present',
       );

  final String chunkId;

  final String text;

  /// 1-based。没有物理页时为 null。
  final int? pageNumber;

  /// 含首，单位见 [textUnit]。
  final int startOffset;

  /// 不含尾，单位见 [textUnit]。
  final int endOffset;

  final TextUnit textUnit;

  final String chunkerVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'chunkId': chunkId,
    'textLength': text.length,
    'pageNumber': pageNumber,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'textUnit': textUnit.name,
    'chunkerVersion': chunkerVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is TextChunk &&
      other.chunkId == chunkId &&
      other.text == text &&
      other.pageNumber == pageNumber &&
      other.startOffset == startOffset &&
      other.endOffset == endOffset &&
      other.textUnit == textUnit &&
      other.chunkerVersion == chunkerVersion;

  @override
  int get hashCode => Object.hash(
    chunkId,
    text,
    pageNumber,
    startOffset,
    endOffset,
    textUnit,
    chunkerVersion,
  );

  @override
  String toString() =>
      'TextChunk($chunkId, page: $pageNumber, '
      '$startOffset:$endOffset ${textUnit.name})';
}

/// 页用于定位，段落用于切分，超长才切窗口。
///
/// 具体级联是 `\n\n`、`\n`、句末标点、硬窗口。实现不得假定每种格式都有段落。
abstract interface class TextChunker {
  /// [documentId] 缺省时，实现用正文内容哈希充当文档标识。
  List<TextChunk> chunk(ParsedDocument document, {String? documentId});
}
