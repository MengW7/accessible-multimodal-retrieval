import 'package:core_storage/core_storage.dart';
import 'package:meta/meta.dart';

/// 检索层的过滤条件。
///
/// 存储层不认识这个类型。查询时转成 [StorageFilter]，避免
/// `core_storage` 反过来依赖检索层。
@immutable
class SearchFilters {
  const SearchFilters({
    this.extensions,
    this.pathPrefix,
    this.modifiedAfter,
    this.modality,
  });

  /// 带点的扩展名，例如 `{'.pdf', '.md'}`。空集合表示没有文件能通过。
  final Set<String>? extensions;

  /// `relativePath` 前缀，分隔符是 `/`。
  final String? pathPrefix;

  final DateTime? modifiedAfter;

  final Modality? modality;

  StorageFilter toStorageFilter() {
    return StorageFilter(
      extensions: extensions,
      pathPrefix: pathPrefix,
      modifiedAfter: modifiedAfter,
      modality: modality,
    );
  }
}
