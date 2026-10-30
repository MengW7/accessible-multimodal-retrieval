import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:core_storage/core_storage.dart';

import 'index_source.dart';
import 'model/index_report.dart';

/// 端到端建库。只消费已经解析好的记录，不自己扫目录。
abstract interface class IndexingPipeline {
  Future<IndexReport> index(
    String rootPath, {
    void Function(IndexProgress)? onProgress,
    CancellationToken? cancel,
    bool force = false,
  });
}

/// 一份文件的文本和图像都嵌完，才交给存储层一次写完。
///
/// 存储层的写入会在同一事务里删掉旧行。嵌入中途失败时旧行还在，不会留下半份文件。
final class DefaultIndexingPipeline implements IndexingPipeline {
  DefaultIndexingPipeline({
    required this.source,
    required this.engine,
    required this.store,
    required this.chunker,
    required this.images,
    required this.textModel,
    required this.imageModel,
    required String chunkerVersion,
    this.documentKeyOf,
  }) : chunkerVersion = bindChunkerVersion(chunker, chunkerVersion);

  final IndexSource source;

  final EmbeddingEngine engine;

  final VectorStore store;

  final TextChunker chunker;

  final ImageDecoder images;

  final ModelInfo textModel;

  final ModelInfo imageModel;

  /// 文本代次里的分块器版本。图像行固定写 `none`。
  final String chunkerVersion;

  /// 把摄取相对路径改写成仓库相对路径。缺省时沿用摄取相对路径。
  final String Function(FileMetadata metadata)? documentKeyOf;

  static const String imageChunkerVersion = 'none';

  /// 文本代次必须用切块器自己的版本串。
  /// 另写一个常量会让 `sameRecipe` 在窗口已经变了的时候仍复用旧库。
  static String bindChunkerVersion(TextChunker chunker, String supplied) {
    if (supplied.isEmpty) {
      throw ArgumentError.value(
        supplied,
        'chunkerVersion',
        'must not be empty',
      );
    }
    if (chunker is CascadeTextChunker && supplied != chunker.chunkerVersion) {
      throw ArgumentError.value(
        supplied,
        'chunkerVersion',
        'must equal CascadeTextChunker.chunkerVersion '
            '(${chunker.chunkerVersion})',
      );
    }
    return supplied;
  }

