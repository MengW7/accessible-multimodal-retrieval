@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

final class _Case {
  const _Case(this.name, this.width, this.height, this.edge);

  final String name;
  final int width;
  final int height;
  final int edge;
}

const List<_Case> _cases = <_Case>[
  _Case('identity', 2, 2, 2),
  _Case('upscale', 2, 2, 4),
  _Case('downscale', 4, 4, 2),
  _Case('non-integer', 3, 3, 2),
  _Case('odd-edge', 5, 5, 3),
  _Case('odd-height-crop', 4, 3, 2),
];

Uint8List _pattern(int width, int height) {
  final Uint8List raw = Uint8List(width * height * 3);
  var index = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      for (var channel = 0; channel < 3; channel++) {
        raw[index] = (x * 17 + y * 29 + channel * 41) & 255;
        index += 1;
      }
    }
  }
  return raw;
}

void main() {
  test('resize shapes match Pillow bilinear on the same RGB', () async {
    final String python = _repoFile('engine/.venv/Scripts/python.exe');
    final Directory temp = await Directory.systemTemp.createTemp(
      'core_embedding_pillow_',
    );
    try {
      final File request = File(p.join(temp.path, 'cases.json'));
      await request.writeAsString(
        jsonEncode(<Map<String, Object>>[
          for (final _Case item in _cases)
            <String, Object>{
              'name': item.name,
              'width': item.width,
              'height': item.height,
              'edge': item.edge,
            },
        ]),
      );
      final ProcessRunResult result = await const IoProcessRunner().run(
        python,
        <String>[_repoFile('engine/pillow_bilinear_ref.py'), request.path],
        environment: <String, String>{
          ...Platform.environment,
          'PYTHONIOENCODING': 'utf-8',
          'PYTHONUNBUFFERED': '1',
        },
        timeout: const Duration(minutes: 1),
      );
      if (!result.isSuccess) {
        throw StateError(
          'pillow_bilinear_ref.py exited ${result.exitCode}: ${result.stderr}',
        );
      }
      final Object? decoded = jsonDecode(result.stdout);
      if (decoded is! Map) {
        throw StateError('Pillow reference is not an object.');
      }
      final Object? pillow = decoded['pillow'];
      final Object? rows = decoded['cases'];
      if (pillow is! String || rows is! List || rows.length != _cases.length) {
        throw StateError('Pillow reference is missing cases.');
      }
      final StringBuffer log = StringBuffer()
        ..writeln('compare=pillow-$pillow bilinear')
        ..writeln('cases=${_cases.length}');
      for (var i = 0; i < _cases.length; i++) {
        final _Case item = _cases[i];
        final Object? row = rows[i];
        if (row is! Map || row['name'] != item.name || row['pixels'] is! List) {
          throw StateError('Pillow row ${item.name} is malformed.');
        }
        final List<Object?> pixels = row['pixels'] as List<Object?>;
        final PreprocessedImage image = ImagePreprocessor(edge: item.edge)
            .preprocess(
              rgb24: _pattern(item.width, item.height),
              width: item.width,
              height: item.height,
            );
        expect(pixels, hasLength(image.pixels.length), reason: item.name);
        var mismatch = 0;
        var maxDelta = 0;
        for (var j = 0; j < pixels.length; j++) {
          final Object? value = pixels[j];
          if (value is! int) {
            throw StateError('Pillow pixel is not an int.');
          }
          final int dartByte = (image.pixels[j] * 255).round();
          final int delta = (dartByte - value).abs();
          if (delta != 0) {
            mismatch += 1;
          }
          if (delta > maxDelta) {
            maxDelta = delta;
          }
        }
        expect(mismatch, 0, reason: '${item.name} maxDelta=$maxDelta');
        log.writeln(
          'name=${item.name} size=${item.width}x${item.height} edge=${item.edge} '
          'mismatch=$mismatch max_delta=$maxDelta',
        );
      }
      log.writeln('gate=pass');
      final Directory logs = Directory(_repoFile('reports/week3/logs'));
      await File(p.join(logs.path, 'image_preprocess_pillow.txt'))
          .writeAsString(log.toString());
    } finally {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    }
  });
}
