# 解析模块 API

## 1. 调用约定

外部代码 import：

```dart
import 'package:core_parsing/core_parsing.dart';
```

一次目录入库：

```dart
final IngestionReport report = await IngestionService(
  registry: StandardParserRegistry(<DocumentParser>[
    TxtParser(),
    const DocxParser(),
    PdfParser(
      textExtractor: TikaCliTextExtractor(
        processRunner: const IoProcessRunner(),
        tikaHome: r'tools\tika-app',
      ),
    ),
    const ImageParser(),
  ]),
  metadata: FileMetadataExtractor(),
).ingestDirectory(r'datasets\samples');
```

**异常。** 文件损坏、缺 Java、超时、权限不足、不支持的扩展名都变成 `ParseFailure`，放进 `ParseResult` 或 `IngestRecord`。`CancelledException` 是唯一会从解析器冒出来的协作式取消。`IngestionService.ingestDirectory` 接住扫描阶段的 `FileSystemException` 和 `CancelledException`，返回报告。`maxDepth < 0` 以及构造参数断言失败仍抛异常，那是调用错误。

**线程。** 全部实现都在调用方的 isolate 上运行。`ImmediateExecutor` 不把工作送进别的 isolate。这些对象没有内部锁。`CancellationToken` 可以在同一个 isolate 里跨回调使用，不要把它传到另一个 isolate。`IoProcessRunner` 通过 `dart:io` 收子进程输出，回调发生在当前 isolate 的事件循环上。

## 2. 结果

### `ParseOutcome`

```dart
enum ParseOutcome { ok, partial, skipped, failed }
bool get isUsable
```

```dart
const ParseOutcome outcome = ParseOutcome.ok;
// outcome.isUsable == true
// ParseOutcome.skipped.isUsable == false
```

`ok` 是完整成功。`partial` 是成功但有截断或降级。`skipped` 是跳过（格式不支持、权限不足、取消前就停）。`failed` 是试过之后失败。`isUsable` 只在 `ok` 和 `partial` 时为真。

### `ParseFailureKind` / `ParseFailure`

```dart
enum ParseFailureKind {
  unsupportedFormat,
  corruptedInput,
  dependencyUnavailable,
  timeout,
  permissionDenied,
  cancelled,
  unknown,
}

class ParseFailure {
  const ParseFailure({required this.kind, required this.message, this.detail});
  ParseOutcome get outcome;
  Map<String, Object?> toJson();
}
```

```dart
const ParseFailure failure = ParseFailure(
  kind: ParseFailureKind.corruptedInput,
  message: 'PDF is empty.',
);
// failure.outcome == ParseOutcome.failed
```

`unsupportedFormat`、`permissionDenied`、`cancelled` 映射到 `skipped`。其余映射到 `failed`。`message` 给人看，`detail` 放 stderr 或异常文本，不放正文。`toJson` 含 `kind`、`outcome`、`message`、`detail`。不抛异常。

### `ParsedDocument`

```dart
class ParsedDocument {
  const ParsedDocument({
    required this.fullText,
    this.pages = const <DocumentPage>[],
    this.imageAsset,
    this.attributes = const <String, Object?>{},
    this.outcome = ParseOutcome.ok,
    this.warnings = const <String>[],
  });
  bool get hasText;
  int get pageCount;
  bool get isImageOnly;
  int get charCount;
  Map<String, Object?> toJson();
}
```

```dart
const ParsedDocument document = ParsedDocument(fullText: 'Hello\n');
// document.pageCount == 1
// document.hasText == true
const ParsedDocument blank = ParsedDocument(fullText: '  ');
// blank.pageCount == 0
```

没有 `pages` 时，有正文记 1 页，只有空白记 0 页。`isImageOnly` 表示有图且没有正文。`warnings` 例如 `encoding-fallback:gbk`。不抛异常。

### `ParseResult`

```dart
class ParseResult {
  const ParseResult.success(ParsedDocument document, {Duration duration = Duration.zero});
  const ParseResult.failure(ParseFailure failure, {Duration duration = Duration.zero});
  ParseOutcome get outcome;
  bool get isSuccess;
  bool get isFailure;
  Map<String, Object?> toJson();
}
```

