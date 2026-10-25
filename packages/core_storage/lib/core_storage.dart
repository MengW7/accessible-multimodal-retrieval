/// 离线无障碍多模态本地内容检索系统的存储层。
///
/// 本文件是外部调用方唯一支持的引用入口。`lib/src/` 下的类型属于实现细节，
/// 除非从这里再导出。
library;

export 'src/keyword_index.dart' show KeywordPath, KeywordPlan, chineseBigrams;
export 'src/model/index_generation.dart';
export 'src/model/index_stats.dart';
export 'src/model/modality.dart';
export 'src/model/scored_id.dart';
export 'src/model/sqlite_open_result.dart';
export 'src/model/storage_failure.dart';
export 'src/model/storage_filter.dart';
export 'src/model/stored_chunk.dart';
export 'src/sqlite_library_locator.dart';
export 'src/sqlite_vector_store.dart' show SqliteVectorStore;
export 'src/store_opener.dart';
export 'src/vector_store.dart';
