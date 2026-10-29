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
// `TextOverBudgetException` is thrown by `TextEmbedder` and `ClipTextEmbedder`
// when the input exceeds the model's `maxInputLength`. Callers that degrade
// instead of failing (see `QueryEncoder` in `core_retrieval`) must be able to
// catch it, so the type has to be visible through this barrel. Keeping it
// internal made the exception uncatchable outside this package, which turned a
// long query into a crash instead of a text-only search.
export 'src/text/text_embedder.dart';
export 'src/text/text_input_builder.dart';
export 'src/text/unigram_tokenizer.dart'
    show AddedToken, TokenEncoding, UnigramTokenizer;
