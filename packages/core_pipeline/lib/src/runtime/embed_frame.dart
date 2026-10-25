import 'dart:convert';
import 'dart:typed_data';

/// 一帧是大端 uint32 长度，后面紧跟 UTF-8 JSON。长度不含这 4 个字节。
Uint8List encodeFrame(Map<String, Object?> message) {
  final List<int> body = utf8.encode(jsonEncode(message));
  final ByteData header = ByteData(4)..setUint32(0, body.length, Endian.big);
  final Uint8List frame = Uint8List(4 + body.length);
  frame.setRange(0, 4, header.buffer.asUint8List());
  frame.setRange(4, frame.length, body);
  return frame;
}

Map<String, Object?> decodePayload(Uint8List payload) {
  final Object? decoded = jsonDecode(utf8.decode(payload));
  if (decoded is! Map) {
    throw const FormatException('Embed frame is not a JSON object.');
  }
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

/// 把可能被拆开的字节粘回完整帧。
class FrameBuffer {
  final BytesBuilder _pending = BytesBuilder(copy: false);

  void add(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    _pending.add(bytes);
  }

  Uint8List? nextPayload() {
    final Uint8List bytes = _pending.takeBytes();
    if (bytes.length < 4) {
      if (bytes.isNotEmpty) {
        _pending.add(bytes);
      }
      return null;
    }
    final int length = ByteData.sublistView(bytes).getUint32(0, Endian.big);
    if (bytes.length < 4 + length) {
      _pending.add(bytes);
      return null;
    }
    final Uint8List payload = Uint8List.fromList(
      bytes.sublist(4, 4 + length),
    );
    if (4 + length < bytes.length) {
      _pending.add(Uint8List.sublistView(bytes, 4 + length));
    }
    return payload;
  }
}
