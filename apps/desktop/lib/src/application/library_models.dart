import 'package:core_storage/core_storage.dart';

enum LibraryStage { preparing, parsing, indexing, saving }

enum LibraryFileStatus { queued, indexed, reused, failed, skipped, cancelled }

final class LibraryFile {
  const LibraryFile({
    required this.path,
    required this.status,
    this.detail,
    this.warning = false,
  });
  final String path;
  final LibraryFileStatus status;
  final String? detail;
  final bool warning;
  Map<String, Object?> toJson() => {
    'path': path,
    'status': status.name,
    'detail': detail,
    'warning': warning,
  };
  factory LibraryFile.fromJson(Map<String, dynamic> json) => LibraryFile(
    path: json['path'] as String,
    status: LibraryFileStatus.values.byName(json['status'] as String),
    detail: json['detail'] as String?,
    warning: json['warning'] == true,
  );
}

final class LibraryProgress {
  const LibraryProgress({
    required this.stage,
    this.processed = 0,
    this.total,
    this.currentPath,
    this.files = const [],
  });
  final LibraryStage stage;
  final int processed;
  final int? total;
  final String? currentPath;
  final List<LibraryFile> files;
}

final class LibraryRun {
  const LibraryRun({
    required this.root,
    required this.finishedAt,
    required this.written,
    required this.reused,
    required this.cancelled,
    required this.files,
  });
  final String root;
  final DateTime finishedAt;
  final int written;
  final int reused;
  final bool cancelled;
  final List<LibraryFile> files;
  int get failed =>
      files.where((f) => f.status == LibraryFileStatus.failed).length;
  int get skipped =>
      files.where((f) => f.status == LibraryFileStatus.skipped).length;
  int get warnings => files.where((f) => f.warning).length;
  String get label => cancelled
      ? '已取消'
      : failed > 0
      ? (written + reused > 0 ? '部分失败' : '失败')
      : warnings > 0
      ? '完成（有警告）'
      : written + reused == 0
      ? '没有可建库内容'
      : '完成';
  Map<String, Object?> toJson() => {
    'root': root,
    'finishedAt': finishedAt.toIso8601String(),
    'written': written,
    'reused': reused,
    'cancelled': cancelled,
    'files': files.map((f) => f.toJson()).toList(),
  };
  factory LibraryRun.fromJson(Map<String, dynamic> json) => LibraryRun(
    root: json['root'] as String,
    finishedAt: DateTime.parse(json['finishedAt'] as String),
    written: json['written'] as int,
    reused: json['reused'] as int,
    cancelled: json['cancelled'] as bool,
    files: List.unmodifiable(
      (json['files'] as List).map(
        (f) => LibraryFile.fromJson(Map<String, dynamic>.from(f as Map)),
      ),
    ),
  );
}

final class LibrarySnapshot {
  const LibrarySnapshot({required this.roots, required this.stats});
  final List<LibraryRun> roots;
  final IndexStats stats;
  Map<String, Object?> toJson() => {
    'roots': roots.map((r) => r.toJson()).toList(),
    'stats': {
      'documents': stats.documents,
      'chunks': stats.chunks,
      'documentText': stats.documentText,
      'clipShared': stats.clipShared,
      'keywordTerms': stats.keywordTerms,
    },
  };
}

final class LibraryResult {
  const LibraryResult({required this.run, required this.snapshot});
  final LibraryRun run;
  final LibrarySnapshot snapshot;
}
