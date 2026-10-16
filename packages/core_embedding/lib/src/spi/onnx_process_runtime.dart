import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;

import 'embedding_runtime.dart';

/// 用外部 Python 进程跑 ONNX Runtime。
///
/// 这是 ADR 0003 的运行时：Dart 不链接 TFLite。进程读一份 JSON 请求，把
/// `last_hidden_state` 以小端 float32 的 base64 写到 stdout。pooling 不在这里做。
final class OnnxProcessEmbeddingRuntime implements EmbeddingRuntime {
  OnnxProcessEmbeddingRuntime({
    required this.pythonExecutable,
    required this.scriptPath,
    required this.modelPath,
    required this.processRunner,
    this.timeout = const Duration(seconds: 120),
  });

  final String pythonExecutable;

  final String scriptPath;

  final String modelPath;

  final ProcessRunner processRunner;

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
    final Int64List ids = _int64(inputs, 'input_ids');
    final Int64List mask = _int64(inputs, 'attention_mask');
    final Int64List types = _int64(inputs, 'token_type_ids');
    final Directory temp = await Directory.systemTemp.createTemp('core_embedding_');
    final File request = File(p.join(temp.path, 'request.json'));
    try {
      await request.writeAsString(
        jsonEncode(<String, Object?>{
          'model_id': modelId,
          'model_path': modelPath,
          'input_ids': ids,
          'attention_mask': mask,
          'token_type_ids': types,
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
      return _decodeHidden(result.stdout);
    } finally {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    }
  }

  Int64List _int64(Map<String, Tensor> inputs, String name) {
    final Tensor? tensor = inputs[name];
    if (tensor == null) {
      throw MissingTensorException('Missing input tensor $name.');
    }
    final TypedData data = tensor.data;
    if (data is! Int64List || tensor.dtype != TensorDType.int64) {
      throw MissingTensorException('Input tensor $name is not int64.');
    }
    return data;
  }

  Float32List _decodeHidden(String stdout) {
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
        'ONNX hidden state length ${bytes.length} is not a multiple of 4.',
      );
    }
    final ByteData view = ByteData.sublistView(bytes);
    final Float32List hidden = Float32List(bytes.length ~/ 4);
    for (var i = 0; i < hidden.length; i++) {
      hidden[i] = view.getFloat32(i * 4, Endian.little);
    }
    return hidden;
  }
}
