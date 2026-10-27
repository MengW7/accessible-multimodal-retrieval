import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('a split frame is reassembled', () {
    final Uint8List frame = encodeFrame(<String, Object?>{'id': 7, 'ok': true});
    final FrameBuffer buffer = FrameBuffer()..add(frame.sublist(0, 3));
    expect(buffer.nextPayload(), isNull);
    buffer.add(frame.sublist(3));
    final Uint8List? payload = buffer.nextPayload();
    expect(payload, isNotNull);
    expect(decodePayload(payload!)['id'], 7);
    expect(buffer.nextPayload(), isNull);
  });

  test('bytes after a complete frame stay in the buffer', () {
    final Uint8List first = encodeFrame(<String, Object?>{'id': 1});
    final Uint8List second = encodeFrame(<String, Object?>{'id': 2});
    final FrameBuffer buffer = FrameBuffer()..add(<int>[...first, ...second]);
    expect(decodePayload(buffer.nextPayload()!)['id'], 1);
    expect(decodePayload(buffer.nextPayload()!)['id'], 2);
    expect(buffer.nextPayload(), isNull);
  });

  test('a closed server restarts without forgetting completed calls', () async {
    final _Host host = _Host(<Map<String, Object?>?>[
      <String, Object?>{'ok': true, 'b64': _one()},
      null,
      <String, Object?>{'ok': true, 'b64': _one()},
    ]);
    final ProcessEmbedServer server = ProcessEmbedServer(host);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: server,
    );
    expect((await runtime.run('m', _input())).single, 1);
    expect(
      runtime.run('m', _input()),
      throwsA(isA<EmbeddingRuntimeException>()),
    );
    expect(server.completed, 1);
    expect((await runtime.run('m', _input())).single, 1);
    expect(server.completed, 2);
    expect(host.opened, 2);
  });

  test('a structured error keeps the same process', () async {
    final _Host host = _Host(<Map<String, Object?>?>[
      <String, Object?>{
        'ok': false,
        'error': <String, Object?>{'type': 'bad', 'message': 'no output'},
      },
      <String, Object?>{'ok': true, 'b64': _one()},
    ]);
    final ProcessEmbedServer server = ProcessEmbedServer(host);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: server,
    );
    expect(runtime.run('m', _input()), throwsA(isA<EmbeddingRuntimeException>()));
    expect(server.completed, 0);
    await runtime.run('m', _input());
    expect(host.opened, 1);
    expect(server.completed, 1);
  });

  test('a dart subprocess echoes one length-prefixed frame', () async {
    final Directory directory = Directory.systemTemp.createTempSync('embed_echo_');
    addTearDown(() => _deleteWhenReleased(directory));
    final File script = File('${directory.path}${Platform.pathSeparator}main.dart');
    await script.writeAsString(_echo);
    final ProcessEmbedServer server = ProcessEmbedServer(
      _DartHost(Platform.resolvedExecutable, script.path),
    );
    addTearDown(server.close);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: server,
    );
    final Float32List values = await runtime.run('m', _input());
    expect(values.single, 1);
    expect(server.completed, 1);
  });

  test('a response id that does not match drops the connection', () async {
    final _Host host = _Host(
      <Map<String, Object?>?>[
        <String, Object?>{'id': 99, 'ok': true, 'b64': _one()},
      ],
      echoId: false,
    );
    final ProcessEmbedServer server = ProcessEmbedServer(host);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: server,
    );
    await expectLater(
      runtime.run('m', _input()),
      throwsA(isA<EmbeddingRuntimeException>()),
    );
    expect(server.completed, 0);
    expect(host.opened, 1);
  });

  test('an unavailable runtime refuses to run', () async {
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'missing.onnx',
      outputName: 'last_hidden_state',
      server: ProcessEmbedServer(_Host(<Map<String, Object?>?>[])),
      available: false,
    );
    expect(runtime.isAvailable, isFalse);
    await expectLater(
      runtime.run('m', _input()),
      throwsA(isA<RuntimeUnavailableException>()),
    );
  });

  test('float32 int32 and uint8 inputs keep their dtypes', () async {
    final _Host host = _Host(<Map<String, Object?>?>[
      <String, Object?>{'ok': true, 'b64': _one()},
      <String, Object?>{'ok': true, 'b64': _one()},
      <String, Object?>{'ok': true, 'b64': _one()},
    ]);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: ProcessEmbedServer(host),
    );
    expect(
      (await runtime.run('m', <String, Tensor>{
        'mask': Tensor(
          dtype: TensorDType.float32,
          shape: const <int>[1],
          data: Float32List.fromList(<double>[0.5]),
        ),
      })).single,
      1,
    );
    await runtime.run('m', <String, Tensor>{
      'ids': Tensor(
        dtype: TensorDType.int32,
        shape: const <int>[1],
        data: Int32List.fromList(<int>[3]),
      ),
    });
    await runtime.run('m', <String, Tensor>{
      'pixels': Tensor(
        dtype: TensorDType.uint8,
        shape: const <int>[1],
        data: Uint8List.fromList(<int>[9]),
      ),
    });
    expect(_dtype(host.sent[0], 'mask'), 'float32');
    expect(_dtype(host.sent[1], 'ids'), 'int32');
    expect(_dtype(host.sent[2], 'pixels'), 'uint8');
  });

  test('a tensor whose bytes do not match its dtype is rejected', () async {
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: ProcessEmbedServer(_Host(<Map<String, Object?>?>[])),
    );
    await expectLater(
      runtime.run('m', <String, Tensor>{
        'mask': Tensor(
          dtype: TensorDType.float32,
          shape: const <int>[1],
          data: Int32List.fromList(<int>[1]),
        ),
      }),
      throwsA(isA<MissingTensorException>()),
    );
    await expectLater(
      runtime.run('m', <String, Tensor>{
        'ids': Tensor(
          dtype: TensorDType.int64,
          shape: const <int>[1],
          data: Int32List.fromList(<int>[1]),
        ),
      }),
      throwsA(isA<MissingTensorException>()),
    );
    await expectLater(
      runtime.run('m', <String, Tensor>{
        'ids': Tensor(
          dtype: TensorDType.int32,
          shape: const <int>[1],
          data: Int64List.fromList(<int>[1]),
        ),
      }),
      throwsA(isA<MissingTensorException>()),
    );
    await expectLater(
      runtime.run('m', <String, Tensor>{
        'pixels': Tensor(
          dtype: TensorDType.uint8,
          shape: const <int>[1],
          data: Int32List.fromList(<int>[1]),
        ),
      }),
      throwsA(isA<MissingTensorException>()),
    );
  });

  test('a bad vector payload is a bad output', () async {
    final _Host host = _Host(<Map<String, Object?>?>[
      <String, Object?>{'ok': true, 'b64': '***'},
      <String, Object?>{'ok': true, 'b64': base64Encode(Uint8List(2))},
    ]);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime(
      modelPath: 'model.onnx',
      outputName: 'last_hidden_state',
      server: ProcessEmbedServer(host),
    );
    await expectLater(
      runtime.run('m', _input()),
      throwsA(isA<BadOutputException>()),
    );
    await expectLater(
      runtime.run('m', _input()),
      throwsA(isA<BadOutputException>()),
    );
  });

  // 这条用例断言真实的产物存在：`.venv`、`embed_server.py` 和 470MB 的权重都被
  // gitignore。默认套件不读它们（计划附录 B），所以在用例级打 integration 标签，
  // 与其他文件里 `test(..., tags: 'integration')` 的写法一致。
  // 同文件的其余用例都注入假 host，留在默认套件里。
  test('the python factory only checks that the three files exist', () {
    final Directory root = _repoRoot();
    final String python = p.join(
      root.path,
      'engine',
      '.venv',
      'Scripts',
      'python.exe',
    );
    final String script = p.join(root.path, 'engine', 'embed_server.py');
    final String model = p.join(
      root.path,
      'models',
      'raw',
      'text',
      'paraphrase-multilingual-MiniLM-L12-v2',
      'onnx',
      'model.onnx',
    );
    expect(File(python).existsSync(), isTrue, reason: python);
    expect(File(script).existsSync(), isTrue, reason: script);
    expect(File(model).existsSync(), isTrue, reason: model);
    final PersistentOnnxRuntime runtime = PersistentOnnxRuntime.python(
      pythonExecutable: python,
      scriptPath: script,
      modelPath: model,
      outputName: 'last_hidden_state',
    );
    expect(runtime.isAvailable, isTrue);
    expect(runtime.server.completed, 0);
  }, tags: 'integration');
}

