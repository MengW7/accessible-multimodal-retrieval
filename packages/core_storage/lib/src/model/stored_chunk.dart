import 'package:meta/meta.dart';

import 'modality.dart';

/// 向量和正文在本地索引里的一条记录。
///
/// [chunkId] 只回指切块结果，不是主键。代次判断用 [contentHash]、
/// [parserName]、[parserVersion]、[chunkerVersion]，再加上向量的模型名和维度。
@immutable
class StoredChunk {
  const StoredChunk({
    required this.documentId,
    required this.chunkId,
    required this.relativePath,
    required this.fileName,
    required this.startOffset,
    required this.endOffset,
    required this.body,
    required this.modality,
    this.mimeType,
    this.pageNumber,
    this.imageAsset,
    this.chunkIndex,
    this.extension,
    this.documentKey,
    this.modifiedAt,
    this.contentHash,
    this.parserName,
    this.parserVersion,
    this.chunkerVersion,
  }) : assert(documentId != '', 'documentId must not be empty'),
       assert(chunkId != '', 'chunkId must not be empty'),
       assert(startOffset >= 0, 'startOffset must be >= 0'),
       assert(endOffset >= startOffset, 'endOffset must be >= startOffset'),
       assert(
         pageNumber == null || pageNumber > 0,
         'pageNumber is 1-based when present',
       );

  final String documentId;

  final String chunkId;

  /// 相对摄取根的路径，分隔符是 `/`。
  final String relativePath;

  final String fileName;

  final String? mimeType;

  /// TXT 和 DOCX 为 null。界面不得把它显示成真实页码。
  final int? pageNumber;

  /// 含首，单位是 UTF-16 code unit。
  final int startOffset;

  /// 不含尾。
  final int endOffset;

  final String body;

  /// 图像行才有值。读回数据库时是 `ImageAsset`。
  final Object? imageAsset;

  final Modality modality;

  /// 同页相邻块用它做 ±1。图像行可以是 null。
  final int? chunkIndex;

  /// 带点的小写扩展名。缺省时从 [fileName] 取。
  final String? extension;

  /// 相对仓库根的路径，供评测集对齐。缺省时等于 [relativePath]。
  final String? documentKey;

  final DateTime? modifiedAt;

  final String? contentHash;

  final String? parserName;

  final String? parserVersion;

  final String? chunkerVersion;

  String get storedExtension {
    final String? given = extension;
    if (given != null && given.isNotEmpty) {
      return given.toLowerCase();
    }
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    return fileName.substring(dot).toLowerCase();
  }

  String get storedDocumentKey {
    final String? key = documentKey;
    if (key == null || key.isEmpty) {
      return relativePath;
    }
    return key.replaceAll('\\', '/');
  }
}
