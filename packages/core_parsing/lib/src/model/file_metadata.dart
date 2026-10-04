import 'package:meta/meta.dart';

import 'image_asset.dart';
import 'parse_outcome.dart';

/// 单个摄取文件的不可变元数据。

@immutable
class FileMetadata {
  const FileMetadata({
    required this.id,
    required this.path,
    required this.relativePath,
    required this.fileName,
    required this.extension,
    required this.sizeBytes,
    this.mimeType,
    this.createdAt,
    this.modifiedAt,
    this.accessedAt,
    this.contentHash,
    this.indexedAt,
    this.parserName,
    this.parserVersion,
    this.parseDurationMs,
    this.status = ParseOutcome.skipped,
    this.errorMessage,
    this.imageAsset,
  });

  /// 文件跨运行周期的稳定唯一标识：若计算了哈希则为其字节内容的 SHA-256，
  /// 否则为基于 [relativePath] 计算的确定性哈希。
  final String id;

  /// 磁盘上的绝对路径。
  final String path;

  /// 相对于摄取根目录的相对路径，始终使用 `/` 分隔。
  final String relativePath;

  /// 包含扩展名的完整文件名。
  final String fileName;

  /// 包含前导句点的小写扩展名，例如 `.pdf`。
  final String extension;

  /// 以字节为单位的文件大小。
  final int sizeBytes;

  /// 根据扩展名解析出的 MIME 类型，例如 `application/pdf`。
  final String? mimeType;

  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final DateTime? accessedAt;

  /// 文件内容的 SHA-256 哈希值；若跳过哈希计算则为 `null`。
  final String? contentHash;

  /// 生成该记录的时间戳。
  final DateTime? indexedAt;

  /// 处理该文件的解析器名称，例如 `pdf`。
  final String? parserName;

  /// 解析器版本号，用于基准测试的可复现性。
  final String? parserVersion;

  /// 解析该文件所消耗的时间（毫秒）。
  final int? parseDurationMs;

  /// 该文件的最终解析状态归类。
  final ParseOutcome status;

  /// 失败原因说明；当 [status] 为 `ok` 或 `partial` 时为 `null`。
  final String? errorMessage;

  /// 图像描述信息，仅在输入为 JPG/PNG 时存在。
  final ImageAsset? imageAsset;

  /// 该文件是否贡献了可供嵌入引擎（Embedding Engine）使用的有效内容。
  bool get isIndexable => status.isUsable;

  FileMetadata copyWith({
    String? id,
    String? path,
    String? relativePath,
    String? fileName,
    String? extension,
    int? sizeBytes,
    String? mimeType,
    DateTime? createdAt,
    DateTime? modifiedAt,
    DateTime? accessedAt,
    String? contentHash,
    DateTime? indexedAt,
    String? parserName,
    String? parserVersion,
    int? parseDurationMs,
    ParseOutcome? status,
    String? errorMessage,
    ImageAsset? imageAsset,
  }) => FileMetadata(
    id: id ?? this.id,
    path: path ?? this.path,
    relativePath: relativePath ?? this.relativePath,
    fileName: fileName ?? this.fileName,
    extension: extension ?? this.extension,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    mimeType: mimeType ?? this.mimeType,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    accessedAt: accessedAt ?? this.accessedAt,
    contentHash: contentHash ?? this.contentHash,
    indexedAt: indexedAt ?? this.indexedAt,
    parserName: parserName ?? this.parserName,
    parserVersion: parserVersion ?? this.parserVersion,
    parseDurationMs: parseDurationMs ?? this.parseDurationMs,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
    imageAsset: imageAsset ?? this.imageAsset,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'path': path,
    'relativePath': relativePath,
    'fileName': fileName,
    'extension': extension,
    'sizeBytes': sizeBytes,
    'mimeType': mimeType,
    'createdAt': createdAt?.toIso8601String(),
    'modifiedAt': modifiedAt?.toIso8601String(),
    'accessedAt': accessedAt?.toIso8601String(),
    'contentHash': contentHash,
    'indexedAt': indexedAt?.toIso8601String(),
    'parserName': parserName,
    'parserVersion': parserVersion,
    'parseDurationMs': parseDurationMs,
    'status': status.name,
    'errorMessage': errorMessage,
    'imageAsset': imageAsset?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is FileMetadata &&
      other.id == id &&
      other.path == path &&
      other.relativePath == relativePath &&
      other.fileName == fileName &&
      other.extension == extension &&
      other.sizeBytes == sizeBytes &&
      other.mimeType == mimeType &&
      other.createdAt == createdAt &&
      other.modifiedAt == modifiedAt &&
      other.accessedAt == accessedAt &&
      other.contentHash == contentHash &&
      other.indexedAt == indexedAt &&
      other.parserName == parserName &&
      other.parserVersion == parserVersion &&
      other.parseDurationMs == parseDurationMs &&
      other.status == status &&
      other.errorMessage == errorMessage &&
      other.imageAsset == imageAsset;

  @override
  int get hashCode => Object.hash(
    id,
    path,
    relativePath,
    fileName,
    extension,
    sizeBytes,
    mimeType,
    modifiedAt,
    contentHash,
    status,
  );

  @override
  String toString() =>
      'FileMetadata($relativePath, ${status.name}, ${sizeBytes}B)';
}
