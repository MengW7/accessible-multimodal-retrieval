import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../model/image_asset.dart';
import '../../model/parsed_document.dart';
import '../../spi/cancellation_token.dart';
import '../file_bytes.dart';
import '../parser.dart';

/// Reads JPEG and PNG dimensions. The document has no text and no OCR.
class ImageParser implements DocumentParser {
  const ImageParser();

  @override
  String get name => 'image';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{
    '.jpg',
    '.jpeg',
    '.png',
  };

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final Object read = await readFileBytes(absolutePath, cancel: cancel);
    if (read is FileBytesFailure) {
      return ParseResult.failure(read.failure, duration: stopwatch.elapsed);
    }
    final FileBytesData data = read as FileBytesData;
    if (data.bytes.isEmpty) {
      return _corrupt(stopwatch, 'Image file is empty.');
    }
    try {
      final _Decoded? decoded = _decode(data.bytes);
      if (decoded == null) {
        return _corrupt(
          stopwatch,
          'Image bytes are not a readable JPEG or PNG.',
        );
      }
      return ParseResult.success(
        ParsedDocument(
          fullText: '',
          imageAsset: ImageAsset(
            format: decoded.format,
            width: decoded.image.width,
            height: decoded.image.height,
            colorMode: _colorMode(decoded.image),
            orientation: _orientation(decoded.image),
          ),
        ),
        duration: stopwatch.elapsed,
      );
    } on img.ImageException catch (error) {
      return _corrupt(
        stopwatch,
        'Image bytes could not be decoded.',
        error.message,
      );
    }
  }

  ParseResult _corrupt(Stopwatch stopwatch, String message, [String? detail]) {
    return ParseResult.failure(
      ParseFailure(
        kind: ParseFailureKind.corruptedInput,
        message: message,
        detail: detail,
      ),
      duration: stopwatch.elapsed,
    );
  }
}

final class _Decoded {
  const _Decoded(this.image, this.format);

  final img.Image image;
  final String format;
}

_Decoded? _decode(Uint8List bytes) {
  final img.JpegDecoder jpeg = img.JpegDecoder();
  if (jpeg.isValidFile(bytes)) {
    final img.Image? image = jpeg.decode(bytes);
    if (image == null) {
      return null;
    }
    return _Decoded(image, 'jpeg');
  }
  final img.PngDecoder png = img.PngDecoder();
  if (png.isValidFile(bytes)) {
    final img.Image? image = png.decode(bytes);
    if (image == null) {
      return null;
    }
    return _Decoded(image, 'png');
  }
  return null;
}

String _colorMode(img.Image image) {
  switch (image.numChannels) {
    case 1:
      return 'grayscale';
    case 2:
      return 'grayscale-alpha';
    case 4:
      return 'rgba';
    default:
      return 'rgb';
  }
}

/// EXIF orientation names used by [ImageAsset]. Missing EXIF stays null.
String? _orientation(img.Image image) {
  if (!image.hasExif || image.exif.isEmpty) {
    return null;
  }
  switch (image.exif.imageIfd.orientation) {
    case 1:
      return 'topLeft';
    case 2:
      return 'topRight';
    case 3:
      return 'bottomRight';
    case 4:
      return 'bottomLeft';
    case 5:
      return 'leftTop';
    case 6:
      return 'rightTop';
    case 7:
      return 'rightBottom';
    case 8:
      return 'leftBottom';
    default:
      return null;
  }
}
