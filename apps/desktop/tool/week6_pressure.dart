import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:desktop/src/runtime/runtime_session.dart';
import 'package:path/path.dart' as p;

const query = '离线检索';
const sizes = [1000, 5000, 10000];
const repeats = 30;
const samples = ['smoke.txt', 'sample.pdf', 'sample.docx', 'sample.png'];

Future<void> main(List<String> args) async {
  if (args.length != 4 ||
      !['build', 'measure', 'lifecycle'].contains(args[0]) ||
      !args.skip(1).every(p.isAbsolute)) {
    throw ArgumentError(
      'build|measure|lifecycle ABS_REPO ABS_SCRATCH ABS_JSON',
    );
  }
  final [mode, repo, work, report] = args;
  final env = Platform.environment;
  if ((env['AMR_RUNTIME_ROOT'] ?? '').isEmpty ||
      (env['AMR_DEV_ROOT'] ?? '').isNotEmpty) {
    throw StateError('Set only AMR_RUNTIME_ROOT to the native resource root.');
  }
  await Directory(work).create(recursive: true);
  final fixtures = p.join(work, 'fixtures');
  final tiny = p.join(work, 'tiny');
  final image = p.join(work, 'image-only');
  final config = RuntimeConfig.fromEnvironment(
    environment: {...env, 'AMR_DATA_DIR': work},
  );
  RuntimeSession open(
    String name, {
    void Function(String, int?, int)? timing,
  }) => RuntimeSession.open(
    config,
    databasePath: p.join(work, '$name.sqlite'),
    onNativeTiming: timing,
  );
  final output = <String, Object?>{
    'ok': false,
    'mode': mode,
    'cwd': Directory.current.path,
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'query': query,
    'warmRuns': repeats,
  };
  Future<void> save() =>
      File(report)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
  try {
    switch (mode) {
      case 'build':
        check(
          !Directory(fixtures).existsSync(),
          'build requires fresh scratch',
        );
        for (final root in [fixtures, tiny, image]) {
          await Directory(root).create();
        }
        await write(
          p.join(tiny, 'smoke.txt'),
          '离线检索验证：本地内容可以在没有云服务的情况下建立索引。\n',
        );
        for (final name in samples.skip(1)) {
          final f = await File(p.join(repo, 'datasets', 'samples', name))
              .copy(p.join(tiny, name));
          await f.setLastModified(DateTime.utc(2020));
        }
        for (final name in samples) {
          await File(p.join(tiny, name)).copy(p.join(fixtures, name));
        }
        await File(p.join(tiny, 'sample.png'))
            .copy(p.join(image, 'sample.png'));
        await write(p.join(fixtures, 'broken.docx'), 'intentionally invalid');
        final growth = <Map<String, Object?>>[];
        output['growth'] = growth;
        var previous = 0;
        for (final size in sizes) {
          for (final group in ['a', 'b']) {
            await Directory(p.join(fixtures, group)).create();
          }
          for (var i = previous; i < size - 98; i++) {
            final name = i.toString().padLeft(5, '0');
            await write(
              p.join(fixtures, i.isEven ? 'a' : 'b', '$name.txt'),
              '离线检索 样本 $name。项目 ${i % 17}，本地资料类别 ${i % 37}。\n',
            );
          }
          final s = open('growth');
          try {
            final indexed = await timed(() => s.indexing.index(fixtures));
            final r = indexed.$1;
            final stats = await s.store.stats();
            final ingest = s.lastIngestion!;
            check(
              stats.chunks == size &&
                  stats.clipShared == 1 &&
                  r.written == size - 98 - previous + (previous == 0 ? 4 : 0) &&
                  r.failed == 0 &&
                  !r.cancelled &&
                  ingest.failed == 1 &&
                  ingest.failures.single.metadata.fileName == 'broken.docx',
              'growth $size: chunks=${stats.chunks} $ingest written=${r.written}',
            );
            checkDb(s);
            growth.add({
              'size': size,
              'files': ingest.total,
              'documents': stats.documents,
              'textChunks': stats.documentText,
              'imageChunks': stats.clipShared,
              'written': r.written,
              'reused': r.reused,
              'parseFailures': ingest.failed,
              'indexMs': indexed.$2,
            });
          } finally {
            await s.close();
          }
          await File(p.join(work, 'growth.sqlite'))
              .copy(p.join(work, 'scale-$size.sqlite'));
          previous = size - 98;
          stdout.writeln('built $size');
          await save();
        }
      case 'measure':
        final cold = <Map<String, Object?>>[];
        output['cold'] = cold;
        final tag = p.basenameWithoutExtension(report);
        for (var i = 0; i < 5; i++) {
          final load = <String, double>{};
          final forwards = <String, List<double>>{};
          var warm = false;
          final start = Stopwatch()..start();
          final s = open(
            '$tag-cold-$i',
            timing: (path, loadUs, runUs) {
              final name = '${p.basename(p.dirname(path))}/${p.basename(path)}';
              if (loadUs != null) load[name] = loadUs / 1000;
              if (warm) (forwards[name] ??= []).add(runUs / 1000);
            },
          );
          final openMs = ms(start);
          try {
            final indexed = await timed(() => s.indexing.index(tiny));
            check(
              indexed.$1.written == 4 && (await s.store.stats()).chunks == 98,
              'tiny index',
            );
            final first = await timed(() => s.search.search(query, topK: 5));
            cold.add({
              'openMs': openMs,
              'indexMs': indexed.$2,
              'firstSearchMs': first.$2,
              'loadMs': load,
              'sources': sources(first.$1),
            });
            if (i == 4) {
              warm = true;
              cold.last['hot'] = await hot(s, [null], warmups: 0, scanK: 5);
              for (var j = 0; j < repeats; j++) {
                final r = await s.indexing.index(image, force: true);
                check(r.written == 1 && r.failed == 0, 'vision forward');
              }
              cold.last['forwardMs'] = forwards;
            }
          } finally {
            await s.close();
          }
        }
        final runs = <String, Object?>{};
        output['scales'] = runs;
        for (final size in sizes) {
          final s = open('scale-$size');
          try {
            check((await s.store.stats()).chunks == size, 'snapshot $size');
            runs['$size'] = await hot(s, [null, 'a']);
          } finally {
            await s.close();
          }
          stdout.writeln('measured $size');
          await save();
        }
        final tieName = '$tag-ties';
        await File(p.join(work, 'scale-10000.sqlite'))
            .copy(p.join(work, '$tieName.sqlite'));
        final s = open(tieName);
        try {
          final q = unitQuery();
          final blob = ByteData(q.dim * 4)..setFloat32(0, 1, Endian.little);
          s.store.database.execute('UPDATE chunk SET vec=? WHERE space=?', [
            blob.buffer.asUint8List(),
            q.space.name,
          ]);
          output['ties'] = await scan(s, null, 50);
        } finally {
          await s.close();
        }
      case 'lifecycle':
        final original = File(p.join(fixtures, 'a', '00000.txt'));
        final bytes = await original.readAsBytes();
        final mtime = await original.lastModified();
        await File(p.join(work, 'scale-10000.sqlite'))
            .copy(p.join(work, 'lifecycle.sqlite'));
        var s = open('lifecycle');
        try {
          final initial = sources(await s.search.search(query, topK: 5));
          await write(original.path, '离线检索 已更新。维护验证唯一内容。\n');
          try {
            final token = CancellationTokenSource();
            final watch = Stopwatch();
            final r = await s.indexing.index(
              fixtures,
              cancel: token.token,
              onProgress: (progress) {
                if (progress.written == 1 && !token.isCancelled) {
                  watch.start();
                  token.cancel();
                }
              },
            );
            watch.stop();
            check(r.cancelled && r.written == 1, 'cancel after one commit');
            checkDb(s);
            output['cancel'] = {
              'written': r.written,
              'reused': r.reused,
              'requestToReturnMs': ms(watch),
            };
            final changed = sources(await s.search.search(query, topK: 5));
            await s.close();
            s = open('lifecycle');
            check(
              jsonEncode(sources(await s.search.search(query, topK: 5))) ==
                  jsonEncode(changed),
              'reopen changed results',
            );
            check(
              (await s.store.stats()).chunks == 10000,
              'reopen chunk count',
            );
            final reuse = await timed(() => s.indexing.index(fixtures));
            check(
              reuse.$1.reused == 9906 &&
                  reuse.$1.written == 0 &&
                  s.lastIngestion!.failed == 1,
              'resume should reuse committed library',
            );
            output['resume'] = {'reused': reuse.$1.reused, 'ms': reuse.$2};
          } finally {
            await original.writeAsBytes(bytes);
            await original.setLastModified(mtime);
          }
          final restored = await timed(() => s.indexing.index(fixtures));
          check(
            restored.$1.written == 1 && restored.$1.reused == 9905,
            'restore should re-embed one file',
          );
          check(
            jsonEncode(sources(await s.search.search(query, topK: 5))) ==
                jsonEncode(initial),
            'restored top-5 mismatch',
          );
          checkDb(s);
          output['restored'] = {
            'written': restored.$1.written,
            'ms': restored.$2,
          };
          await s.store.clear();
          check(
            (await s.store.stats()).chunks == 0 &&
                (await s.search.search(query, topK: 5)).isEmpty,
            'clear failed',
          );
          checkDb(s);
          output['cleared'] = true;
        } finally {
          await s.close();
        }
    }
    output['ok'] = true;
  } finally {
    output['peakRssBytes'] = ProcessInfo.maxRss;
    await save();
  }
}