String _dtype(Map<String, Object?> request, String name) {
  final Object? inputs = request['inputs'];
  expect(inputs, isA<Map<String, Object?>>());
  final Map<String, Object?> inputsMap = inputs! as Map<String, Object?>;
  final Object? tensor = inputsMap[name];
  final Map<String, Object?> tensorMap = tensor! as Map<String, Object?>;
  final Object? dtype = tensorMap['dtype'];
  return dtype! as String;
}

Directory _repoRoot() {
  Directory dir = Directory.current;
  for (var hop = 0; hop < 5; hop++) {
    if (File(p.join(dir.path, 'engine', 'embed_server.py')).existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('repo root not found from ${Directory.current.path}');
}

Map<String, Tensor> _input() {
  return <String, Tensor>{
    'input_ids': Tensor(
      dtype: TensorDType.int64,
      shape: const <int>[1, 1],
      data: Int64List.fromList(<int>[7]),
    ),
  };
}

String _one() {
  final ByteData data = ByteData(4)..setFloat32(0, 1, Endian.little);
  return _b64(data.buffer.asUint8List());
}

String _b64(List<int> bytes) {
  const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final StringBuffer out = StringBuffer();
  for (var index = 0; index < bytes.length; index += 3) {
    final int b0 = bytes[index];
    final int b1 = index + 1 < bytes.length ? bytes[index + 1] : 0;
    final int b2 = index + 2 < bytes.length ? bytes[index + 2] : 0;
    final int triple = (b0 << 16) | (b1 << 8) | b2;
    out.write(alphabet[(triple >> 18) & 63]);
    out.write(alphabet[(triple >> 12) & 63]);
    out.write(index + 1 < bytes.length ? alphabet[(triple >> 6) & 63] : '=');
    out.write(index + 2 < bytes.length ? alphabet[triple & 63] : '=');
  }
  return out.toString();
}

final class _Host implements EmbedServerHost {
  _Host(this.responses, {this.echoId = true});

  final List<Map<String, Object?>?> responses;

  final bool echoId;

  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  int opened = 0;

  int _cursor = 0;

  @override
  Future<EmbedServerConnection> open() async {
    opened += 1;
    return _Connection(this);
  }
}

final class _Connection implements EmbedServerConnection {
  _Connection(this.host);

  final _Host host;

  Map<String, Object?>? last;

  @override
  Future<void> send(Map<String, Object?> message) async {
    last = message;
    host.sent.add(message);
  }

  @override
  Future<Map<String, Object?>?> receive() async {
    final Map<String, Object?>? response = host.responses[host._cursor];
    host._cursor += 1;
    if (response == null) {
      return null;
    }
    if (!host.echoId) {
      return response;
    }
    return <String, Object?>{...response, 'id': last?['id']};
  }

  @override
  Future<void> close() async {}
}

final class _DartHost implements EmbedServerHost {
  const _DartHost(this.executable, this.scriptPath);

  final String executable;

  final String scriptPath;

  @override
  Future<EmbedServerConnection> open() async {
    final Process process = await Process.start(executable, <String>[scriptPath]);
    final ProcessEmbedConnection connection = ProcessEmbedConnection(process);
    connection.listen();
    return connection;
  }
}

Future<void> _deleteWhenReleased(Directory directory) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    if (!directory.existsSync()) {
      return;
    }
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException catch (error) {
      final bool stillOpen = error.osError?.errorCode == 32;
      if (!stillOpen || attempt == 24) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

const String _echo = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> _exact(StreamIterator<int> input, int count) async {
  final Uint8List out = Uint8List(count);
  for (var index = 0; index < count; index++) {
    if (!await input.moveNext()) {
      return null;
    }
    out[index] = input.current;
  }
  return out;
}

Future<void> main() async {
  final StreamIterator<int> input = StreamIterator<int>(
    stdin.expand((List<int> chunk) => chunk),
  );
  while (true) {
    final Uint8List? header = await _exact(input, 4);
    if (header == null) {
      return;
    }
    final int length = ByteData.sublistView(header).getUint32(0, Endian.big);
    final Uint8List? body = await _exact(input, length);
    if (body == null) {
      return;
    }
    final Object? message = jsonDecode(utf8.decode(body));
    final Object? id = message is Map ? message['id'] : null;
    final ByteData data = ByteData(4)..setFloat32(0, 1, Endian.little);
    final List<int> response = utf8.encode(jsonEncode(<String, Object?>{
      'id': id,
      'ok': true,
      'b64': base64Encode(data.buffer.asUint8List()),
      'shape': <int>[1],
    }));
    final ByteData prefix = ByteData(4)..setUint32(0, response.length, Endian.big);
    stdout.add(prefix.buffer.asUint8List());
    stdout.add(response);
    await stdout.flush();
  }
}
''';
