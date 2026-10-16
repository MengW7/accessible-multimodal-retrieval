import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// MobileCLIP-S0 的预处理结果。像素是 NCHW float32，值域 0–1。
@immutable
class PreprocessedImage {
  const PreprocessedImage({
    required this.pixels,
    required this.edge,
  });

  /// 长度 `1 * 3 * edge * edge`，通道顺序 RGB。
  final Float32List pixels;

  final int edge;

  int get channels => 3;

  List<int> get shape => <int>[1, channels, edge, edge];
}

/// 短边缩放到 [edge]，Pillow `Image.BILINEAR`，再中心裁成正方形，像素除以 255。
///
/// 缩小会加宽卷积核。8-bit 先横向再纵向，系数是 22 位定点，和 Pillow 的
/// `Resample.c` 一致。尺寸不变时直接拷贝像素。`do_normalize` 是 false，
/// 这里不加 mean/std。
final class ImagePreprocessor {
  const ImagePreprocessor({this.edge = mobileClipEdge});

  static const int mobileClipEdge = 256;

  static const int _resampleBits = 22;

  static const int _resampleUnit = 1 << _resampleBits;

  static const int _resampleBias = 1 << (_resampleBits - 1);

  final int edge;

  PreprocessedImage preprocess({
    required Uint8List rgb24,
    required int width,
    required int height,
  }) {
    if (edge < 1) {
      throw ArgumentError.value(edge, 'edge', 'must be positive');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive.');
    }
    final int expected = width * height * 3;
    if (rgb24.length != expected) {
      throw ArgumentError(
        'Image bytes must be packed RGB24, length $expected, got ${rgb24.length}.',
      );
    }
    final int shortSide = math.min(width, height);
    final double scale = edge / shortSide;
    final int resizedWidth = math.max(edge, _pythonRound(width * scale));
    final int resizedHeight = math.max(edge, _pythonRound(height * scale));
    final Uint8List resized = _resize(
      rgb24,
      width,
      height,
      resizedWidth,
      resizedHeight,
    );
    final int left = (resizedWidth - edge) ~/ 2;
    final int top = (resizedHeight - edge) ~/ 2;
    final Float32List pixels = Float32List(3 * edge * edge);
    for (var y = 0; y < edge; y++) {
      for (var x = 0; x < edge; x++) {
        final int source = ((top + y) * resizedWidth + (left + x)) * 3;
        for (var channel = 0; channel < 3; channel++) {
          pixels[channel * edge * edge + y * edge + x] = resized[source + channel] / 255.0;
        }
      }
    }
    return PreprocessedImage(pixels: pixels, edge: edge);
  }

  Uint8List _resize(
    Uint8List source,
    int sourceWidth,
    int sourceHeight,
    int destWidth,
    int destHeight,
  ) {
    final Uint8List horizontal = sourceWidth == destWidth
        ? source
        : _resampleHorizontal(source, sourceWidth, sourceHeight, destWidth);
    if (sourceHeight == destHeight) {
      return horizontal;
    }
    return _resampleVertical(horizontal, destWidth, sourceHeight, destHeight);
  }

  Uint8List _resampleHorizontal(Uint8List source, int sourceWidth, int sourceHeight, int destWidth) {
    final _Kernel kernel = _kernel(sourceWidth, destWidth);
    final Uint8List dest = Uint8List(destWidth * sourceHeight * 3);
    for (var y = 0; y < sourceHeight; y++) {
      for (var x = 0; x < destWidth; x++) {
        final int start = kernel.starts[x];
        final Int32List weights = kernel.weights[x];
        final int at = (y * destWidth + x) * 3;
        for (var channel = 0; channel < 3; channel++) {
          var sum = _resampleBias;
          for (var tap = 0; tap < weights.length; tap++) {
            final int pixel = source[((y * sourceWidth) + start + tap) * 3 + channel];
            sum += pixel * weights[tap];
          }
          dest[at + channel] = _clip8(sum);
        }
      }
    }
    return dest;
  }

  Uint8List _resampleVertical(Uint8List source, int width, int sourceHeight, int destHeight) {
    final _Kernel kernel = _kernel(sourceHeight, destHeight);
    final Uint8List dest = Uint8List(width * destHeight * 3);
    for (var y = 0; y < destHeight; y++) {
      final int start = kernel.starts[y];
      final Int32List weights = kernel.weights[y];
      for (var x = 0; x < width; x++) {
        final int at = (y * width + x) * 3;
        for (var channel = 0; channel < 3; channel++) {
          var sum = _resampleBias;
          for (var tap = 0; tap < weights.length; tap++) {
            final int pixel = source[(((start + tap) * width) + x) * 3 + channel];
            sum += pixel * weights[tap];
          }
          dest[at + channel] = _clip8(sum);
        }
      }
    }
    return dest;
  }

  /// Pillow `precompute_coeffs` for bilinear, then the 8-bit fixed-point weights.
  _Kernel _kernel(int inSize, int outSize) {
    final double scale = inSize / outSize;
    final double filterScale = scale < 1.0 ? 1.0 : scale;
    final double support = filterScale;
    final double inverse = 1.0 / filterScale;
    final List<int> starts = List<int>.filled(outSize, 0);
    final List<Int32List> weights = List<Int32List>.generate(outSize, (int index) {
      return Int32List(0);
    });
    for (var index = 0; index < outSize; index++) {
      final double center = (index + 0.5) * scale;
      var start = (center - support + 0.5).toInt();
      if (start < 0) {
        start = 0;
      }
      var stop = (center + support + 0.5).toInt();
      if (stop > inSize) {
        stop = inSize;
      }
      final int count = stop - start;
      final Float64List raw = Float64List(count);
      var total = 0.0;
      for (var tap = 0; tap < count; tap++) {
        final double distance = (tap + start - center + 0.5) * inverse;
        final double absolute = distance < 0 ? -distance : distance;
        final double weight = absolute < 1.0 ? 1.0 - absolute : 0.0;
        raw[tap] = weight;
        total += weight;
      }
      final Int32List fixed = Int32List(count);
      if (total != 0) {
        for (var tap = 0; tap < count; tap++) {
          fixed[tap] = (0.5 + raw[tap] / total * _resampleUnit).toInt();
        }
      }
      starts[index] = start;
      weights[index] = fixed;
    }
    return _Kernel(starts, weights);
  }

  int _clip8(int fixed) {
    final int value = fixed >> _resampleBits;
    if (value <= 0) {
      return 0;
    }
    if (value >= 255) {
      return 255;
    }
    return value;
  }

  /// Python 3 的 `round`：恰好 .5 时向偶数靠拢。
  int _pythonRound(double value) {
    final double lower = value.floorToDouble();
    final double fraction = value - lower;
    if (fraction < 0.5) {
      return lower.toInt();
    }
    if (fraction > 0.5) {
      return lower.toInt() + 1;
    }
    final int base = lower.toInt();
    if (base.isEven) {
      return base;
    }
    return base + 1;
  }
}

final class _Kernel {
  const _Kernel(this.starts, this.weights);

  final List<int> starts;

  final List<Int32List> weights;
}
