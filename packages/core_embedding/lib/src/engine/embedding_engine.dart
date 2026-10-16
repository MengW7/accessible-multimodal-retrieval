import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';

import '../image/image_embedder.dart';
import '../model/embedding_input.dart';
import '../model/embedding_space.dart';
import '../model/embedding_vector.dart';
import '../model/model_info.dart';
import '../text/clip_text_embedder.dart';
import '../text/text_embedder.dart';

/// 一次调用混用了两个向量空间。
///
/// 文本空间和 MobileCLIP 空间不能比较，也不能当成同一次 `embed` 的两侧。
/// 实现必须抛这个异常，不能靠文档约定。
class EmbeddingSpaceMismatchException implements Exception {
  const EmbeddingSpaceMismatchException({
    required this.requested,
    required this.actual,
    this.message = 'Embedding spaces cannot be mixed.',
  });

  final EmbeddingSpace requested;

  final EmbeddingSpace actual;

  final String message;

  @override
  String toString() =>
      'EmbeddingSpaceMismatchException: $message '
      '(requested: ${requested.name}, actual: ${actual.name})';
}

/// 文本和图像共用的入口。
///
/// 图像输入的空间必须是 [EmbeddingSpace.clipShared]。文本输入用
/// [EmbeddingSpace.documentText] 走文档模型，用 [EmbeddingSpace.clipShared]
/// 走 MobileCLIP 文本塔。空间和模型不一致时抛
/// [EmbeddingSpaceMismatchException]。
abstract interface class EmbeddingEngine {
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  });

  List<ModelInfo> get models;
}

/// 按输入的空间把文本和图像分到对应的模型。
///
/// 图像只走 [ImageEmbedder]。`documentText` 走 [TextEmbedder]。
/// `clipShared` 的文本走 [ClipTextEmbedder]；没有文本塔时抛
/// [EmbeddingSpaceMismatchException]，不拿 384 维的文档模型顶上。
final class DefaultEmbeddingEngine implements EmbeddingEngine {
  DefaultEmbeddingEngine({
    required this._text,
    required this._image,
    this._clipText,
  });

  final TextEmbedder _text;

  final ImageEmbedder _image;

  final ClipTextEmbedder? _clipText;

  @override
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  }) {
    if (input.isImage) {
      if (input.space != _image.model.space) {
        throw EmbeddingSpaceMismatchException(
          requested: input.space,
          actual: _image.model.space,
        );
      }
      final Uint8List? bytes = input.imageBytes;
      final int? width = input.imageWidth;
      final int? height = input.imageHeight;
      if (bytes == null || width == null || height == null) {
        throw ArgumentError('Image input is missing pixels.');
      }
      return _image.embed(bytes: bytes, width: width, height: height, cancel: cancel);
    }
    final String text = input.text ?? '';
    if (input.space == EmbeddingSpace.documentText) {
      if (_text.model.space != EmbeddingSpace.documentText) {
        throw EmbeddingSpaceMismatchException(
          requested: input.space,
          actual: _text.model.space,
        );
      }
      return _text.embed(text, chunkId: input.chunkId, cancel: cancel);
    }
    final ClipTextEmbedder? clipText = _clipText;
    if (clipText == null || clipText.model.space != EmbeddingSpace.clipShared) {
      throw EmbeddingSpaceMismatchException(
        requested: input.space,
        actual: _text.model.space,
      );
    }
    return clipText.embed(text, chunkId: input.chunkId, cancel: cancel);
  }

  @override
  List<ModelInfo> get models => <ModelInfo>[
    _text.model,
    _image.model,
    if (_clipText != null) _clipText.model,
  ];
}
