/// 离线无障碍多模态本地内容检索系统的检索层。
///
/// 本文件是外部调用方唯一支持的引用入口。`lib/src/` 下的类型属于实现细节，
/// 除非从这里再导出。
library;

export 'src/default_retriever.dart';
export 'src/model/retriever.dart';
export 'src/model/search_channel.dart';
export 'src/model/search_filters.dart';
export 'src/model/search_result.dart';
export 'src/neighborhood.dart';
export 'src/query_encoder.dart';
export 'src/rrf_fusion.dart';
