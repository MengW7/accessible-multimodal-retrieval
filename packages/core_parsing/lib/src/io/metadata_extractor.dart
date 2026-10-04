import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../model/file_metadata.dart';
import '../model/parsed_document.dart';
import '../parsing/file_bytes.dart';
import '../parsing/parser_registry.dart';
import '../spi/cancellation_token.dart';

/// Builds a [FileMetadata] shell before parsing.
///
/// Permission errors come back as [ParseOutcome.skipped]. Other I/O errors
/// come back as [ParseOutcome.failed]. Neither throws.
abstract interface class MetadataExtractor {
  Future<FileMetadata> describe(
    String absolutePath, {
    required String rootPath,
    int? maxFileSizeBytes,
    CancellationToken? cancel,
  });
}

/// Stat, MIME, and SHA-256 for one file.
///
/// Files larger than [maxFileSizeBytes] keep a path id and a null content hash
/// so a batch does not read unbounded bytes twice.
class FileMetadataExtractor implements MetadataExtractor {
  FileMetadataExtractor({this.maxFileSizeBytes = 10 * 1024 * 1024})
    : assert(maxFileSizeBytes > 0, 'maxFileSizeBytes must be positive');

  final int maxFileSizeBytes;

  @override
  Future<FileMetadata> describe(
    String absolutePath, {
    required String rootPath,
    int? maxFileSizeBytes,
    CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final int limit = maxFileSizeBytes ?? this.maxFileSizeBytes;
    final String relativePath = _relativePosix(rootPath, absolutePath);
    final String fileName = p.basename(absolutePath);
    final String extension =
        normalizeParserExtension(p.extension(fileName)) ?? '';
    final DateTime indexedAt = DateTime.now().toUtc();
    try {
      final FileStat stat = await File(absolutePath).stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return _failed(
          absolutePath: absolutePath,
          relativePath: relativePath,
          fileName: fileName,
          extension: extension,
          indexedAt: indexedAt,
          failure: const ParseFailure(
            kind: ParseFailureKind.unknown,
            message: 'File not found.',
          ),
        );
      }
      String? contentHash;
      if (stat.size <= limit) {
        contentHash = await _sha256OfFile(absolutePath, cancel);
      }
      return FileMetadata(
        id: contentHash ?? _idForRelativePath(relativePath),
        path: absolutePath,
        relativePath: relativePath,
        fileName: fileName,
        extension: extension,
        sizeBytes: stat.size,
        mimeType: mimeTypeForExtension(extension),
        // dart:io reports ctime as changed. It does not expose birth time.
        createdAt: stat.changed,
        modifiedAt: stat.modified,
        accessedAt: stat.accessed,
        contentHash: contentHash,
        indexedAt: indexedAt,
      );
    } on CancelledException {
      rethrow;
    } on FileSystemException catch (error) {
      return _failed(
        absolutePath: absolutePath,
        relativePath: relativePath,
        fileName: fileName,
        extension: extension,
        indexedAt: indexedAt,
        failure: failureForFileSystemException(error),
      );
    }
  }

  FileMetadata _failed({
    required String absolutePath,
    required String relativePath,
    required String fileName,
    required String extension,
    required DateTime indexedAt,
    required ParseFailure failure,
  }) {
    return FileMetadata(
      id: _idForRelativePath(relativePath),
      path: absolutePath,
      relativePath: relativePath,
      fileName: fileName,
      extension: extension,
      sizeBytes: 0,
      mimeType: mimeTypeForExtension(extension),
      indexedAt: indexedAt,
      status: failure.outcome,
      errorMessage: failure.message,
    );
  }
}

/// MIME type for a lowercase dotted extension, or null when unknown.
String? mimeTypeForExtension(String extension) {
  switch (extension) {
    case '.txt':
      return 'text/plain';
    case '.pdf':
      return 'application/pdf';
    case '.docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    default:
      return null;
  }
}

String _relativePosix(String rootPath, String absolutePath) {
  final String relative = p.relative(absolutePath, from: rootPath);
  if (relative == '.') {
    return p.basename(absolutePath);
  }
  return p.split(relative).join('/');
}

String _idForRelativePath(String relativePath) {
  return sha256.convert(utf8.encode(relativePath)).toString();
}

Future<String> _sha256OfFile(String path, CancellationToken? cancel) async {
  final RandomAccessFile handle = await File(path).open();
  final _DigestSink sink = _DigestSink();
  final ByteConversionSink input = sha256.startChunkedConversion(sink);
  try {
    while (true) {
      cancel?.throwIfCancelled();
      final Uint8List chunk = await handle.read(65536);
      if (chunk.isEmpty) {
        break;
      }
      input.add(chunk);
    }
  } finally {
    input.close();
    await handle.close();
  }
  return sink.value.toString();
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final Digest? digest = _value;
    if (digest == null) {
      throw StateError('SHA-256 digest was not produced.');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}
