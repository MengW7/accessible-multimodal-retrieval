import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';

import 'process_embed_server.dart';

/// 把 [EmbeddingRuntime] 接到一个常驻 ONNX 进程。
///
/// 文本模型的 [outputName] 必须是 `last_hidden_state`。这里不池化。
/// 图像和 CLIP 文本塔用 `image_embeds` 或 `text_embeds`。
final class PersistentOnnxRuntime implements EmbeddingRuntime {
  PersistentOnnxRuntime({
    required this.modelPath,
    required this.outputName,
    required this.server,
    this.available,
  });

  factory PersistentOnnxRuntime.python({
    required String pythonExecutable,
    required String scriptPath,
    required String modelPath,
    required String outputName,
    ProcessEmbedServer? server,
  }) {
    return PersistentOnnxRuntime(
      modelPath: modelPath,
      outputName: outputName,
      server:
          server ??
          ProcessEmbedServer(
            PythonEmbedServerHost(
              pythonExecutable: pythonExecutable,
              scriptPath: scriptPath,
            ),
          ),
      available:
          File(pythonExecutable).existsSync() &&
          File(scriptPath).existsSync() &&
          File(modelPath).existsSync(),
    );
  }

  final String modelPath;

  final String outputName;

  final ProcessEmbedServer server;

  /// 为 null 时视为可用。Python 工厂会按文件是否存在写入 false。
  final bool? available;

  int _nextId = 0;

  @override
  bool get isAvailable => available ?? true;

  @override
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs) async {
    if (!isAvailable) {
      throw RuntimeUnavailableException(
        'Persistent ONNX runtime is not available.',
        detail: modelPath,
      );
    }
    final int id = _nextId;
    _nextId += 1;
    final Map<String, Object?> response = await server.exchange(<String, Object?>{
      'id': id,
      'model_path': modelPath,
      'output_name': outputName,
      'model_id': modelId,
      'inputs': <String, Object?>{
        for (final MapEntry<String, Tensor> entry in inputs.entries)
          entry.key: _tensorJson(entry.key, entry.value),
      },
    });
    return _floats(response['b64']);
  }

  Map<String, Object?> _tensorJson(String name, Tensor tensor) {
    final TypedData data = tensor.data;
    switch (tensor.dtype) {
      case TensorDType.float32:
        if (data is! Float32List) {
          throw MissingTensorException('Tensor $name is not float32.');
        }
        return <String, Object?>{
          'dtype': 'float32',
          'shape': tensor.shape,
          'b64': base64Encode(_littleEndian(data)),
        };
      case TensorDType.int64:
        if (data is! Int64List) {
          throw MissingTensorException('Tensor $name is not int64.');
        }
        return <String, Object?>{
          'dtype': 'int64',
          'shape': tensor.shape,
          'values': data.toList(growable: false),
        };
      case TensorDType.int32:
        if (data is! Int32List) {
          throw MissingTensorException('Tensor $name is not int32.');
        }
        return <String, Object?>{
          'dtype': 'int32',
          'shape': tensor.shape,
          'values': data.toList(growable: false),
        };
      case TensorDType.uint8:
        if (data is! Uint8List) {
          throw MissingTensorException('Tensor $name is not uint8.');
        }
        return <String, Object?>{
          'dtype': 'uint8',
          'shape': tensor.shape,
          'b64': base64Encode(data),
        };
    }
  }

  Uint8List _littleEndian(Float32List values) {
    final ByteData view = ByteData(values.length * 4);
    for (var index = 0; index < values.length; index++) {
      view.setFloat32(index * 4, values[index], Endian.little);
    }
    return view.buffer.asUint8List();
  }

  Float32List _floats(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) {
      throw const BadOutputException('Embed server returned no vector.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException catch (error) {
      throw BadOutputException(
        'Embed server vector is not base64.',
        detail: error.message,
      );
    }
    if (bytes.isEmpty || bytes.length % 4 != 0) {
      throw BadOutputException(
        'Embed server vector length ${bytes.length} is not a multiple of 4.',
      );
    }
    final ByteData view = ByteData.sublistView(bytes);
    final Float32List values = Float32List(bytes.length ~/ 4);
    for (var index = 0; index < values.length; index++) {
      values[index] = view.getFloat32(index * 4, Endian.little);
    }
    return values;
  }
}
