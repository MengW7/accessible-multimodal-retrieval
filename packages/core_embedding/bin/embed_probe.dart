import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;

/// Scans a directory, parses it, chunks text, and prints embedding heads.
///
/// Each vector line is one [EmbeddingRecord]: outcome, dimension, call time,
/// and the first three components. Call time includes process start and model
/// load. A missing path is a usage error. A directory that exists but cannot
/// be listed becomes a report line.
Future<void> main(List<String> args) async {
  final String requested;
  try {
    requested = _requirePath(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _usage();
    exitCode = 64;
    return;
  }

  final String resolved;
  try {
    resolved = _resolveExisting(requested);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final FileSystemEntityType type = await FileSystemEntity.type(resolved);
  if (type != FileSystemEntityType.directory) {
    stderr.writeln('Pass a directory, not a file: $resolved');
    _usage();
    exitCode = 64;
    return;
  }

  final String root;
  try {
    root = _findRepoRoot();
    _requireRuntime(root);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  final IngestionReport ingestion = await IngestionService(
    registry: _standardRegistry(root),
    metadata: FileMetadataExtractor(),
  ).ingestDirectory(resolved);

  final UnigramTokenizer textTokenizer = UnigramTokenizer.fromFile(
    _textTokenizer(root),
  );
  final _TimingEngine timing = _TimingEngine(_engine(root, textTokenizer));
  final EmbeddingReport embedded = await DefaultEmbeddingService(
    engine: timing,
    chunker: CascadeTextChunker(
      countTokens: (String text) => textTokenizer.encode(text).length,
    ),
  ).embedAll(
    ingestion,
    onProgress: (EmbeddingProgress progress) {
      stderr.writeln(
        'progress ${progress.processed}/${progress.total} '
        '${progress.currentId ?? ''}',
      );
    },
  );

  stdout.writeln('root: ${ingestion.rootPath}');
  stdout.writeln('embed_ms_includes=process_start_and_model_load');
  stdout.writeln(
    'text_model=${documentTextModel.modelId}  '
    'image_model=${clipVisionModel.modelId}',
  );
  stdout.writeln(
    'ingest_total: ${ingestion.total}  ingest_ok: ${ingestion.succeeded}  '
    'ingest_partial: ${ingestion.partial}  ingest_skipped: ${ingestion.skipped}  '
    'ingest_failed: ${ingestion.failed}  '
    'ingest_cancelled: ${ingestion.cancelled}  '
    'ingest_ms: ${ingestion.duration.inMilliseconds}',
  );
  stdout.writeln(
    'embed_total: ${embedded.total}  embed_ok: ${embedded.succeeded}  '
    'embed_failed: ${embedded.failed}  embed_cancelled: ${embedded.cancelled}  '
    'embed_ms: ${embedded.duration.inMilliseconds}  '
    'embed_calls: ${timing.callMs.length}',
  );

  final List<int?> lineMs = _lineTimes(embedded.records, timing.callMs);
  for (var index = 0; index < embedded.records.length; index++) {
    stdout.writeln(_recordLine(embedded.records[index], lineMs[index]));
  }

  if (ingestion.failed > 0 ||
      ingestion.cancelled ||
      embedded.failed > 0 ||
      embedded.cancelled) {
    exitCode = 1;
  }
}

void _usage() {
  stderr.writeln(
    'Usage: dart run packages/core_embedding/bin/embed_probe.dart '
    '--path <directory>',
  );
}

String _requirePath(List<String> args) {
  String? path;
  for (var index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (arg == '--path') {
      if (index + 1 >= args.length) {
        throw const FormatException('Missing value for --path.');
      }
      path = args[++index];
      continue;
    }
    if (arg.startsWith('--path=')) {
      path = arg.substring('--path='.length);
      continue;
    }
    throw FormatException('Unknown argument: $arg');
  }
  if (path == null || path.isEmpty) {
    throw const FormatException('Pass --path <directory>.');
  }
  return path;
}

String _resolveExisting(String input) {
  if (p.isAbsolute(input)) {
    if (_exists(input)) {
      return input;
    }
    throw StateError('Path not found: $input');
  }
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final String candidate = p.join(dir.path, input);
    if (_exists(candidate)) {
      return candidate;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  throw StateError('Path not found: $input');
}

String _findRepoRoot() {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final File marker = File(p.join(dir.path, 'engine', 'embed_text_hidden.py'));
    if (marker.existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  throw StateError(
    'Repo root not found from ${Directory.current.path}. '
    'Run this from the repository.',
  );
}

String _findTikaHome(String root) {
  final String home = p.join(root, 'tools', 'tika-app');
  if (Directory(home).existsSync()) {
    return home;
  }
  return home;
}

StandardParserRegistry _standardRegistry(String root) {
  return StandardParserRegistry(<DocumentParser>[
    TxtParser(),
    const DocxParser(),
    PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: _findTikaHome(root),
      ),
    ),
    const ImageParser(),
  ]);
}

String _python(String root) => p.join(root, 'engine', '.venv', 'Scripts', 'python.exe');

String _textTokenizer(String root) => p.join(
  root,
  'models',
  'raw',
  'text',
  'paraphrase-multilingual-MiniLM-L12-v2',
  'tokenizer.json',
);

String _textModel(String root) => p.join(
  root,
  'models',
  'raw',
  'text',
  'paraphrase-multilingual-MiniLM-L12-v2',
  'onnx',
  'model.onnx',
);

String _visionModel(String root) => p.join(
  root,
  'models',
  'raw',
  'image',
  'mobileclip-s0',
  'onnx',
  'vision_model.onnx',
);

String _clipTextModel(String root) => p.join(
  root,
  'models',
  'raw',
  'image',
  'mobileclip-s0',
  'onnx',
  'text_model.onnx',
);

String _clipTokenizer(String root) =>
    p.join(root, 'models', 'raw', 'image', 'mobileclip-s0', 'tokenizer.json');

void _requireRuntime(String root) {
  final List<String> required = <String>[
    _python(root),
    p.join(root, 'engine', 'embed_text_hidden.py'),
    p.join(root, 'engine', 'embed_onnx_output.py'),
    _textTokenizer(root),
    _textModel(root),
    _visionModel(root),
    _clipTextModel(root),
    _clipTokenizer(root),
    p.join(root, 'tools', 'tika-app'),
  ];
  final List<String> missing = <String>[
    for (final String path in required)
      if (!_exists(path)) path,
  ];
  if (missing.isNotEmpty) {
    throw StateError('ONNX runtime files are missing:\n${missing.join('\n')}');
  }
}

EmbeddingEngine _engine(String root, UnigramTokenizer textTokenizer) {
  const IoProcessRunner runner = IoProcessRunner();
  const Duration timeout = Duration(minutes: 3);
  final String python = _python(root);
  final ClipBpeTokenizer clipTokenizer = ClipBpeTokenizer.fromJsonString(
    File(_clipTokenizer(root)).readAsStringSync(),
  );
  return DefaultEmbeddingEngine(
    text: TextEmbedder(
      model: documentTextModel,
      tokenizer: textTokenizer,
      runtime: OnnxProcessEmbeddingRuntime(
        pythonExecutable: python,
        scriptPath: p.join(root, 'engine', 'embed_text_hidden.py'),
        modelPath: _textModel(root),
        processRunner: runner,
        timeout: timeout,
      ),
    ),
    image: ImageEmbedder(
      model: clipVisionModel,
      runtime: OnnxTensorEmbeddingRuntime(
        pythonExecutable: python,
        scriptPath: p.join(root, 'engine', 'embed_onnx_output.py'),
        modelPath: _visionModel(root),
        processRunner: runner,
        outputName: 'image_embeds',
        timeout: timeout,
      ),
    ),
    clipText: ClipTextEmbedder(
      model: clipTextModel,
      tokenizer: clipTokenizer,
      runtime: OnnxTensorEmbeddingRuntime(
        pythonExecutable: python,
        scriptPath: p.join(root, 'engine', 'embed_onnx_output.py'),
        modelPath: _clipTextModel(root),
        processRunner: runner,
        outputName: 'text_embeds',
        timeout: timeout,
      ),
    ),
  );
}

/// Success lines take the next embed-call time when the counts line up.
///
/// A failure that happens before `embed` (empty text, chunk budget, unreadable
/// image) does not push a time. If the two lists disagree, per-line time is
/// left empty rather than attached to the wrong record.
List<int?> _lineTimes(List<EmbeddingRecord> records, List<int> callMs) {
  final int successes = records.where((EmbeddingRecord record) => record.isSuccess).length;
  final bool zipSuccesses = callMs.length == successes;
  final bool zipAll = callMs.length == records.length;
  final List<int?> times = List<int?>.filled(records.length, null);
  var cursor = 0;
  for (var index = 0; index < records.length; index++) {
    final bool take = zipAll || (zipSuccesses && records[index].isSuccess);
    if (!take) {
      continue;
    }
    times[index] = callMs[cursor];
    cursor += 1;
  }
  return times;
}

String _recordLine(EmbeddingRecord record, int? milliseconds) {
  final StringBuffer line = StringBuffer(record.sourceId.replaceAll('\n', ' '));
  final EmbeddingVector? vector = record.vector;
  if (vector == null) {
    final EmbeddingFailure? failure = record.failure;
    line.write('  failed  kind=${failure?.kind.name ?? 'unknown'}');
    final String? message = failure?.message.replaceAll('\n', ' ');
    if (message != null && message.isNotEmpty) {
      line.write('  $message');
    }
    return line.toString();
  }
  line
    ..write('  ok')
    ..write('  dim=${vector.dim}')
    ..write('  space=${vector.space.name}')
    ..write('  model=${vector.modelId}');
  if (milliseconds != null) {
    line.write('  ms=$milliseconds');
  }
  line.write('  ${_head(vector.values)}');
  return line.toString();
}

String _head(List<double> values) {
  final StringBuffer buffer = StringBuffer();
  final int count = values.length < 3 ? values.length : 3;
  for (var index = 0; index < count; index++) {
    if (index > 0) {
      buffer.write('  ');
    }
    buffer.write('v$index=${values[index].toStringAsFixed(6)}');
  }
  return buffer.toString();
}

bool _exists(String path) {
  return File(path).existsSync() || Directory(path).existsSync();
}

final class _TimingEngine implements EmbeddingEngine {
  _TimingEngine(this._inner);

  final EmbeddingEngine _inner;

  final List<int> callMs = <int>[];

  @override
  List<ModelInfo> get models => _inner.models;

  @override
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      return await _inner.embed(input, cancel: cancel);
    } finally {
      callMs.add(watch.elapsedMilliseconds);
    }
  }
}