Future<void> write(String path, String contents) async {
  final file = await File(path).writeAsString(contents);
  await file.setLastModified(DateTime.utc(2020));
}

void check(bool condition, String context) {
  if (!condition) throw StateError(context);
}

void checkDb(RuntimeSession s) => check(
  s.store.database.select('PRAGMA quick_check').single.columnAt(0) == 'ok',
  'SQLite quick_check',
);

double ms(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

Future<(T, double)> timed<T>(Future<T> Function() call) async {
  final watch = Stopwatch()..start();
  final result = await call();
  return (result, ms(watch));
}

List<Object?> sources(List<SearchResult> hits) => [
  for (final hit in hits)
    [
      hit.relativePath,
      hit.pageNumber,
      hit.startOffset,
      hit.endOffset,
      hit.chunkId,
      hit.channels.map((channel) => channel.name).toList(),
      hit.score,
      hit.snippet,
    ],
];

EmbeddingVector unitQuery() => EmbeddingVector(
  values: Float32List(384)..[0] = 1,
  space: EmbeddingSpace.documentText,
  dim: 384,
  modelId: documentTextModel.modelId,
  normalized: true,
);

Future<Map<String, Object?>> scan(
  RuntimeSession s,
  String? filter,
  int k,
) async {
  final storageFilter = SearchFilters(pathPrefix: filter).toStorageFilter();
  final vector = unitQuery();
  String? signature;
  final times = <double>[];
  for (var i = -3; i < repeats; i++) {
    final measured = await timed(
      () => s.store.search(vector, filter: storageFilter, topK: k),
    );
    final next = jsonEncode([
      for (final hit in measured.$1)
        [
          hit.chunkId,
          hit.relativePath,
          hit.pageNumber,
          hit.startOffset,
          hit.endOffset,
          hit.score,
        ],
    ]);
    signature ??= next;
    check(next == signature && measured.$1.length == k, 'unstable vector scan');
    if (i >= 0) times.add(measured.$2);
  }
  return {'ms': times, 'sources': jsonDecode(signature!)};
}

Future<Map<String, Object?>> hot(
  RuntimeSession s,
  List<String?> filters, {
  int warmups = 3,
  int scanK = 50,
}) async {
  final output = <String, Object?>{};
  final retriever =
      (s.search as DefaultSearchPipeline).retriever as DefaultRetriever;
  for (final filter in filters) {
    final times = <Object?>[];
    String? signature;
    for (var i = -warmups; i < repeats; i++) {
      final hit = await timed(
        () => s.search.search(
          query,
          filters: SearchFilters(pathPrefix: filter),
          topK: 5,
        ),
      );
      final next = jsonEncode(sources(hit.$1));
      signature ??= next;
      check(
        hit.$1.length == 5 && next == signature,
        'unstable pipeline for prefix $filter repeat $i: ${hit.$1.length} hits',
      );
      if (i >= 0) {
        times.add({
          'totalMs': hit.$2,
          'encodeMs': retriever.lastEncodeMs,
          'storeMs': retriever.lastStoreMs,
          'fuseMs': retriever.lastFuseMs,
        });
      }
    }
    output[filter == null ? 'all' : '$filter/'] = {
      'samples': times,
      'sources': jsonDecode(signature!),
      'vector': await scan(s, filter, scanK),
      'rssBytes': ProcessInfo.currentRss,
    };
  }
  return output;
}
