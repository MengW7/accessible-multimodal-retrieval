import 'dart:convert';
import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:core_storage/core_storage.dart';
import 'package:path/path.dart' as p;

import 'probe_common.dart';

/// 对已经建好的库做一次或一批查询。
///
/// ```text
/// dart run packages/core_pipeline/bin/search_probe.dart --db <file> --query "..." --top 10
/// ```
Future<void> main(List<String> args) async {
  final ProbeArgs flags;
  try {
    flags = parseProbeArgs(
      args,
      valued: const <String>{
        'db',
        'query',
        'top',
        'arm',
        'arms',
        'extension',
        'path-prefix',
        'modified-after',
        'modality',
        'evidence',
        'split',
      },
      flags: const <String>{'json', 'bench'},
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _usage();
    exitCode = 64;
    return;
  }

  final String? databasePath = flags.optional('db');
  final bool bench = flags.has('bench') || flags.optional('evidence') != null;
  final List<String> queries = flags.many('query');
  if (databasePath == null || databasePath.isEmpty || (!bench && queries.isEmpty)) {
    stderr.writeln('Pass --db and --query, or --db and --evidence.');
    _usage();
    exitCode = 64;
    return;
  }
  if (bench && queries.isNotEmpty) {
    stderr.writeln('Pass either --query or --evidence, not both.');
    exitCode = 64;
    return;
  }

  SqliteVectorStore? store;
  ProbeRuntime? runtime;
  try {
    final ProbePaths repo = findProbePaths();
    final String db = p.isAbsolute(databasePath)
        ? databasePath
        : p.join(repo.root, databasePath);
    final OpenedStore opened = openStore(const SystemSqliteLibraryLocator(), db);
    store = opened.store;
    if (store == null) {
      stderr.writeln(opened.failure?.message ?? 'SQLite could not be opened.');
      exitCode = 1;
      return;
    }
    final int topK = flags.optionalInt('top') ?? 10;
    if (topK < 1) {
      stderr.writeln('--top must be positive.');
      exitCode = 64;
      return;
    }
    final SearchFilters? filters = _filters(flags);
    final List<_Arm> arms = _arms(flags, bench: bench);
    final bool needsEngine = arms.any((_Arm arm) {
      return arm.channels.contains(SearchChannel.documentText) ||
          arm.channels.contains(SearchChannel.clipShared);
    });
    if (needsEngine) {
      requireProbeFiles(repo);
      runtime = openProbeRuntime(repo);
    }
    final DefaultRetriever retriever = DefaultRetriever(
      store: store,
      encoder: QueryEncoder(
        runtime?.engine ?? const _UnusedEngine(),
      ),
    );
    // 探针经由 SearchPipeline 调用，与 W5 将要使用的入口是同一条链。
    // 分路与融合的计时仍来自 retriever 自己的 last*Ms。
    final SearchPipeline pipeline = DefaultSearchPipeline(retriever);
    if (bench) {
      await _bench(
        flags: flags,
        repo: repo,
        pipeline: pipeline,
        retriever: retriever,
        arms: arms,
        topK: topK,
        filters: filters,
      );
      return;
    }
    final _Arm arm = arms.single;
    final bool asJson = flags.has('json');
    final List<Map<String, Object?>> payload = <Map<String, Object?>>[];
    for (final String query in queries) {
      final List<SearchResult> hits = await pipeline.search(
        query,
        topK: topK,
        filters: filters,
        channels: arm.channels,
        expandNeighborhood: arm.expand,
      );
      if (asJson) {
        payload.add(_queryJson(query, arm, retriever, hits));
      } else {
        _writeHuman(query, arm, retriever, hits);
      }
    }
    if (asJson) {
      stdout.writeln(jsonEncode(payload.length == 1 ? payload.single : payload));
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on ArgumentError catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    await runtime?.close();
    store?.close();
  }
}

Future<void> _bench({
  required ProbeArgs flags,
  required ProbePaths repo,
  required SearchPipeline pipeline,
  required DefaultRetriever retriever,
  required List<_Arm> arms,
  required int topK,
  required SearchFilters? filters,
}) async {
  final String evidencePath = flags.require('evidence');
  final String resolved = p.isAbsolute(evidencePath)
      ? evidencePath
      : p.join(repo.root, evidencePath);
  final String split = flags.optional('split') ?? 'all';
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  for (final String line in File(resolved).readAsLinesSync()) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final Object? decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?>) {
      rows.add(decoded);
    } else if (decoded is Map) {
      rows.add(decoded.map((Object? key, Object? value) {
        return MapEntry<String, Object?>(key.toString(), value);
      }));
    }
  }
  for (final Map<String, Object?> row in rows) {
    final String rowSplit = row['split']?.toString() ?? '';
    if (split != 'all' && rowSplit != split) {
      continue;
    }
    final String id = row['id']?.toString() ?? '';
    final String question = row['question']?.toString() ?? '';
    if (question.trim().isEmpty) {
      throw FormatException('Evidence $id has an empty question.');
    }
    for (final _Arm arm in arms) {
      final List<SearchResult> hits = await pipeline.search(
        question,
        topK: topK,
        filters: filters,
        channels: arm.channels,
        expandNeighborhood: arm.expand,
      );
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'split': rowSplit,
          'arm': arm.name,
          'question': question,
          'encodeMs': retriever.lastEncodeMs,
          'storeMs': retriever.lastStoreMs,
          'fuseMs': retriever.lastFuseMs,
          'hits': <Map<String, Object?>>[
            for (var index = 0; index < hits.length; index++)
              _hitJson(index + 1, hits[index], includeSnippet: arm.expand),
          ],
        }),
      );
    }
  }
}

