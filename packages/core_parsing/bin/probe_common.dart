import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;

/// Reads `--path <value>` or `--path=<value>` from [args].
String requirePath(List<String> args) {
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
    throw const FormatException('Pass --path <file-or-directory>.');
  }
  return path;
}

/// Resolves [input] against the current directory, then walks up to the repo.
String resolveExisting(String input) {
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

/// `tools/tika-app` found by walking up from the current directory.
String findTikaHome() {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final String home = p.join(dir.path, 'tools', 'tika-app');
    if (Directory(home).existsSync()) {
      return home;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return p.join(Directory.current.path, 'tools', 'tika-app');
}

/// TXT, DOCX, PDF (Tika CLI), and JPEG/PNG.
StandardParserRegistry standardRegistry() {
  return StandardParserRegistry(<DocumentParser>[
    TxtParser(),
    const DocxParser(),
    PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: findTikaHome(),
      ),
    ),
    const ImageParser(),
  ]);
}

bool _exists(String path) {
  return File(path).existsSync() || Directory(path).existsSync();
}

const List<String> _stageOrder = <String>[
  'stat',
  'process_start',
  'process_wait',
  'stream_drain',
  'xhtml_split',
  'text_fallback',
  'assemble',
];

/// One probe line for `attributes['stageMs']`, or null when it is absent.
String? formatStageLine(Object? stages) {
  if (stages is! Map) {
    return null;
  }
  final List<String> parts = <String>[];
  final Set<Object?> seen = <Object?>{};
  for (final String key in _stageOrder) {
    if (!stages.containsKey(key)) {
      continue;
    }
    parts.add('$key=${stages[key]}');
    seen.add(key);
  }
  for (final MapEntry<Object?, Object?> entry in stages.entries) {
    if (seen.contains(entry.key)) {
      continue;
    }
    parts.add('${entry.key}=${entry.value}');
  }
  if (parts.isEmpty) {
    return null;
  }
  return '  stages  ${parts.join('  ')}';
}
