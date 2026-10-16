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
    final List<int> idList = <int>[];
    for (final Object? id in ids) {
      if (id is! int) {
        throw StateError('token id is not an int.');
      }
      idList.add(id);
    }
    final List<String> tokenList = <String>[];
    for (final Object? token in tokens) {
      if (token is! String) {
        throw StateError('token text is not a string.');
      }
      tokenList.add(token);
    }
    return _Row(idList, tokenList);
  }
}

const List<String> _sentences = <String>[
  '离线检索可以在没有网络的电脑上运行。',
  'Offline retrieval runs on a computer without a network.',
  'The Apollo 17 crew left the Moon in December 1972.',
  '这份文档记录了页码和字符偏移。',
  'A man is in a kitchen making pizzas.',
  '',
  ' ',
  '\n\n',
  '\t',
  '\u00A0',
  '\u3000',
  'Hello',
  'hello',
  'HELLO',
  'a',
  '##',
  '<unk>',
  '你好',
  'Hello, world!',
  '  spaced  ',
  'café',
  'ﬁle',
  'ＡＢＣ',
  'ﬁle and Ａ',
  'cafe\u0301',
  '</s>',
  '<s>',
  '<pad>',
  '<mask>',
  ' <pad> ',
  '  <mask>',
  'hello  <mask>',
  '<mask>  next',
  'x<mask>y',
  'hello <unk> world',
  'hello<unk>world',
  'say </s> now',
  '\u0378',
  '\u0378\u0378',
  '\u0378 \u0378',
  '🙂',
  'a\u000Bb',
  'a\u0085b',
  'hello▁world',
];

const Map<String, List<int>> _goldens = <String, List<int>>{
  '离线检索可以在没有网络的电脑上运行。': <int>[
    0, 6, 18542, 9005, 61026, 20615, 54093, 3029, 10294, 43, 45974, 575, 43565, 30, 2,
  ],
  'Offline retrieval runs on a computer without a network.': <int>[
    0, 9791, 2256, 456, 97351, 1405, 127877, 98, 10, 13909, 15490, 10, 33120, 5, 2,
  ],
  'The Apollo 17 crew left the Moon in December 1972.': <int>[
    0, 581, 107184, 729, 172040, 25737, 70, 55583, 23, 14487, 29172, 5, 2,
  ],
  '这份文档记录了页码和字符偏移。': <int>[
    0, 6, 151324, 2564, 59529, 42750, 274, 80238, 39453, 264, 7234, 53853, 21919, 20373, 30, 2,
  ],
  'A man is in a kitchen making pizzas.': <int>[
    0, 62, 332, 83, 23, 10, 98483, 20662, 32960, 7, 5, 2,
  ],
  '': <int>[0, 2],
  'Hello': <int>[0, 35378, 2],
  'hello': <int>[0, 33600, 31, 2],
  'HELLO': <int>[0, 572, 174444, 2],
  'a': <int>[0, 10, 2],
  '##': <int>[0, 173894, 2],
  '<unk>': <int>[0, 3, 2],
  '你好': <int>[0, 6, 124084, 2],
  'Hello, world!': <int>[0, 35378, 4, 8999, 38, 2],
  '  spaced  ': <int>[0, 32628, 71, 2],
  'café': <int>[0, 26216, 2],
  'ﬁle': <int>[0, 11435, 2],
  'ＡＢＣ': <int>[0, 47457, 2],
  'ﬁle and Ａ': <int>[0, 11435, 136, 62, 2],
  'cafe\u0301': <int>[0, 26216, 2],
};

final class _Harness {
  const _Harness(this.tokenizer, this.python, this.tokenizerPath);

  final UnigramTokenizer tokenizer;
  final String python;
  final String tokenizerPath;
}

Future<_Harness>? _harness;

Future<_Harness> _open() {
  return _harness ??= () async {
    final String tokenizerPath = _repoFile(
      'models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json',
    );
    return _Harness(
      UnigramTokenizer.fromFile(tokenizerPath),
      _repoFile('engine/.venv/Scripts/python.exe'),
      tokenizerPath,
    );
  }();
}

