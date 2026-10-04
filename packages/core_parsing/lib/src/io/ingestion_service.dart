import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../model/file_metadata.dart';
import '../model/ingestion_report.dart';
import '../model/parse_outcome.dart';
import '../model/parsed_document.dart';
import '../parsing/parser.dart';
import '../parsing/parser_registry.dart';
import '../spi/cancellation_token.dart';
import '../spi/executor.dart';
import 'file_scanner.dart';
import 'metadata_extractor.dart';

/// Scans a directory, parses each file, and returns one [IngestionReport].
///
/// One bad file is recorded and does not stop the batch. A root that is
/// missing, not a directory, or not listable is also one record on that
/// report, not an exception. Cancellation stops before the next file and
/// keeps records that already finished.
class IngestionService {
  IngestionService({
    required this.registry,
    required this.metadata,
    this.scanner = const FileScanner(),
    this.executor = const ImmediateExecutor(),
    this.concurrency = 2,
    this.maxFileSizeBytes = 10 * 1024 * 1024,
  }) : assert(concurrency >= 1, 'concurrency must be >= 1'),
       assert(maxFileSizeBytes > 0, 'maxFileSizeBytes must be positive');

  final ParserRegistry registry;
  final MetadataExtractor metadata;
  final FileScanner scanner;
  final Executor executor;
  final int concurrency;
  final int maxFileSizeBytes;

