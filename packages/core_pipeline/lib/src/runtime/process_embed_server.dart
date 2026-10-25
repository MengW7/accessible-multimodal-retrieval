import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';

import 'embed_frame.dart';

/// 一条到常驻进程的连接。读到 EOF 时 [receive] 返回 null。
abstract interface class EmbedServerConnection {
  Future<void> send(Map<String, Object?> message);

  Future<Map<String, Object?>?> receive();

  Future<void> close();
}

/// 进程从哪来。单测注入假实现，生产用本机 Python。
abstract interface class EmbedServerHost {
  Future<EmbedServerConnection> open();
}

/// 多个运行时共用的一个进程。请求按顺序写，避免两帧缠在一起。
///
/// 对端关掉连接时丢掉这条连接，下一次调用再打开。[completed] 只加不减，
/// 已经成功的次数在重启后还在。`ok: false` 不关进程。
final class ProcessEmbedServer {
  ProcessEmbedServer(this.host);

  final EmbedServerHost host;

  EmbedServerConnection? _live;

  int completed = 0;

  Future<void> _queue = Future<void>.value();

  Future<Map<String, Object?>> exchange(Map<String, Object?> request) {
    final Completer<void> gate = Completer<void>();
    final Future<void> previous = _queue;
    _queue = gate.future;
    return previous.then((_) => _exchange(request)).whenComplete(gate.complete);
  }

  Future<Map<String, Object?>> _exchange(Map<String, Object?> request) async {
    final EmbedServerConnection connection = _live ??= await host.open();
    await connection.send(request);
    final Map<String, Object?>? response = await connection.receive();
    if (response == null) {
      await drop();
      throw const EmbeddingRuntimeException(
        'Embed server closed before a response.',
      );
    }
    if (response['id'] != request['id']) {
      await drop();
      throw EmbeddingRuntimeException(
        'Response id ${response['id']} does not match ${request['id']}.',
      );
    }
    if (response['ok'] != true) {
      throw EmbeddingRuntimeException(_errorMessage(response));
    }
    completed += 1;
    return response;
  }

  Future<void> drop() async {
    final EmbedServerConnection? live = _live;
    _live = null;
    if (live != null) {
      await live.close();
    }
  }

  Future<void> close() => drop();
}

String _errorMessage(Map<String, Object?> response) {
  final Object? error = response['error'];
  if (error is Map) {
    final Object? message = error['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return 'Embed server rejected the request.';
}

/// 用操作系统进程实现的连接。stderr 只排空，不拿它判断成功。
final class ProcessEmbedConnection implements EmbedServerConnection {
  ProcessEmbedConnection(this._process);

  final Process _process;

  final FrameBuffer _buffer = FrameBuffer();

  final List<Map<String, Object?>> _ready = <Map<String, Object?>>[];

  Completer<Map<String, Object?>?>? _waiter;

  bool _done = false;

  void listen() {
    _process.stdout.listen(
      (List<int> data) {
        _buffer.add(data);
        Uint8List? payload = _buffer.nextPayload();
        while (payload != null) {
          final Map<String, Object?> message = decodePayload(payload);
          final Completer<Map<String, Object?>?>? waiter = _waiter;
          if (waiter != null && !waiter.isCompleted) {
            _waiter = null;
            waiter.complete(message);
          } else {
            _ready.add(message);
          }
          payload = _buffer.nextPayload();
        }
      },
      onDone: _finish,
      onError: (Object _) => _finish(),
    );
    _process.stderr.listen((List<int> _) {});
  }

  void _finish() {
    _done = true;
    final Completer<Map<String, Object?>?>? waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete(null);
    }
  }

  @override
  Future<void> send(Map<String, Object?> message) async {
    _process.stdin.add(encodeFrame(message));
    await _process.stdin.flush();
  }

  @override
  Future<Map<String, Object?>?> receive() {
    if (_ready.isNotEmpty) {
      return Future<Map<String, Object?>?>.value(_ready.removeAt(0));
    }
    if (_done) {
      return Future<Map<String, Object?>?>.value();
    }
    final Completer<Map<String, Object?>?> waiter =
        Completer<Map<String, Object?>?>();
    _waiter = waiter;
    return waiter.future;
  }

  @override
  Future<void> close() async {
    _process.kill();
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // 进程没有在预算内退出。句柄留给系统回收，调用方不再等。
    }
  }
}

/// 启动 `engine/embed_server.py`。一个宿主可以被多个运行时共用。
final class PythonEmbedServerHost implements EmbedServerHost {
  const PythonEmbedServerHost({
    required this.pythonExecutable,
    required this.scriptPath,
  });

  final String pythonExecutable;

  final String scriptPath;

  @override
  Future<EmbedServerConnection> open() async {
    final Process process = await Process.start(
      pythonExecutable,
      <String>[scriptPath],
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUNBUFFERED': '1',
      },
    );
    final ProcessEmbedConnection connection = ProcessEmbedConnection(process);
    connection.listen();
    return connection;
  }
}
