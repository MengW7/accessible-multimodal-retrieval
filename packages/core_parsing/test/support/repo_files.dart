import 'dart:io';

import 'package:path/path.dart' as p;

/// Walks up from the current directory until [relative] exists.
String repoFile(String relative) {
  Directory dir = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    final String candidate = p.join(dir.path, relative);
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  throw StateError('Could not find $relative from ${Directory.current.path}');
}

String fixturePath(String name) {
  return p.join(Directory.current.path, 'test', 'fixtures', name);
}
