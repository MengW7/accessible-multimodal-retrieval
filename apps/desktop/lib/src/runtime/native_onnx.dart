import 'dart:ffi';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:ffi/ffi.dart';

final class _InputTensor extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Void> data;
  @Size()
  external int bytes;
  external Pointer<Int64> shape;
  @Size()
  external int rank;
  @Int32()
  external int elementType;
}

typedef _RunNative = Int32 Function(
  Pointer<Void>,
  Pointer<_InputTensor>,
  Size,
  Pointer<Utf8>,
  Pointer<Float>,
  Size,
  Pointer<Utf8>,
  Size,
);
typedef _Run = int Function(
  Pointer<Void>,
  Pointer<_InputTensor>,
  int,
  Pointer<Utf8>,
  Pointer<Float>,
  int,
  Pointer<Utf8>,
  int,
);

/// Windows CPU backend owned by one RuntimeSession on the library worker.
final class NativeOnnx {
  NativeOnnx._(DynamicLibrary bridge)
    : _open = bridge
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf8>, Size),
            Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf8>, int)
          >('amr_onnx_open'),
      _run = bridge.lookupFunction<_RunNative, _Run>('amr_onnx_run'),
      _close = bridge
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('amr_onnx_close'),
      version = using((arena) {
        final probe = bridge
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Size),
              int Function(Pointer<Utf8>, int)
            >('amr_onnx_probe');
        final message = _message(arena);
        if (probe(message, _messageSize) != 0) {
          throw RuntimeUnavailableException(message.toDartString());
        }
        return message.toDartString();
      });

  factory NativeOnnx.load(String library, String bridge) {
    if (Abi.current() != Abi.windowsX64) {
      throw const RuntimeUnavailableException('生产推理适配当前支持 Windows x64。');
    }
    try {
      // Load the configured absolute DLL before its import is resolved by the
      // bridge. In particular, neither path is searched relative to cwd.
      DynamicLibrary.open(library);
      return NativeOnnx._(DynamicLibrary.open(bridge));
    } on ArgumentError catch (error) {
      throw RuntimeUnavailableException('无法加载原生推理库：${error.message}');
    }
  }

  static const _messageSize = 2048;
  static Pointer<Utf8> _message(Arena arena) =>
      arena<Uint8>(_messageSize).cast<Utf8>();

  final Pointer<Void> Function(Pointer<Utf16>, Pointer<Utf8>, int) _open;
  final _Run _run;
  final void Function(Pointer<Void>) _close;
  final String version;
  final _sessions = <String, Pointer<Void>>{};
  int completed = 0;
  void Function(String path, int? loadUs, int forwardUs)? onTiming;

  Float32List forward(
    String path,
    String outputName,
    int outputCount,
    Map<String, Tensor> inputs,
  ) => using((arena) {
    final message = _message(arena);
    final nativeInputs = arena<_InputTensor>(inputs.length);
    var index = 0;
    for (final entry in inputs.entries) {
      final tensor = entry.value;
      final data = tensor.data;
      // Values are defined by ONNXTensorElementDataType.
      final type = switch ((tensor.dtype, data)) {
        (TensorDType.float32, Float32List()) => 1,
        (TensorDType.uint8, Uint8List()) => 2,
        (TensorDType.int32, Int32List()) => 6,
        (TensorDType.int64, Int64List()) => 7,
        _ => throw MissingTensorException('Invalid tensor: ${entry.key}.'),
      };
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final input = arena<Uint8>(bytes.length);
      input.asTypedList(bytes.length).setAll(0, bytes);
      final shape = arena<Int64>(tensor.shape.length);
      shape.asTypedList(tensor.shape.length).setAll(0, tensor.shape);
      nativeInputs[index++]
        ..name = entry.key.toNativeUtf8(allocator: arena)
        ..data = input.cast()
        ..bytes = bytes.length
        ..shape = shape
        ..rank = tensor.shape.length
        ..elementType = type;
    }
    final observe = onTiming;
    int? loadUs;
    final session = _sessions.putIfAbsent(path, () {
      final loading = observe == null ? null : (Stopwatch()..start());
      final handle = _open(
        path.toNativeUtf16(allocator: arena),
        message,
        _messageSize,
      );
      if (handle == nullptr) {
        throw RuntimeUnavailableException(
          '无法加载模型 $path：${message.toDartString()}',
        );
      }
      loadUs = loading?.elapsedMicroseconds;
      return handle;
    });
    final output = arena<Float>(outputCount);
    final outputKey = outputName.toNativeUtf8(allocator: arena);
    final running = observe == null ? null : (Stopwatch()..start());
    final result = _run(
      session,
      nativeInputs,
      inputs.length,
      outputKey,
      output,
      outputCount,
      message,
      _messageSize,
    );
    final forwardUs = running?.elapsedMicroseconds;
    if (result != 0) {
      throw EmbeddingRuntimeException('ONNX 推理失败：${message.toDartString()}');
    }
    completed++;
    if (forwardUs != null) observe!(path, loadUs, forwardUs);
    return Float32List.fromList(output.asTypedList(outputCount));
  });

  void close() {
    for (final session in _sessions.values) {
      _close(session);
    }
    _sessions.clear();
  }
}

final class NativeOnnxModel implements EmbeddingRuntime {
  const NativeOnnxModel(
    this.backend,
    this.path,
    this.outputName,
    this.outputCount,
  );

  final NativeOnnx backend;
  final String path;
  final String outputName;
  final int outputCount;

  @override
  bool get isAvailable => true;

  @override
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs) async =>
      backend.forward(path, outputName, outputCount, inputs);
}
