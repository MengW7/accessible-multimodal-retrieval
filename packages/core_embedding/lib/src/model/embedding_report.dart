import 'package:meta/meta.dart';

import 'embedding_vector.dart';

/// 单条向量失败的分类。批量服务按它汇总，不让一条坏输入中断整批。
enum EmbeddingFailureKind {
  runtimeUnavailable,
  badOutput,
  missingTensor,
  timeout,
  spaceMismatch,
  cancelled,
  unknown,
}

/// 对一条输入失败的结构化描述。不含向量，也不含正文。
@immutable
class EmbeddingFailure {
  const EmbeddingFailure({
    required this.kind,
    required this.message,
    this.detail,
  });

  final EmbeddingFailureKind kind;

  final String message;

  final String? detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'message': message,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      other is EmbeddingFailure &&
      other.kind == kind &&
      other.message == message &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, message, detail);

  @override
  String toString() => 'EmbeddingFailure(${kind.name}: $message)';
}

/// 批量向量化里的一条记录。成功和失败二选一。
@immutable
class EmbeddingRecord {
  const EmbeddingRecord.success({required this.sourceId, required this.vector})
    : failure = null;

  const EmbeddingRecord.failure({required this.sourceId, required this.failure})
    : vector = null;

  /// 文件相对路径或 chunkId。
  final String sourceId;

  final EmbeddingVector? vector;

  final EmbeddingFailure? failure;

  bool get isSuccess => vector != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'vector': vector?.toJson(),
    'failure': failure?.toJson(),
  };

  @override
  String toString() =>
      'EmbeddingRecord($sourceId, ${isSuccess ? 'ok' : failure?.kind.name})';
}

/// 一次批量向量化的汇总。形状对齐 `IngestionReport`：单条失败留在记录里。
@immutable
class EmbeddingReport {
  const EmbeddingReport({
    required this.startedAt,
    required this.finishedAt,
    this.records = const <EmbeddingRecord>[],
    this.cancelled = false,
  });

  final DateTime startedAt;

  final DateTime finishedAt;

  final List<EmbeddingRecord> records;

  final bool cancelled;

  Duration get duration => finishedAt.difference(startedAt);

  int get total => records.length;

  int get succeeded => records.where((EmbeddingRecord r) => r.isSuccess).length;

  int get failed => total - succeeded;

  bool get isClean => failed == 0 && !cancelled;

  Map<String, Object?> toJson() => <String, Object?>{
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'cancelled': cancelled,
    'isClean': isClean,
    'counts': <String, Object?>{
      'total': total,
      'ok': succeeded,
      'failed': failed,
    },
    'records': records
        .map((EmbeddingRecord record) => record.toJson())
        .toList(growable: false),
  };

  @override
  String toString() =>
      'EmbeddingReport(total: $total, ok: $succeeded, failed: $failed, '
      'cancelled: $cancelled)';
}

/// 批量运行期间的进度。`processed` 与 `total` 同时存在，方便读屏播报。
@immutable
class EmbeddingProgress {
  const EmbeddingProgress({
    required this.processed,
    required this.total,
    this.currentId,
    this.elapsed = Duration.zero,
  });

  final int processed;

  final int total;

  final String? currentId;

  final Duration elapsed;

  Map<String, Object?> toJson() => <String, Object?>{
    'processed': processed,
    'total': total,
    'currentId': currentId,
    'elapsedMs': elapsed.inMilliseconds,
  };

  @override
  String toString() => 'EmbeddingProgress($processed/$total)';
}
