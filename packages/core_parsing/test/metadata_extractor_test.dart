import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:core_parsing/src/parsing/file_bytes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final FileMetadataExtractor extractor = FileMetadataExtractor();

  test('content hash is stable and times are present', () async {
    final Directory root = await _temp();
    final File file = File(p.join(root.path, '中文目录', '说明.txt'));
    await file.parent.create();
    await file.writeAsString('same bytes');
    final FileMetadata first = await extractor.describe(
      file.path,
      rootPath: root.path,
    );
    final FileMetadata second = await extractor.describe(
      file.path,
      rootPath: root.path,
    );
    expect(first.contentHash, isNotNull);
    expect(second.contentHash, first.contentHash);
    expect(first.modifiedAt, isNotNull);
    expect(first.accessedAt, isNotNull);
    expect(first.createdAt, isNotNull);
    expect(first.relativePath, '中文目录/说明.txt');
    expect(first.mimeType, 'text/plain');
    expect(first.extension, '.txt');
    expect(first.fileName, '说明.txt');
    expect(first.sizeBytes, file.lengthSync());
  });

  test(
    'a file above the hash ceiling has a path id and no content hash',
    () async {
      final Directory root = await _temp();
      final File file = File(p.join(root.path, 'big.txt'));
      await file.writeAsString('hello');
      final FileMetadata described = await extractor.describe(
        file.path,
        rootPath: root.path,
        maxFileSizeBytes: 4,
      );
      expect(described.contentHash, isNull);
      expect(described.id, isNotEmpty);
      expect(described.sizeBytes, 5);
    },
  );

  test('a missing file is failed and does not throw', () async {
    final Directory root = await _temp();
    final FileMetadata described = await extractor.describe(
      p.join(root.path, 'missing.txt'),
      rootPath: root.path,
    );
    expect(described.status, ParseOutcome.failed);
    expect(described.errorMessage, 'File not found.');
  });

  test('access denied maps to skipped', () {
    final ParseFailure failure = failureForFileSystemException(
      const FileSystemException('denied', 'x', OSError('Access is denied', 5)),
    );
    expect(failure.kind, ParseFailureKind.permissionDenied);
    expect(failure.outcome, ParseOutcome.skipped);
    expect(
      failureForFileSystemException(
        const FileSystemException('denied', 'x', OSError('EACCES', 13)),
      ).outcome,
      ParseOutcome.skipped,
    );
  });
}

Future<Directory> _temp() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'core_parsing_meta_',
  );
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}
