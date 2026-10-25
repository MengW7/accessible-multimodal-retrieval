import 'package:core_parsing/core_parsing.dart';

/// Markdown 按纯文本解析。页码仍交给切块器：单页文件不写成真实页码。
final class MarkdownParser extends TxtParser {
  MarkdownParser({super.maxBytes});

  @override
  String get name => 'markdown';

  @override
  String get version => '1';

  @override
  Set<String> get supportedExtensions => const <String>{'.md'};
}
