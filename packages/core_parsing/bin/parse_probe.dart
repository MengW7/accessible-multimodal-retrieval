import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;

import 'probe_common.dart';

/// Parses one file, or every whitelisted file under a directory.
///
/// PDF time includes one Tika CLI process, and therefore one JVM start.
Future<void> main(List<String> args) async {
  final String requested;
  try {
    requested = requirePath(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run packages/core_parsing/bin/parse_probe.dart '
      '--path <file-or-directory>',
    );
    exitCode = 64;
    return;
  }

  final String resolved;
  try {
    resolved = resolveExisting(requested);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final List<String> files;
  try {
    files = await _inputs(resolved);
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  final StandardParserRegistry registry = standardRegistry();
  var ok = 0;
  var partial = 0;
  var skipped = 0;
  var failed = 0;
  stdout.writeln('root: $resolved');
  for (final String file in files) {
    final ParseResult result = await registry.parse(file);
    switch (result.outcome) {
      case ParseOutcome.ok:
        ok += 1;
      case ParseOutcome.partial:
        partial += 1;
      case ParseOutcome.skipped:
        skipped += 1;
      case ParseOutcome.failed:
        failed += 1;
    }
    _writeFile(file, result);
  }
  stdout.writeln(
    'summary  files=${files.length}  ok=$ok  partial=$partial  '
    'skipped=$skipped  failed=$failed',
  );
  if (failed > 0) {
    exitCode = 1;
  }
}

Future<List<String>> _inputs(String path) async {
  final FileSystemEntityType type = await FileSystemEntity.type(path);
  if (type == FileSystemEntityType.file) {
    return <String>[path];
  }
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException('Path not found', path);
  }
  return const FileScanner().scan(path);
}

void _writeFile(String path, ParseResult result) {
  final ParsedDocument? document = result.document;
  final ImageAsset? image = document?.imageAsset;
  final StringBuffer line = StringBuffer(p.basename(path))
    ..write('  outcome=${result.outcome.name}')
    ..write('  ms=${result.duration.inMilliseconds}');
  if (document != null) {
    line
      ..write('  pages=${document.pageCount}')
      ..write('  chars=${document.charCount}');
  }
  if (image != null) {
    line
      ..write('  format=${image.format}')
      ..write('  size=${image.width}x${image.height}')
      ..write('  color=${image.colorMode}');
  }
  final ParseFailure? failure = result.failure;
  if (failure != null) {
    line.write('  failure=${failure.kind.name}: ${failure.message}');
  }
  stdout.writeln(line);
  final String preview = _preview(document?.fullText ?? '');
  if (preview.isNotEmpty) {
    stdout.writeln('  preview: $preview');
  }
}

String _preview(String text) {
  final String flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) {
    return '';
  }
  if (flat.length <= 120) {
    return flat;
  }
  return '${flat.substring(0, 120)}…';
}