  @override
  Future<IndexReport> index(
    String rootPath, {
    void Function(IndexProgress)? onProgress,
    CancellationToken? cancel,
    bool force = false,
  }) async {
    cancel?.throwIfCancelled();
    final IngestionReport loaded = await source.load(rootPath, cancel: cancel);
    final List<IngestRecord> records = loaded.indexable;
    var processed = 0;
    var written = 0;
    var reused = 0;
    var failed = 0;
    var chunksWritten = 0;
    var cancelled = loaded.cancelled;
    onProgress?.call(IndexProgress(processed: 0, total: records.length));
    for (final IngestRecord record in records) {
      if (cancel?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      IndexFileOutcome fileOutcome;
      String? errorMessage;
      try {
        final _FileOutcome outcome = await _indexFile(
          record,
          force: force,
          cancel: cancel,
        );
        if (outcome.reused) {
          reused += 1;
          fileOutcome = IndexFileOutcome.reused;
        } else {
          written += 1;
          chunksWritten += outcome.chunks;
          fileOutcome = IndexFileOutcome.written;
        }
      } on CancelledException {
        cancelled = true;
        break;
      } on Object catch (error) {
        failed += 1;
        fileOutcome = IndexFileOutcome.failed;
        errorMessage = error.toString();
      }
      processed += 1;
      onProgress?.call(
        IndexProgress(
          processed: processed,
          total: records.length,
          path: record.metadata.path,
          outcome: fileOutcome,
          errorMessage: errorMessage,
          written: written,
          reused: reused,
          failed: failed,
        ),
      );
      // Let worker-isolate ports deliver cancellation even when SQLite reuse
      // completes only through microtasks and no new inference is needed.
      await Future<void>.delayed(Duration.zero);
    }
    return IndexReport(
      documents: records.length,
      written: written,
      reused: reused,
      failed: failed,
      cancelled: cancelled,
      chunksWritten: chunksWritten,
    );
  }

  Future<_FileOutcome> _indexFile(
    IngestRecord record, {
    required bool force,
    CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final FileMetadata metadata = record.metadata;
    final ParsedDocument? document = record.document;
    final bool hasText = document?.hasText ?? false;
    final ImageAsset? asset = metadata.imageAsset ?? document?.imageAsset;
    final bool hasImage = asset != null;
    final String documentId = metadata.contentHash ?? metadata.id;
    if (await _canReuse(
      metadata,
      documentId: documentId,
      hasText: hasText,
      hasImage: hasImage,
      force: force,
    )) {
      return const _FileOutcome.reused();
    }
    final List<StoredChunk> chunks = <StoredChunk>[];
    final List<EmbeddingVector> vectors = <EmbeddingVector>[];
    if (hasText) {
      final List<TextChunk> pieces = chunker.chunk(
        document!,
        documentId: documentId,
      );
      final Map<int?, int> nextIndex = <int?, int>{};
      for (final TextChunk piece in pieces) {
        cancel?.throwIfCancelled();
        if (piece.text.trim().isEmpty) {
          continue;
        }
        final int chunkIndex = nextIndex[piece.pageNumber] ?? 0;
        nextIndex[piece.pageNumber] = chunkIndex + 1;
        final EmbeddingVector vector = await engine.embed(
          EmbeddingInput.text(piece.text, chunkId: piece.chunkId),
          cancel: cancel,
        );
        chunks.add(
          _textChunk(
            metadata,
            documentId: documentId,
            piece: piece,
            chunkIndex: chunkIndex,
          ),
        );
        vectors.add(vector);
      }
    }
    if (hasImage) {
      cancel?.throwIfCancelled();
      final DecodedImage decoded = images.decodeFile(metadata.path);
      final EmbeddingVector vector = await engine.embed(
        EmbeddingInput.image(
          bytes: decoded.rgb24,
          width: decoded.width,
          height: decoded.height,
        ),
        cancel: cancel,
      );
      chunks.add(_imageChunk(metadata, documentId: documentId, asset: asset));
      vectors.add(vector);
    }
    if (chunks.isEmpty) {
      throw StateError(
        'Indexable file ${metadata.relativePath} has no chunks.',
      );
    }
    await store.write(chunks, vectors);
    return _FileOutcome.wrote(chunks.length);
  }

  Future<bool> _canReuse(
    FileMetadata metadata, {
    required String documentId,
    required bool hasText,
    required bool hasImage,
    required bool force,
  }) async {
    final bool empty = !hasText && !hasImage;
    if (force || empty) {
      return false;
    }
    final String? hash = metadata.contentHash;
    final String? parserName = metadata.parserName;
    final String? parserVersion = metadata.parserVersion;
    if (hash == null ||
        hash.isEmpty ||
        parserName == null ||
        parserName.isEmpty ||
        parserVersion == null ||
        parserVersion.isEmpty) {
      return false;
    }
    if (hasText &&
        !await store.canReuse(
          _generation(
            documentId: documentId,
            hash: hash,
            parserName: parserName,
            parserVersion: parserVersion,
            chunkerVersion: chunkerVersion,
            model: textModel,
          ),
        )) {
      return false;
    }
    if (hasImage &&
        !await store.canReuse(
          _generation(
            documentId: documentId,
            hash: hash,
            parserName: parserName,
            parserVersion: parserVersion,
            chunkerVersion: imageChunkerVersion,
            model: imageModel,
          ),
        )) {
      return false;
    }
    return true;
  }

  String _documentKey(FileMetadata metadata) {
    final String? custom = documentKeyOf?.call(metadata);
    final String key = (custom == null || custom.isEmpty)
        ? metadata.relativePath
        : custom;
    return key.replaceAll('\\', '/');
  }

  IndexGeneration _generation({
    required String documentId,
    required String hash,
    required String parserName,
    required String parserVersion,
    required String chunkerVersion,
    required ModelInfo model,
  }) {
    return IndexGeneration(
      documentId: documentId,
      contentHash: hash,
      parserName: parserName,
      parserVersion: parserVersion,
      chunkerVersion: chunkerVersion,
      modelId: model.modelId,
      vectorDim: model.dim,
      embeddedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  StoredChunk _textChunk(
    FileMetadata metadata, {
    required String documentId,
    required TextChunk piece,
    required int chunkIndex,
  }) {
    return StoredChunk(
      documentId: documentId,
      chunkId: piece.chunkId,
      relativePath: metadata.relativePath,
      documentKey: _documentKey(metadata),
      fileName: metadata.fileName,
      extension: metadata.extension,
      mimeType: metadata.mimeType,
      pageNumber: piece.pageNumber,
      chunkIndex: chunkIndex,
      startOffset: piece.startOffset,
      endOffset: piece.endOffset,
      body: piece.text,
      modality: Modality.text,
      modifiedAt: metadata.modifiedAt,
      contentHash: metadata.contentHash,
      parserName: metadata.parserName,
      parserVersion: metadata.parserVersion,
      chunkerVersion: chunkerVersion,
    );
  }

  StoredChunk _imageChunk(
    FileMetadata metadata, {
    required String documentId,
    required ImageAsset asset,
  }) {
    return StoredChunk(
      documentId: documentId,
      chunkId: '$documentId:image',
      relativePath: metadata.relativePath,
      documentKey: _documentKey(metadata),
      fileName: metadata.fileName,
      extension: metadata.extension,
      mimeType: metadata.mimeType,
      startOffset: 0,
      endOffset: 0,
      body: '',
      modality: Modality.image,
      imageAsset: asset,
      modifiedAt: metadata.modifiedAt,
      contentHash: metadata.contentHash,
      parserName: metadata.parserName,
      parserVersion: metadata.parserVersion,
      chunkerVersion: imageChunkerVersion,
    );
  }
}

final class _FileOutcome {
  const _FileOutcome.reused() : reused = true, chunks = 0;

  const _FileOutcome.wrote(this.chunks) : reused = false;

  final bool reused;

  final int chunks;
}