```dart
const ParseResult ok = ParseResult.success(
  ParsedDocument(fullText: 'Hello\n'),
);
const ParseResult bad = ParseResult.failure(
  ParseFailure(kind: ParseFailureKind.unknown, message: 'missing'),
);
// ok.isSuccess == true
// bad.document == null
// bad.failure?.outcome == ParseOutcome.failed
```

成功时 `failure` 为 null，失败时 `document` 为 null。`duration` 是这一次解析的墙钟时间。

### `DocumentPage`

```dart
class DocumentPage {
  const DocumentPage({required this.pageNumber, required this.text});
  bool get isEmpty;
  int get charCount;
  Map<String, Object?> toJson();
}
```

```dart
const DocumentPage page = DocumentPage(pageNumber: 1, text: '第一页');
// page.charCount == 3
// page.isEmpty == false
```

`pageNumber` 从 1 开始。TXT 和 DOCX 只有第 1 页。PDF 一页一条。

### `ImageAsset`

```dart
class ImageAsset {
  const ImageAsset({
    required this.format,
    required this.width,
    required this.height,
    this.colorMode,
    this.orientation,
  });
  int get pixelCount;
  double get aspectRatio;
  Map<String, Object?> toJson();
}
```

```dart
const ImageAsset asset = ImageAsset(
  format: 'png',
  width: 1186,
  height: 1137,
  colorMode: 'rgb',
);
// asset.pixelCount == 1186 * 1137
// asset.orientation == null
```

`format` 是小写容器名，本包写出 `png` 或 `jpeg`。`colorMode` 为 `rgb`、`rgba`、`grayscale`、`grayscale-alpha`。没有 EXIF 时 `orientation` 为 null。高度为 0 时 `aspectRatio` 为 0。

## 3. 文件与入库

### `FileMetadata`

```dart
class FileMetadata {
  const FileMetadata({
    required this.id,
    required this.path,
    required this.relativePath,
    required this.fileName,
    required this.extension,
    required this.sizeBytes,
    this.mimeType,
    this.createdAt,
    this.modifiedAt,
    this.accessedAt,
    this.contentHash,
    this.indexedAt,
    this.parserName,
    this.parserVersion,
    this.parseDurationMs,
    this.status = ParseOutcome.skipped,
    this.errorMessage,
    this.imageAsset,
  });
  bool get isIndexable;
  FileMetadata copyWith({/* 与字段同名的可选参数 */});
  Map<String, Object?> toJson();
}
```

```dart
const FileMetadata metadata = FileMetadata(
  id: 'abc',
  path: r'datasets\samples\sample.txt',
  relativePath: 'sample.txt',
  fileName: 'sample.txt',
  extension: '.txt',
  sizeBytes: 12,
  status: ParseOutcome.ok,
);
// metadata.isIndexable == true
```

`id` 有内容哈希时是 SHA-256，否则是相对路径的哈希。`relativePath` 用 `/`。`createdAt` 来自 `stat.changed`，因为 `dart:io` 没有 birth time。`isIndexable` 等于 `status.isUsable`。`copyWith` 只替换传入的字段。

### `IngestRecord` / `IngestionReport` / `IngestProgress`

```dart
class IngestRecord {
  const IngestRecord({required this.metadata, this.document, this.failure});
  ParseOutcome get outcome;
  bool get hasContent;
  Map<String, Object?> toJson({bool includeText = false});
}

class IngestionReport {
  const IngestionReport({
    required this.rootPath,
    required this.startedAt,
    required this.finishedAt,
    this.records = const <IngestRecord>[],
    this.cancelled = false,
  });
  Duration get duration;
  int get total;
  int countOf(ParseOutcome outcome);
  int get succeeded; int get partial; int get skipped; int get failed;
  List<IngestRecord> get failures;
  List<IngestRecord> get indexable;
  bool get isClean;
  Map<String, Object?> toJson({bool includeRecords = true});
}

class IngestProgress {
  const IngestProgress({
    required this.processed,
    required this.total,
    this.currentPath,
    this.elapsed = Duration.zero,
  });
  double get fraction;
  Map<String, Object?> toJson();
}
```

