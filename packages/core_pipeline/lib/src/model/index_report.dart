import 'package:meta/meta.dart';

/// 建库进度。两个数都要有，界面才能报「第几份，共几份」。
@immutable
class IndexProgress {
  const IndexProgress({required this.processed, required this.total});

  final int processed;

  final int total;
}

/// 一次建库的计数。
///
/// [written] 是这次真正重写的文件数。[reused] 是代次未变、没有再嵌入的文件数。
/// [chunksWritten] 只计新写入的块。
@immutable
class IndexReport {
  const IndexReport({
    required this.documents,
    required this.written,
    required this.reused,
    required this.failed,
    required this.cancelled,
    required this.chunksWritten,
  });

  final int documents;

  final int written;

  final int reused;

  final int failed;

  final bool cancelled;

  final int chunksWritten;
}
