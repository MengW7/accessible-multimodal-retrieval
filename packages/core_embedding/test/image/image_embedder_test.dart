import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

const ModelInfo _toyVision = ModelInfo(
  modelId: 'vision-toy',
  space: EmbeddingSpace.clipShared,
  dim: 2,
  pooling: 'none',
  normalized: true,
);

final class _Runtime implements EmbeddingRuntime {
  _Runtime(this._handle);

  final Float32List Function(Map<String, Tensor> inputs) _handle;
  var available = true;
  var calls = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs) async {
    calls += 1;
    return _handle(inputs);
  }
}

void main() {
  test('one image becomes an L2 normalized clip vector', () async {
    final _Runtime runtime = _Runtime((Map<String, Tensor> inputs) {
      final Tensor pixels = inputs['pixel_values']!;
      expect(pixels.shape, <int>[1, 3, 1, 1]);
      expect(pixels.dtype, TensorDType.float32);
      return Float32List.fromList(<double>[3, 4]);
    });
    final ImageEmbedder embedder = ImageEmbedder(
      model: _toyVision,
      runtime: runtime,
      preprocessor: const ImagePreprocessor(edge: 1),
    );
    final EmbeddingVector vector = await embedder.embed(
      bytes: Uint8List.fromList(<int>[255, 0, 0]),
      width: 1,
      height: 1,
    );
    expect(runtime.calls, 1);
    expect(vector.space, EmbeddingSpace.clipShared);
    expect(vector.dim, 2);
    expect(vector.modelId, 'vision-toy');
    expect(vector.normalized, isTrue);
    expect(vector.values[0], closeTo(0.6, 1e-9));
    expect(vector.values[1], closeTo(0.8, 1e-9));
    expect(clipVisionModel.dim, 512);
    expect(clipVisionModel.pooling, 'none');
  });

  test(
    'unavailable runtime, bad output, and cancellation do not invent a vector',
    () async {
      final _Runtime runtime = _Runtime((Map<String, Tensor> inputs) {
        return Float32List.fromList(<double>[double.nan, 1]);
      });
      final ImageEmbedder embedder = ImageEmbedder(
        model: _toyVision,
        runtime: runtime,
        preprocessor: const ImagePreprocessor(edge: 1),
      );
      runtime.available = false;
      await expectLater(
        () => embedder.embed(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          width: 1,
          height: 1,
        ),
        throwsA(isA<RuntimeUnavailableException>()),
      );
      expect(runtime.calls, 0);
      runtime.available = true;
      await expectLater(
        () => embedder.embed(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          width: 1,
          height: 1,
        ),
        throwsA(isA<BadOutputException>()),
      );
      final CancellationTokenSource source = CancellationTokenSource()
        ..cancel();
      await expectLater(
        () => embedder.embed(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          width: 1,
          height: 1,
          cancel: source.token,
        ),
        throwsA(isA<CancelledException>()),
      );
    },
  );

  test('the wrong output length is a dimension mismatch', () async {
    final ImageEmbedder embedder = ImageEmbedder(
      model: _toyVision,
      runtime: _Runtime(
        (Map<String, Tensor> inputs) => Float32List.fromList(<double>[1]),
      ),
      preprocessor: const ImagePreprocessor(edge: 1),
    );
    await expectLater(
      () => embedder.embed(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        width: 1,
        height: 1,
      ),
      throwsA(isA<DimensionMismatchException>()),
    );
  });

  test('a document-text model cannot be an image embedder', () {
    expect(
      () => ImageEmbedder(
        model: documentTextModel,
        runtime: _Runtime((_) => Float32List(0)),
      ),
      throwsArgumentError,
    );
  });
}
