import 'package:meta/meta.dart';

import 'file_metadata.dart';
import 'parse_outcome.dart';
import 'parsed_document.dart';

/// 单个文件在一次入库中的记录。
@immutable
class IngestRecord {
  const IngestRecord({required this.metadata, this.document, this.failure});

  /// 文件描述信息，包含文件路径、大小、修改时间、类型等。
  final FileMetadata metadata;

  /// 提取的内容，当没有提取任何内容时为 `null`。
  final ParsedDocument? document;

  /// 失败描述，当文件解析成功时为 `null`。
  final ParseFailure? failure;

  /// 最终分类，取自 [metadata]。
  ParseOutcome get outcome => metadata.status;

  /// 嵌入引擎是否有文本或图像可用。
  bool get hasContent {
    final parsed = document;
    if (parsed == null) {
      return false;
    }
    return parsed.hasText || parsed.imageAsset != null;
  }

  /// 序列化该记录。
  ///
  /// [includeText] 默认为 `false`：报告不复制全文（日志同样不写正文），只记长度。
  Map<String, Object?> toJson({bool includeText = false}) => <String, Object?>{
    'metadata': metadata.toJson(),
    'outcome': outcome.name,
    'failure': failure?.toJson(),
    'pageCount': document?.pageCount ?? 0,
    'charCount': document?.charCount ?? 0,
    'text': includeText ? document?.fullText : null,
  };

  @override
  bool operator ==(Object other) =>
      other is IngestRecord &&
      other.metadata == metadata &&
      other.document == document &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(metadata, document, failure);

  @override
  String toString() => 'IngestRecord(${metadata.relativePath}, ${outcome.name})';
}

/// 一次 `ingestDirectory` 调用的汇总。
@immutable
class IngestionReport {
  const IngestionReport({
    required this.rootPath,
    required this.startedAt,
    required this.finishedAt,
    this.records = const <IngestRecord>[],
    this.cancelled = false,
  });

  /// 被扫描的目录。
  final String rootPath;

  final DateTime startedAt;
  final DateTime finishedAt;

  /// 每个被访问的文件一条记录，按扫描顺序排列。
  final List<IngestRecord> records;

  /// 是否因请求取消而提前结束。
  final bool cancelled;

  /// 本次运行的墙钟耗时。
  Duration get duration => finishedAt.difference(startedAt);

  /// 被访问的文件数。
  int get total => records.length;

  /// 分类为 [outcome] 的文件数。
  int countOf(ParseOutcome outcome) =>
      records.where((IngestRecord record) => record.outcome == outcome).length;

  int get succeeded => countOf(ParseOutcome.ok);
  int get partial => countOf(ParseOutcome.partial);
  int get skipped => countOf(ParseOutcome.skipped);
  int get failed => countOf(ParseOutcome.failed);

  /// 带 [ParseFailure] 的记录。
  List<IngestRecord> get failures => records
      .where((IngestRecord record) => record.failure != null)
      .toList(growable: false);

  /// 嵌入引擎可以消费的记录。
  List<IngestRecord> get indexable => records
      .where((IngestRecord record) => record.metadata.isIndexable)
      .toList(growable: false);

  /// 没有失败且未被取消时为 `true`。
  bool get isClean => failed == 0 && !cancelled;

  Map<String, Object?> toJson({bool includeRecords = true}) =>
      <String, Object?>{
        'rootPath': rootPath,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'cancelled': cancelled,
        'isClean': isClean,
        'counts': <String, Object?>{
          'total': total,
          'ok': succeeded,
          'partial': partial,
          'skipped': skipped,
          'failed': failed,
        },
        'records': includeRecords
            ? records
                  .map((IngestRecord record) => record.toJson())
                  .toList(growable: false)
            : null,
      };

  @override
  String toString() =>
      'IngestionReport(total: $total, ok: $succeeded, partial: $partial, '
      'skipped: $skipped, failed: $failed, cancelled: $cancelled)';
}

/// 批次运行期间发出的进度通知。
///
/// UI 层（W5）用它画进度条，无障碍层用它播报，因此 [processed] 与
/// [total] 始终同时存在，不会为 `null`。
@immutable
class IngestProgress {
  const IngestProgress({
    required this.processed,
    required this.total,
    this.currentPath,
    this.elapsed = Duration.zero,
  });

  /// 已完成的文件数。
  final int processed;

  /// 本次发现的文件总数。
  final int total;

  /// 当前正在解析的文件。
  final String? currentPath;

  /// 运行至今的耗时。
  final Duration elapsed;

  /// 完成比例，取值 `[0, 1]`；无事可做时为 `1.0`。
  double get fraction {
    if (total <= 0 || processed >= total) {
      return 1.0;
    }
    return processed / total;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'processed': processed,
    'total': total,
    'currentPath': currentPath,
    'fraction': fraction,
    'elapsedMs': elapsed.inMilliseconds,
  };

  @override
  String toString() =>
      'IngestProgress($processed/$total, ${(fraction * 100).toStringAsFixed(1)}%)';
}
