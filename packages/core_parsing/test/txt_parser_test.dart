import 'dart:io';
import 'dart:typed_data';

import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  final TxtParser parser = TxtParser();

  test('utf-8 fixture keeps Chinese and normalizes CRLF', () async {
    final ParseResult result = await parser.parse(fixturePath('hello.txt'));
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, 'Hello core_parsing.\n第二行：中文内容。\n');
    expect(result.document?.warnings, isEmpty);
    expect(result.document?.pages, hasLength(1));
  });

  test('utf-8 BOM fixture strips the mark', () async {
    final ParseResult result = await parser.parse(
      fixturePath('hello_utf8_bom.txt'),
    );
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, 'BOM prefixed ASCII and 中文。\n');
    expect(result.document?.warnings, isEmpty);
  });

  test('utf-16 LE fixture decodes Chinese', () async {
    final ParseResult result = await parser.parse(
      fixturePath('hello_utf16le.txt'),
    );
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, 'UTF-16LE 中文\n');
    expect(result.document?.warnings, isEmpty);
  });

  test('gbk fixture falls back and records the warning', () async {
    final ParseResult result = await parser.parse(fixturePath('hello_gbk.txt'));
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, 'GBK: 中文测试\n');
    expect(result.document?.warnings, <String>['encoding-fallback:gbk']);
  });

  test('empty file is ok with an empty body', () async {
    final ParseResult result = await parser.parse(fixturePath('empty.txt'));
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, isEmpty);
    expect(result.document?.pages.single.text, isEmpty);
    expect(result.isSuccess, isTrue);
  });

  test('utf-16 BE is detected from its BOM', () async {
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}core_parsing_utf16be.txt',
    );
    final Uint8List bytes = Uint8List.fromList(<int>[
      0xFE,
      0xFF,
      0x00,
      0x42,
      0x00,
      0x45,
      0x00,
      0x20,
      0x4E,
      0x2D,
      0x65,
      0x87,
      0x00,
      0x0A,
    ]);
    await file.writeAsBytes(bytes);
    addTearDown(() => file.existsSync() ? file.delete() : null);
    final ParseResult result = await parser.parse(file.path);
    expect(result.document?.fullText, 'BE 中文\n');
    expect(result.document?.warnings, isEmpty);
  });

  test('a newline-free line under the ceiling stays ok', () async {
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}core_parsing_one_line.txt',
    );
    final String line = 'core_parsing ' * 40;
    await file.writeAsString(line);
    addTearDown(() => file.existsSync() ? file.delete() : null);
    final ParseResult result = await parser.parse(file.path);
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, line);
    expect(result.document?.pages.single.text, line);
    expect(result.document?.warnings, isEmpty);
  });

  test('bytes past the ceiling are partial and truncated', () async {
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}core_parsing_big.txt',
    );
    await file.writeAsString('abcdefg');
    addTearDown(() => file.existsSync() ? file.delete() : null);
    final ParseResult result = await TxtParser(maxBytes: 4).parse(file.path);
    expect(result.outcome, ParseOutcome.partial);
    expect(result.document?.fullText, 'abcd');
    expect(result.document?.warnings, <String>['truncated:4']);
  });

  test('a cut inside a UTF-8 character does not switch to GBK', () async {
    final File file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}core_parsing_cut.txt',
    );
    await file.writeAsString('你好');
    addTearDown(() => file.existsSync() ? file.delete() : null);
    final ParseResult result = await TxtParser(maxBytes: 4).parse(file.path);
    expect(result.outcome, ParseOutcome.partial);
    expect(result.document?.fullText, '你');
    expect(result.document?.warnings, <String>['truncated:4']);
  });

  test('a missing file is a failure, not an exception', () async {
    final ParseResult result = await parser.parse(
      fixturePath('does-not-exist.txt'),
    );
    expect(result.failure?.kind, ParseFailureKind.unknown);
    expect(result.isFailure, isTrue);
  });

  test('cancellation before reading throws', () async {
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    expect(
      parser.parse(fixturePath('hello.txt'), cancel: source.token),
      throwsA(isA<CancelledException>()),
    );
  });
}
