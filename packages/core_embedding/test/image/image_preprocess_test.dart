import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

Uint8List _rgb(List<List<int>> pixels) {
  return Uint8List.fromList(<int>[for (final List<int> pixel in pixels) ...pixel]);
}

void main() {
  test('a same-size image keeps its pixels and divides by 255', () {
    final PreprocessedImage image = const ImagePreprocessor(edge: 2).preprocess(
      rgb24: _rgb(<List<int>>[
        <int>[10, 20, 30],
        <int>[40, 50, 60],
        <int>[70, 80, 90],
        <int>[100, 110, 120],
      ]),
      width: 2,
      height: 2,
    );
    expect(image.edge, 2);
    expect(image.channels, 3);
    expect(image.shape, <int>[1, 3, 2, 2]);
    expect(image.pixels, hasLength(12));
    expect(image.pixels[0], closeTo(10 / 255, 1e-6));
    expect(image.pixels[1], closeTo(40 / 255, 1e-6));
    expect(image.pixels[4], closeTo(20 / 255, 1e-6));
    expect(image.pixels[8], closeTo(30 / 255, 1e-6));
  });

  test('upscaling matches Pillow bilinear rounding', () {
    final PreprocessedImage image = const ImagePreprocessor(edge: 4).preprocess(
      rgb24: _rgb(<List<int>>[
        <int>[10, 20, 30],
        <int>[40, 50, 60],
        <int>[70, 80, 90],
        <int>[100, 110, 120],
      ]),
      width: 2,
      height: 2,
    );
    expect(image.pixels[0], closeTo(10 / 255, 1e-6));
    expect(image.pixels[1], closeTo(18 / 255, 1e-6));
    expect(image.pixels[2], closeTo(33 / 255, 1e-6));
    expect(image.pixels[3], closeTo(40 / 255, 1e-6));
  });

  test('a wide image is center-cropped on the red channel', () {
    final List<int> wide = <int>[];
    for (var i = 0; i < 8; i++) {
      wide.addAll(<int>[i * 10, 0, 255 - i]);
    }
    final PreprocessedImage image = const ImagePreprocessor(edge: 2).preprocess(
      rgb24: Uint8List.fromList(wide),
      width: 4,
      height: 2,
    );
    expect(image.pixels[0], closeTo(10 / 255, 1e-6));
    expect(image.pixels[1], closeTo(20 / 255, 1e-6));
    expect(image.pixels[2], closeTo(50 / 255, 1e-6));
    expect(image.pixels[4], 0);
    expect(image.pixels[8], closeTo(254 / 255, 1e-6));
  });

  test('downscaling matches Pillow bilinear fixed point', () {
    final PreprocessedImage image = const ImagePreprocessor(edge: 2).preprocess(
      rgb24: Uint8List.fromList(<int>[for (var i = 0; i < 36; i++) i]),
      width: 4,
      height: 3,
    );
    expect(image.pixels, hasLength(12));
    expect(image.pixels[0], closeTo(6 / 255, 1e-6));
    expect(image.pixels[1], closeTo(10 / 255, 1e-6));
    expect(image.pixels[2], closeTo(21 / 255, 1e-6));
    expect(image.pixels[3], closeTo(25 / 255, 1e-6));
    expect(image.pixels[4], closeTo(7 / 255, 1e-6));
    expect(image.pixels[5], closeTo(11 / 255, 1e-6));
    expect(image.pixels[8], closeTo(8 / 255, 1e-6));
  });

  test('a solid color stays in its channel', () {
    final PreprocessedImage image = const ImagePreprocessor(edge: 2).preprocess(
      rgb24: Uint8List.fromList(<int>[255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0]),
      width: 2,
      height: 2,
    );
    expect(image.pixels.sublist(0, 4).every((double value) => value == 1), isTrue);
    expect(image.pixels.sublist(4).every((double value) => value == 0), isTrue);
  });

  test('bad dimensions and byte lengths are rejected', () {
    const ImagePreprocessor preprocessor = ImagePreprocessor(edge: 2);
    expect(
      () => preprocessor.preprocess(rgb24: Uint8List(0), width: 0, height: 1),
      throwsArgumentError,
    );
    expect(
      () => preprocessor.preprocess(rgb24: Uint8List(3), width: 2, height: 1),
      throwsArgumentError,
    );
    expect(
      () => const ImagePreprocessor(edge: 0).preprocess(
        rgb24: Uint8List.fromList(<int>[0, 0, 0]),
        width: 1,
        height: 1,
      ),
      throwsArgumentError,
    );
  });
}
