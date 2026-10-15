import 'embedding_runtime.dart';

/// TFLite C API 的绑定缝。
///
/// 真正的 `dlopen` / `TfLiteInterpreter*` 调用只允许出现在这个接口的一个
/// 实现里。默认单测用假绑定覆盖适配器分支，不链接动态库，也不加载模型。
/// Day 1 的权重跑在外部 ONNX Runtime 进程上；这个接口把以后换进进程内
/// TFLite 时要改的面收在一处。
abstract interface class TfliteBindings {
  /// 从模型字节建一个解释器，返回调用方持有的句柄。失败抛
  /// [RuntimeUnavailableException]。
  int loadModel(List<int> bytes);

  /// 读出输入输出端口。
  List<TensorInfo> describe(int handle);

  /// 写入 [inputs]，调用解释器，把结果填进 [outputs]。
  void invoke(
    int handle,
    Map<String, Tensor> inputs,
    Map<String, Tensor> outputs,
  );

  /// 释放 [loadModel] 返回的句柄。重复关闭应当无害。
  void close(int handle);
}
