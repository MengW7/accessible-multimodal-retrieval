import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

final class _FakeProcess implements ProcessRunner {
  _FakeProcess(this._result) : error = null;

  final ProcessRunResult? _result;
  final Exception? error;
  var calls = 0;
  String? requestText;

  _FakeProcess.throws(this.error) : _result = null;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    CancellationToken? cancel,
  }) async {
    calls += 1;
    requestText = File(arguments[1]).readAsStringSync();
    final Exception? thrown = error;
    if (thrown != null) {
      throw thrown;
    }
    return _result!;
  }
}

String _b64(List<double> values) {
  final ByteData data = ByteData(values.length * 4);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return base64Encode(data.buffer.asUint8List());
}

OnnxTensorEmbeddingRuntime _runtime(_FakeProcess process) {
  return OnnxTensorEmbeddingRuntime(
    pythonExecutable: Platform.resolvedExecutable,
    scriptPath: Platform.resolvedExecutable,
    modelPath: Platform.resolvedExecutable,
    processRunner: process,
    outputName: 'image_embeds',
  );
}

Map<String, Tensor> _pixels() {
  return <String, Tensor>{
    'pixel_values': Tensor(
      dtype: TensorDType.float32,
      shape: const <int>[1, 3, 1, 1],
      data: Float32List.fromList(<double>[0.25, 0.5, 0.75]),
    ),
  };
}

void main() {
  test('decodes a little-endian image vector and records the tensor', () async {
    final _FakeProcess process = _FakeProcess(
      ProcessRunResult(
        exitCode: 0,
        stdout: _b64(<double>[1.5, -2]),
        stderr: '',
      ),
    );
    final Float32List values = await _runtime(process).run('vision', _pixels());
    expect(process.calls, 1);
    expect(values, hasLength(2));
    expect(values[0], closeTo(1.5, 1e-6));
    final Object? decoded = jsonDecode(process.requestText!);
    expect(decoded, isA<Map<dynamic, dynamic>>());
    final Map<dynamic, dynamic> request = decoded as Map<dynamic, dynamic>;
    expect(request['output_name'], 'image_embeds');
    final Object? inputs = request['inputs'];
    expect(inputs, isA<Map<dynamic, dynamic>>());
    final Object? pixels = (inputs as Map<dynamic, dynamic>)['pixel_values'];
    expect(pixels, isA<Map<dynamic, dynamic>>());
    expect((pixels as Map<dynamic, dynamic>)['dtype'], 'float32');
  });

  test(
    'a failed start, a timeout, and a bad exit keep their exception types',
    () async {
      await expectLater(
        () => _runtime(
          _FakeProcess.throws(const ProcessStartException('python', 'missing')),
        ).run('vision', _pixels()),
        throwsA(isA<RuntimeUnavailableException>()),
      );
      await expectLater(
        () => _runtime(
          _FakeProcess.throws(
            const ProcessTimeoutException('python', Duration(seconds: 1)),
          ),
        ).run('vision', _pixels()),
        throwsA(isA<EmbeddingTimeoutException>()),
      );
      await expectLater(
        () => _runtime(
          _FakeProcess(
            const ProcessRunResult(exitCode: 1, stdout: '', stderr: 'boom'),
          ),
        ).run('vision', _pixels()),
        throwsA(isA<EmbeddingRuntimeException>()),
      );
    },
  );

  test('stdout that is not base64 is a bad output', () async {
    await expectLater(
      () => _runtime(
        _FakeProcess(
          const ProcessRunResult(exitCode: 0, stdout: 'not-base64', stderr: ''),
        ),
      ).run('vision', _pixels()),
      throwsA(isA<BadOutputException>()),
    );
  });

  test(
    'missing or mistyped tensors are reported before the process starts',
    () async {
      final _FakeProcess process = _FakeProcess(
        const ProcessRunResult(exitCode: 0, stdout: '', stderr: ''),
      );
      final OnnxTensorEmbeddingRuntime runtime = _runtime(process);
      await expectLater(
        () => runtime.run('vision', <String, Tensor>{}),
        throwsA(isA<MissingTensorException>()),
      );
      await expectLater(
        () => runtime.run('vision', <String, Tensor>{
          'input_ids': Tensor(
            dtype: TensorDType.int64,
            shape: const <int>[1],
            data: Uint8List(1),
          ),
        }),
        throwsA(isA<MissingTensorException>()),
      );
      expect(process.calls, 0);
    },
  );

  test('missing files are unavailable', () async {
    final OnnxTensorEmbeddingRuntime runtime = OnnxTensorEmbeddingRuntime(
      pythonExecutable: r'Z:\missing\python.exe',
      scriptPath: r'Z:\missing\script.py',
      modelPath: r'Z:\missing\model.onnx',
      processRunner: _FakeProcess(
        const ProcessRunResult(exitCode: 0, stdout: '', stderr: ''),
      ),
      outputName: 'image_embeds',
    );
    expect(runtime.isAvailable, isFalse);
    await expectLater(
      () => runtime.run('vision', _pixels()),
      throwsA(isA<RuntimeUnavailableException>()),
    );
  });
}
