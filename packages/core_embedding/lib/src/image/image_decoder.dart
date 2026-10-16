import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';

/// 一行行的 RGB24。解析层只留宽高，像素由这里按原路径重新读出。
@immutable
class DecodedImage {
  const DecodedImage({
    required this.rgb24,
    required this.width,
    required this.height,
  });

  final Uint8List rgb24;

  final int width;

  final int height;
}

/// 把图像文件解码成 RGB24。默认套件注入假实现，不读数据集。
abstract interface class ImageDecoder {
  DecodedImage decodeFile(String path);
}

/// `package:image` 的 JPEG/PNG 解码。不做 EXIF 旋转，和探针里的 Pillow 一致。
final class PackageImageDecoder implements ImageDecoder {
  const PackageImageDecoder();

  @override
  DecodedImage decodeFile(String path) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Image file is missing.', path);
    }
    final Uint8List bytes = file.readAsBytesSync();
    if (bytes.isEmpty) {
      throw FormatException('Image file is empty.');
    }
    return decodeBytes(bytes);
  }

  DecodedImage decodeBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('Image bytes are empty.');
    }
    final img.Image? image = _decodeOrFormat(bytes);
    if (image == null) {
      throw const FormatException('Image bytes are not a readable JPEG or PNG.');
    }
    if (image.width <= 0 || image.height <= 0) {
      throw const FormatException('Image dimensions must be positive.');
    }
    final Uint8List rgb24 = Uint8List(image.width * image.height * 3);
    var offset = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final img.Pixel pixel = image.getPixel(x, y);
        rgb24[offset] = _channel(pixel.r);
        rgb24[offset + 1] = _channel(pixel.g);
        rgb24[offset + 2] = _channel(pixel.b);
        offset += 3;
      }
    }
    return DecodedImage(rgb24: rgb24, width: image.width, height: image.height);
  }

  img.Image? _decodeOrFormat(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Image bytes are not a readable JPEG or PNG.');
    }
  }

  int _channel(num value) {
    final int rounded = value.round();
    if (rounded < 0) {
      return 0;
    }
    if (rounded > 255) {
      return 255;
    }
    return rounded;
  }
}
