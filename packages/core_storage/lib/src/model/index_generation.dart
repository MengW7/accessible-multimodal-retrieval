import 'package:meta/meta.dart';

/// 一个文档的一种模型能不能复用。
///
/// 五项是 [contentHash]、解析器名加版本、[chunkerVersion]、[modelId]、[vectorDim]。
/// [documentId] 用来找到这一行，不单独算成第六项。
@immutable
class IndexGeneration {
  const IndexGeneration({
    required this.documentId,
    required this.contentHash,
    required this.parserName,
    required this.parserVersion,
    required this.chunkerVersion,
    required this.modelId,
    required this.vectorDim,
    required this.embeddedAt,
  }) : assert(documentId != '', 'documentId must not be empty'),
       assert(contentHash != '', 'contentHash must not be empty'),
       assert(parserName != '', 'parserName must not be empty'),
       assert(parserVersion != '', 'parserVersion must not be empty'),
       assert(chunkerVersion != '', 'chunkerVersion must not be empty'),
       assert(modelId != '', 'modelId must not be empty'),
       assert(vectorDim > 0, 'vectorDim must be positive');

  final String documentId;

  final String contentHash;

  final String parserName;

  final String parserVersion;

  final String chunkerVersion;

  final String modelId;

  final int vectorDim;

  final DateTime embeddedAt;

  bool sameRecipe(IndexGeneration other) {
    return contentHash == other.contentHash &&
        parserName == other.parserName &&
        parserVersion == other.parserVersion &&
        chunkerVersion == other.chunkerVersion &&
        modelId == other.modelId &&
        vectorDim == other.vectorDim;
  }
}
