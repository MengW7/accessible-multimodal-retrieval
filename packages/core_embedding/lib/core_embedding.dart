/// 离线无障碍多模态本地内容检索系统的向量层。
///
/// 本文件是外部调用方唯一支持的引用入口。`lib/src/` 下的类型属于实现细节，
/// 除非从这里再导出。
library;

export 'src/engine/embedding_engine.dart';
export 'src/engine/embedding_service.dart';
export 'src/image/image_decoder.dart';
export 'src/image/image_embedder.dart';
export 'src/image/image_preprocess.dart';
export 'src/model/embedding_input.dart';
export 'src/model/embedding_report.dart';
export 'src/model/embedding_space.dart';
export 'src/model/embedding_vector.dart';
export 'src/model/model_info.dart';
export 'src/model/text_chunk.dart';
export 'src/spi/embedding_runtime.dart';
export 'src/spi/onnx_process_runtime.dart';
export 'src/spi/onnx_tensor_runtime.dart';
export 'src/spi/tflite_bindings.dart';
export 'src/text/clip_bpe_tokenizer.dart';
export 'src/text/clip_text_embedder.dart';
export 'src/text/text_chunker.dart';
export 'src/text/text_embedder.dart';
export 'src/text/text_input_builder.dart';
export 'src/text/unigram_tokenizer.dart'
    show AddedToken, TokenEncoding, UnigramTokenizer;
