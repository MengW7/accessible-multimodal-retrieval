/// 打开库或建表时可以预期的失败。
///
/// 找不到 SQLite 动态库走这个类型，不把 [ArgumentError] 扔给调用方。
enum StorageFailureKind {
  libraryUnavailable,
  schemaUnsupported,
  spaceMismatch,
  dimensionMismatch,
  notNormalized,
  conflict,
  unknown,
}

class StorageFailure {
  const StorageFailure({
    required this.kind,
    required this.message,
    this.detail,
  });

  final StorageFailureKind kind;

  final String message;

  final String? detail;

  @override
  String toString() => 'StorageFailure(${kind.name}: $message)';
}

class StorageException implements Exception {
  const StorageException(this.failure);

  final StorageFailure failure;

  @override
  String toString() => 'StorageException: ${failure.message}';
}
