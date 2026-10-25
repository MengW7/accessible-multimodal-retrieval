import 'package:core_parsing/core_parsing.dart';
import 'package:core_pipeline/core_pipeline.dart';
import 'package:test/test.dart';

void main() {
  test('a null extension set uses the parser default', () async {
    final _Ingest ingest = _Ingest();
    final CancellationTokenSource source = CancellationTokenSource();
    final IngestionIndexSource adapter = IngestionIndexSource(ingest);
    await adapter.load('root', cancel: source.token);
    expect(ingest.roots, <String>['root']);
    expect(ingest.extensionsSeen.single, defaultIngestExtensions);
    expect(ingest.cancels.single, same(source.token));
  });

  test('an explicit extension set is forwarded', () async {
    final _Ingest ingest = _Ingest();
    final IngestionIndexSource adapter = IngestionIndexSource(
      ingest,
      extensions: const <String>{'.md', '.txt'},
    );
    await adapter.load('docs');
    expect(ingest.roots, <String>['docs']);
    expect(ingest.extensionsSeen.single, <String>{'.md', '.txt'});
    expect(ingest.cancels.single, isNull);
  });
}

final class _Ingest extends IngestionService {
  _Ingest() : super(registry: const _Registry(), metadata: const _Metadata());

  final List<String> roots = <String>[];
  final List<Set<String>> extensionsSeen = <Set<String>>[];
  final List<CancellationToken?> cancels = <CancellationToken?>[];

  @override
  Future<IngestionReport> ingestDirectory(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    void Function(IngestProgress)? onProgress,
    CancellationToken? cancel,
  }) async {
    roots.add(rootPath);
    extensionsSeen.add(extensions);
    cancels.add(cancel);
    final DateTime now = DateTime.utc(2026, 10, 25);
    return IngestionReport(
      rootPath: rootPath,
      startedAt: now,
      finishedAt: now,
      records: const <IngestRecord>[],
    );
  }
}

final class _Registry implements ParserRegistry {
  const _Registry();

  @override
  List<DocumentParser> get parsers => const <DocumentParser>[];

  @override
  Set<String> get supportedExtensions => const <String>{};

  @override
  DocumentParser? resolveForExtension(String extension) => null;

  @override
  DocumentParser? resolveForPath(String absolutePath) => null;

  @override
  bool supports(String absolutePath) => false;
}

final class _Metadata implements MetadataExtractor {
  const _Metadata();

  @override
  Future<FileMetadata> describe(
    String absolutePath, {
    required String rootPath,
    int? maxFileSizeBytes,
    CancellationToken? cancel,
  }) {
    throw UnimplementedError();
  }
}
