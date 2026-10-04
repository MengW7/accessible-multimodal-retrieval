/// 离线无障碍多模态本地内容检索系统的文件 I/O 层与解析层。
///
/// 本导出文件（Barrel File）是外部调用方（apps/desktop、嵌入引擎、检索流水线）
/// 唯一支持的引用入口。lib/src/ 下的所有内容均属于内部实现细节。
///
library;

export 'src/model/document_page.dart';
export 'src/model/file_metadata.dart';
export 'src/model/image_asset.dart';
export 'src/model/ingestion_report.dart';
export 'src/model/parse_outcome.dart';
export 'src/model/parsed_document.dart';
export 'src/parsing/parser.dart';
export 'src/parsing/parser_registry.dart';
export 'src/spi/cancellation_token.dart';
export 'src/spi/executor.dart';
export 'src/spi/process_runner.dart';
export 'src/spi/text_extractor.dart';
