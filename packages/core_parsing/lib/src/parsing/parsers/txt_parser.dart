import 'dart:convert';
import 'dart:typed_data';

import '../../model/document_page.dart';
import '../../model/parse_outcome.dart';
import '../../model/parsed_document.dart';
import '../../spi/cancellation_token.dart';
import '../encoding/gbk.dart';
import '../file_bytes.dart';
import '../parser.dart';

/// Plain-text parser.
///
/// Encoding order: UTF-8 BOM, UTF-16 LE/BE BOM, strict UTF-8, then GBK.
/// Newlines become `\n`. Files longer than [maxBytes] are cut and marked
/// `partial`.
class TxtParser implements DocumentParser {
  TxtParser({this.maxBytes = defaultMaxBytes}) : assert(maxBytes > 0);

  /// 10 MiB. The Week 2 plan calls this the 10 MB ceiling.
  static const int defaultMaxBytes = 10 * 1024 * 1024;

  final int maxBytes;

  @override
  String get name => 'txt';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{'.txt'};

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final Object read = await readFileBytes(
      absolutePath,
      maxBytes: maxBytes,
      cancel: cancel,
    );
    if (read is FileBytesFailure) {
      return ParseResult.failure(read.failure, duration: stopwatch.elapsed);
    }
    final FileBytesData data = read as FileBytesData;
    final _DecodedText decoded = _decode(data.bytes, truncated: data.truncated);
    final String text = _normalizeNewlines(decoded.text);
    return ParseResult.success(
      ParsedDocument(
        fullText: text,
        pages: <DocumentPage>[DocumentPage(pageNumber: 1, text: text)],
        outcome: data.truncated ? ParseOutcome.partial : ParseOutcome.ok,
        warnings: List<String>.unmodifiable(decoded.warnings),
      ),
      duration: stopwatch.elapsed,
    );
  }

  _DecodedText _decode(Uint8List bytes, {required bool truncated}) {
    final List<String> warnings = <String>[];
    if (truncated) {
      warnings.add('truncated:$maxBytes');
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _DecodedText(
        _decodeUtf8(Uint8List.sublistView(bytes, 3), allowTrimTail: truncated),
        warnings,
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _DecodedText(_decodeUtf16(bytes, littleEndian: true), warnings);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _DecodedText(_decodeUtf16(bytes, littleEndian: false), warnings);
    }
    final Uint8List utf8Bytes = truncated ? _trimIncompleteUtf8(bytes) : bytes;
    if (_isStrictUtf8(utf8Bytes) &&
        (!truncated ||
            utf8Bytes.length == bytes.length ||
            _onlyTailWasCut(bytes, utf8Bytes))) {
      return _DecodedText(utf8.decode(utf8Bytes), warnings);
    }
    warnings.add('encoding-fallback:gbk');
    final Uint8List gbkBytes = truncated ? _trimIncompleteGbk(bytes) : bytes;
    return _DecodedText(decodeGbk(gbkBytes), warnings);
  }

  bool _onlyTailWasCut(Uint8List original, Uint8List trimmed) {
    if (trimmed.length >= original.length) {
      return true;
    }
    if (original.length - trimmed.length > 3) {
      return false;
    }
    return _isStrictUtf8(trimmed);
  }
}

class _DecodedText {
  const _DecodedText(this.text, this.warnings);

  final String text;
  final List<String> warnings;
}

String _normalizeNewlines(String input) {
  return input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

String _decodeUtf8(Uint8List bytes, {required bool allowTrimTail}) {
  final Uint8List payload = allowTrimTail ? _trimIncompleteUtf8(bytes) : bytes;
  return utf8.decode(payload);
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  var start = 0;
  if (bytes.length >= 2) {
    final bool bomLe = bytes[0] == 0xFF && bytes[1] == 0xFE;
    final bool bomBe = bytes[0] == 0xFE && bytes[1] == 0xFF;
    if ((littleEndian && bomLe) || (!littleEndian && bomBe)) {
      start = 2;
    }
  }
  final int end = start + ((bytes.length - start) ~/ 2) * 2;
  final StringBuffer buffer = StringBuffer();
  for (var i = start; i < end; i += 2) {
    final int unit = littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1];
    buffer.writeCharCode(unit);
  }
  return buffer.toString();
}

bool _isStrictUtf8(Uint8List bytes) {
  try {
    utf8.decode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

/// Drop a trailing partial UTF-8 sequence so a size cut is not reread as GBK.
Uint8List _trimIncompleteUtf8(Uint8List bytes) {
  var index = 0;
  var lastGood = 0;
  while (index < bytes.length) {
    final int lead = bytes[index];
    final int width;
    if (lead < 0x80) {
      width = 1;
    } else if ((lead & 0xE0) == 0xC0) {
      width = 2;
    } else if ((lead & 0xF0) == 0xE0) {
      width = 3;
    } else if ((lead & 0xF8) == 0xF0) {
      width = 4;
    } else {
      return bytes;
    }
    if (index + width > bytes.length) {
      return Uint8List.sublistView(bytes, 0, lastGood);
    }
    for (var offset = 1; offset < width; offset++) {
      if ((bytes[index + offset] & 0xC0) != 0x80) {
        return bytes;
      }
    }
    index += width;
    lastGood = index;
  }
  return bytes;
}

Uint8List _trimIncompleteGbk(Uint8List bytes) {
  if (bytes.isEmpty) {
    return bytes;
  }
  final int last = bytes[bytes.length - 1];
  if (last >= 0x81 && last <= 0xFE) {
    return Uint8List.sublistView(bytes, 0, bytes.length - 1);
  }
  return bytes;
}
