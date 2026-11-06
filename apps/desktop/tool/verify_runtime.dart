import 'dart:convert';
import 'dart:io';

import 'package:desktop/src/runtime/library_smoke.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:desktop/src/runtime/runtime_session.dart';
import 'package:path/path.dart' as p;

/// Run the same runtime and library smoke checks without a desktop window.
Future<void> main(List<String> args) async {
  if (args.length != 3 ||
      !['runtime', 'library', 'restart'].contains(args[0]) ||
      !p.isAbsolute(args[1]) ||
      !p.isAbsolute(args[2]) ||
      (Platform.environment['AMR_DATA_DIR'] ?? '').isEmpty) {
    stderr.writeln(
      'Set AMR_DATA_DIR to a dedicated test directory and pass '
      'runtime|library|restart, absolute fixture directory or prior report, '
      'and absolute output JSON path.',
    );
    exitCode = 64;
    return;
  }
  final config = RuntimeConfig.fromEnvironment();
  final output = <String, Object?>{
    'pid': pid,
    'workingDirectory': Directory.current.path,
    'dataDirectory': config.dataDirectory,
    'mode': config.development ? 'development' : 'release',
  };
  try {
    output.addAll(switch (args[0]) {
      'runtime' => await verifyRuntime(config, args[1]),
      'library' => await verifyLibrary(config, args[1]),
      _ => await _restart(config, args[1]),
    });
  } catch (error, stack) {
    output.addAll({'ok': false, 'error': '$error', 'stack': '$stack'});
  } finally {
    await File(args[2])
        .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
    exitCode = output['ok'] == true ? 0 : 1;
  }
}

Future<Map<String, Object?>> _restart(
  RuntimeConfig config,
  String previous,
) async {
  final first = jsonDecode(await File(previous).readAsString()) as Map;
  final database = first['smokeDatabase'] as String;
  if (first['ok'] != true ||
      first['pid'] == pid ||
      !p.isWithin(config.dataDirectory, database) ||
      !await File(database).exists()) {
    throw StateError(
      'A successful prior process and its isolated index are required.',
    );
  }
  final search = first['search'] as Map;
  final session = RuntimeSession.open(config, databasePath: database);
  try {
    final hits = await session.search.search(
      search['query'] as String,
      topK: 5,
    );
    final sources = [
      for (final hit in hits)
        {
          'fileName': hit.fileName,
          'sourcePath': hit.documentKey,
          'pageNumber': hit.pageNumber,
          'startOffset': hit.startOffset,
          'endOffset': hit.endOffset,
          'channels': hit.channels.map((c) => c.name).toList(),
        },
    ];
    return {
      'ok':
          sources.isNotEmpty &&
          jsonEncode(sources) == jsonEncode(search['files']),
      'firstPid': first['pid'],
      'database': database,
      'sources': sources,
    };
  } finally {
    await session.close();
  }
}
