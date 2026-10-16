@Tags(['integration'])
library;

import 'dart:io';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _repoFile(String relative) {
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

final class _Dist {
  _Dist(List<int> raw) : values = List<int>.of(raw)..sort();

  final List<int> values;

  int get count => values.length;

  int get min => values.first;

  int get max => values.last;

  int get p50 => values[count ~/ 2];

  int get overBudget => values
      .where((int value) => value > CascadeTextChunker.defaultMaxTokens)
      .length;

  String get mean {
    final int sum = values.fold(0, (int total, int value) => total + value);
    return (sum / count).toStringAsFixed(2);
  }
}

/// 按 [chunkChars] 切不重叠窗口。窗口落在代理对中间时把低位一起带上。
List<String> _windows(String text, int chunkChars) {
  final List<String> windows = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = start + chunkChars;
    if (end > text.length) {
      end = text.length;
    } else if (_splitsSurrogate(text, end)) {
      end += 1;
    }
    final String slice = text.substring(start, end);
    if (slice.trim().isNotEmpty) {
      windows.add(slice);
    }
    start = end;
  }
  return windows;
}

bool _splitsSurrogate(String text, int index) {
  if (index <= 0 || index >= text.length) {
    return false;
  }
  final int high = text.codeUnitAt(index - 1);
  final int low = text.codeUnitAt(index);
  return high >= 0xD800 && high <= 0xDBFF && low >= 0xDC00 && low <= 0xDFFF;
}

void main() {
  test('default chunkChars is measured on datasets/samples', () async {
    final String tokenizerPath = _repoFile(
      'models/raw/text/paraphrase-multilingual-MiniLM-L12-v2/tokenizer.json',
    );
    final UnigramTokenizer tokenizer = UnigramTokenizer.fromFile(tokenizerPath);
    int countTokens(String text) => tokenizer.encode(text).ids.length;
    final CascadeTextChunker chunker = CascadeTextChunker(
      countTokens: countTokens,
    );
    final PdfParser pdfParser = PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: _repoFile('tools/tika-app'),
      ),
    );

    final StringBuffer log = StringBuffer()
      ..writeln('corpus=datasets/samples')
      ..writeln('counter=unigram')
      ..writeln('specials=included')
      ..writeln('chunkChars=${CascadeTextChunker.defaultChunkChars}')
      ..writeln('maxTokens=${CascadeTextChunker.defaultMaxTokens}')
      ..writeln('chunker=${CascadeTextChunker.defaultVersion}')
      ..writeln('image=datasets/samples/sample.png skipped_no_text');

    final List<(String, ParsedDocument)> documents = <(String, ParsedDocument)>[
      (
        'datasets/samples/sample.docx',
        await _document(const DocxParser(), 'datasets/samples/sample.docx'),
      ),
      (
        'datasets/samples/sample.pdf',
        await _document(pdfParser, 'datasets/samples/sample.pdf'),
      ),
    ];

    var windowsOverBudget = 0;
    for (final (String relative, ParsedDocument document) in documents) {
      final List<int> windowTokens = <int>[];
      for (final DocumentPage page in document.pages) {
        for (final String window in _windows(page.text, chunker.chunkChars)) {
          windowTokens.add(countTokens(window));
        }
      }
      expect(windowTokens, isNotEmpty, reason: relative);
      final _Dist windows = _Dist(windowTokens);
      windowsOverBudget += windows.overBudget;
      final List<TextChunk> chunks = chunker.chunk(
        document,
        documentId: relative,
      );
      final List<int> chunkTokens = <int>[
        for (final TextChunk chunk in chunks) countTokens(chunk.text),
      ];
      expect(chunkTokens, isNotEmpty, reason: relative);
      final _Dist chunkDist = _Dist(chunkTokens);
      expect(chunkDist.overBudget, 0, reason: '$relative chunk tokens');
      final int contentTokens = countTokens(document.fullText) - 2;
      final String charsPerToken = contentTokens <= 0
          ? 'na'
          : (document.fullText.length / contentTokens).toStringAsFixed(2);
      log
        ..writeln(
          'file=$relative pages=${document.pages.length} chars=${document.fullText.length}',
        )
        ..writeln(
          'file=$relative windows=${windows.count} tokens_min=${windows.min} '
          'tokens_p50=${windows.p50} tokens_mean=${windows.mean} tokens_max=${windows.max} '
          'windows_over_budget=${windows.overBudget}',
        )
        ..writeln(
          'file=$relative chunks=${chunkDist.count} chunk_tokens_min=${chunkDist.min} '
          'chunk_tokens_p50=${chunkDist.p50} chunk_tokens_max=${chunkDist.max} '
          'chars_per_content_token=$charsPerToken',
        );
    }
    log
      ..writeln(
        'note=120 is the initial character window on this MiniLM corpus, not a universal optimum. '
        'windows_over_budget counts 120-code-unit windows whose Unigram length, specials included, exceeds 128. '
        'sample.docx and sample.pdf are about 4 characters per content token, so this log does not measure the Chinese one-character bound.',
      )
      ..writeln('windows_over_budget=$windowsOverBudget')
      ..writeln('gate=${windowsOverBudget == 0 ? 'pass' : 'fail'}');
    final Directory logs = Directory(_repoFile('reports/week3/logs'));
    await File(p.join(logs.path, 'chunk_chars_calibration.txt'))
        .writeAsString(log.toString());
    expect(windowsOverBudget, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<ParsedDocument> _document(DocumentParser parser, String relative) async {
  final ParseResult result = await parser.parse(_repoFile(relative));
  expect(result.outcome, ParseOutcome.ok, reason: relative);
  final ParsedDocument? document = result.document;
  expect(document, isNotNull, reason: relative);
  return document!;
}
