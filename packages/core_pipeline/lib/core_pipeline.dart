/// 离线无障碍多模态本地内容检索系统的编排层。
///
/// 本文件是外部调用方唯一支持的引用入口。`lib/src/` 下的类型属于实现细节，
/// 除非从这里再导出。
library;

export 'src/index_source.dart';
export 'src/indexing_pipeline.dart';
export 'src/markdown_parser.dart';
export 'src/model/index_report.dart';
export 'src/runtime/embed_frame.dart' show FrameBuffer, decodePayload, encodeFrame;
export 'src/runtime/persistent_onnx_runtime.dart';
export 'src/runtime/process_embed_server.dart';
export 'src/search_pipeline.dart';
