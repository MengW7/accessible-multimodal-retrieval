/// 执行一个工作单元，并隐藏它在何处执行。
///
/// 这个接缝让 `IngestionService` 在 `dart test` 下保持确定性，
abstract interface class Executor {
  /// 执行 [action] 并以它的结果完成。
  Future<T> run<T>(Future<T> Function() action);
}

/// 在当前 isolate 上执行 [action]。
///
class ImmediateExecutor implements Executor {
  const ImmediateExecutor();

  @override
  Future<T> run<T>(Future<T> Function() action) => action();
}
