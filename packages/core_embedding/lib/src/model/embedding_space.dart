/// 向量所处的空间。
///
/// 两个空间的维度和训练目标都不同，数值不能直接比较，也不能拼进同一个索引。
enum EmbeddingSpace {
  /// 文档正文与文本查询。
  documentText,

  /// MobileCLIP 图文共享空间。图像检索和自然语言查图都用它。
  clipShared,
}