  Future<IngestionReport> ingestDirectory(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    void Function(IngestProgress)? onProgress,
    CancellationToken? cancel,
  }) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final String root = Directory(rootPath).absolute.path;
    final Stopwatch stopwatch = Stopwatch()..start();

    IngestionReport finish(
      List<IngestRecord> records, {
      required bool cancelled,
    }) {
      return IngestionReport(
        rootPath: root,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        records: List<IngestRecord>.unmodifiable(records),
        cancelled: cancelled,
      );
    }

    if (cancel?.isCancelled ?? false) {
      onProgress?.call(const IngestProgress(processed: 0, total: 0));
      return finish(const <IngestRecord>[], cancelled: true);
    }

    final List<String> files;
    try {
      files = await scanner.scan(
        root,
        extensions: extensions,
        followLinks: followLinks,
        maxDepth: maxDepth,
        cancel: cancel,
      );
    } on CancelledException {
      return finish(const <IngestRecord>[], cancelled: true);
    } on FileSystemException catch (error) {
      return finish(
        <IngestRecord>[_rootFailure(root, error, startedAt)],
        cancelled: false,
      );
    }

    onProgress?.call(
      IngestProgress(
        processed: 0,
        total: files.length,
        elapsed: stopwatch.elapsed,
      ),
    );
    if (files.isEmpty) {
      return finish(const <IngestRecord>[], cancelled: false);
    }

    final Map<String, String> firstPathForHash = <String, String>{};
    final List<IngestRecord?> slots = List<IngestRecord?>.filled(
      files.length,
      null,
    );
    var cursor = 0;
    var completed = 0;
    var stop = false;

    Future<void> worker() async {
      while (!stop) {
        if (cancel?.isCancelled ?? false) {
          stop = true;
          return;
        }
        final int index = cursor;
        if (index >= files.length) {
          return;
        }
        cursor = index + 1;
        final String path = files[index];
        onProgress?.call(
          IngestProgress(
            processed: completed,
            total: files.length,
            currentPath: path,
            elapsed: stopwatch.elapsed,
          ),
        );
        try {
          slots[index] = await executor.run(
            () => _ingestOne(
              path,
              rootPath: root,
              cancel: cancel,
              firstPathForHash: firstPathForHash,
            ),
          );
        } on CancelledException {
          stop = true;
          return;
        }
        completed += 1;
        onProgress?.call(
          IngestProgress(
            processed: completed,
            total: files.length,
            currentPath: path,
            elapsed: stopwatch.elapsed,
          ),
        );
      }
    }

    final int workers = concurrency < files.length ? concurrency : files.length;
    await Future.wait<void>(
      List<Future<void>>.generate(workers, (_) => worker()),
    );
    final List<IngestRecord> records = <IngestRecord>[
      for (final IngestRecord? record in slots) ?record,
    ];
    return finish(records, cancelled: cancel?.isCancelled ?? false);
  }

  /// One record for a root the scanner refused to walk.
  ///
  /// Permission errors are [ParseOutcome.skipped]. Anything else, including
  /// a missing path, is [ParseOutcome.failed].
  IngestRecord _rootFailure(
    String root,
    FileSystemException error,
    DateTime indexedAt,
  ) {
    final int? code = error.osError?.errorCode;
    final ParseFailure failure;
    // Windows ERROR_ACCESS_DENIED is 5. POSIX EPERM is 1 and EACCES is 13.
    if (code == 5 || code == 13 || code == 1) {
      failure = ParseFailure(
        kind: ParseFailureKind.permissionDenied,
        message: 'Permission denied.',
        detail: error.message,
      );
    } else {
      final String message = error.message.trim().isEmpty
          ? 'Unable to scan directory.'
          : error.message;
      failure = ParseFailure(
        kind: ParseFailureKind.unknown,
        message: message,
        detail: error.path,
      );
    }
    final String name = p.basename(root);
    final String fileName = name.isEmpty ? root : name;
    return IngestRecord(
      metadata: FileMetadata(
        id: sha256.convert(utf8.encode(root)).toString(),
        path: root,
        relativePath: fileName,
        fileName: fileName,
        extension: '',
        sizeBytes: 0,
        indexedAt: indexedAt,
        status: failure.outcome,
        errorMessage: failure.message,
      ),
      failure: failure,
    );
  }

  Future<IngestRecord> _ingestOne(
    String absolutePath, {
    required String rootPath,
    required CancellationToken? cancel,
    required Map<String, String> firstPathForHash,
  }) async {
    cancel?.throwIfCancelled();
    final FileMetadata described = await metadata.describe(
      absolutePath,
      rootPath: rootPath,
      maxFileSizeBytes: maxFileSizeBytes,
      cancel: cancel,
    );
    final String? ioError = described.errorMessage;
    if (ioError != null) {
      final ParseFailureKind kind = described.status == ParseOutcome.skipped
          ? ParseFailureKind.permissionDenied
          : ParseFailureKind.unknown;
      return IngestRecord(
        metadata: described,
        failure: ParseFailure(kind: kind, message: ioError),
      );
    }

    final String? hash = described.contentHash;
    if (hash != null) {
      final String? earlier = firstPathForHash[hash];
      if (earlier != null) {
        return IngestRecord(
          metadata: described.copyWith(
            status: ParseOutcome.skipped,
            errorMessage: 'Duplicate content of $earlier.',
          ),
        );
      }
      firstPathForHash[hash] = described.relativePath;
    }

    final DocumentParser? parser = registry.resolveForPath(absolutePath);
    if (parser == null) {
      final ParseFailure failure = ParseFailure(
        kind: ParseFailureKind.unsupportedFormat,
        message: 'No parser registered for "${described.extension}".',
      );
      return IngestRecord(
        metadata: described.copyWith(
          status: failure.outcome,
          errorMessage: failure.message,
        ),
        failure: failure,
      );
    }

    try {
      final ParseResult result = await parser.parse(
        absolutePath,
        cancel: cancel,
      );
      return IngestRecord(
        metadata: described.copyWith(
          parserName: parser.name,
          parserVersion: parser.version,
          parseDurationMs: result.duration.inMilliseconds,
          status: result.outcome,
          errorMessage: result.failure?.message,
          imageAsset: result.document?.imageAsset,
        ),
        document: result.document,
        failure: result.failure,
      );
    } on CancelledException {
      rethrow;
    } on Object catch (error) {
      final ParseFailure failure = ParseFailure(
        kind: ParseFailureKind.unknown,
        message: 'Parser threw ${error.runtimeType}.',
      );
      return IngestRecord(
        metadata: described.copyWith(
          parserName: parser.name,
          parserVersion: parser.version,
          status: failure.outcome,
          errorMessage: failure.message,
        ),
        failure: failure,
      );
    }
  }
}
