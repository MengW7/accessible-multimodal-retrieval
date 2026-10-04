import 'dart:io';

import 'package:path/path.dart' as p;

import '../spi/cancellation_token.dart';

/// Extensions ingested by default, lowercase and including the leading dot.
const Set<String> defaultIngestExtensions = <String>{
  '.txt',
  '.pdf',
  '.docx',
  '.jpg',
  '.jpeg',
  '.png',
};

const Set<String> _systemDirectories = <String>{
  '\$recycle.bin',
  'system volume information',
};

/// Recursive whitelist scan. Results are absolute paths in sorted order.
///
/// Names starting with `.` or `~$` are skipped, as are hidden directories and
/// a few OS directories. [followLinks] defaults to false. [maxDepth] counts
/// directory levels below [rootPath]; `0` lists only the root's own files.
class FileScanner {
  const FileScanner();

  Future<List<String>> scan(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    CancellationToken? cancel,
  }) async {
    if (maxDepth < 0) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'must be >= 0');
    }
    cancel?.throwIfCancelled();
    final Directory root = Directory(rootPath);
    final FileSystemEntityType type = await FileSystemEntity.type(
      rootPath,
      followLinks: followLinks,
    );
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Directory not found', rootPath);
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException('Not a directory', rootPath);
    }
    final Set<String> allowed = <String>{};
    for (final String extension in extensions) {
      final String? normalized = _normalizeExtension(extension);
      if (normalized != null) {
        allowed.add(normalized);
      }
    }
    final List<String> found = <String>[];
    await _walk(
      directory: root,
      depth: 0,
      maxDepth: maxDepth,
      followLinks: followLinks,
      allowed: allowed,
      found: found,
      seen: <String>{},
      cancel: cancel,
    );
    found.sort();
    return List<String>.unmodifiable(found);
  }

  Future<void> _walk({
    required Directory directory,
    required int depth,
    required int maxDepth,
    required bool followLinks,
    required Set<String> allowed,
    required List<String> found,
    required Set<String> seen,
    required CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final String identity = directory.absolute.path.toLowerCase();
    if (!seen.add(identity)) {
      return;
    }
    await for (final FileSystemEntity entity in directory.list(
      followLinks: followLinks,
    )) {
      cancel?.throwIfCancelled();
      if (!followLinks && entity is Link) {
        continue;
      }
      final String name = p.basename(entity.path);
      final bool isDirectory = entity is Directory;
      if (_skippedName(name, directory: isDirectory)) {
        continue;
      }
      if (isDirectory) {
        if (depth < maxDepth) {
          await _walk(
            directory: Directory(entity.path),
            depth: depth + 1,
            maxDepth: maxDepth,
            followLinks: followLinks,
            allowed: allowed,
            found: found,
            seen: seen,
            cancel: cancel,
          );
        }
        continue;
      }
      if (entity is! File) {
        continue;
      }
      final String? extension = _normalizeExtension(p.extension(entity.path));
      if (extension != null && allowed.contains(extension)) {
        found.add(entity.absolute.path);
      }
    }
  }
}

bool _skippedName(String name, {required bool directory}) {
  if (name.startsWith('.')) {
    return true;
  }
  if (name.startsWith('~\$')) {
    return true;
  }
  return directory && _systemDirectories.contains(name.toLowerCase());
}

String? _normalizeExtension(String extension) {
  var value = extension.trim().toLowerCase();
  if (value.isEmpty) {
    return null;
  }
  if (!value.startsWith('.')) {
    value = '.$value';
  }
  if (value == '.') {
    return null;
  }
  return value;
}
