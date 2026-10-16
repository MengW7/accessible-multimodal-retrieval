@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 从当前目录向上找仓库文件。默认套件不走这里。
String _repoFile(String relative) {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final String candidate = p.join(dir.path, relative);
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  throw StateError('Could not find $relative from ${Directory.current.path}');
}

void main() {
  test('one coco image matches the pillow vision vector', () async {
    final String python = _repoFile('engine/.venv/Scripts/python.exe');
    final String imagePath = _repoFile('datasets/coco/val_sample/images/000000397133.jpg');
    final String modelPath = _repoFile('models/raw/image/mobileclip-s0/onnx/vision_model.onnx');
    final DecodedImage decoded = const PackageImageDecoder().decodeFile(imagePath);
    final OnnxTensorEmbeddingRuntime runtime = OnnxTensorEmbeddingRuntime(
      pythonExecutable: python,
      scriptPath: _repoFile('engine/embed_onnx_output.py'),
      modelPath: modelPath,
      processRunner: const IoProcessRunner(),
      outputName: 'image_embeds',
      timeout: const Duration(minutes: 3),
    );
    expect(runtime.isAvailable, isTrue);
    final ImageEmbedder embedder = ImageEmbedder(model: clipVisionModel, runtime: runtime);
    final Stopwatch watch = Stopwatch()..start();
    final EmbeddingVector vector = await embedder.embed(
      bytes: decoded.rgb24,
      width: decoded.width,
      height: decoded.height,
    );
    watch.stop();

    expect(vector.dim, 512);
    expect(vector.values, hasLength(512));
    expect(vector.space, EmbeddingSpace.clipShared);
    expect(vector.modelId, clipVisionModel.modelId);
    expect(vector.normalized, isTrue);
    final double norm = _norm(vector.values);
    expect(norm, closeTo(1, 1e-5));

    final Float32List reference = await _reference(python, imagePath, modelPath);
    expect(reference, hasLength(512));
    final double score = _cosine(vector.values, reference);
    expect(score, greaterThanOrEqualTo(0.999), reason: 'cosine $score');

    final StringBuffer log = StringBuffer()
      ..writeln('path=$imagePath')
      ..writeln('dim=${vector.dim}')
      ..writeln('space=${vector.space.name}')
      ..writeln('model=${vector.modelId}')
      ..writeln('normalized=${vector.normalized}')
      ..writeln('l2=${norm.toStringAsFixed(6)}')
      ..writeln('finite=1')
      ..writeln('values_head=${vector.values.take(3).map((double v) => v.toStringAsFixed(6)).join(',')}')
      ..writeln('cosine_vs_pillow=${score.toStringAsFixed(6)}')
      ..writeln('total_ms=${watch.elapsedMilliseconds}')
      ..writeln('total_ms_includes=process_start_and_model_load')
      ..writeln('gate=pass');
    await _writeLog('image_coco_vector.txt', log.toString());
  }, timeout: const Timeout(Duration(minutes: 5)));
}

double _norm(List<double> values) {
  var square = 0.0;
  for (final double value in values) {
    expect(value.isFinite, isTrue);
    square += value * value;
  }
  return math.sqrt(square);
}

double _cosine(List<double> left, List<double> right) {
  var dot = 0.0;
  var leftSquare = 0.0;
  var rightSquare = 0.0;
  for (var i = 0; i < left.length; i++) {
    dot += left[i] * right[i];
    leftSquare += left[i] * left[i];
    rightSquare += right[i] * right[i];
  }
  return dot / (math.sqrt(leftSquare) * math.sqrt(rightSquare));
}

Future<Float32List> _reference(String python, String imagePath, String modelPath) async {
  final ProcessRunResult result = await const IoProcessRunner().run(
    python,
    <String>[
      _repoFile('engine/embed_onnx_output.py'),
      '--reference-image',
      imagePath,
      modelPath,
    ],
    environment: <String, String>{
      ...Platform.environment,
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUNBUFFERED': '1',
    },
    timeout: const Duration(minutes: 3),
  );
  if (!result.isSuccess) {
    throw StateError('embed_onnx_output.py exited ${result.exitCode}: ${result.stderr}');
  }
  final Uint8List bytes = base64Decode(result.stdout.trim());
  final ByteData view = ByteData.sublistView(bytes);
  final Float32List values = Float32List(bytes.length ~/ 4);
  for (var i = 0; i < values.length; i++) {
    values[i] = view.getFloat32(i * 4, Endian.little);
  }
  return values;
}

Future<void> _writeLog(String name, String text) async {
  final Directory dir = Directory(_repoFile('reports/week3/logs'));
  await File(p.join(dir.path, name)).writeAsString(text);
}
