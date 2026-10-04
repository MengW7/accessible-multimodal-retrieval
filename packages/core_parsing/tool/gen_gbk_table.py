"""Write lib/src/parsing/encoding/gbk.dart from Python's gbk codec."""

import base64
import pathlib
import struct

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "lib" / "src" / "parsing" / "encoding" / "gbk.dart"

TRAILS = list(range(0x40, 0x7F)) + list(range(0x80, 0xFF))


def mappings() -> list[int]:
    units: list[int] = []
    for lead in range(0x81, 0xFF):
        for trail in TRAILS:
            try:
                text = bytes([lead, trail]).decode("gbk")
                units.append(ord(text) if len(text) == 1 else 0)
            except UnicodeDecodeError:
                units.append(0)
    return units


def main() -> None:
    units = mappings()
    if len(TRAILS) != 190 or len(units) != 126 * 190:
        raise SystemExit(f"unexpected table size {len(units)}")
    raw = struct.pack("<" + "H" * len(units), *units)
    encoded = base64.b64encode(raw).decode("ascii")
    folded = "\n".join(encoded[i : i + 80] for i in range(0, len(encoded), 80))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        """import 'dart:convert';
import 'dart:typed_data';

/// GBK decoder used when a text file is not valid UTF-8.
///
/// Mappings follow Python's `gbk` codec for lead bytes 0x81-0xFE and trail
/// bytes 0x40-0x7E, 0x80-0xFE. Unmapped bytes become U+FFFD.
String decodeGbk(List<int> bytes) {
  final Uint16List table = _table();
  final StringBuffer buffer = StringBuffer();
  var index = 0;
  while (index < bytes.length) {
    final int lead = bytes[index];
    if (lead < 0x80) {
      buffer.writeCharCode(lead);
      index++;
      continue;
    }
    if (lead < 0x81 || lead > 0xFE || index + 1 >= bytes.length) {
      buffer.writeCharCode(0xFFFD);
      index++;
      continue;
    }
    final int trail = bytes[index + 1];
    final int? unit = _lookup(table, lead, trail);
    buffer.writeCharCode(unit ?? 0xFFFD);
    index += 2;
  }
  return buffer.toString();
}

Uint16List? _cached;

Uint16List _table() {
  final Uint16List? cached = _cached;
  if (cached != null) {
    return cached;
  }
  final Uint8List packed = base64Decode(_tableBase64);
  final ByteData data = ByteData.sublistView(packed);
  final Uint16List table = Uint16List(packed.length ~/ 2);
  for (var i = 0; i < table.length; i++) {
    table[i] = data.getUint16(i * 2, Endian.little);
  }
  _cached = table;
  return table;
}

int? _lookup(Uint16List table, int lead, int trail) {
  final int trailIndex;
  if (trail >= 0x40 && trail <= 0x7E) {
    trailIndex = trail - 0x40;
  } else if (trail >= 0x80 && trail <= 0xFE) {
    trailIndex = 63 + (trail - 0x80);
  } else {
    return null;
  }
  final int unit = table[(lead - 0x81) * 190 + trailIndex];
  if (unit == 0) {
    return null;
  }
  return unit;
}

const String _tableBase64 =
'''
"""
        + folded
        + """
''';
""",
        encoding="utf-8",
        newline="\n",
    )
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
