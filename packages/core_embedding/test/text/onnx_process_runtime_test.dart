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

Map<String, Tensor> _inputs() {
  return <String, Tensor>{
    'input_ids': Tensor(
      dtype: TensorDType.int64,
      shape: const <int>[1, 2],
      data: Int64List.fromList(<int>[1, 2]),
    ),
    'attention_mask': Tensor(
      dtype: TensorDType.int64,
      shape: const <int>[1, 2],
      data: Int64List.fromList(<int>[1, 0]),
    ),
    'token_type_ids': Tensor(
      dtype: TensorDType.int64,
      shape: const <int>[1, 2],
      data: Int64List.fromList(<int>[0, 0]),
    ),
  };
}

OnnxProcessEmbeddingRuntime _runtime(_FakeProcess process) {
  return OnnxProcessEmbeddingRuntime(
    pythonExecutable: Platform.resolvedExecutable,
    scriptPath: Platform.resolvedExecutable,
    modelPath: Platform.resolvedExecutable,
    processRunner: process,
  );
}

void main() {
  test('decodes a little-endian hidden state from the process', () async {
    final _FakeProcess process = _FakeProcess(
      ProcessRunResult(exitCode: 0, stdout: _b64(<double>[1.5, -2]), stderr: ''),
    );
    final Float32List hidden = await _runtime(process).run('toy', _inputs());
    expect(process.calls, 1);
    expect(hidden, hasLength(2));
    expect(hidden[0], closeTo(1.5, 1e-6));
    expect(hidden[1], closeTo(-2, 1e-6));
  });

  test('a failed start becomes runtime unavailable', () async {
    final _FakeProcess process = _FakeProcess.throws(
      const ProcessStartException('python', 'missing'),
    );
    expect(
      () => _runtime(process).run('toy', _inputs()),
      throwsA(isA<RuntimeUnavailableException>()),
    );
  });

  test('a process timeout becomes an embedding timeout', () async {
    final _FakeProcess process = _FakeProcess.throws(
      const ProcessTimeoutException('python', Duration(seconds: 1)),
    );
    expect(
      () => _runtime(process).run('toy', _inputs()),
      throwsA(isA<EmbeddingTimeoutException>()),
    );
  });

  test('a non-zero exit is a runtime failure', () async {
    final _FakeProcess process = _FakeProcess(
      const ProcessRunResult(exitCode: 1, stdout: '', stderr: 'boom'),
    );
    expect(
      () => _runtime(process).run('toy', _inputs()),
      throwsA(isA<EmbeddingRuntimeException>()),
    );
  });

  test('stdout that is not base64 is a bad output', () async {
    final _FakeProcess process = _FakeProcess(
      const ProcessRunResult(exitCode: 0, stdout: 'not-base64', stderr: ''),
    );
    expect(
      () => _runtime(process).run('toy', _inputs()),
      throwsA(isA<BadOutputException>()),
    );
  });

  test('a missing input tensor is reported', () async {
    final _FakeProcess process = _FakeProcess(
      const ProcessRunResult(exitCode: 0, stdout: '', stderr: ''),
    );
    expect(
      () => _runtime(process).run('toy', <String, Tensor>{}),
      throwsA(isA<MissingTensorException>()),
    );
    expect(process.calls, 0);
  });
}
