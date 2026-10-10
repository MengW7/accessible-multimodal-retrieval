import 'dart:io';

import 'package:path/path.dart' as p;

import '../../model/document_page.dart';
import '../../spi/cancellation_token.dart';
import '../../spi/process_runner.dart';
import '../../spi/text_extractor.dart';

/// Tika produced neither XHTML pages nor a plain-text fallback.
class TextExtractionException implements Exception {
  const TextExtractionException(this.message, {this.exitCode, this.stderr});

  final String message;
  final int? exitCode;

  /// Diagnostic stderr tail. This is not document text.
  final String? stderr;

  @override
  String toString() => 'TextExtractionException: $message';
}

/// Apache Tika CLI behind [TextExtractor].
///
/// Runs `TikaCLI -x` and splits `<div class="page">`. If that yields no pages,
/// runs `-t` and returns one page. stdout is the only text; stderr is diagnostic.
/// The classpath separator is `;` on Windows and `:` elsewhere.
class TikaCliTextExtractor implements TextExtractor {
  TikaCliTextExtractor({
    required this.processRunner,
    required this.tikaHome,
    this.javaExecutable = 'java',
    this.version = '4.0.0',
    this.timeout = const Duration(seconds: 60),
    String? classpathSeparator,
  }) : classpathSeparator =
           classpathSeparator ?? (Platform.isWindows ? ';' : ':');

  final ProcessRunner processRunner;
  final String tikaHome;
  final String javaExecutable;

  @override
  final String version;

  final Duration timeout;
  final String classpathSeparator;

  static const String _mainClass = 'org.apache.tika.cli.TikaCLI';

  @override
  String get name => 'tika-cli';

  @override
  Future<ExtractedText> extract(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    final ProcessRunResult xhtml = await _run('-x', absolutePath, cancel);
    final Stopwatch split = Stopwatch()..start();
    final List<String> pages = pageTextsFromXhtml(xhtml.stdout);
    final int xhtmlSplitMs = split.elapsed.inMilliseconds;
    if (pages.isNotEmpty) {
      return _extracted(
        pages,
        mode: 'xhtml',
        stageMs: _stageMs(xhtml, xhtmlSplitMs, textFallbackMs: 0),
      );
    }
    final ProcessRunResult plain = await _run('-t', absolutePath, cancel);
    if (!plain.isSuccess) {
      throw TextExtractionException(
        'Tika text extraction failed.',
        exitCode: plain.exitCode,
        stderr: _stderrTail(plain.stderr),
      );
    }
    return _extracted(
      <String>[_normalizeNewlines(plain.stdout).trim()],
      mode: 'text',
      stageMs: _stageMs(
        xhtml,
        xhtmlSplitMs,
        textFallbackMs: plain.duration.inMilliseconds,
      ),
    );
  }

  Future<ProcessRunResult> _run(
    String modeFlag,
    String absolutePath,
    CancellationToken? cancel,
  ) {
    return processRunner.run(
      javaExecutable,
      <String>['-cp', _classpath(), _mainClass, modeFlag, absolutePath],
      timeout: timeout,
      cancel: cancel,
    );
  }

  String _classpath() {
    final String jar = p.join(tikaHome, 'tika-app-$version.jar');
    final String lib = p.join(tikaHome, 'lib', '*');
    return '$jar$classpathSeparator$lib';
  }

  ExtractedText _extracted(
    List<String> pages, {
    required String mode,
    required Map<String, int> stageMs,
  }) {
    final List<DocumentPage> documents = <DocumentPage>[
      for (var index = 0; index < pages.length; index++)
        DocumentPage(pageNumber: index + 1, text: pages[index]),
    ];
    return ExtractedText(
      pages: documents,
      extractorName: name,
      attributes: <String, Object?>{'mode': mode, 'stageMs': stageMs},
    );
  }
}

/// Milliseconds for one `-x` process plus the optional `-t` fallback.
///
/// [textFallbackMs] is the whole second process. It is 0 when `-x` already
/// produced page divs. `process_wait` still includes JVM startup.
Map<String, int> _stageMs(
  ProcessRunResult xhtml,
  int xhtmlSplitMs, {
  required int textFallbackMs,
}) {
  return <String, int>{
    'process_start': xhtml.processStart.inMilliseconds,
    'process_wait': xhtml.processWait.inMilliseconds,
    'stream_drain': xhtml.streamDrain.inMilliseconds,
    'xhtml_split': xhtmlSplitMs,
    'text_fallback': textFallbackMs,
  };
}

/// Page bodies from Tika XHTML, in document order.
///
/// Returns an empty list when no `class="page"` div is present so the caller
/// can fall back to plain text.
List<String> pageTextsFromXhtml(String xhtml) {
  final RegExp pattern = RegExp(
    '<div\\b[^>]*\\bclass\\s*=\\s*([\'"])(.*?)\\1[^>]*>',
    caseSensitive: false,
  );
  final List<RegExpMatch> matches = pattern.allMatches(xhtml).where((
    RegExpMatch match,
  ) {
    final String classes = match.group(2) ?? '';
    return classes.split(RegExp(r'\s+')).contains('page');
  }).toList();
  if (matches.isEmpty) {
    return const <String>[];
  }
  final List<String> pages = <String>[];
  for (var index = 0; index < matches.length; index++) {
    final int start = matches[index].end;
    final int end = index + 1 < matches.length
        ? matches[index + 1].start
        : xhtml.length;
    pages.add(_htmlToText(xhtml.substring(start, end)));
  }
  return pages;
}

String _htmlToText(String html) {
  final String withBreaks = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
  final String stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');
  return _normalizeNewlines(_decodeEntities(stripped)).trim();
}

String _decodeEntities(String input) {
  return input.replaceAllMapped(
    RegExp(r'&(#x[0-9A-Fa-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);'),
    (Match match) {
      final String token = match.group(1)!;
      if (token.startsWith('#x')) {
        final int? code = int.tryParse(token.substring(2), radix: 16);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      if (token.startsWith('#')) {
        final int? code = int.tryParse(token.substring(1));
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      switch (token) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
        default:
          return match.group(0)!;
      }
    },
  );
}

String _normalizeNewlines(String input) {
  return input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

String _stderrTail(String stderr) {
  const int limit = 400;
  if (stderr.length <= limit) {
    return stderr;
  }
  return stderr.substring(stderr.length - limit);
}
