import 'dart:io';

import 'package:core_parsing/core_parsing.dart';

import '../image/image_decoder.dart';
import '../model/embedding_input.dart';
import '../model/embedding_report.dart';
import '../model/embedding_vector.dart';
import '../model/text_chunk.dart';
import '../spi/embedding_runtime.dart';
import '../text/text_chunker.dart';
import '../text/text_embedder.dart';
import 'embedding_engine.dart';

/// 批量向量化。接口形状对齐 `IngestionService.ingestDirectory`。
///
/// 只消费 [IngestionReport.indexable]。单条失败写进 [EmbeddingReport]，
/// 不中断后面的文件。取消是协作式的，沿用 [CancellationToken]。
abstract interface class EmbeddingService {
  Future<EmbeddingReport> embedAll(
    IngestionReport ingestion, {
    void Function(EmbeddingProgress)? onProgress,
    CancellationToken? cancel,
  });
}

/// 消费 [IngestionReport.indexable]，一条失败不打断后面的文件。
///
/// 文本按 [TextChunker] 切块后走文档空间。图像按原路径重新解码，不读
/// [ParsedDocument] 里不存在的像素。进度按文件计，取消停在下一个文件或下一块。
final class DefaultEmbeddingService implements EmbeddingService {
  DefaultEmbeddingService({
    required this._engine,
    required this._chunker,
    ImageDecoder? images,
    DateTime Function()? clock,
  }) : _images = images ?? const PackageImageDecoder(),
       _clock = clock ?? _utcNow;

  final EmbeddingEngine _engine;

  final TextChunker _chunker;

  final ImageDecoder _images;

  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  Future<EmbeddingReport> embedAll(
    IngestionReport ingestion, {
    void Function(EmbeddingProgress)? onProgress,
    CancellationToken? cancel,
  }) async {
    final DateTime startedAt = _clock();
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<IngestRecord> pending = ingestion.indexable;

    EmbeddingReport finish(List<EmbeddingRecord> records, {required bool cancelled}) {
      return EmbeddingReport(
        startedAt: startedAt,
        finishedAt: _clock(),
        records: List<EmbeddingRecord>.unmodifiable(records),
        cancelled: cancelled,
      );
    }

    if (cancel?.isCancelled ?? false) {
      onProgress?.call(const EmbeddingProgress(processed: 0, total: 0));
      return finish(const <EmbeddingRecord>[], cancelled: true);
    }

    onProgress?.call(
      EmbeddingProgress(processed: 0, total: pending.length, elapsed: stopwatch.elapsed),
    );
    if (pending.isEmpty) {
      return finish(const <EmbeddingRecord>[], cancelled: false);
    }

    final List<EmbeddingRecord> records = <EmbeddingRecord>[];
    var processed = 0;
    for (final IngestRecord record in pending) {
      if (cancel?.isCancelled ?? false) {
        return finish(records, cancelled: true);
      }
      final String sourceId = record.metadata.relativePath;
      onProgress?.call(
        EmbeddingProgress(
          processed: processed,
          total: pending.length,
          currentId: sourceId,
          elapsed: stopwatch.elapsed,
        ),
      );
      try {
        final bool stopped = await _embedOne(
          record,
          records: records,
          cancel: cancel,
        );
        if (stopped) {
          return finish(records, cancelled: true);
        }
      } on CancelledException {
        return finish(records, cancelled: true);
      }
      processed += 1;
      onProgress?.call(
        EmbeddingProgress(
          processed: processed,
          total: pending.length,
          currentId: sourceId,
          elapsed: stopwatch.elapsed,
        ),
      );
    }
    return finish(records, cancelled: false);
  }

