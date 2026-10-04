import 'package:meta/meta.dart';

import 'document_page.dart';
import 'image_asset.dart';
import 'parse_outcome.dart';

/// 文件无法转成内容的原因
///
/// 分类刻意做得粗：入库报告按它分组，UI（W5）用它拼给读屏的说明。
enum ParseFailureKind {
  /// 没有为该扩展名注册解析器。
  unsupportedFormat,

  /// 字节内容不是所声明格式的合法文档。
  corruptedInput,

  /// 解析器需要的外部依赖不可用（例如 Apache Tika 所需的 JDK）。
  dependencyUnavailable,

  /// 解析器超出了时间预算。
  timeout,

  /// 文件因文件系统权限无法打开。
  permissionDenied,

  /// 在文件开始解析前就收到了取消请求。
  cancelled,

  /// 以上都不属于的情况；细节见 [ParseFailure.message]。
  unknown,
}

/// 对解析失败的结构化、非致命描述。
@immutable
class ParseFailure {
  const ParseFailure({required this.kind, required this.message, this.detail});

  /// 用于报告与降级策略的分类。
  final ParseFailureKind kind;

  /// 面向使用者的简短说明（不含堆栈）。
  final String message;

  /// 诊断细节：stderr 片段、异常文本等。绝不包含文件正文。
  final String? detail;

  /// 该失败映射到的结果分类。
  ///
  /// 格式不支持与权限问题属于*跳过*而非错误：批次必须继续，
  /// 报告也不应把它们算作缺陷。
  ParseOutcome get outcome {
    switch (kind) {
      case ParseFailureKind.unsupportedFormat:
      case ParseFailureKind.permissionDenied:
      case ParseFailureKind.cancelled:
        return ParseOutcome.skipped;
      case ParseFailureKind.corruptedInput:
      case ParseFailureKind.dependencyUnavailable:
      case ParseFailureKind.timeout:
      case ParseFailureKind.unknown:
        return ParseOutcome.failed;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'outcome': outcome.name,
    'message': message,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      other is ParseFailure &&
      other.kind == kind &&
      other.message == message &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, message, detail);

  @override
  String toString() => 'ParseFailure(${kind.name}: $message)';
}

/// 解析器从单个文件中提取出的全部内容。
@immutable
class ParsedDocument {
  const ParsedDocument({
    required this.fullText,
    this.pages = const <DocumentPage>[],
    this.imageAsset,
    this.attributes = const <String, Object?>{},
    this.outcome = ParseOutcome.ok,
    this.warnings = const <String>[],
  });

  /// 所有页拼接后的文本，换行符已归一。
  final String fullText;

  /// 逐页文本；纯图像文档可能为空。
  final List<DocumentPage> pages;

  /// 仅在输入为 JPG/PNG 时存在。
  final ImageAsset? imageAsset;

  /// 还不足以单独建字段的格式特有信息（例如 DOCX 的 `dc:title` / `dc:creator`）。
  final Map<String, Object?> attributes;

  /// 本次解析的分类。
  final ParseOutcome outcome;

  /// 机器可读的非致命提示，如 `encoding-fallback:gbk`。
  final List<String> warnings;

  /// 是否提取到了任何文本。
  bool get hasText => fullText.trim().isNotEmpty;

  /// 页数；没有显式分页列表的纯文本文档记为一页。
  /// 只有空白字符时记为 0 页：它没有可供嵌入引擎消费的内容。
  int get pageCount {
    if (pages.isNotEmpty) {
      return pages.length;
    }
    return hasText ? 1 : 0;
  }

  /// 文档含图像且无文本时为 `true`（W3 的 MobileCLIP 路径）。
  bool get isImageOnly {
    final asset = imageAsset;
    return asset != null && !hasText;
  }

  /// [fullText] 的字符数。
  int get charCount => fullText.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'outcome': outcome.name,
    'charCount': charCount,
    'pageCount': pageCount,
    'hasText': hasText,
    'imageAsset': imageAsset?.toJson(),
    'attributes': attributes,
    'warnings': warnings,
    'pages': pages.map((DocumentPage page) => page.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is ParsedDocument &&
      other.fullText == fullText &&
      other.imageAsset == imageAsset &&
      other.outcome == outcome &&
      _listEquals(other.pages, pages) &&
      _mapEquals(other.attributes, attributes) &&
      _listEquals(other.warnings, warnings);

  @override
  int get hashCode => Object.hash(
    fullText,
    imageAsset,
    outcome,
    Object.hashAll(pages),
    Object.hashAll(warnings),
  );

  @override
  String toString() =>
      'ParsedDocument(outcome: ${outcome.name}, pages: $pageCount, chars: $charCount)';
}

/// 解析单个文件的结果：要么是内容，要么是失败。
@immutable
class ParseResult {
  const ParseResult.success(
    ParsedDocument this.document, {
    this.duration = Duration.zero,
  }) : failure = null;

  const ParseResult.failure(
    ParseFailure this.failure, {
    this.duration = Duration.zero,
  }) : document = null;

  /// 提取到的内容；解析失败或被跳过时为 `null`。
  final ParsedDocument? document;

  /// 失败描述；成功时为 `null`。
  final ParseFailure? failure;

  /// 解析该文件消耗的墙钟时间。
  final Duration duration;

  /// 实际分类，由存在的那一侧推导。
  ParseOutcome get outcome {
    final parsed = document;
    if (parsed != null) {
      return parsed.outcome;
    }
    final error = failure;
    return error?.outcome ?? ParseOutcome.failed;
  }

  /// 是否产出了可用内容。
  bool get isSuccess {
    final parsed = document;
    return parsed != null && parsed.outcome.isUsable;
  }

  /// 是否没有产出任何内容。
  bool get isFailure => document == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'outcome': outcome.name,
    'durationMs': duration.inMilliseconds,
    'document': document?.toJson(),
    'failure': failure?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ParseResult &&
      other.document == document &&
      other.failure == failure &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(document, failure, duration);

  @override
  String toString() => 'ParseResult(outcome: ${outcome.name})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<K, V> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
