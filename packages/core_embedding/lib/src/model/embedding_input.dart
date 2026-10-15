import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'embedding_space.dart';

/// 统一入口的一条输入。
///
/// 文本可以落在 [EmbeddingSpace.documentText]（正文或文本查询），也可以落在
/// [EmbeddingSpace.clipShared]（MobileCLIP 文本塔，用来查图）。图像只能落在
/// [EmbeddingSpace.clipShared]。
///
/// 图像字节是行优先 RGB24，长度等于 `width * height * 3`。解析结果只保留
/// 图像宽高，不保留像素，所以批量服务会按原路径再读一次文件，不再做解析。
@immutable
class EmbeddingInput {
  EmbeddingInput.text(
    this.text, {
    this.chunkId,
    this.space = EmbeddingSpace.documentText,
  }) : imageBytes = null,
       imageWidth = null,
       imageHeight = null {
    if (chunkId == '') {
      throw ArgumentError.value(chunkId, 'chunkId', 'must be null or non-empty');
    }
  }

  EmbeddingInput.image({
    required Uint8List bytes,
    required int width,
    required int height,
    this.space = EmbeddingSpace.clipShared,
  }) : text = null,
       chunkId = null,
       imageBytes = bytes,
       imageWidth = width,
       imageHeight = height {
    if (space != EmbeddingSpace.clipShared) {
      throw ArgumentError.value(
        space,
        'space',
        'Image embeddings use EmbeddingSpace.clipShared.',
      );
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive.');
    }
    final int expected = width * height * 3;
    if (bytes.length != expected) {
      throw ArgumentError(
        'Image bytes must be packed RGB24, length $expected, got ${bytes.length}.',
      );
    }
  }

  final EmbeddingSpace space;

  /// 文本输入的正文。图像输入时为 null。
  final String? text;

  /// 文本来自分块时带上，供结果回指。
  final String? chunkId;

  /// 图像输入的 RGB24 像素。文本输入时为 null。
  final Uint8List? imageBytes;

  final int? imageWidth;

  final int? imageHeight;

  bool get isImage => imageBytes != null;

  @override
  String toString() {
    if (isImage) {
      return 'EmbeddingInput.image(${imageWidth}x$imageHeight, ${space.name})';
    }
    return 'EmbeddingInput.text(chars: ${text?.length ?? 0}, ${space.name})';
  }
}
