import 'dart:async';

/// 取消请求打断协作式工作时抛出。
class CancelledException implements Exception {
  const CancelledException([this.message = 'Operation cancelled']);

  /// 可读的原因说明。
  final String message;

  @override
  String toString() => 'CancelledException: $message';
}

/// 入库服务、解析器与进程运行器共用的协作式取消标志。
///
/// 取消是协作式的：不会从外部强杀任何东西。各工作单元在安全点调用
/// [throwIfCancelled]，避免把写到一半的状态带进流水线（对应风险 R3）。
class CancellationToken {
  CancellationToken._();

  bool _isCancelled = false;
  final List<void Function()> _listeners = <void Function()>[];
  Completer<void>? _completer;

  /// 是否已请求取消。
  bool get isCancelled => _isCancelled;

  /// 已请求取消时抛出 [CancelledException]。
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const CancelledException();
    }
  }

  /// 取消请求发生后完成；若请求早于本次调用，则立即完成。
  Future<void> get whenCancelled {
    if (_isCancelled) {
      return Future<void>.value();
    }
    return (_completer ??= Completer<void>()).future;
  }

  /// 注册 [listener]；若已取消则立即触发。
  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// 注销先前注册的 [listener]。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _completer?.complete();
    for (final void Function() listener
        in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}

/// 持有 [CancellationToken]，并且只允许一方发起取消。
///
/// UI 层持有 source，入库服务只拿到 token，解析器因此无法取消别人的批次。
class CancellationTokenSource {
  final CancellationToken _token = CancellationToken._();

  /// 交给工作单元使用的只读令牌。
  CancellationToken get token => _token;

  /// 是否已请求取消。
  bool get isCancelled => _token.isCancelled;

  /// 请求取消，幂等。
  void cancel() => _token._cancel();
}
