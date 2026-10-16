import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;

import 'embedding_runtime.dart';

/// 用外部 ONNX Runtime 跑图像塔或 CLIP 文本塔。
///
/// 请求 JSON 带上每个输入张量。float32 用小端 base64，int64 用数字列表。
/// stdout 是指定输出的小端 float32 base64。文本 MiniLM 仍走
/// [OnnxProcessEmbeddingRuntime]，不改那条已经固定的请求。
final class OnnxTensorEmbeddingRuntime implements EmbeddingRuntime {
  OnnxTensorEmbeddingRuntime({
    required this.pythonExecutable,
    required this.scriptPath,
    required this.modelPath,
    required this.processRunner,
    required this.outputName,
    this.timeout = const Duration(seconds: 120),
  });

  final String pythonExecutable;

  final String scriptPath;

  final String modelPath;

  final ProcessRunner processRunner;

  /// `image_embeds` 或 `text_embeds`。
  final String outputName;

  final Duration timeout;

  @override
  bool get isAvailable =>
      File(pythonExecutable).existsSync() &&
      File(scriptPath).existsSync() &&
      File(modelPath).existsSync();

  @override
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs) async {
    if (!isAvailable) {
      throw RuntimeUnavailableException(
        'ONNX runtime files are missing.',
        detail: 'python=$pythonExecutable model=$modelPath',
      );
    }
    if (inputs.isEmpty) {
      throw const MissingTensorException('Missing input tensors.');
    }
    final Map<String, Object?> encoded = <String, Object?>{};
    inputs.forEach((String name, Tensor tensor) {
      encoded[name] = _encodeTensor(name, tensor);
    });
    final Directory temp = await Directory.systemTemp.createTemp('core_embedding_');
    final File request = File(p.join(temp.path, 'request.json'));
    try {
      await request.writeAsString(
        jsonEncode(<String, Object?>{
          'model_id': modelId,
          'model_path': modelPath,
          'output_name': outputName,
          'inputs': encoded,
        }),
      );
      final ProcessRunResult result;
      try {
        result = await processRunner.run(
          pythonExecutable,
          <String>[scriptPath, request.path],
          environment: <String, String>{
            ...Platform.environment,
            'PYTHONIOENCODING': 'utf-8',
            'PYTHONUNBUFFERED': '1',
          },
          timeout: timeout,
        );
      } on ProcessStartException catch (error) {
        throw RuntimeUnavailableException(
          'ONNX process failed to start.',
          detail: error.toString(),
        );
      } on ProcessTimeoutException catch (error) {
        throw EmbeddingTimeoutException(
          'ONNX process timed out.',
          detail: error.toString(),
        );
      }
      if (!result.isSuccess) {
        throw EmbeddingRuntimeException(
          'ONNX process exited ${result.exitCode}.',
          detail: result.stderr,
        );
      }
      return _decode(result.stdout);
    } finally {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    }
  }

  Map<String, Object?> _encodeTensor(String name, Tensor tensor) {
    final TypedData data = tensor.data;
    if (tensor.dtype == TensorDType.float32) {
      if (data is! Float32List) {
        throw MissingTensorException('Input tensor $name is not float32.');
      }
      final ByteData view = ByteData(data.length * 4);
      for (var i = 0; i < data.length; i++) {
        view.setFloat32(i * 4, data[i], Endian.little);
      }
      return <String, Object?>{
        'dtype': 'float32',
        'shape': tensor.shape,
        'b64': base64Encode(view.buffer.asUint8List()),
      };
    }
    if (tensor.dtype == TensorDType.int64) {
      if (data is! Int64List) {
        throw MissingTensorException('Input tensor $name is not int64.');
      }
      return <String, Object?>{
        'dtype': 'int64',
        'shape': tensor.shape,
        'values': data,
      };
    }
    throw MissingTensorException('Input tensor $name uses ${tensor.dtype.name}.');
  }

  Float32List _decode(String stdout) {
    final String payload = stdout.trim();
    if (payload.isEmpty) {
      throw const BadOutputException('ONNX process returned an empty vector.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(payload);
    } on FormatException catch (error) {
      throw BadOutputException('ONNX process stdout is not base64.', detail: error.message);
    }
    if (bytes.isEmpty || bytes.length % 4 != 0) {
      throw BadOutputException(
        'ONNX output length ${bytes.length} is not a multiple of 4.',
      );
    }
    final ByteData view = ByteData.sublistView(bytes);
    final Float32List values = Float32List(bytes.length ~/ 4);
    for (var i = 0; i < values.length; i++) {
      values[i] = view.getFloat32(i * 4, Endian.little);
    }
    return values;
  }
}
