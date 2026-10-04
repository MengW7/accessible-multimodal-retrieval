import 'dart:io';

import 'package:core_parsing/core_parsing.dart';

import 'probe_common.dart';

/// Scans one directory and prints the [IngestionReport] counts.
///
/// A directory that exists but cannot be listed becomes a report line.
/// A path that does not exist is a usage error.
Future<void> main(List<String> args) async {
  final String requested;
  try {
    requested = requirePath(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run packages/core_parsing/bin/ingest_probe.dart '
      '--path <directory>',
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

  final FileSystemEntityType type = await FileSystemEntity.type(resolved);
  if (type == FileSystemEntityType.notFound) {
    stderr.writeln('Path not found: $resolved');
    exitCode = 64;
    return;
  }

  final IngestionReport report = await IngestionService(
    registry: standardRegistry(),
    metadata: FileMetadataExtractor(),
  ).ingestDirectory(resolved);
  stdout.writeln('root: ${report.rootPath}');
  stdout.writeln(
    'total: ${report.total}  ok: ${report.succeeded}  '
    'partial: ${report.partial}  skipped: ${report.skipped}  '
    'failed: ${report.failed}  cancelled: ${report.cancelled}  '
    'ms: ${report.duration.inMilliseconds}',
  );
  for (final IngestRecord record in report.records) {
    final StringBuffer line = StringBuffer(record.metadata.relativePath)
      ..write('  ${record.outcome.name}')
      ..write('  ${record.metadata.sizeBytes} B');
    final String? errorMessage = record.metadata.errorMessage;
    if (errorMessage != null) {
      line.write('  $errorMessage');
    }
    stdout.writeln(line);
  }
  if (report.failed > 0 || report.cancelled) {
    exitCode = 1;
  }
}