```dart
final IngestRecord record = IngestRecord(
  metadata: FileMetadata(
    id: 'abc',
    path: r'datasets\samples\sample.txt',
    relativePath: 'sample.txt',
    fileName: 'sample.txt',
    extension: '.txt',
    sizeBytes: 12,
    status: ParseOutcome.ok,
  ),
);
final IngestionReport report = IngestionReport(
  rootPath: r'datasets\samples',
  startedAt: DateTime.utc(2026, 10, 5),
  finishedAt: DateTime.utc(2026, 10, 5, 0, 0, 1),
  records: <IngestRecord>[record],
);
const IngestProgress progress = IngestProgress(processed: 1, total: 2);
// record.toJson() 不含正文，只留 charCount
// progress.fraction == 0.5
// report.isClean == true
```

`toJson(includeText: false)` 不复制正文，只留长度。`isClean` 表示没有 `failed` 且没有取消。`fraction` 在 `total <= 0` 或已经做完时为 1。

### `defaultIngestExtensions` / `FileScanner`

```dart
const Set<String> defaultIngestExtensions;
class FileScanner {
  const FileScanner();
  Future<List<String>> scan(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    CancellationToken? cancel,
  });
}
```

```dart
const FileScanner scanner = FileScanner();
final List<String> files = await scanner.scan(r'datasets\samples');
// files 是已排序的绝对路径，扩展名落在 defaultIngestExtensions 里
```

白名单默认是 `.txt`、`.pdf`、`.docx`、`.jpg`、`.jpeg`、`.png`。扩展名可以不带点，比较时忽略大小写。跳过 `.` 或 `~$` 开头的名字，以及 `$Recycle.Bin`、`System Volume Information`。结果是绝对路径，已排序。`maxDepth` 为 0 只看根目录自己的文件。

抛出异常：`maxDepth < 0` 抛 `ArgumentError`；根不存在或不是目录抛 `FileSystemException`；已取消抛 `CancelledException`。入库服务会把后两种收成报告，直接调用扫描器则不会。

### `MetadataExtractor` / `FileMetadataExtractor` / `mimeTypeForExtension`

```dart
abstract interface class MetadataExtractor {
  Future<FileMetadata> describe(
    String absolutePath, {
    required String rootPath,
    int? maxFileSizeBytes,
    CancellationToken? cancel,
  });
}

class FileMetadataExtractor implements MetadataExtractor {
  FileMetadataExtractor({this.maxFileSizeBytes = 10 * 1024 * 1024});
}

String? mimeTypeForExtension(String extension);
```

```dart
final FileMetadataExtractor extractor = FileMetadataExtractor();
final FileMetadata described = await extractor.describe(
  r'datasets\samples\sample.png',
  rootPath: r'datasets\samples',
);
// mimeTypeForExtension('.png') == 'image/png'
// mimeTypeForExtension('.bin') == null
```

超过大小上限的文件仍返回元数据，但 `contentHash` 为 null。权限错误的 `status` 是 `skipped`，其他读失败是 `failed`，两者都不抛 `FileSystemException`。已取消则抛 `CancelledException`。`maxFileSizeBytes` 必须为正，否则构造时断言失败。

`mimeTypeForExtension` 认识 `.txt`、`.pdf`、`.docx`、`.jpg`、`.jpeg`、`.png`，其余返回 null。不抛异常。

### `IngestionService`

```dart
class IngestionService {
  IngestionService({
    required this.registry,
    required this.metadata,
    this.scanner = const FileScanner(),
    this.executor = const ImmediateExecutor(),
    this.concurrency = 2,
    this.maxFileSizeBytes = 10 * 1024 * 1024,
  });

  Future<IngestionReport> ingestDirectory(
    String rootPath, {
    Set<String> extensions = defaultIngestExtensions,
    bool followLinks = false,
    int maxDepth = 32,
    void Function(IngestProgress)? onProgress,
    CancellationToken? cancel,
  });
}
```

调用示例见第 1 节。

顺序是扫描、逐文件描述、按 SHA-256 去重、解析、汇总。一个坏文件记入报告后继续。相同内容的第二个文件为 `skipped`，不再解析。`concurrency` 是同时处理的文件数，默认执行器仍在当前 isolate。`concurrency >= 1`，`maxFileSizeBytes > 0`，否则构造时断言失败。

