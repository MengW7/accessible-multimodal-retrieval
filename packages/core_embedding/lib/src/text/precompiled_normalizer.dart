import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';

/// SentencePiece `precompiled_charsmap` 归一化。
///
/// 二进制布局与 Hugging Face `spm_precompiled` 一致：小端
/// `u32` 的 trie 字节数，接着是 `u32` 单元的 double-array，剩下的字节是
/// 以 `0` 分隔的替换串。对一个 grapheme，先查整段（UTF-8 短于 6 字节时），
/// 没有命中再逐个码位。命中用最短前缀的替换，和 tokenizers 0.23 一样。
final class PrecompiledNormalizer {
  PrecompiledNormalizer._(this._array, this._normalized);

  final Uint32List _array;

  /// 替换表的原始 UTF-8 字节。trie 里的下标是字节偏移，不是 Dart 字符下标。
  final Uint8List _normalized;

  /// [bytes] 是 `precompiled_charsmap` 的原始字节，不是 base64。
  factory PrecompiledNormalizer.fromBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw FormatException('precompiled_charsmap is shorter than 4 bytes.');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final int trieBytes = data.getUint32(0, Endian.little);
    if (trieBytes % 4 != 0 || 4 + trieBytes > bytes.length) {
      throw FormatException('precompiled_charsmap trie length is invalid.');
    }
    final int units = trieBytes ~/ 4;
    final Uint32List array = Uint32List(units);
    for (var i = 0; i < units; i++) {
      array[i] = data.getUint32(4 + i * 4, Endian.little);
    }
    final Uint8List normalized = Uint8List.sublistView(bytes, 4 + trieBytes);
    return PrecompiledNormalizer._(array, normalized);
  }

  /// 按 grapheme 重写 [input]。空串仍是空串。
  String normalize(String input) {
    if (input.isEmpty) {
      return input;
    }
    final StringBuffer out = StringBuffer();
    for (final String grapheme in input.characters) {
      final int graphemeBytes = utf8.encode(grapheme).length;
      if (graphemeBytes < 6) {
        final String? whole = _transform(utf8.encode(grapheme));
        if (whole != null) {
          out.write(whole);
          continue;
        }
      }
      var byteIndex = 0;
      final List<int> graphemeUtf8 = utf8.encode(grapheme);
      for (final int rune in grapheme.runes) {
        final int width = utf8.encode(String.fromCharCodes(<int>[rune])).length;
        final String? part = _transform(
          graphemeUtf8.sublist(byteIndex, byteIndex + width),
        );
        if (part != null) {
          out.write(part);
        } else {
          out.writeCharCode(rune);
        }
        byteIndex += width;
      }
    }
    return out.toString();
  }

  /// 最短命中的替换。没有命中返回 null。命中但替换为空串时返回空串，表示删掉。
  String? _transform(List<int> key) {
    final List<int> hits = _prefixValues(key);
    if (hits.isEmpty) {
      return null;
    }
    return _replacement(hits.first);
  }

  List<int> _prefixValues(List<int> key) {
    final Uint32List array = _array;
    if (array.isEmpty) {
      return const <int>[];
    }
    final List<int> results = <int>[];
    var node = 0;
    var unit = array[node];
    node ^= _offset(unit);
    for (final int byte in key) {
      if (byte == 0) {
        break;
      }
      node ^= byte;
      _check(node);
      unit = array[node];
      if (_label(unit) != byte) {
        return results;
      }
      final bool leaf = _hasLeaf(unit);
      node ^= _offset(unit);
      if (leaf) {
        _check(node);
        results.add(_value(array[node]));
      }
    }
    return results;
  }

  void _check(int node) {
    if (node < 0 || node >= _array.length) {
      throw StateError('precompiled trie walked out of range at $node.');
    }
  }

  String _replacement(int index) {
    if (index < 0 || index > _normalized.length) {
      throw StateError('precompiled replacement index $index is out of range.');
    }
    var end = index;
    while (end < _normalized.length && _normalized[end] != 0) {
      end += 1;
    }
    if (end == index) {
      return '';
    }
    return utf8.decode(_normalized.sublist(index, end));
  }

  static bool _hasLeaf(int unit) => ((unit >> 8) & 1) == 1;

  static int _value(int unit) => unit & ((1 << 31) - 1);

  static int _label(int unit) => unit & ((1 << 31) | 0xFF);

  static int _offset(int unit) => (unit >> 10) << ((unit & (1 << 9)) >> 6);
}
