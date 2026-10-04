import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  const FileScanner scanner = FileScanner();

  test(
    'fixtures include nested files and skip hidden and temp names',
    () async {
      final String root = p.join(Directory.current.path, 'test', 'fixtures');
      final List<String> paths = await scanner.scan(root);
      final List<String> bases = paths.map(p.basename).toList();
      expect(paths, orderedEquals(List<String>.of(paths)..sort()));
      expect(
        paths.any(
          (String path) => path.replaceAll('\\', '/').endsWith('nested/a.txt'),
        ),
        isTrue,
      );
      expect(bases, contains('UPPER.TXT'));
      expect(bases, contains('hello.txt'));
      expect(bases.where((String name) => name.startsWith('.')), isEmpty);
      expect(bases.where((String name) => name.startsWith('~\$')), isEmpty);
    },
  );

  // rvlcdip pngs are gitignored, so this stays off the default suite.
  test('rvlcdip sample yields 16 files', () async {
    final List<String> paths = await scanner.scan(
      repoFile('datasets/rvlcdip/sample'),
    );
    expect(paths, hasLength(16));
  }, tags: 'integration');

  test('maxDepth 0 does not enter subdirectories', () async {
    final Directory root = await _temp();
    await File(p.join(root.path, 'top.txt')).writeAsString('top');
    final Directory nested = Directory(p.join(root.path, 'nested'))
      ..createSync();
    await File(p.join(nested.path, 'child.txt')).writeAsString('child');
    final List<String> paths = await scanner.scan(root.path, maxDepth: 0);
    expect(paths.map(p.basename), <String>['top.txt']);
  });

  test(
    'hidden directories, temp files, and system directories are skipped',
    () async {
      final Directory root = await _temp();
      await File(p.join(root.path, 'keep.txt')).writeAsString('keep');
      await File(p.join(root.path, '~\$lock.docx')).writeAsString('lock');
      await File(p.join(root.path, '.secret.txt')).writeAsString('secret');
      final Directory hidden = Directory(p.join(root.path, '.hidden'))
        ..createSync();
      await File(p.join(hidden.path, 'inside.txt')).writeAsString('no');
      final Directory recycle = Directory(p.join(root.path, '\$Recycle.Bin'))
        ..createSync();
      await File(p.join(recycle.path, 'gone.txt')).writeAsString('no');
      await File(p.join(root.path, 'notes.bin')).writeAsString('no');
      final List<String> bases = (await scanner.scan(root.path))
          .map(p.basename)
          .toList();
      expect(bases, <String>['keep.txt']);
    },
  );

  test('an already cancelled token throws', () async {
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    expect(
      scanner.scan(Directory.current.path, cancel: source.token),
      throwsA(isA<CancelledException>()),
    );
  });
}

Future<Directory> _temp() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'core_parsing_scan_',
  );
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}
