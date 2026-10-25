/// 一条命中来自哪一路。读屏可以按这个名字播报。
enum SearchChannel {
  /// 文档文本空间的向量召回。
  documentText,

  /// 中文 bigram、FTS5 trigram 或 LIKE。
  keyword,

  /// MobileCLIP 文本塔对图像空间的召回。
  clipShared,
}
