/// 计划里的路径按 BERT WordPiece 写。
///
/// ADR 0003 的文本模型是 Unigram。词表文件是 `tokenizer.json`，不是
/// `vocab.txt`。实现在 [unigram_tokenizer.dart]。这个文件只保留计划里的路径。
library;

export 'unigram_tokenizer.dart';