根目录不存在、不是目录或列不出来：返回一条记录，权限不足为 `skipped`，其余为 `failed`，不抛 `FileSystemException`。调用前已经取消：空报告且 `cancelled` 为真，并回调一次 `0/0`。扫描或单个解析器抛出 `CancelledException`：停掉剩余文件，已完成的记录保留。

## 4. 解析器

### `DocumentParser`

```dart
abstract interface class DocumentParser {
  String get name;
  String get version;
  Set<String> get supportedExtensions;
  Future<ParseResult> parse(String absolutePath, {CancellationToken? cancel});
}
```

```dart
final DocumentParser parser = TxtParser();
final ParseResult parsed = await parser.parse(r'test\fixtures\hello.txt');
// 损坏或缺失返回 ParseResult.failure，不向外抛文件错误
```

文件本身的问题必须返回 `ParseResult.failure`。实现应在读取前调用 `cancel.throwIfCancelled()`，那时抛 `CancelledException`。不要为损坏文件抛其他异常；万一抛了，入库服务会记成 `unknown`。

### `ParserRegistry` / `StandardParserRegistry` / `normalizeParserExtension`

```dart
abstract interface class ParserRegistry {
  List<DocumentParser> get parsers;
  Set<String> get supportedExtensions;
  DocumentParser? resolveForExtension(String extension);
  DocumentParser? resolveForPath(String absolutePath);
  bool supports(String absolutePath);
}

class StandardParserRegistry implements ParserRegistry {
  StandardParserRegistry(Iterable<DocumentParser> parsers);
  Future<ParseResult> parse(String absolutePath, {CancellationToken? cancel});
}

String? normalizeParserExtension(String extension);
```

```dart
final StandardParserRegistry registry = StandardParserRegistry(<DocumentParser>[
  TxtParser(),
]);
final DocumentParser? parser = registry.resolveForPath(r'notes\A.TXT');
// parser != null
// normalizeParserExtension('TXT') == '.txt'
// normalizeParserExtension('.') == null
```

同一个扩展名第一次注册的解析器生效。未知扩展名返回 null，`parse` 返回 `unsupportedFormat`，不抛异常。`normalizeParserExtension` 把 `TXT`、`.TXT`、`txt` 都收成 `.txt`；空串和单独的 `.` 返回 null。不抛异常。

### `TxtParser`

```dart
class TxtParser implements DocumentParser {
  TxtParser({this.maxBytes = 10 * 1024 * 1024});
  static const int defaultMaxBytes = 10 * 1024 * 1024;
}
```

```dart
final ParseResult result = await TxtParser().parse(r'test\fixtures\hello.txt');
// result.outcome == ParseOutcome.ok
// result.document?.fullText 含归一化后的换行
```

嗅探顺序：UTF-8 BOM、UTF-16 LE/BE BOM、严格 UTF-8，最后 GBK。换行收成 `\n`。超过 `maxBytes` 时 `outcome` 为 `partial`，并尽量不把半个字符留给 GBK。GBK 兜底会在 `warnings` 里写 `encoding-fallback:gbk`。空文件是 `ok` 加空正文。缺失文件是 `failed`。`maxBytes` 必须为正。取消抛 `CancelledException`。

### `DocxParser`

```dart
class DocxParser implements DocumentParser {
  const DocxParser();
}
```

```dart
final ParseResult result = await const DocxParser().parse(
  r'datasets\samples\sample.docx',
);
// 成功时 outcome 为 ok，正文非空，且不调用 Tika
```

纯 Dart：解 `word/document.xml`，按段落拼接，`w:tab` 成制表符，`w:br` 成换行。`docProps/core.xml` 里有值才写入 `dc:title`、`dc:creator`、`dcterms:created`。没有该部件时正文仍然成功，这三个键不出现。坏 zip、缺 `word/document.xml`、XML 无法解析都是 `corruptedInput` / `failed`。不调用 Tika。取消抛 `CancelledException`。

### `PdfParser`