  /// 返回 true 表示调用方已经取消，已经写好的记录保留。
  Future<bool> _embedOne(
    IngestRecord record, {
    required List<EmbeddingRecord> records,
    required CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final ParsedDocument? document = record.document;
    if (document == null) {
      records.add(
        EmbeddingRecord.failure(
          sourceId: record.metadata.relativePath,
          failure: const EmbeddingFailure(
            kind: EmbeddingFailureKind.unknown,
            message: 'Indexable record has no document.',
          ),
        ),
      );
      return false;
    }

    if (document.hasText) {
      final String documentId = record.metadata.contentHash ?? record.metadata.id;
      final List<TextChunk> chunks;
      try {
        chunks = _chunker.chunk(document, documentId: documentId);
      } on ChunkBudgetException catch (error) {
        records.add(_failed(documentId, error));
        return false;
      }
      if (chunks.isEmpty && document.imageAsset == null && record.metadata.imageAsset == null) {
        records.add(
          EmbeddingRecord.failure(
            sourceId: documentId,
            failure: const EmbeddingFailure(
              kind: EmbeddingFailureKind.unknown,
              message: 'Document has no embeddable text.',
            ),
          ),
        );
        return false;
      }
      for (final TextChunk chunk in chunks) {
        if (cancel?.isCancelled ?? false) {
          return true;
        }
        try {
          final EmbeddingVector vector = await _engine.embed(
            EmbeddingInput.text(chunk.text, chunkId: chunk.chunkId),
            cancel: cancel,
          );
          records.add(EmbeddingRecord.success(sourceId: chunk.chunkId, vector: vector));
        } on CancelledException {
          rethrow;
        } on Object catch (error) {
          records.add(_failed(chunk.chunkId, error));
        }
      }
    }

    final ImageAsset? asset = document.imageAsset ?? record.metadata.imageAsset;
    if (asset != null) {
      if (cancel?.isCancelled ?? false) {
        return true;
      }
      final String sourceId = record.metadata.relativePath;
      try {
        final DecodedImage decoded = _images.decodeFile(record.metadata.path);
        final EmbeddingVector vector = await _engine.embed(
          EmbeddingInput.image(
            bytes: decoded.rgb24,
            width: decoded.width,
            height: decoded.height,
          ),
          cancel: cancel,
        );
        records.add(EmbeddingRecord.success(sourceId: sourceId, vector: vector));
      } on CancelledException {
        rethrow;
      } on Object catch (error) {
        records.add(_failed(sourceId, error));
      }
    } else if (!document.hasText) {
      records.add(
        EmbeddingRecord.failure(
          sourceId: record.metadata.relativePath,
          failure: const EmbeddingFailure(
            kind: EmbeddingFailureKind.unknown,
            message: 'Document has no text or image.',
          ),
        ),
      );
    }
    return false;
  }

  EmbeddingRecord _failed(String sourceId, Object error) {
    return EmbeddingRecord.failure(sourceId: sourceId, failure: _describe(error));
  }

  EmbeddingFailure _describe(Object error) {
    if (error is ChunkBudgetException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.overBudget,
        message: error.toString(),
      );
    }
    if (error is TextOverBudgetException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.overBudget,
        message: error.toString(),
      );
    }
    if (error is RuntimeUnavailableException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.runtimeUnavailable,
        message: error.message,
        detail: error.detail,
      );
    }
    if (error is DimensionMismatchException || error is BadOutputException) {
      final EmbeddingRuntimeException runtime = error as EmbeddingRuntimeException;
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.badOutput,
        message: runtime.message,
        detail: runtime.detail,
      );
    }
    if (error is MissingTensorException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.missingTensor,
        message: error.message,
        detail: error.detail,
      );
    }
    if (error is EmbeddingTimeoutException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.timeout,
        message: error.message,
        detail: error.detail,
      );
    }
    if (error is EmbeddingSpaceMismatchException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.spaceMismatch,
        message: error.toString(),
      );
    }
    if (error is EmbeddingRuntimeException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.unknown,
        message: error.message,
        detail: error.detail,
      );
    }
    if (error is FileSystemException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.unknown,
        message: 'Image file could not be read.',
        detail: error.message,
      );
    }
    if (error is FormatException) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.unknown,
        message: 'Image bytes could not be decoded.',
        detail: error.message,
      );
    }
    if (error is ArgumentError) {
      return EmbeddingFailure(
        kind: EmbeddingFailureKind.unknown,
        message: error.message?.toString() ?? 'Invalid embedding input.',
      );
    }
    return EmbeddingFailure(
      kind: EmbeddingFailureKind.unknown,
      message: 'Embedding failed (${error.runtimeType}).',
    );
  }
}
