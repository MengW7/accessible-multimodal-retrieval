import 'dart:typed_data';

import 'package:meta/meta.dart';

/// 张量元素类型。只覆盖本包模型实际会用到、且能放进 [TypedData] 的几种。
enum TensorDType { float32, int32, int64, uint8 }

/// 一次推理的输入或输出张量。
///
/// [data] 的元素类型要和 [dtype] 一致：float32 用 `Float32List`，int32 用
/// `Int32List`，int64 用 `Int64List`，uint8 用 `Uint8List`。形状按模型签名，
/// 不含调用方自己的批外维。
@immutable
class Tensor {
  const Tensor({required this.dtype, required this.shape, required this.data});

  final TensorDType dtype;

  final List<int> shape;

  final TypedData data;

  @override
  String toString() => 'Tensor(${dtype.name}, $shape)';
}

/// 端口属于输入还是输出。只靠名字区分不了该放进 inputs 还是 outputs。
enum TensorDirection { input, output }

/// 模型端口的名字、方向、类型和形状。动态维可以是 -1。
@immutable
class TensorInfo {
  const TensorInfo({
    required this.name,
    required this.direction,
    required this.dtype,
    required this.shape,
  });

  final String name;

  final TensorDirection direction;

  final TensorDType dtype;

  final List<int> shape;

  @override
  String toString() =>
      'TensorInfo($name, ${direction.name}, ${dtype.name}, $shape)';
}

/// 推理运行时。TFLite 动态库和外部 ONNX 进程实现同一个接口。
///
/// 单测注入假实现，不加载真模型。Day 1 已验证的是外部 ONNX Runtime 进程，
/// 见 `engine/embed_spike.py`。文本模型的 [run] 返回展平的
/// `last_hidden_state`，形状是 `sequence * hidden`，不做 pooling，也不做
/// L2。这两步在 `TextEmbedder` 里，才能单独固定用例。
abstract interface class EmbeddingRuntime {
  /// 按 [modelId] 跑一次前向，返回模型 float 输出的行优先展平。
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

/// 输出不是有限数，或范数为 0，无法做 L2。
final class BadOutputException extends EmbeddingRuntimeException {
  const BadOutputException(super.message, {super.detail});
}
