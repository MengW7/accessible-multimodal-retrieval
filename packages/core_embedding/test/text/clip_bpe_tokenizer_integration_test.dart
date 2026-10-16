@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

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

const List<String> _sentences = <String>[
  'a man is in a kitchen making pizzas.',
  'hello',
  'Hello',
  '',
  '!',
  'the apollo 17 crew',
  'hello\nworld',
  'Hello, World!',
  '  spaced  ',
  'cafe\u0301',
  '离线',
];

const Map<String, List<int>> _goldens = <String, List<int>>{
  'a man is in a kitchen making pizzas.': <int>[
    49406, 320, 786, 533, 530, 320, 4485, 1665, 30647, 269, 49407,
  ],
  'hello': <int>[49406, 3306, 49407],
  'Hello': <int>[49406, 3306, 49407],
  '': <int>[49406, 49407],
  '!': <int>[49406, 256, 49407],
  'the apollo 17 crew': <int>[49406, 518, 11554, 272, 278, 3462, 49407],
  'hello\nworld': <int>[49406, 3306, 1002, 49407],
  'Hello, World!': <int>[49406, 3306, 267, 1002, 256, 49407],
  '  spaced  ': <int>[49406, 10336, 538, 49407],
  'cafe\u0301': <int>[49406, 15304, 49407],
  '离线': <int>[49406, 163, 99, 119, 163, 118, 379, 49407],
};

final class _Row {
  const _Row(this.ids, this.tokens);

  final List<int> ids;
  final List<String> tokens;

  static _Row parse(Object? raw) {
    if (raw is! Map) {
      throw StateError('token row is not an object.');
    }
    final Object? ids = raw['ids'];
    final Object? tokens = raw['tokens'];
    if (ids is! List || tokens is! List) {
      throw StateError('token row is missing ids or tokens.');
    }
    return _Row(
      <int>[for (final Object? id in ids) id as int],
      <String>[for (final Object? token in tokens) token as String],
    );
  }
}

Future<ClipBpeTokenizer>? _tokenizer;

Future<ClipBpeTokenizer> _open() {
  return _tokenizer ??= () async {
    final String path = _repoFile('models/raw/image/mobileclip-s0/tokenizer.json');
    return ClipBpeTokenizer.fromJsonString(File(path).readAsStringSync());
  }();
}

void main() {
  test('clip ids match tokenizers without padding', () async {
    final ClipBpeTokenizer tokenizer = await _open();
    final String python = _repoFile('engine/.venv/Scripts/python.exe');
    final String tokenizerPath = _repoFile('models/raw/image/mobileclip-s0/tokenizer.json');
    final List<_Row> pythonRows = await _pythonRows(python, tokenizerPath, _sentences);
    final StringBuffer log = StringBuffer()
      ..writeln('compare=tokenizers-0.23.2')
      ..writeln('tokenizer=mobileclip-s0')
      ..writeln('mode=no_pad')
      ..writeln('sentences=${_sentences.length}');
    for (var i = 0; i < _sentences.length; i++) {
      final String sentence = _sentences[i];
      final TokenEncoding dart = tokenizer.encode(sentence);
      expect(dart.ids, _goldens[sentence], reason: 'golden ${jsonEncode(sentence)}');
      expect(dart.ids, pythonRows[i].ids, reason: 'ids ${jsonEncode(sentence)}');
      expect(dart.tokens, pythonRows[i].tokens, reason: 'tokens ${jsonEncode(sentence)}');
      expect(dart.ids.length, lessThanOrEqualTo(77), reason: jsonEncode(sentence));
      log.writeln(
        'match=1 len=${dart.ids.length} ids=${dart.ids.join(',')} '
        'sentence=${jsonEncode(sentence)}',
      );
    }
    log.writeln('gate=pass');
    await _writeLog('clip_tokenizer_ids.txt', log.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<List<_Row>> _pythonRows(
  String python,
  String tokenizerPath,
  List<String> sentences,
) async {
  final Directory temp = await Directory.systemTemp.createTemp('core_embedding_clip_ids_');
  try {
    final File file = File(p.join(temp.path, 'sentences.json'));
    await file.writeAsString(jsonEncode(sentences));
    final ProcessRunResult result = await const IoProcessRunner().run(
      python,
      <String>[
        _repoFile('engine/dump_token_ids.py'),
        tokenizerPath,
        file.path,
        '--no-truncate',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUNBUFFERED': '1',
      },
      timeout: const Duration(minutes: 2),
    );
    if (!result.isSuccess) {
      throw StateError('dump_token_ids.py exited ${result.exitCode}: ${result.stderr}');
    }
    final Object? decoded = jsonDecode(result.stdout);
    if (decoded is! List || decoded.length != sentences.length) {
      throw StateError('dump_token_ids.py returned an unexpected payload.');
    }
    return <_Row>[for (final Object? row in decoded) _Row.parse(row)];
  } finally {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

Future<void> _writeLog(String name, String text) async {
  final Directory dir = Directory(_repoFile('reports/week3/logs'));
  await File(p.join(dir.path, name)).writeAsString(text);
}
