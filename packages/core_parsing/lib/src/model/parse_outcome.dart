/// 解析与入库共用的结果分类，下游各层都按它分支。
enum ParseOutcome {
  /// 完整解析成功。
  ok,

  /// 解析成功，但内容被截断或降级（例如超过大小上限、缺少文本层）。
  partial,

  /// 有意未解析：格式不支持、权限不足，或在开工前就被取消。
  skipped,

  /// 尝试解析后失败（文件损坏、缺少依赖、超时等）。
  failed;

  /// 产物是否可以交给 embedding 引擎。
  bool get isUsable => this == ParseOutcome.ok || this == ParseOutcome.partial;
}