void _usage() {
  stderr.writeln(
    'Usage: dart run packages/core_pipeline/bin/search_probe.dart '
    '--db <sqlite> --query "..." [--top 10] [--json] [--arm A4]',
  );
}

SearchFilters? _filters(ProbeArgs flags) {
  final List<String> extensions = flags.many('extension');
  final String? prefix = flags.optional('path-prefix');
  final String? modified = flags.optional('modified-after');
  final String? modalityName = flags.optional('modality');
  if (extensions.isEmpty &&
      (prefix == null || prefix.isEmpty) &&
      (modified == null || modified.isEmpty) &&
      (modalityName == null || modalityName.isEmpty)) {
    return null;
  }
  Modality? modality;
  if (modalityName != null && modalityName.isNotEmpty) {
    modality = Modality.values.byName(modalityName);
  }
  return SearchFilters(
    extensions: extensions.isEmpty
        ? null
        : extensions.map((String item) => item.toLowerCase()).toSet(),
    pathPrefix: prefix,
    modifiedAfter: modified == null || modified.isEmpty
        ? null
        : DateTime.parse(modified),
    modality: modality,
  );
}

List<_Arm> _arms(ProbeArgs flags, {required bool bench}) {
  final String? one = flags.optional('arm');
  final String? many = flags.optional('arms');
  if (one != null && many != null) {
    throw const FormatException('Pass --arm or --arms, not both.');
  }
  if (!bench && many != null) {
    throw const FormatException('--arms is only for --evidence.');
  }
  final String raw = many ?? one ?? 'A5';
  return <_Arm>[
    for (final String name in raw.split(','))
      if (name.trim().isNotEmpty) _armByName(name.trim()),
  ];
}

