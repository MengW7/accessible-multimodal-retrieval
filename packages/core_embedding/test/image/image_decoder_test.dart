import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  test('png bytes round-trip to packed rgb24', () {
    final img.Image image = img.Image(width: 2, height: 1);
    image.setPixelRgb(0, 0, 10, 20, 30);
    image.setPixelRgb(1, 0, 40, 50, 60);
    final Uint8List png = Uint8List.fromList(img.encodePng(image));
    final DecodedImage decoded = const PackageImageDecoder().decodeBytes(png);
    expect(decoded.width, 2);
    expect(decoded.height, 1);
    expect(decoded.rgb24, <int>[10, 20, 30, 40, 50, 60]);
  });

  test('decodeFile reads a png from disk', () async {
    final img.Image image = img.Image(width: 1, height: 1);
    image.setPixelRgb(0, 0, 9, 8, 7);
    final Directory temp = await Directory.systemTemp.createTemp('core_embedding_png_');
    try {
      final File file = File('${temp.path}\\pixel.png');
      await file.writeAsBytes(img.encodePng(image));
      final DecodedImage decoded = const PackageImageDecoder().decodeFile(file.path);
      expect(decoded.rgb24, <int>[9, 8, 7]);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('empty, missing, and undecodable images fail', () {
    const PackageImageDecoder decoder = PackageImageDecoder();
    expect(() => decoder.decodeBytes(Uint8List(0)), throwsFormatException);
    expect(() => decoder.decodeBytes(Uint8List.fromList(<int>[1, 2, 3])), throwsFormatException);
    expect(() => decoder.decodeFile('Z:\\missing\\no-such.png'), throwsA(isA<FileSystemException>()));
  });
}
