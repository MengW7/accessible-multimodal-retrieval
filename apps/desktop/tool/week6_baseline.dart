import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:desktop/src/runtime/runtime_diagnostics.dart';
import 'package:desktop/src/runtime/runtime_session.dart';
import 'package:path/path.dart' as p;

const query = '离线检索';
const topK = 5;
const coldRuns = 5;
const warmRuns = 30;

/// Runs without Flutter, the native picker, a viewer or a screenshot.
Future<void> main(List<String> args) async {
  if (args.length != 1 || !p.isAbsolute(args.single)) {
    stderr.writeln('Pass one absolute path for the output JSON.');
    exitCode = 64;
    return;
  }
  final repo = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '../../..'),
  );
  final scratchRoot = await Directory(
    p.join(repo, '.dart_tool', 'week6-baseline'),
  ).create(recursive: true);
  final scratch = await scratchRoot.createTemp('run-');
  final fixture = await Directory(p.join(scratch.path, 'fixtures')).create();
  await File(p.join(fixture.path, 'smoke.txt'))
      .writeAsString('离线检索验证：本地内容可以在没有云服务的情况下建立索引。\n');
  for (final name in ['sample.pdf', 'sample.docx', 'sample.png']) {
    await File(p.join(repo, 'datasets', 'samples', name))
        .copy(p.join(fixture.path, name));
  }
  for (final file in fixture.listSync().whereType<File>()) {
    await file.setLastModified(DateTime.utc(2020, 1, 1));
  }

  RuntimeConfig config({String? root, String? data, String java = 'java'}) =>
      RuntimeConfig.fromEnvironment(
        environment: {
          'AMR_JAVA': java,
          'AMR_DEV_ROOT': ?root,
          'AMR_DATA_DIR': ?data,
          // Exercise Windows default path resolution with isolated user data.
          'LOCALAPPDATA': p.join(scratch.path, 'local-app-data'),
          'HOME': p.join(scratch.path, 'home'),
          'XDG_DATA_HOME': p.join(scratch.path, 'xdg'),
        },
      );

  final cases = <String, Object?>{};
  final output = <String, Object?>{
    'ok': false,
    'workingDirectory': Directory.current.path,
    'fixtureDirectory': fixture.path,
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'runtimeChecks': cases,
  };
  try {
    final badData = await File(p.join(scratch.path, 'not-a-directory'))
        .writeAsString('test fixture');
    for (final entry in {
      'developmentDefaultDataDirectory': config(root: repo),
      'production': config(data: p.join(scratch.path, 'production')),
      'missingResources': config(
        root: p.join(scratch.path, 'missing'),
        data: p.join(scratch.path, 'missing-resources-data'),
      ),
      'missingJava': config(
        root: repo,
        data: p.join(scratch.path, 'missing-java-data'),
        java: p.join(scratch.path, 'missing-java.exe'),
      ),
      'invalidDataDirectory': config(root: repo, data: badData.path),
      'relativeDataOverride': config(root: repo, data: 'relative-index'),
    }.entries) {
      final report = await inspectRuntime(entry.value);
      cases[entry.key] = report.toJson();
      final expectedReady = entry.key == 'developmentDefaultDataDirectory';
      if (report.ready != expectedReady) {
        throw StateError('Unexpected readiness in ${entry.key}.');
      }
    }
    final development = config(
      root: repo,
      data: p.join(scratch.path, 'runtime-smoke'),
    );
    final smoke = await verifyRuntime(development, fixture.path);
    output['runtimeSmoke'] = smoke;
    if (smoke['ok'] != true) throw StateError('Real runtime smoke failed.');

    final samples = <Map<String, Object?>>[];
    output['coldSamples'] = samples;
    final hotSearch = <double>[];
    final hotScan = <double>[];
    final forward = <Map<String, Object?>>[];
    output['warmSearchMs'] = hotSearch;
    output['warmVectorScanMs'] = hotScan;
    output['workerResponses'] = forward;
    String? expectedHits;
    String? expectedVectorHits;
    for (var run = 1; run <= coldRuns; run++) {
      final active = config(
        root: repo,
        data: p.join(scratch.path, 'cold-$run'),
      );
      await Directory(active.dataDirectory).create();
      var stage = 'index';
      final host = _TimedHost(
        PythonEmbedServerHost(
          pythonExecutable: active.python,
          scriptPath: active.serverScript,
        ),
        (response, model) => forward.add({
          'run': run,
          'stage': stage,
          'model': model,
          'forwardMs': response['forward_ms'],
          'sessionLoadMs': response['session_load_ms'],
        }),
      );
      final startup = Stopwatch()..start();
      final session = RuntimeSession.open(active, embedServerHost: host);
      startup.stop();
      try {
        final indexTime = Stopwatch()..start();
        final indexed = await session.indexing.index(fixture.path);
        indexTime.stop();
        final stats = await session.store.stats();
        if (indexed.written != 4 ||
            indexed.failed != 0 ||
            stats.documentText == 0 ||
            stats.clipShared == 0) {
          throw StateError('Unexpected index counts in run $run.');
        }
        stage = 'firstSearch';
        final searchTime = Stopwatch()..start();
        final hits = await session.search.search(query, topK: topK);
        searchTime.stop();
        final sourceSignature = jsonEncode([
          for (final hit in hits)
            [hit.fileName, hit.pageNumber, hit.startOffset, hit.endOffset],
        ]);
        expectedHits ??= sourceSignature;
        if (hits.isEmpty || expectedHits != sourceSignature) {
          throw StateError('Missing or changed results in run $run.');
        }
        samples.add({
          'openMs': _ms(startup),
          'indexMs': _ms(indexTime),
          'firstSearchMs': _ms(searchTime),
          'documents': stats.documents,
          'chunks': stats.chunks,
          'textChunks': stats.documentText,
          'imageChunks': stats.clipShared,
          'sources': jsonDecode(sourceSignature),
          'sqlite': session.store.database
              .select('SELECT sqlite_version()')
              .single
              .columnAt(0),
        });
        if (run != coldRuns) continue;
        stage = 'warmSearch';
        final vector = EmbeddingVector(
          values: Float32List(documentTextModel.dim)..[0] = 1,
          space: EmbeddingSpace.documentText,
          dim: documentTextModel.dim,
          modelId: documentTextModel.modelId,
          normalized: true,
        );
        for (var repeat = 0; repeat < warmRuns; repeat++) {
          final searchWatch = Stopwatch()..start();
          final warm = await session.search.search(query, topK: topK);
          searchWatch.stop();
          hotSearch.add(_ms(searchWatch));
          final signature = jsonEncode([
            for (final hit in warm)
              [hit.fileName, hit.pageNumber, hit.startOffset, hit.endOffset],
          ]);
          if (signature != expectedHits) {
            throw StateError('Warm results changed at repeat $repeat.');
          }
          final scanWatch = Stopwatch()..start();
          final scanned = await session.store.search(vector, topK: topK);
          scanWatch.stop();
          hotScan.add(_ms(scanWatch));
          final scanSignature = jsonEncode(
            scanned.map((h) => h.chunkId).toList(),
          );
          expectedVectorHits ??= scanSignature;
          if (scanned.isEmpty || scanSignature != expectedVectorHits) {
            throw StateError('Vector results changed at repeat $repeat.');
          }
        }
        stage = 'warmImageForward';
        final imageRequest = host.imageRequest;
        if (imageRequest == null) {
          throw StateError('Missing the fixed image inference request.');
        }
        for (var repeat = 0; repeat < warmRuns; repeat++) {
          await session.server.exchange(imageRequest);
        }
      } finally {
        await session.close();
      }
    }
    output.addAll({
      'ok': true,
      'query': query,
      'topK': topK,
      'dartPeakRssBytes': ProcessInfo.maxRss,
      'vectorChunkIds': jsonDecode(expectedVectorHits!),
    });
  } catch (error, stack) {
    output['error'] = error.toString();
    output['stack'] = stack.toString();
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await File(args.single)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
  }
}

double _ms(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

typedef _Sample = void Function(Map<String, Object?> response, Object? model);

final class _TimedHost implements EmbedServerHost {
  _TimedHost(this.delegate, this.record);

  final EmbedServerHost delegate;
  final _Sample record;
  Map<String, Object?>? imageRequest;

  @override
  Future<EmbedServerConnection> open() async =>
      _TimedConnection(await delegate.open(), record, (request) {
        if (request['model_id'] == clipVisionModel.modelId) {
          imageRequest = request;
        }
      });
}

final class _TimedConnection implements EmbedServerConnection {
  _TimedConnection(this.delegate, this.record, this.recordRequest);

  final EmbedServerConnection delegate;
  final _Sample record;
  final void Function(Map<String, Object?>) recordRequest;
  Object? _model;

  @override
  Future<void> send(Map<String, Object?> message) {
    recordRequest(message);
    _model = message['model_id'];
    return delegate.send(message);
  }

  @override
  Future<Map<String, Object?>?> receive() async {
    final response = await delegate.receive();
    if (response?['ok'] == true) record(response!, _model);
    return response;
  }

  @override
  Future<void> close() => delegate.close();
}