void main() {
  test('ids match tokenizers without truncation', () async {
    final _Harness harness = await _open();
    final UnigramTokenizer tokenizer = harness.tokenizer;
    final List<_Row> pythonRows = await _pythonRows(
      harness.python,
      harness.tokenizerPath,
      _sentences,
      noTruncate: true,
    );
    final StringBuffer log = StringBuffer()
      ..writeln('compare=tokenizers-0.23.2')
      ..writeln('mode=no_truncate')
      ..writeln('sentences=${_sentences.length}');
    for (var i = 0; i < _sentences.length; i++) {
      final String sentence = _sentences[i];
      final TokenEncoding dart = tokenizer.encode(sentence);
      expect(dart.ids, pythonRows[i].ids, reason: 'ids ${jsonEncode(sentence)}');
      expect(dart.tokens, pythonRows[i].tokens, reason: 'tokens ${jsonEncode(sentence)}');
      final List<int>? golden = _goldens[sentence];
      if (golden != null) {
        expect(dart.ids, golden, reason: 'golden ${jsonEncode(sentence)}');
      }
      log.writeln(
        'match=1 len=${dart.ids.length} ids=${dart.ids.join(',')} '
        'sentence=${jsonEncode(sentence)}',
      );
    }
    expect(tokenizer.encode('##').tokens, <String>['<s>', '▁##', '</s>']);
    log.writeln('gate=pass');
    await _writeLog('text_tokenizer_ids.txt', log.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('truncateTo 128 matches the tokenizer file default', () async {
    final _Harness harness = await _open();
    final UnigramTokenizer tokenizer = harness.tokenizer;
    final String repeated = 'word ' * 200;
    final String numbered = List<String>.generate(200, (int i) => 'w$i').join(' ');
    final String withMarker =
        'say </s> ${List<String>.generate(160, (int i) => 'w$i').join(' ')}';
    final List<String> sentences = <String>[repeated, numbered, withMarker];
    final List<_Row> full = await _pythonRows(
      harness.python,
      harness.tokenizerPath,
      sentences,
      noTruncate: true,
    );
    final List<_Row> truncated = await _pythonRows(
      harness.python,
      harness.tokenizerPath,
      sentences,
      noTruncate: false,
    );
    final StringBuffer log = StringBuffer()
      ..writeln('compare=tokenizers-0.23.2')
      ..writeln('mode=truncate_128');
    for (var i = 0; i < sentences.length; i++) {
      final TokenEncoding dartFull = tokenizer.encode(sentences[i]);
      final TokenEncoding dartCut = tokenizer.encode(sentences[i], truncateTo: 128);
      expect(dartFull.ids, full[i].ids, reason: 'full $i');
      expect(dartCut.ids, truncated[i].ids, reason: 'cut $i');
      expect(dartCut.tokens, truncated[i].tokens, reason: 'cut tokens $i');
      expect(dartFull.ids.length, greaterThan(128));
      expect(dartCut.ids, hasLength(128));
      expect(dartCut.tokens.last, '</s>');
      expect(dartCut.ids.last, 2);
      log.writeln(
        'index=$i untruncated=${dartFull.ids.length} truncated=128 '
        'tail=${dartCut.tokens.last} head=${dartCut.ids.take(8).join(',')} '
        'match=1',
      );
    }
    log.writeln('gate=pass');
    await _writeLog('text_tokenizer_truncation.txt', log.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the first NQ validation question yields a 384-d vector', () async {
    final _Harness harness = await _open();
    final UnigramTokenizer tokenizer = harness.tokenizer;
    final File nq = File(_repoFile('datasets/nq/validation/nq_open_val50.jsonl'));
    final Object? row = jsonDecode(nq.readAsLinesSync().first);
    if (row is! Map || row['question'] is! String) {
      throw StateError('NQ line 1 has no question.');
    }
    final String question = row['question'] as String;
    expect(question, 'when was the last time anyone was on the moon');

    final List<_Row> pythonRows = await _pythonRows(
      harness.python,
      harness.tokenizerPath,
      <String>[question],
      noTruncate: true,
    );
    final TokenEncoding encoding = tokenizer.encode(question);
    expect(encoding.ids, pythonRows.single.ids);
    expect(encoding.length, lessThanOrEqualTo(128));

    final TextInputResult built = TextInputBuilder(
      tokenizer: tokenizer,
      maxLength: documentTextModel.maxInputLength!,
    ).build(question);
    expect(built, isA<TextInputTensors>());
    final TextInputTensors tensors = built as TextInputTensors;
    expect(tensors.tensors['input_ids']!.shape, <int>[1, 128]);
    final Int64List mask = tensors.tensors['attention_mask']!.data as Int64List;
    expect(mask.where((int bit) => bit == 1).length, encoding.length);

    final String modelPath = _repoFile(
      'models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/onnx/model.onnx',
    );
    final OnnxProcessEmbeddingRuntime runtime = OnnxProcessEmbeddingRuntime(
      pythonExecutable: harness.python,
      scriptPath: _repoFile('engine/embed_text_hidden.py'),
      modelPath: modelPath,
      processRunner: const IoProcessRunner(),
    );
    expect(runtime.isAvailable, isTrue);
    final TextEmbedder embedder = TextEmbedder(
      model: documentTextModel,
      tokenizer: tokenizer,
      runtime: runtime,
    );
    final Stopwatch watch = Stopwatch()..start();
    final EmbeddingVector vector = await embedder.embed(question, chunkId: 'nq-0');
    watch.stop();

    expect(vector.dim, 384);
    expect(vector.values, hasLength(384));
    expect(vector.space, EmbeddingSpace.documentText);
    expect(vector.modelId, documentTextModel.modelId);
    expect(vector.normalized, isTrue);
    expect(vector.chunkId, 'nq-0');
    var square = 0.0;
    for (final double value in vector.values) {
      expect(value.isFinite, isTrue);
      square += value * value;
    }
    final double norm = math.sqrt(square);
    expect(norm, closeTo(1, 1e-5));

    final StringBuffer log = StringBuffer()
      ..writeln('question=$question')
      ..writeln('ids=${encoding.ids.join(',')}')
      ..writeln('tokens=${encoding.length}')
      ..writeln('dim=${vector.dim}')
      ..writeln('space=${vector.space.name}')
      ..writeln('model=${vector.modelId}')
      ..writeln('normalized=${vector.normalized}')
      ..writeln('l2=${norm.toStringAsFixed(6)}')
      ..writeln('finite=1')
      ..writeln('total_ms=${watch.elapsedMilliseconds}')
      ..writeln('total_ms_includes=process_start_and_model_load')
      ..writeln('gate=pass');
    await _writeLog('text_nq_vector.txt', log.toString());
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<List<_Row>> _pythonRows(
  String python,
  String tokenizerPath,
  List<String> sentences, {
  required bool noTruncate,
}) async {
  final Directory temp = await Directory.systemTemp.createTemp('core_embedding_ids_');
  try {
    final File file = File(p.join(temp.path, 'sentences.json'));
    await file.writeAsString(jsonEncode(sentences));
    final ProcessRunResult result = await const IoProcessRunner().run(
      python,
      <String>[
        _repoFile('engine/dump_token_ids.py'),
        tokenizerPath,
        file.path,
        if (noTruncate) '--no-truncate',
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
