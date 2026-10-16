import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:core_embedding/src/text/precompiled_normalizer.dart';
import 'package:test/test.dart';

/// 一张只含三条规则的 double-array，不读 17 MB 的 tokenizer.json。
///
/// 根单元的 offset 是 1。字节 `b` 的转移落在 `1 ^ b`。bit 9 保持 0，
/// 所以 offset 直接放在第 10 位以上。叶节点的替换下标写在跳转之后的那个单元。
///
/// - `A` → `BB`
/// - `X` → 空串
/// - U+00E9（UTF-8 `C3 A9`）最短叶是首字节，替换成 `Z`；整段本来可以换成 `e`
Uint8List _tinyCharsmap() {
  const int slots = 256;
  final Uint32List units = Uint32List(slots);
  units[0] = 1 << 10;

  void transition(int index, int label, int offset, {required bool leaf}) {
    units[index] = (offset << 10) | (leaf ? (1 << 8) : 0) | label;
  }

  const int aSlot = 1 ^ 0x41;
  const int aValue = 2;
  transition(aSlot, 0x41, aSlot ^ aValue, leaf: true);
  units[aValue] = 0;

  const int xSlot = 1 ^ 0x58;
  const int xValue = 4;
  transition(xSlot, 0x58, xSlot ^ xValue, leaf: true);
  units[xValue] = 2;

  const int first = 1 ^ 0xC3;
  const int base = 10;
  transition(first, 0xC3, first ^ base, leaf: true);
  units[base] = 5;
  const int second = base ^ 0xA9;
  const int fullValue = 6;
  transition(second, 0xA9, second ^ fullValue, leaf: true);
  units[fullValue] = 3;

  const List<int> blob = <int>[
    0x42, 0x42, 0, // 0: BB
    0x65, 0, // 3: e
    0x5A, 0, // 5: Z
  ];
  final Uint8List bytes = Uint8List(4 + slots * 4 + blob.length);
  final ByteData data = ByteData.sublistView(bytes);
  data.setUint32(0, slots * 4, Endian.little);
  for (var i = 0; i < slots; i++) {
    data.setUint32(4 + i * 4, units[i], Endian.little);
  }
  bytes.setRange(4 + slots * 4, bytes.length, blob);
  return bytes;
}

void main() {
  final PrecompiledNormalizer normalizer = PrecompiledNormalizer.fromBytes(
    _tinyCharsmap(),
  );

  test('a hand-built table replaces, deletes, and keeps unknown text', () {
    expect(normalizer.normalize(''), isEmpty);
    expect(normalizer.normalize('A'), 'BB');
    expect(normalizer.normalize('X'), isEmpty);
    expect(normalizer.normalize('C'), 'C');
    expect(normalizer.normalize('AXC'), 'BBC');
    expect(normalizer.normalize('你'), '你');
    expect(normalizer.normalize('\u0000'), '\u0000');
  });

  test('the shortest leaf wins inside one grapheme', () {
    expect(normalizer.normalize('\u00E9'), 'Z');
  });

  test('a grapheme of 6 bytes or more is rewritten per scalar', () {
    const String cluster = 'e\u0301\u0301\u0301';
    expect(cluster.characters.length, 1);
    expect(utf8.encode(cluster).length, greaterThanOrEqualTo(6));
    expect(normalizer.normalize(cluster), cluster);
  });

  test('an empty trie leaves text unchanged', () {
    final PrecompiledNormalizer empty = PrecompiledNormalizer.fromBytes(
      Uint8List(4),
    );
    expect(empty.normalize('A'), 'A');
  });

  test('a truncated charsmap is rejected', () {
    expect(
      () => PrecompiledNormalizer.fromBytes(Uint8List(3)),
      throwsFormatException,
    );
    final Uint8List badLength = Uint8List(4);
    ByteData.sublistView(badLength).setUint32(0, 8, Endian.little);
    expect(
      () => PrecompiledNormalizer.fromBytes(badLength),
      throwsFormatException,
    );
  });
}
