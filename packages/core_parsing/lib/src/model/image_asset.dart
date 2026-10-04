import 'package:meta/meta.dart';

/// 图像文件的描述性元数据。
///
/// MobileCLIP 嵌入引擎生成，而 OCR 功能在检索基准测试证明确有必要之前暂不纳入范围。
@immutable
class ImageAsset {
  const ImageAsset({
    required this.format,
    required this.width,
    required this.height,
    this.colorMode,
    this.orientation,
  });

  /// 规范化的容器格式名称：`png`、`jpeg`、`gif`、`bmp` 等。
  final String format;

  /// 以像素为单位的宽度。
  final int width;

  /// 以像素为单位的高度。
  final int height;

  /// 解码器报告的通道布局：`rgb`、`rgba`、`grayscale`（灰度）等。
  final String? colorMode;

  /// 存在时的 EXIF 方向信息（`topLeft`、`rightTop` 等）。
  final String? orientation;

  /// 像素总数。
  int get pixelCount => width * height;

  /// 宽高比（宽度除以高度）；退化图像（高度为 0）时为 `0.0`。
  double get aspectRatio => height == 0 ? 0.0 : width / height;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': format,
    'width': width,
    'height': height,
    'colorMode': colorMode,
    'orientation': orientation,
  };

  @override
  bool operator ==(Object other) =>
      other is ImageAsset &&
      other.format == format &&
      other.width == width &&
      other.height == height &&
      other.colorMode == colorMode &&
      other.orientation == orientation;

  @override
  int get hashCode =>
      Object.hash(format, width, height, colorMode, orientation);

  @override
  String toString() =>
      'ImageAsset(format: $format, size: ${width}x$height, colorMode: $colorMode)';
}
