import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:core_storage/core_storage.dart';
import 'package:path/path.dart' as p;

import 'runtime_config.dart';
import 'runtime_diagnostics.dart';

/// Owns SQLite and the persistent embedding process together. Construct and use
/// this only in a worker isolate. No bin/probe imports or stdout parsing.
/// B/C can expose these typed pipelines through a persistent worker protocol
/// with progress and cancellation; the A smoke uses an isolated short session.
final class RuntimeSession {
  RuntimeSession._(
    this.store,
    this.server,
    this.indexing,
    this.search,
    this._source,
  );
  final SqliteVectorStore store;
  final ProcessEmbedServer server;
  final IndexingPipeline indexing;
  final SearchPipeline search;
  final _ReportingSource _source;
  IngestionReport? get lastIngestion => _source.last;

  static RuntimeSession open(
    RuntimeConfig config, {
    String? databasePath,
    void Function(IngestProgress)? onIngestProgress,
    void Function(IngestionReport)? onIngested,
  }) {
    if (!config.development || config.configurationErrors.isNotEmpty) {
      throw StateError('可用的开发运行时尚未配置；生产推理适配器待接通。');
    }
    final opened = openStore(
      const SystemSqliteLibraryLocator(),
      databasePath ?? config.databasePath,
    );
    final store = opened.store;
    if (store == null) {
      throw StateError('${opened.failure?.message} ${opened.failure?.detail}');
    }
    final server = ProcessEmbedServer(
      PythonEmbedServerHost(
        pythonExecutable: config.python,
        scriptPath: config.serverScript,
      ),
    );
    try {
      final tokenizer = UnigramTokenizer.fromFile(config.textTokenizer);
      final clipTokenizer = ClipBpeTokenizer.fromJsonString(
        File(config.clipTokenizer).readAsStringSync(),
      );
      final engine = DefaultEmbeddingEngine(
        text: TextEmbedder(
          model: documentTextModel,
          tokenizer: tokenizer,
          runtime: PersistentOnnxRuntime(
            modelPath: config.textModel,
            outputName: 'last_hidden_state',
            server: server,
          ),
        ),
        image: ImageEmbedder(
          model: clipVisionModel,
          runtime: PersistentOnnxRuntime(
            modelPath: config.imageModel,
            outputName: 'image_embeds',
            server: server,
          ),
        ),
        clipText: ClipTextEmbedder(
          model: clipTextModel,
          tokenizer: clipTokenizer,
          runtime: PersistentOnnxRuntime(
            modelPath: config.clipTextModel,
            outputName: 'text_embeds',
            server: server,
          ),
        ),
      );
      final source = _ReportingSource(
        IngestionService(
          registry: StandardParserRegistry([
            TxtParser(),
            MarkdownParser(),
            const DocxParser(),
            PdfParser(
              textExtractor: TikaCliTextExtractor(
                processRunner: const IoProcessRunner(),
                tikaHome: config.tikaHome,
                javaExecutable: config.javaExecutable,
              ),
            ),
            const ImageParser(),
          ]),
          metadata: FileMetadataExtractor(),
        ),
        onProgress: onIngestProgress,
        onIngested: onIngested,
      );
      final chunker = CascadeTextChunker(
        countTokens: (text) => tokenizer.encode(text).length,
      );
      return RuntimeSession._(
        store,
        server,
        DefaultIndexingPipeline(
          source: source,
          engine: engine,
          store: store,
          chunker: chunker,
          images: const PackageImageDecoder(),
          textModel: documentTextModel,
          imageModel: clipVisionModel,
          chunkerVersion: chunker.chunkerVersion,
          documentKeyOf: (metadata) => metadata.path.replaceAll('\\', '/'),
        ),
        DefaultSearchPipeline(
          DefaultRetriever(store: store, encoder: QueryEncoder(engine)),
        ),
        source,
      );
    } catch (_) {
      // The process is lazy and has not started during construction.
      store.close();
      rethrow;
    }
  }

  Future<void> close() async {
    try {
      await server.close();
    } finally {
      store.close();
    }
  }
}

/// Real inference/parse/index/search evidence, always in a new database. This
/// never clears or re-embeds an existing user or evaluation index.
Future<Map<String, Object?>> verifyRuntime(
  RuntimeConfig config,
  String fixtureDirectory,
) async {
  final watch = Stopwatch()..start();
  final report = await inspectRuntime(config);
  final output = <String, Object?>{'ok': false, 'startup': report.toJson()};
  if (!report.ready) return output;
  RuntimeSession? session;
  try {
    if (!p.isAbsolute(fixtureDirectory) ||
        !Directory(fixtureDirectory).existsSync()) {
      throw ArgumentError(
        'Smoke fixture directory must exist and be absolute.',
      );
    }
    final scratch = await Directory(config.dataDirectory)
        .createTemp('runtime-smoke-');
    final db = p.join(scratch.path, 'smoke.sqlite');
    output['smokeDatabase'] = db;
    session = RuntimeSession.open(config, databasePath: db);
    final indexed = await session.indexing
        .index(fixtureDirectory)
        .timeout(const Duration(minutes: 3));
    final stats = await session.store.stats();
    final hits = await session.search
        .search('离线检索', topK: 5)
        .timeout(const Duration(minutes: 1));
    final ingest = session._source.last!;
    output.addAll({
      'ingestion': ingest.toJson(),
      'index': {
        'written': indexed.written,
        'reused': indexed.reused,
        'failed': indexed.failed,
        'cancelled': indexed.cancelled,
      },
      'stats': {
        'documents': stats.documents,
        'chunks': stats.chunks,
        'documentText': stats.documentText,
        'clipShared': stats.clipShared,
      },
      'search': {
        'query': '离线检索',
        'count': hits.length,
        'files': [
          for (final hit in hits)
            {
              'fileName': hit.fileName,
              'sourcePath': hit.documentKey,
              'pageNumber': hit.pageNumber,
              'startOffset': hit.startOffset,
              'endOffset': hit.endOffset,
              'channels': hit.channels.map((c) => c.name).toList(),
            },
        ],
      },
      'inferenceRequests': session.server.completed,
      'ok':
          ingest.failed == 0 &&
          indexed.failed == 0 &&
          !indexed.cancelled &&
          stats.documentText > 0 &&
          stats.clipShared > 0 &&
          hits.isNotEmpty,
    });
  } catch (error, stack) {
    output['error'] = error.toString();
    output['stack'] = stack.toString();
  } finally {
    await session?.close();
    output['elapsedMs'] = watch.elapsedMilliseconds;
  }
  return output;
}

final class _ReportingSource implements IndexSource {
  _ReportingSource(this.service, {this.onProgress, this.onIngested});
  final IngestionService service;
  final void Function(IngestProgress)? onProgress;
  final void Function(IngestionReport)? onIngested;
  IngestionReport? last;
  @override
  Future<IngestionReport> load(
    String rootPath, {
    CancellationToken? cancel,
  }) async {
    final report = await service.ingestDirectory(
      rootPath,
      cancel: cancel,
      extensions: const {
        '.txt',
        '.md',
        '.pdf',
        '.docx',
        '.jpg',
        '.jpeg',
        '.png',
      },
      onProgress: onProgress,
    );
    last = report;
    onIngested?.call(report);
    return report;
  }
}