_Arm _armByName(String name) {
  return switch (name) {
    'A0' => const _Arm('A0', <SearchChannel>{SearchChannel.keyword}, false),
    'A1' => const _Arm(
      'A1',
      <SearchChannel>{SearchChannel.documentText},
      false,
    ),
    'A2' => const _Arm('A2', <SearchChannel>{SearchChannel.clipShared}, false),
    'A3' => const _Arm(
      'A3',
      <SearchChannel>{SearchChannel.documentText, SearchChannel.keyword},
      false,
    ),
    'A4' => const _Arm('A4', <SearchChannel>{
      SearchChannel.documentText,
      SearchChannel.keyword,
      SearchChannel.clipShared,
    }, false),
    'A5' => const _Arm('A5', <SearchChannel>{
      SearchChannel.documentText,
      SearchChannel.keyword,
      SearchChannel.clipShared,
    }, true),
    _ => throw FormatException('Unknown arm $name.'),
  };
}

void _writeHuman(
  String query,
  _Arm arm,
  DefaultRetriever retriever,
  List<SearchResult> hits,
) {
  stdout.writeln('query=$query');
  stdout.writeln(
    'arm=${arm.name} expand=${arm.expand} top=${hits.length} '
    'encode_ms=${retriever.lastEncodeMs} store_ms=${retriever.lastStoreMs} '
    'fuse_ms=${retriever.lastFuseMs}',
  );
  if (hits.isEmpty) {
    stdout.writeln('hits=0');
    return;
  }
  for (var index = 0; index < hits.length; index++) {
    final SearchResult hit = hits[index];
    stdout.writeln(
      'rank=${index + 1} score=${hit.score.toStringAsFixed(6)} '
      'key=${hit.documentKey ?? hit.relativePath} '
      'file=${hit.fileName} page=${hit.pageNumber ?? 'null'} '
      'start=${hit.startOffset} end=${hit.endOffset} '
      'channels=${hit.channels.map((SearchChannel item) => item.name).join(',')} '
      'modality=${hit.modality.name}',
    );
    final String snippet = hit.snippet.replaceAll('\n', '\\n');
    stdout.writeln('snippet=$snippet');
  }
}

Map<String, Object?> _queryJson(
  String query,
  _Arm arm,
  DefaultRetriever retriever,
  List<SearchResult> hits,
) {
  return <String, Object?>{
    'query': query,
    'arm': arm.name,
    'expand': arm.expand,
    'encodeMs': retriever.lastEncodeMs,
    'storeMs': retriever.lastStoreMs,
    'fuseMs': retriever.lastFuseMs,
    'hits': <Map<String, Object?>>[
      for (var index = 0; index < hits.length; index++)
        _hitJson(index + 1, hits[index], includeSnippet: arm.expand),
    ],
  };
}

Map<String, Object?> _hitJson(
  int rank,
  SearchResult hit, {
  required bool includeSnippet,
}) {
  final String snippet = hit.snippet.replaceAll('\n', ' ');
  return <String, Object?>{
    'rank': rank,
    'documentKey': hit.documentKey ?? hit.relativePath,
    'relativePath': hit.relativePath,
    'fileName': hit.fileName,
    'pageNumber': hit.pageNumber,
    // Needed by engine/error_analysis.py to tell "this chunk is the gold span"
    // apart from "this chunk is the gold span's immediate neighbour", which the
    // returned snippet also shows.
    'chunkIndex': hit.chunkIndex,
    'startOffset': hit.startOffset,
    'endOffset': hit.endOffset,
    'score': hit.score,
    'channels': <String>[
      for (final SearchChannel channel in hit.channels) channel.name,
    ],
    'modality': hit.modality.name,
    if (includeSnippet)
      'snippet': snippet.length <= 240 ? snippet : snippet.substring(0, 240),
  };
}

final class _Arm {
  const _Arm(this.name, this.channels, this.expand);

  final String name;

  final Set<SearchChannel> channels;

  final bool expand;
}

final class _UnusedEngine implements EmbeddingEngine {
  const _UnusedEngine();

  @override
  Future<EmbeddingVector> embed(
    EmbeddingInput input, {
    CancellationToken? cancel,
  }) {
    throw StateError('This arm does not encode a query.');
  }

  @override
  List<ModelInfo> get models => const <ModelInfo>[];
}
