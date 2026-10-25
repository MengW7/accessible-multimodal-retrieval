import 'package:meta/meta.dart';

import 'modality.dart';

/// 存储层自己的过滤条件。
///
/// 检索层的 `SearchFilters` 可以转成它。这个类型不能引用检索层，
/// 否则 `core_storage` 就要 import `core_retrieval`。
@immutable
class StorageFilter {
  const StorageFilter({
    this.extensions,
    this.pathPrefix,
    this.modifiedAfter,
    this.modality,
  });

  /// 带点的小写扩展名，例如 `{'.pdf', '.md'}`。空集表示没有文件能通过。
  final Set<String>? extensions;

  /// `relativePath` 的前缀，分隔符用 `/`。
  final String? pathPrefix;

  final DateTime? modifiedAfter;

  final Modality? modality;
}
