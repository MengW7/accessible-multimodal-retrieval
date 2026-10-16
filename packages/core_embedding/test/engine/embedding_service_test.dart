import 'dart:io';
import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

FileMetadata _meta({
  required String name,
  required String extension,
  ParseOutcome status = ParseOutcome.ok,
  String? hash,
  ImageAsset? image,
}) {
  return FileMetadata(
    id: hash ?? name,
    path: 'E:/batch/$name',
    relativePath: name,
    fileName: name,
    extension: extension,
    sizeBytes: 4,
    status: status,
    contentHash: hash,
    imageAsset: image,
  );
}

ParsedDocument _text(
  String text, {
  List<DocumentPage>? pages,
  Map<String, Object?> attributes = const <String, Object?>{},
  ImageAsset? image,
}) {
  return ParsedDocument(
    fullText: text,
    pages: pages ?? <DocumentPage>[DocumentPage(pageNumber: 1, text: text)],
    attributes: attributes,
    imageAsset: image,
  );
}

IngestionReport _report(List<IngestRecord> records) {
  final DateTime now = DateTime.utc(2026, 10, 16);
  return IngestionReport(
    rootPath: 'E:/batch',
    startedAt: now,
    finishedAt: now,
    records: records,
  );
}

final class _Engine implements EmbeddingEngine {
  _Engine(this._throwFor);

  final Map<String, Exception> _throwFor;
  var calls = 0;

  @override
  Future<EmbeddingVector> embed(EmbeddingInput input, {CancellationToken? cancel}) async {
    cancel?.throwIfCancelled();
    calls += 1;
    final String key = input.text ?? '';
    final Exception? error = _throwFor[key];
    if (error != null) {
      throw error;
    }
    return EmbeddingVector(
      values: const <double>[1, 0],
      space: input.space,
      dim: 2,
      modelId: input.isImage ? 'image' : 'text',
      normalized: true,
      chunkId: input.chunkId,
    );
  }

  @override
  List<ModelInfo> get models => const <ModelInfo>[documentTextModel, clipVisionModel];
}

final class _Images implements ImageDecoder {
  @override
  DecodedImage decodeFile(String path) {
    return DecodedImage(rgb24: Uint8List.fromList(<int>[9, 8, 7]), width: 1, height: 1);
  }
}

DefaultEmbeddingService _service({
  Map<String, Exception> throwFor = const <String, Exception>{},
  int Function(String text)? countTokens,
}) {
  return DefaultEmbeddingService(
    engine: _Engine(throwFor),
    chunker: CascadeTextChunker(
      countTokens: countTokens ?? ((String text) => text.length + 2),
      chunkChars: 32,
      maxTokens: 64,
      counterLabel: 'chars',
    ),
    images: _Images(),
    clock: () => DateTime.utc(2026, 10, 16, 1),
  );
}

