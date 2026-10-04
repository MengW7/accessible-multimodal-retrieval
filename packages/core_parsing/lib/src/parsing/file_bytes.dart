import 'dart:io';
import 'dart:typed_data';

import '../model/parsed_document.dart';
import '../spi/cancellation_token.dart';

/// Bytes read from one file, possibly cut at a caller-supplied ceiling.
class FileBytesData {
  const FileBytesData(this.bytes, {required this.truncated});

  final Uint8List bytes;

  /// True when [bytes] is a prefix because the file was longer than the limit.
  final bool truncated;
}

/// The path could not be read. Callers turn this into a [ParseResult.failure].
class FileBytesFailure {
  const FileBytesFailure(this.failure);

  final ParseFailure failure;
}

/// Read [absolutePath], optionally stopping after [maxBytes].
///
/// A missing path or a directory becomes [FileBytesFailure]. Cancellation is
/// not converted: [CancellationToken.throwIfCancelled] still throws.
Future<Object> readFileBytes(
  String absolutePath, {
  int? maxBytes,
  CancellationToken? cancel,
}) async {
  cancel?.throwIfCancelled();
  final File file = File(absolutePath);
  try {
    final FileSystemEntityType type = await FileSystemEntity.type(
      absolutePath,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      return const FileBytesFailure(
        ParseFailure(
          kind: ParseFailureKind.unknown,
          message: 'File not found.',
        ),
      );
    }
    if (type == FileSystemEntityType.directory) {
      return const FileBytesFailure(
        ParseFailure(
          kind: ParseFailureKind.unknown,
          message: 'Path is a directory.',
        ),
      );
    }
    final int length = await file.length();
    final bool truncated = maxBytes != null && length > maxBytes;
    final int toRead = truncated ? maxBytes : length;
    final RandomAccessFile handle = await file.open();
    try {
      final BytesBuilder builder = BytesBuilder(copy: false);
      var remaining = toRead;
      while (remaining > 0) {
        cancel?.throwIfCancelled();
        final int chunkSize = remaining > 65536 ? 65536 : remaining;
        final Uint8List chunk = await handle.read(chunkSize);
        if (chunk.isEmpty) {
          break;
        }
        builder.add(chunk);
        remaining -= chunk.length;
      }
      return FileBytesData(builder.toBytes(), truncated: truncated);
    } finally {
      await handle.close();
    }
  } on CancelledException {
    rethrow;
  } on FileSystemException catch (error) {
    return FileBytesFailure(failureForFileSystemException(error));
  }
}

/// Maps a filesystem error to a [ParseFailure].
///
/// Windows access denied is 5. POSIX `EPERM` is 1 and `EACCES` is 13.
ParseFailure failureForFileSystemException(FileSystemException error) {
  final int? code = error.osError?.errorCode;
  // Windows ERROR_ACCESS_DENIED is 5. POSIX EPERM is 1 and EACCES is 13.
  if (code == 5 || code == 13 || code == 1) {
    return ParseFailure(
      kind: ParseFailureKind.permissionDenied,
      message: 'Permission denied.',
      detail: error.message,
    );
  }
  return ParseFailure(
    kind: ParseFailureKind.unknown,
    message: 'Unable to read file.',
    detail: error.message,
  );
}