```dart
class PdfParser implements DocumentParser {
  PdfParser({required this.textExtractor});
}
```

```dart
final PdfParser parser = PdfParser(
  textExtractor: TikaCliTextExtractor(
    processRunner: const IoProcessRunner(),
    tikaHome: r'tools\tika-app',
  ),
);
final ParseResult result = await parser.parse(r'datasets\samples\sample.pdf');
// result.document?.attributes['pageCount'] 与页列表长度一致
```

页文本来自 `textExtractor`。每页一个 `DocumentPage`，`attributes['pageCount']` 与页列表长度一致。空文件和目录是 `failed`，不会去启动提取器。`ProcessStartException` 变成 `dependencyUnavailable`（缺 Java）。`ProcessTimeoutException` 变成 `timeout`。`TextExtractionException` 变成 `corruptedInput`，stderr 在 `detail`。取消抛 `CancelledException`。

### `ImageParser`

```dart
class ImageParser implements DocumentParser {
  const ImageParser();
}
```

```dart
final ParseResult result = await const ImageParser().parse(
  r'datasets\samples\sample.png',
);
// result.document?.fullText 为空
// result.document?.imageAsset?.format == 'png'
```

读 JPEG 和 PNG 的格式、宽高、色彩模式。正文为空。没有 EXIF 不报错，`orientation` 为 null。空文件、伪装扩展名、解码失败都是 `corruptedInput`。缺失文件是 `failed`。取消抛 `CancelledException`。

### `TextExtractor` / `ExtractedText`

```dart
abstract interface class TextExtractor {
  String get name;
  String get version;
  Future<ExtractedText> extract(String absolutePath, {CancellationToken? cancel});
}

class ExtractedText {
  const ExtractedText({
    required this.pages,
    required this.extractorName,
    this.title,
    this.attributes = const <String, Object?>{},
  });
  String get fullText;
  bool get hasText;
}
```

```dart
const ExtractedText text = ExtractedText(
  pages: <DocumentPage>[
    DocumentPage(pageNumber: 1, text: '第一页'),
    DocumentPage(pageNumber: 2, text: '第二页'),
  ],
  extractorName: 'tika-cli',
);
// text.fullText == '第一页\n\n第二页'
```

`fullText` 用空行连接各页。文档问题由实现抛出调用方已经声明的异常，再由 `PdfParser` 收成 `ParseFailure`。取消抛 `CancelledException`。

### `TikaCliTextExtractor` / `TextExtractionException` / `pageTextsFromXhtml`

```dart
class TikaCliTextExtractor implements TextExtractor {
  TikaCliTextExtractor({
    required this.processRunner,
    required this.tikaHome,
    this.javaExecutable = 'java',
    this.version = '4.0.0',
    this.timeout = const Duration(seconds: 60),
    String? classpathSeparator,
  });
}

class TextExtractionException implements Exception {
  const TextExtractionException(this.message, {this.exitCode, this.stderr});
}

List<String> pageTextsFromXhtml(String xhtml);
```

```dart
final List<String> pages = pageTextsFromXhtml(
  '<div class="page">第一页</div><div class="page">第二页</div>',
);
// pages.length == 2
// pageTextsFromXhtml('<html></html>') 返回空列表
```

先跑 `TikaCLI -x`。XHTML 里有 `class="page"` 的 div 就按页切开；没有则再跑 `-t`，整篇作为一页。正文只取 stdout。classpath 在 Windows 上用 `;`，其他系统用 `:`。`-x` 起不来或超时会直接抛，不再跑 `-t`；`-x` 有退出码但没有 page div 时会回退 `-t`。两种模式都拿不到正文时抛 `TextExtractionException`。Java 起不来由 `ProcessRunner` 抛 `ProcessStartException`。`pageTextsFromXhtml` 没有 page div 时返回空列表，不抛异常。HTML 实体支持 `amp lt gt quot apos nbsp` 以及十进制、十六进制数字实体。

## 5. 进程、执行与取消

### `ProcessRunner` / `IoProcessRunner` / `ProcessRunResult`

```dart
abstract interface class ProcessRunner {
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    CancellationToken? cancel,
  });
}

class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();
}

class ProcessRunResult {
  const ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.duration = Duration.zero,
  });
  bool get isSuccess;
  Map<String, Object?> toJson();
}
```