void main() {
  test('five formats produce vectors, and one bad file does not stop the batch', () async {
    const ImageAsset photo = ImageAsset(format: 'jpeg', width: 1, height: 1);
    const ImageAsset scan = ImageAsset(format: 'png', width: 1, height: 1);
    final List<EmbeddingProgress> progress = <EmbeddingProgress>[];
    final EmbeddingReport report = await _service(
      throwFor: <String, Exception>{'坏': const BadOutputException('bad pixels')},
    ).embedAll(
      _report(<IngestRecord>[
        IngestRecord(metadata: _meta(name: 'note.txt', extension: '.txt', hash: 'txt'), document: _text('甲\n\n乙')),
        IngestRecord(
          metadata: _meta(name: 'paper.pdf', extension: '.pdf', hash: 'pdf'),
          document: _text(
            '第一页第二页',
            pages: const <DocumentPage>[
              DocumentPage(pageNumber: 1, text: '第一页'),
              DocumentPage(pageNumber: 2, text: '第二页'),
            ],
            attributes: const <String, Object?>{'pageCount': 2},
          ),
        ),
        IngestRecord(
          metadata: _meta(name: 'notes.docx', extension: '.docx', hash: 'docx'),
          document: _text('段落一\n段落二'),
        ),
        IngestRecord(
          metadata: _meta(name: 'photo.jpg', extension: '.jpg', image: photo),
          document: const ParsedDocument(fullText: '', imageAsset: photo),
        ),
        IngestRecord(
          metadata: _meta(name: 'scan.png', extension: '.png', image: scan, status: ParseOutcome.partial),
          document: const ParsedDocument(fullText: '', imageAsset: scan, outcome: ParseOutcome.partial),
        ),
        IngestRecord(metadata: _meta(name: 'bad.txt', extension: '.txt', hash: 'bad'), document: _text('坏')),
        IngestRecord(metadata: _meta(name: 'skip.bin', extension: '.bin', status: ParseOutcome.skipped)),
      ]),
      onProgress: progress.add,
    );

    expect(report.cancelled, isFalse);
    expect(report.failed, 1);
    expect(report.succeeded, 8);
    expect(report.isClean, isFalse);
    expect(report.records[8].failure?.kind, EmbeddingFailureKind.badOutput);
    expect(report.records.sublist(0, 2).every((EmbeddingRecord record) => record.sourceId.contains('pna')), isTrue);
    expect(report.records[2].sourceId, contains('-p1-'));
    expect(report.records[3].sourceId, contains('-p2-'));
    expect(report.records[3].vector?.chunkId, report.records[3].sourceId);
    expect(report.records[6].sourceId, 'photo.jpg');
    expect(report.records[6].vector?.modelId, 'image');
    expect(report.records[6].vector?.space, EmbeddingSpace.clipShared);
    expect(report.records[7].sourceId, 'scan.png');
    expect(report.records.map((EmbeddingRecord record) => record.sourceId), isNot(contains('skip.bin')));
    expect(progress.first.processed, 0);
    expect(progress.last.processed, progress.last.total);
    expect(progress.last.toJson()['processed'], 6);
    expect(report.toJson()['counts'], <String, Object?>{'total': 9, 'ok': 8, 'failed': 1});
    expect(report.records.first.toJson()['vector'], isA<Map<String, Object?>>());
    expect(report.toString(), contains('failed: 1'));
    expect(report.duration, Duration.zero);
    final EmbeddingVector vector = report.records.first.vector!;
    expect(vector.hashCode, vector.hashCode);
    expect(vector.toJson()['normalized'], isTrue);
  });

  test('cancellation keeps finished records and stops before the next file', () async {
    final CancellationTokenSource source = CancellationTokenSource();
    final EmbeddingReport report = await _service().embedAll(
      _report(<IngestRecord>[
        IngestRecord(metadata: _meta(name: 'a.txt', extension: '.txt', hash: 'a'), document: _text('甲\n\n乙')),
        IngestRecord(metadata: _meta(name: 'b.txt', extension: '.txt', hash: 'b'), document: _text('丙')),
      ]),
      cancel: source.token,
      onProgress: (EmbeddingProgress progress) {
        if (progress.processed >= 1) {
          source.cancel();
        }
      },
    );
    expect(report.cancelled, isTrue);
    expect(report.records, hasLength(2));
    expect(report.isClean, isFalse);
    expect(report.records.every((EmbeddingRecord record) => record.isSuccess), isTrue);
  });

  test('an already cancelled token returns an empty report', () async {
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    final List<EmbeddingProgress> progress = <EmbeddingProgress>[];
    final EmbeddingReport report = await _service().embedAll(
      _report(<IngestRecord>[
        IngestRecord(metadata: _meta(name: 'a.txt', extension: '.txt'), document: _text('甲')),
      ]),
      cancel: source.token,
      onProgress: progress.add,
    );
    expect(report.cancelled, isTrue);
    expect(report.records, isEmpty);
    expect(progress.single.total, 0);
  });

  test('a chunk that cannot fit is over-budget and the next file still runs', () async {
    final EmbeddingReport report = await _service(
      countTokens: (String text) => text == '甲' ? 1000 : text.length + 2,
    ).embedAll(
      _report(<IngestRecord>[
        IngestRecord(metadata: _meta(name: 'long.txt', extension: '.txt', hash: 'long'), document: _text('甲')),
        IngestRecord(metadata: _meta(name: 'ok.txt', extension: '.txt', hash: 'ok'), document: _text('乙')),
      ]),
    );
    expect(report.records, hasLength(2));
    expect(report.records.first.failure?.kind, EmbeddingFailureKind.overBudget);
    expect(report.records.last.isSuccess, isTrue);
  });

  test('runtime failures are isolated by kind', () async {
    final EmbeddingReport report = await _service(
      throwFor: <String, Exception>{
        'down': const RuntimeUnavailableException('down'),
        'mask': const MissingTensorException('mask'),
        'slow': const EmbeddingTimeoutException('slow'),
        'space': EmbeddingSpaceMismatchException(
          requested: EmbeddingSpace.clipShared,
          actual: EmbeddingSpace.documentText,
        ),
        'odd': const EmbeddingRuntimeException('odd'),
        'long': TextOverBudgetException(tokenCount: 9, maxLength: 8),
      },
    ).embedAll(
      _report(<IngestRecord>[
        for (final String text in <String>['down', 'mask', 'slow', 'space', 'odd', 'long'])
          IngestRecord(
            metadata: _meta(name: '$text.txt', extension: '.txt', hash: text),
            document: _text(text),
          ),
      ]),
    );
    expect(report.records.map((EmbeddingRecord record) => record.failure?.kind), <EmbeddingFailureKind>[
      EmbeddingFailureKind.runtimeUnavailable,
      EmbeddingFailureKind.missingTensor,
      EmbeddingFailureKind.timeout,
      EmbeddingFailureKind.spaceMismatch,
      EmbeddingFailureKind.unknown,
      EmbeddingFailureKind.overBudget,
    ]);
    expect(report.records.first.failure, report.records.first.failure);
    expect(report.records.first.failure.hashCode, isNotNull);
    expect(report.succeeded, 0);
  });

  test('a missing document and an unreadable image are recorded and skipped past', () async {
    final DefaultEmbeddingService service = DefaultEmbeddingService(
      engine: _Engine(const <String, Exception>{}),
      chunker: CascadeTextChunker(countTokens: (String text) => text.length + 2),
      images: _BrokenImages(),
      clock: () => DateTime.utc(2026, 10, 16),
    );
    final EmbeddingReport report = await service.embedAll(
      _report(<IngestRecord>[
        IngestRecord(metadata: _meta(name: 'empty.txt', extension: '.txt')),
        IngestRecord(
          metadata: _meta(name: 'gone.jpg', extension: '.jpg'),
          document: const ParsedDocument(
            fullText: '',
            imageAsset: ImageAsset(format: 'jpeg', width: 1, height: 1),
          ),
        ),
        IngestRecord(metadata: _meta(name: 'ok.txt', extension: '.txt', hash: 'ok'), document: _text('乙')),
      ]),
    );
    expect(report.records, hasLength(3));
    expect(report.records[0].failure?.kind, EmbeddingFailureKind.unknown);
    expect(report.records[1].failure?.message, contains('Image'));
    expect(report.records[2].isSuccess, isTrue);
  });

  test('an empty indexable list reports that there was nothing to do', () async {
    final List<EmbeddingProgress> progress = <EmbeddingProgress>[];
    final EmbeddingReport report = await _service().embedAll(
      _report(const <IngestRecord>[]),
      onProgress: progress.add,
    );
    expect(report.isClean, isTrue);
    expect(report.total, 0);
    expect(progress.single.toString(), 'EmbeddingProgress(0/0)');
  });
}

final class _BrokenImages implements ImageDecoder {
  @override
  DecodedImage decodeFile(String path) {
    throw const FileSystemException('denied');
  }
}
