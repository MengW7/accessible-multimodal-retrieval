import 'dart:io';

import '../../model/document_page.dart';
import '../../model/parsed_document.dart';
import '../../spi/cancellation_token.dart';
import '../../spi/process_runner.dart';
import '../../spi/text_extractor.dart';
import '../adapters/tika_cli_text_extractor.dart';
import '../file_bytes.dart';
import '../parser.dart';

/// PDF parser. Page text comes from [TextExtractor].
///
/// A missing runtime becomes [ParseFailureKind.dependencyUnavailable].
/// A timed-out process becomes [ParseFailureKind.timeout]. Both are `failed`.
class PdfParser implements DocumentParser {
  PdfParser({required this.textExtractor});

  final TextExtractor textExtractor;

  @override
  String get name => 'pdf';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{'.pdf'};

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final Stopwatch statWatch = Stopwatch()..start();
    try {
      cancel?.throwIfCancelled();
      final FileStat stat = await File(absolutePath).stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return _fail(
          stopwatch,
          const ParseFailure(
            kind: ParseFailureKind.unknown,
            message: 'File not found.',
          ),
        );
      }
      if (stat.type == FileSystemEntityType.directory) {
        return _fail(
          stopwatch,
          const ParseFailure(
            kind: ParseFailureKind.unknown,
            message: 'Path is a directory.',
          ),
        );
      }
      if (stat.size == 0) {
        return _fail(
          stopwatch,
          const ParseFailure(
            kind: ParseFailureKind.corruptedInput,
            message: 'PDF is empty.',
          ),
        );
      }
      final int statMs = statWatch.elapsed.inMilliseconds;
      final ExtractedText text = await textExtractor.extract(
        absolutePath,
        cancel: cancel,
      );
      final Stopwatch assembleWatch = Stopwatch()..start();
      final Map<String, int> stageMs = _copyStageMs(text.attributes['stageMs'])
        ..['stat'] = statMs;
      final Map<String, Object?> attributes = <String, Object?>{
        'pageCount': text.pages.length,
        'extractor': text.extractorName,
        ...text.attributes,
        'stageMs': stageMs,
      };
      if (text.title != null) {
        attributes['title'] = text.title;
      }
      final ParsedDocument document = ParsedDocument(
        fullText: text.fullText,
        pages: List<DocumentPage>.unmodifiable(text.pages),
        attributes: Map<String, Object?>.unmodifiable(attributes),
      );
      // The nested map stays mutable so this includes building the document.
      stageMs['assemble'] = assembleWatch.elapsed.inMilliseconds;
      return ParseResult.success(document, duration: stopwatch.elapsed);
    } on CancelledException {
      rethrow;
    } on FileSystemException catch (error) {
      return _fail(stopwatch, failureForFileSystemException(error));
    } on ProcessStartException catch (error) {
      return _fail(
        stopwatch,
        ParseFailure(
          kind: ParseFailureKind.dependencyUnavailable,
          message: 'Java runtime is not available.',
          detail: error.message,
        ),
      );
    } on ProcessTimeoutException catch (error) {
      return _fail(
        stopwatch,
        ParseFailure(
          kind: ParseFailureKind.timeout,
          message: 'PDF extraction timed out.',
          detail: error.toString(),
        ),
      );
    } on TextExtractionException catch (error) {
      return _fail(
        stopwatch,
        ParseFailure(
          kind: ParseFailureKind.corruptedInput,
          message: error.message,
          detail: error.stderr,
        ),
      );
    }
  }

  ParseResult _fail(Stopwatch stopwatch, ParseFailure failure) {
    return ParseResult.failure(failure, duration: stopwatch.elapsed);
  }
}

Map<String, int> _copyStageMs(Object? raw) {
  if (raw is Map<String, int>) {
    return Map<String, int>.of(raw);
  }
  if (raw is! Map) {
    return <String, int>{};
  }
  final Map<String, int> copy = <String, int>{};
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final Object? key = entry.key;
    final Object? value = entry.value;
    if (key is String && value is int) {
      copy[key] = value;
    }
  }
  return copy;
}
