import 'dart:convert';
import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;

/// Prints one JSON object per text chunk and per image.
///
/// Chunk ids come from [CascadeTextChunker] and the unigram token count.
/// This command does not load ONNX. Vectors are attached later by
/// `engine/export_vectors.py`, from these same ids.
Future<void> main(List<String> args) async {
  final String requested;
  try {
    requested = _requirePath(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run packages/core_embedding/bin/dump_chunks.dart --path <directory>',
    );
    exitCode = 64;
    return;
  }

  final String root = _findRepoRoot();
  final String resolved = _resolveExisting(root, requested);
  final String tokenizerPath = p.join(
    root,
    'models',
    'raw',
    'text',
    'paraphrase-multilingual-MiniLM-L12-v2',
    'tokenizer.json',
  );
  if (!File(tokenizerPath).existsSync()) {
    stderr.writeln('Tokenizer is missing: $tokenizerPath');
    exitCode = 1;
    return;
  }

  final IngestionReport report = await IngestionService(
    registry: _registry(root),
    metadata: FileMetadataExtractor(),
  ).ingestDirectory(resolved);
  final UnigramTokenizer tokenizer = UnigramTokenizer.fromFile(tokenizerPath);
  final CascadeTextChunker chunker = CascadeTextChunker(
    countTokens: (String text) => tokenizer.encode(text).length,
  );
  final JsonEncoder encoder = JsonEncoder();
  var lines = 0;
  for (final IngestRecord record in report.indexable) {
    final ParsedDocument? document = record.document;
    final FileMetadata metadata = record.metadata;
    final String documentId = metadata.contentHash ?? metadata.id;
    final String documentKey = p
        .relative(metadata.path, from: root)
        .replaceAll('\\', '/');
    if (document != null && document.hasText) {
      final Map<int?, int> nextIndex = <int?, int>{};
      for (final TextChunk chunk in chunker.chunk(document, documentId: documentId)) {
        final int chunkIndex = nextIndex[chunk.pageNumber] ?? 0;
        nextIndex[chunk.pageNumber] = chunkIndex + 1;
        stdout.writeln(
          encoder.convert(
            _row(
              metadata: metadata,
              documentId: documentId,
              documentKey: documentKey,
              chunkId: chunk.chunkId,
              body: chunk.text,
              pageNumber: chunk.pageNumber,
              startOffset: chunk.startOffset,
              endOffset: chunk.endOffset,
              chunkIndex: chunkIndex,
              modality: 'text',
              space: documentTextModel.space.name,
              dim: documentTextModel.dim,
              modelId: documentTextModel.modelId,
              chunkerVersion: chunk.chunkerVersion,
            ),
          ),
        );
        lines += 1;
      }
    }
    final ImageAsset? asset = metadata.imageAsset ?? document?.imageAsset;
    if (asset != null) {
      stdout.writeln(
        encoder.convert(
          _row(
            metadata: metadata,
            documentId: documentId,
            documentKey: documentKey,
            chunkId: documentKey,
            body: '',
            pageNumber: null,
            startOffset: 0,
            endOffset: 0,
            chunkIndex: null,
            modality: 'image',
            space: clipVisionModel.space.name,
            dim: clipVisionModel.dim,
            modelId: clipVisionModel.modelId,
            chunkerVersion: 'none',
            imagePath: documentKey,
          ),
        ),
      );
      lines += 1;
    }
  }
  stderr.writeln('dump_lines=$lines indexable=${report.indexable.length} failed=${report.failed}');
  if (report.failed > 0) {
    exitCode = 1;
  }
}

Map<String, Object?> _row({
  required FileMetadata metadata,
  required String documentId,
  required String documentKey,
  required String chunkId,
  required String body,
  required int? pageNumber,
  required int startOffset,
  required int endOffset,
  required int? chunkIndex,
  required String modality,
  required String space,
  required int dim,
  required String modelId,
  required String chunkerVersion,
  String? imagePath,
}) {
  return <String, Object?>{
    'space': space,
    'dim': dim,
    'modelId': modelId,
    'chunkId': chunkId,
    'normalized': false,
    'relativePath': metadata.relativePath.replaceAll('\\', '/'),
    'documentKey': documentKey,
    'fileName': metadata.fileName,
    'extension': metadata.extension,
    'mimeType': metadata.mimeType,
    'pageNumber': pageNumber,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'chunkIndex': chunkIndex,
    'body': body,
    'modality': modality,
    'contentHash': metadata.contentHash,
    'parserName': metadata.parserName,
    'parserVersion': metadata.parserVersion,
    'chunkerVersion': chunkerVersion,
    'documentId': documentId,
    'imagePath': imagePath,
  };
}

String _requirePath(List<String> args) {
  for (var index = 0; index < args.length; index++) {
    if (args[index] == '--path' && index + 1 < args.length) {
      return args[index + 1];
    }
  }
  throw const FormatException('Pass --path <directory>.');
}

String _findRepoRoot() {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final File marker = File(p.join(dir.path, 'engine', 'embed_text_hidden.py'));
    if (marker.existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  throw StateError('Repo root not found from ${Directory.current.path}.');
}

String _resolveExisting(String root, String requested) {
  if (p.isAbsolute(requested) && Directory(requested).existsSync()) {
    return requested;
  }
  final String fromHere = p.normalize(p.join(Directory.current.path, requested));
  if (Directory(fromHere).existsSync()) {
    return fromHere;
  }
  final String fromRoot = p.normalize(p.join(root, requested));
  if (Directory(fromRoot).existsSync()) {
    return fromRoot;
  }
  throw StateError('Directory not found: $requested');
}

StandardParserRegistry _registry(String root) {
  return StandardParserRegistry(<DocumentParser>[
    TxtParser(),
    const DocxParser(),
    PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: p.join(root, 'tools', 'tika-app'),
      ),
    ),
    const ImageParser(),
  ]);
}
