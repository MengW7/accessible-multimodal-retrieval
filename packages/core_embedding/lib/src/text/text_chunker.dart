import 'dart:convert';

import 'package:core_parsing/core_parsing.dart';
import 'package:crypto/crypto.dart';

import '../model/text_chunk.dart';

/// 一个 UTF-16 窗口仍然放不进 token 预算。
///
/// 调用方应把它记成超长失败，不能改成截断后的向量。
class ChunkBudgetException implements Exception {
  const ChunkBudgetException({
    required this.tokenCount,
    required this.maxTokens,
  });

  final int tokenCount;

  final int maxTokens;

  @override
  String toString() =>
      'ChunkBudgetException: $tokenCount tokens exceed maxTokens $maxTokens.';
}

/// 防御性级联切块：`\n\n`、单个 `\n`、句末标点，最后才是字符窗口。
///
/// 页与页之间不合并。偏移相对该页文本，含首不含尾，单位是 UTF-16 code unit。
/// TXT 和 DOCX 解析器不会写 `pageCount` 或 `extractor`，因此单页文档的
/// [TextChunk.pageNumber] 为 null。PDF 解析器会写这两个属性；多于一页时也保留页码。
///
/// [countTokens] 必须和嵌入器使用同一个分词器，并且把起止标记算进去。
/// [chunkChars] 只是这个模型和语料上的字符窗口初值，不是跨语言的最优长度。
/// 真正的硬门是 [maxTokens]。窗口超长就缩短重切，不截断成一个半截向量。
final class CascadeTextChunker implements TextChunker {
  CascadeTextChunker({
    required this.countTokens,
    this.chunkChars = defaultChunkChars,
    this.maxTokens = defaultMaxTokens,
    this.chunkerVersion = defaultVersion,
    this.counterLabel = 'unigram',
  }) {
    if (chunkChars < 1) {
      throw ArgumentError.value(chunkChars, 'chunkChars', 'must be positive');
    }
    if (maxTokens < 2) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be at least 2');
    }
    if (chunkerVersion.isEmpty) {
      throw ArgumentError.value(
        chunkerVersion,
        'chunkerVersion',
        'must not be empty',
      );
    }
    if (counterLabel.isEmpty) {
      throw ArgumentError.value(
        counterLabel,
        'counterLabel',
        'must not be empty',
      );
    }
  }

  /// MiniLM 上的字符窗口初值。中文大约一字一 token，120 加两个特殊标记仍低于
  /// 128；英文会切得更碎。`datasets/samples` 里的两份文本偏英文，120 字窗口的
  /// token 分布见 `reports/week3/logs/chunk_chars_calibration.txt`，那里没有
  /// 把中文一字一 token 的上沿测出来。换语料要重定这个数。
  static const int defaultChunkChars = 120;

  static const int defaultMaxTokens = 128;

  static const String defaultVersion = 'w3-cascade-1';

  final int Function(String text) countTokens;

  final int chunkChars;

  final int maxTokens;

  final String chunkerVersion;

  /// 写进 `chunkId` 的分词器标记。同一套计数函数才和这个标记一起复现。
  final String counterLabel;

  @override
  List<TextChunk> chunk(ParsedDocument document, {String? documentId}) {
    if (documentId == '') {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'must be null or non-empty',
      );
    }
    final String id =
        documentId ?? sha256.convert(utf8.encode(document.fullText)).toString();
    final bool physical = _physicalPages(document);
    final List<_Page> pages = _pagesOf(document, physical);
    final List<TextChunk> chunks = <TextChunk>[];
    for (var ordinal = 0; ordinal < pages.length; ordinal++) {
      final _Page page = pages[ordinal];
      final List<_Span> spans = _cascade(page.text);
      var index = 0;
      for (final _Span span in spans) {
        final String text = page.text.substring(span.start, span.end);
        chunks.add(
          TextChunk(
            chunkId: _chunkId(
              documentId: id,
              ordinal: ordinal,
              pageNumber: page.pageNumber,
              index: index,
            ),
            text: text,
            startOffset: span.start,
            endOffset: span.end,
            textUnit: TextUnit.utf16CodeUnit,
            chunkerVersion: chunkerVersion,
            pageNumber: page.pageNumber,
          ),
        );
        index += 1;
      }
    }
    return chunks;
  }

  bool _physicalPages(ParsedDocument document) {
    if (document.attributes.containsKey('pageCount') ||
        document.attributes.containsKey('extractor')) {
      return true;
    }
    return document.pages.length > 1;
  }

  List<_Page> _pagesOf(ParsedDocument document, bool physical) {
    if (document.pages.isNotEmpty) {
      return <_Page>[
        for (final DocumentPage page in document.pages)
          _Page(physical ? page.pageNumber : null, page.text),
      ];
    }
    if (!document.hasText) {
      return const <_Page>[];
    }
    return <_Page>[_Page(physical ? 1 : null, document.fullText)];
  }

  List<_Span> _cascade(String page) {
    if (page.trim().isEmpty) {
      return const <_Span>[];
    }
    final List<_Span> paragraphs;
    if (page.contains('\n\n')) {
      paragraphs = _splitLiteral(page, _Span(0, page.length), '\n\n');
    } else if (page.contains('\n')) {
      paragraphs = _splitLiteral(page, _Span(0, page.length), '\n');
    } else {
      final _Span? only = _trimmed(page, _Span(0, page.length));
      paragraphs = only == null ? const <_Span>[] : <_Span>[only];
    }

    final List<_Span> lines = <_Span>[];
    for (final _Span span in paragraphs) {
      final String text = page.substring(span.start, span.end);
      if (page.contains('\n\n') && text.contains('\n') && _over(text)) {
        lines.addAll(_splitLiteral(page, span, '\n'));
      } else {
        lines.add(span);
      }
    }

    final List<_Span> sentences = <_Span>[];
    for (final _Span span in lines) {
      final String text = page.substring(span.start, span.end);
      if (_needsSplit(text)) {
        sentences.addAll(_splitSentences(page, span));
      } else {
        sentences.add(span);
      }
    }

    final List<_Span> windows = <_Span>[];
    for (final _Span span in sentences) {
      final String text = page.substring(span.start, span.end);
      if (_needsSplit(text)) {
        windows.addAll(_hardWindows(page, span));
      } else {
        windows.add(span);
      }
    }
    return windows;
  }

  bool _over(String text) => countTokens(text) > maxTokens;

  /// 字符窗口是初切，token 数是硬门槛。两者任一超了都要继续切。
  bool _needsSplit(String text) => _over(text) || text.length > chunkChars;

  List<_Span> _splitLiteral(String page, _Span span, String separator) {
    final String hay = page.substring(span.start, span.end);
    final List<_Span> pieces = <_Span>[];
    var from = 0;
    while (true) {
      final int at = hay.indexOf(separator, from);
      if (at < 0) {
        final _Span? tail = _trimmed(page, _Span(span.start + from, span.end));
        if (tail != null) {
          pieces.add(tail);
        }
        break;
      }
      final _Span? head = _trimmed(
        page,
        _Span(span.start + from, span.start + at),
      );
      if (head != null) {
        pieces.add(head);
      }
      from = at + separator.length;
    }
    return pieces;
  }

  List<_Span> _splitSentences(String page, _Span span) {
    final List<_Span> raw = <_Span>[];
    var cursor = span.start;
    for (var i = span.start; i < span.end; i++) {
      if (_sentenceEnd(page.codeUnitAt(i))) {
        raw.add(_Span(cursor, i + 1));
        cursor = i + 1;
      }
    }
    if (cursor < span.end) {
      raw.add(_Span(cursor, span.end));
    }
    if (raw.length <= 1) {
      final _Span? only = _trimmed(page, span);
      return only == null ? const <_Span>[] : <_Span>[only];
    }
    return <_Span>[for (final _Span piece in raw) ?_trimmed(page, piece)];
  }

  List<_Span> _hardWindows(String page, _Span span) {
    final List<_Span> pieces = <_Span>[];
    var start = span.start;
    while (start < span.end) {
      while (start < span.end && _isSpace(page.codeUnitAt(start))) {
        start += 1;
      }
      if (start >= span.end) {
        break;
      }
      var end = start + chunkChars;
      if (end > span.end) {
        end = span.end;
      }
      end = _keepPair(page, start, end, span.end);
      while (end > start && _over(page.substring(start, end))) {
        end = _shrink(page, start, end);
      }
      if (end <= start) {
        final int unitEnd = _oneScalar(page, start, span.end);
        throw ChunkBudgetException(
          tokenCount: countTokens(page.substring(start, unitEnd)),
          maxTokens: maxTokens,
        );
      }
      final int cut = end;
      var emitEnd = end;
      while (emitEnd > start && _isSpace(page.codeUnitAt(emitEnd - 1))) {
        emitEnd -= 1;
      }
      if (emitEnd > start) {
        pieces.add(_Span(start, emitEnd));
      }
      start = cut;
    }
    return pieces;
  }

  int _keepPair(String page, int start, int end, int limit) {
    if (end > start && end < limit && _isLow(page.codeUnitAt(end))) {
      return end + 1;
    }
    return end;
  }

  int _shrink(String page, int start, int end) {
    var next = end - 1;
    if (next > start && _isLow(page.codeUnitAt(next))) {
      next -= 1;
    }
    if (next < start) {
      return start;
    }
    return next;
  }

  int _oneScalar(String page, int start, int limit) {
    if (start + 1 < limit && _isHigh(page.codeUnitAt(start))) {
      return start + 2;
    }
    return start + 1;
  }

  _Span? _trimmed(String page, _Span span) {
    var start = span.start;
    var end = span.end;
    while (start < end && _isSpace(page.codeUnitAt(start))) {
      start += 1;
    }
    while (end > start && _isSpace(page.codeUnitAt(end - 1))) {
      end -= 1;
    }
    if (start >= end) {
      return null;
    }
    return _Span(start, end);
  }

  bool _sentenceEnd(int unit) {
    return unit == 0x3002 ||
        unit == 0xFF01 ||
        unit == 0xFF1F ||
        unit == 0xFF1B ||
        unit == 0x2E ||
        unit == 0x21 ||
        unit == 0x3F ||
        unit == 0x3B;
  }

  bool _isSpace(int unit) => String.fromCharCode(unit).trim().isEmpty;

  bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  String _chunkId({
    required String documentId,
    required int ordinal,
    required int? pageNumber,
    required int index,
  }) {
    final String page = pageNumber == null ? 'na' : '$pageNumber';
    return '$documentId-$chunkerVersion-$counterLabel-c$chunkChars-t$maxTokens-'
        'o$ordinal-p$page-i$index';
  }
}

final class _Page {
  const _Page(this.pageNumber, this.text);

  final int? pageNumber;
  final String text;
}

final class _Span {
  const _Span(this.start, this.end);

  final int start;
  final int end;
}
