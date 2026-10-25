import 'dart:io';

import 'package:core_pipeline/core_pipeline.dart';
import 'package:test/test.dart';

void main() {
  test('markdown is read as text under its own parser name', () async {
    final Directory root = await Directory.systemTemp.createTemp('w4-md-');
    addTearDown(() => root.delete(recursive: true));
    final File file = File('${root.path}/note.md');
    await file.writeAsString('离线检索\n\n可以没有网络。');
    final MarkdownParser parser = MarkdownParser();
    expect(parser.supportedExtensions, <String>{'.md'});
    expect(parser.name, 'markdown');
    expect(parser.version, '1');
    final result = await parser.parse(file.path);
    expect(result.isSuccess, isTrue);
    expect(result.document?.fullText, '离线检索\n\n可以没有网络。');
  });
}
