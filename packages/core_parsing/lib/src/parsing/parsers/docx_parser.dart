import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../model/document_page.dart';
import '../../model/parsed_document.dart';
import '../../spi/cancellation_token.dart';
import '../file_bytes.dart';
import '../parser.dart';

/// DOCX reader. The body comes from `word/document.xml`; title, creator, and
/// created time come from `docProps/core.xml` when that part exists.
class DocxParser implements DocumentParser {
  const DocxParser();

  @override
  String get name => 'docx';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{'.docx'};

  @override
  Future<ParseResult> parse(
    String absolutePath, {
    CancellationToken? cancel,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    final Object read = await readFileBytes(absolutePath, cancel: cancel);
    if (read is FileBytesFailure) {
      return ParseResult.failure(read.failure, duration: stopwatch.elapsed);
    }
    final FileBytesData data = read as FileBytesData;
    try {
      final Archive archive = ZipDecoder().decodeBytes(data.bytes);
      final ArchiveFile? documentPart = _findPart(archive, 'word/document.xml');
      if (documentPart == null) {
        return _corrupt(stopwatch, 'DOCX is missing word/document.xml.');
      }
      final String body = _paragraphText(
        _parseXml(documentPart.content as List<int>),
      );
      final Map<String, Object?> attributes = _coreAttributes(archive);
      return ParseResult.success(
        ParsedDocument(
          fullText: body,
          pages: <DocumentPage>[DocumentPage(pageNumber: 1, text: body)],
          attributes: Map<String, Object?>.unmodifiable(attributes),
        ),
        duration: stopwatch.elapsed,
      );
    } on ArchiveException catch (error) {
      return _corrupt(
        stopwatch,
        'DOCX is not a valid zip container.',
        error.message,
      );
    } on FormatException catch (error) {
      return _corrupt(
        stopwatch,
        'DOCX XML could not be parsed.',
        error.message,
      );
    } on XmlException catch (error) {
      return _corrupt(
        stopwatch,
        'DOCX XML could not be parsed.',
        error.message,
      );
    } on RangeError {
      return _corrupt(stopwatch, 'DOCX is not a valid zip container.');
    }
  }

  ParseResult _corrupt(Stopwatch stopwatch, String message, [String? detail]) {
    return ParseResult.failure(
      ParseFailure(
        kind: ParseFailureKind.corruptedInput,
        message: message,
        detail: detail,
      ),
      duration: stopwatch.elapsed,
    );
  }
}

ArchiveFile? _findPart(Archive archive, String wanted) {
  final ArchiveFile? direct = archive.findFile(wanted);
  if (direct != null) {
    return direct;
  }
  for (final ArchiveFile file in archive.files) {
    if (file.name.replaceAll('\\', '/') == wanted) {
      return file;
    }
  }
  return null;
}

XmlDocument _parseXml(List<int> bytes) {
  return XmlDocument.parse(utf8.decode(bytes));
}

String _paragraphText(XmlDocument document) {
  final List<String> paragraphs = <String>[];
  for (final XmlElement paragraph in document.descendantElements) {
    if (paragraph.name.local != 'p' || _hasParagraphAncestor(paragraph)) {
      continue;
    }
    paragraphs.add(_inlineText(paragraph));
  }
  return paragraphs.join('\n').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

bool _hasParagraphAncestor(XmlElement element) {
  XmlNode? parent = element.parent;
  while (parent != null) {
    if (parent is XmlElement && parent.name.local == 'p') {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}

String _inlineText(XmlElement paragraph) {
  final StringBuffer buffer = StringBuffer();
  for (final XmlElement element in paragraph.descendantElements) {
    switch (element.name.local) {
      case 't':
        buffer.write(element.innerText);
      case 'tab':
        buffer.write('\t');
      case 'br':
      case 'cr':
        buffer.write('\n');
    }
  }
  return buffer.toString();
}

Map<String, Object?> _coreAttributes(Archive archive) {
  final ArchiveFile? core = _findPart(archive, 'docProps/core.xml');
  if (core == null) {
    return const <String, Object?>{};
  }
  final XmlDocument document;
  try {
    document = _parseXml(core.content as List<int>);
  } on FormatException {
    return const <String, Object?>{};
  } on XmlException {
    return const <String, Object?>{};
  }
  final Map<String, Object?> attributes = <String, Object?>{};
  final String? title = _elementText(document, 'title');
  final String? creator = _elementText(document, 'creator');
  final String? created = _elementText(document, 'created');
  if (title != null) {
    attributes['dc:title'] = title;
  }
  if (creator != null) {
    attributes['dc:creator'] = creator;
  }
  if (created != null) {
    attributes['dcterms:created'] = created;
  }
  return attributes;
}

String? _elementText(XmlDocument document, String localName) {
  for (final XmlElement element in document.descendantElements) {
    if (element.name.local == localName) {
      return element.innerText;
    }
  }
  return null;
}
