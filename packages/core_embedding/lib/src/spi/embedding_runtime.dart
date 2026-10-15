import 'dart:typed_data';

import 'package:meta/meta.dart';

/// 张量元素类型。只覆盖本包模型实际会用到的几种。
enum TensorDType { float32, int32, int64, uint8, boolean }

/// 一次推理的输入或输出张量。
///
/// [data] 的元素类型要和 [dtype] 一致：float32 用 `Float32List`，int64 用
/// `Int64List`，其余类推。形状按模型签名，不含调用方自己的批外维。
@immutable
class Tensor {
  const Tensor({required this.dtype, required this.shape, required this.data});

  final TensorDType dtype;

  final List<int> shape;

  final TypedData data;

  @override
  String toString() => 'Tensor(${dtype.name}, $shape)';
}

/// 模型端口的名字、类型和形状。动态维可以是 -1。
@immutable
class TensorInfo {
  const TensorInfo({
    required this.name,
    required this.dtype,
    required this.shape,
  });

  final String name;

  final TensorDType dtype;

  final List<int> shape;

  @override
  String toString() => 'TensorInfo($name, ${dtype.name}, $shape)';
}

/// 推理运行时。TFLite 动态库和外部 ONNX 进程实现同一个接口。
///
/// 单测注入假实现，不加载真模型。Day 1 已验证的是外部 ONNX Runtime 进程，
/// 见 `engine/embed_spike.py`。
abstract interface class EmbeddingRuntime {
  /// 按 [modelId] 跑一次前向，返回已经从输出张量取出的 float 向量。
  ///
  /// 维度不符、缺张量、超时、运行时不可用都抛 [EmbeddingRuntimeException]
  /// 的对应子类，不返回空向量。
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs);

  /// 当前进程能不能真正调用这个运行时。假实现在单测里返回 true。
  bool get isAvailable;
}

/// 运行时失败的根类型。批量服务把它收成一条失败记录，不让它冒泡。
class EmbeddingRuntimeException implements Exception {
  const EmbeddingRuntimeException(this.message, {this.detail});

  final String message;

  final String? detail;

  @override
  String toString() => 'EmbeddingRuntimeException: $message';
}

/// 动态库、解释器或外部进程不存在。
final class RuntimeUnavailableException extends EmbeddingRuntimeException {
  const RuntimeUnavailableException(super.message, {super.detail});
}

/// 输出维度和模型登记的维度不一致。
final class DimensionMismatchException extends EmbeddingRuntimeException {
  const DimensionMismatchException(super.message, {super.detail});
}

/// 模型签名里的某个输入或输出没有提供。
final class MissingTensorException extends EmbeddingRuntimeException {
  const MissingTensorException(super.message, {super.detail});
}

/// 单次推理超过预算。
final class EmbeddingTimeoutException extends EmbeddingRuntimeException {
  const EmbeddingTimeoutException(super.message, {super.detail});
}
