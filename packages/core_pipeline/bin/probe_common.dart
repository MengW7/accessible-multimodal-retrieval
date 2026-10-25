import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:path/path.dart' as p;

/// 探针共用的仓库路径和常驻嵌入进程。
final class ProbePaths {
  ProbePaths(this.root);

  final String root;

  String get python => p.join(root, 'engine', '.venv', 'Scripts', 'python.exe');

  String get serverScript => p.join(root, 'engine', 'embed_server.py');

  String get textTokenizer => p.join(
    root,
    'models',
    'raw',
    'text',
    'paraphrase-multilingual-MiniLM-L12-v2',
    'tokenizer.json',
  );

  String get textModel => p.join(
    root,
    'models',
    'raw',
    'text',
    'paraphrase-multilingual-MiniLM-L12-v2',
    'onnx',
    'model.onnx',
  );

  String get visionModel => p.join(
    root,
    'models',
    'raw',
    'image',
    'mobileclip-s0',
    'onnx',
    'vision_model.onnx',
  );

  String get clipTextModel => p.join(
    root,
    'models',
    'raw',
    'image',
    'mobileclip-s0',
    'onnx',
    'text_model.onnx',
  );

  String get clipTokenizer =>
      p.join(root, 'models', 'raw', 'image', 'mobileclip-s0', 'tokenizer.json');

  String get tikaHome => p.join(root, 'tools', 'tika-app');
}

final class ProbeRuntime {
  ProbeRuntime({
    required this.engine,
    required this.tokenizer,
    required this.server,
  });

  final EmbeddingEngine engine;

  final UnigramTokenizer tokenizer;

  final ProcessEmbedServer server;

  Future<void> close() => server.close();
}

/// 命令行参数。`--name value` 与 `--name=value` 都收进 [values]。
final class ProbeArgs {
  ProbeArgs(this.values, this.switches);

  final Map<String, List<String>> values;

  final Set<String> switches;

  bool has(String name) => switches.contains(name) || values.containsKey(name);

  String? optional(String name) {
    final List<String>? found = values[name];
    if (found == null || found.isEmpty) {
      return null;
    }
    return found.last;
  }

  String require(String name) {
    final String? value = optional(name);
    if (value == null || value.isEmpty) {
      throw FormatException('Missing value for --$name.');
    }
    return value;
  }

  List<String> many(String name) => values[name] ?? const <String>[];

  int? optionalInt(String name) {
    final String? value = optional(name);
    if (value == null) {
      return null;
    }
    final int? parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException('--$name needs an integer, got $value.');
    }
    return parsed;
  }
}

ProbeArgs parseProbeArgs(
  List<String> args, {
  required Set<String> valued,
  required Set<String> flags,
}) {
  final Map<String, List<String>> values = <String, List<String>>{};
  final Set<String> switches = <String>{};
  for (var index = 0; index < args.length; index++) {
    final String arg = args[index];
    if (!arg.startsWith('--') || arg.length < 3) {
      throw FormatException('Unknown argument: $arg');
    }
    final String body = arg.substring(2);
    final int equals = body.indexOf('=');
    if (equals >= 0) {
      final String name = body.substring(0, equals);
      final String value = body.substring(equals + 1);
      if (!valued.contains(name)) {
        throw FormatException('Unknown argument: --$name');
      }
      values.putIfAbsent(name, () => <String>[]).add(value);
      continue;
    }
    if (flags.contains(body)) {
      switches.add(body);
      continue;
    }
    if (!valued.contains(body)) {
      throw FormatException('Unknown argument: --$body');
    }
    if (index + 1 >= args.length) {
      throw FormatException('Missing value for --$body.');
    }
    values.putIfAbsent(body, () => <String>[]).add(args[++index]);
  }
  return ProbeArgs(values, switches);
}

ProbePaths findProbePaths() {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final File marker = File(p.join(dir.path, 'engine', 'embed_server.py'));
    if (marker.existsSync()) {
      return ProbePaths(dir.path);
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

void requireProbeFiles(ProbePaths paths) {
  final List<String> required = <String>[
    paths.python,
    paths.serverScript,
    paths.textTokenizer,
    paths.textModel,
    paths.visionModel,
    paths.clipTextModel,
    paths.clipTokenizer,
    paths.tikaHome,
  ];
  final List<String> missing = <String>[
    for (final String path in required)
      if (!File(path).existsSync() && !Directory(path).existsSync()) path,
  ];
  if (missing.isNotEmpty) {
    throw StateError('Runtime files are missing:\n${missing.join('\n')}');
  }
}

String repoPrefix(String repoRoot, String directory) {
  final String relative = p.relative(directory, from: repoRoot);
  final String normalized = relative.replaceAll('\\', '/');
  if (normalized == '.' || normalized.startsWith('..')) {
    return '';
  }
  return normalized;
}

String joinDocumentKey(String prefix, String relativePath) {
  final String relative = relativePath.replaceAll('\\', '/');
  if (prefix.isEmpty) {
    return relative;
  }
  final String head = prefix.endsWith('/')
      ? prefix.substring(0, prefix.length - 1)
      : prefix;
  return '$head/$relative';
}

StandardParserRegistry probeRegistry(ProbePaths paths) {
  return StandardParserRegistry(<DocumentParser>[
    TxtParser(),
    MarkdownParser(),
    const DocxParser(),
    PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: paths.tikaHome,
      ),
    ),
    const ImageParser(),
  ]);
}

const Set<String> probeExtensions = <String>{
  '.txt',
  '.md',
  '.pdf',
  '.docx',
  '.jpg',
  '.jpeg',
  '.png',
};

ProbeRuntime openProbeRuntime(ProbePaths paths) {
  final ProcessEmbedServer server = ProcessEmbedServer(
    PythonEmbedServerHost(
      pythonExecutable: paths.python,
      scriptPath: paths.serverScript,
    ),
  );
  final UnigramTokenizer tokenizer = UnigramTokenizer.fromFile(
    paths.textTokenizer,
  );
  final ClipBpeTokenizer clipTokenizer = ClipBpeTokenizer.fromJsonString(
    File(paths.clipTokenizer).readAsStringSync(),
  );
  final EmbeddingEngine engine = DefaultEmbeddingEngine(
    text: TextEmbedder(
      model: documentTextModel,
      tokenizer: tokenizer,
      runtime: PersistentOnnxRuntime(
        modelPath: paths.textModel,
        outputName: 'last_hidden_state',
        server: server,
      ),
    ),
    image: ImageEmbedder(
      model: clipVisionModel,
      runtime: PersistentOnnxRuntime(
        modelPath: paths.visionModel,
        outputName: 'image_embeds',
        server: server,
      ),
    ),
    clipText: ClipTextEmbedder(
      model: clipTextModel,
      tokenizer: clipTokenizer,
      runtime: PersistentOnnxRuntime(
        modelPath: paths.clipTextModel,
        outputName: 'text_embeds',
        server: server,
      ),
    ),
  );
  return ProbeRuntime(engine: engine, tokenizer: tokenizer, server: server);
}

CascadeTextChunker probeChunker(UnigramTokenizer tokenizer) {
  return CascadeTextChunker(
    countTokens: (String text) => tokenizer.encode(text).length,
  );
}