```dart
const ProcessRunResult run = ProcessRunResult(
  exitCode: 0,
  stdout: '<div class="page">ok</div>',
  stderr: '',
);
// run.isSuccess == true
// run.toJson() 只记 stdout、stderr 的长度
// 真 Java 用 const IoProcessRunner()，只出现在 integration 用例里
```

这是包内唯一允许启动进程的类型。`IoProcessRunner` 调用 `Process.start`。起不来抛 `ProcessStartException`。超时先杀掉进程再抛 `ProcessTimeoutException`。取消杀掉进程并抛 `CancelledException`。`toJson` 只记 stdout/stderr 的长度，不记内容。默认单测注入假实现；真 Java 只放在 `integration` tag 的用例里，用 `dart test --tags integration` 跑。

### `ProcessStartException` / `ProcessTimeoutException`

```dart
class ProcessStartException implements Exception {
  const ProcessStartException(this.executable, this.message);
}
class ProcessTimeoutException implements Exception {
  const ProcessTimeoutException(this.executable, this.timeout);
}
```

```dart
const ProcessStartException missing = ProcessStartException('java', 'not found');
const ProcessTimeoutException timedOut = ProcessTimeoutException(
  'java',
  Duration(seconds: 60),
);
// PdfParser 把 missing 收成 dependencyUnavailable，把 timedOut 收成 timeout
```

两者都是异常，不是 `ParseFailure`。`PdfParser` 负责转换。

### `Executor` / `ImmediateExecutor`

```dart
abstract interface class Executor {
  Future<T> run<T>(Future<T> Function() action);
}
class ImmediateExecutor implements Executor {
  const ImmediateExecutor();
}
```

```dart
const Executor executor = ImmediateExecutor();
final String value = await executor.run(() async => 'ok');
// value == 'ok'，在当前 isolate 上执行
```

`run` 执行 `action` 并返回它的结果。默认实现就在当前 isolate 上直接调用，异常原样抛出。不抛自己的异常。

### `CancellationToken` / `CancellationTokenSource` / `CancelledException`

```dart
class CancelledException implements Exception {
  const CancelledException([this.message = 'Operation cancelled']);
}

class CancellationToken {
  bool get isCancelled;
  void throwIfCancelled();
  Future<void> get whenCancelled;
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

class CancellationTokenSource {
  CancellationToken get token;
  bool get isCancelled;
  void cancel();
}
```

```dart
final CancellationTokenSource source = CancellationTokenSource();
source.cancel();
// source.token.isCancelled == true
// source.token.throwIfCancelled() 抛 CancelledException
```

令牌没有公开构造函数，只能从 source 拿。`cancel` 可以多次调用。已经取消后再 `addListener` 会立刻调用监听器。`throwIfCancelled` 抛不带自定义消息的 `CancelledException`。`whenCancelled` 在已经取消时返回一个已经完成的 future。监听器应短小，不要在里面再取消同一条流水线的锁。仅限当前 isolate。

## 6. 公开符号清单

对照 `lib/core_parsing.dart` 的导出文件：

`defaultIngestExtensions`、`FileScanner`、`IngestionService`、`MetadataExtractor`、`FileMetadataExtractor`、`mimeTypeForExtension`、`DocumentPage`、`FileMetadata`、`ImageAsset`、`IngestRecord`、`IngestionReport`、`IngestProgress`、`ParseOutcome`、`ParseFailureKind`、`ParseFailure`、`ParsedDocument`、`ParseResult`、`TextExtractionException`、`TikaCliTextExtractor`、`pageTextsFromXhtml`、`DocumentParser`、`ParserRegistry`、`StandardParserRegistry`、`normalizeParserExtension`、`DocxParser`、`ImageParser`、`PdfParser`、`TxtParser`、`CancelledException`、`CancellationToken`、`CancellationTokenSource`、`Executor`、`ImmediateExecutor`、`IoProcessRunner`、`ProcessRunResult`、`ProcessStartException`、`ProcessTimeoutException`、`ProcessRunner`、`ExtractedText`、`TextExtractor`。
