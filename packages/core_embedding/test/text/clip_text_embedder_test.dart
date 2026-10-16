import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

import 'toy_clip.dart';

const ModelInfo _toyClip = ModelInfo(
  modelId: 'clip-toy',
  space: EmbeddingSpace.clipShared,
  dim: 2,
  pooling: 'none',
  normalized: true,
  maxInputLength: 6,
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
  test(
    'clip text pads with the exclamation id and has no attention mask',
    () async {
      final _Runtime runtime = _Runtime((Map<String, Tensor> inputs) {
        expect(inputs.keys, <String>['input_ids']);
        final Int64List ids = inputs['input_ids']!.data as Int64List;
        expect(ids, <int>[10, 4, 11, 5, 5, 5]);
        return Float32List.fromList(<double>[3, 4]);
      });
      final ClipTextEmbedder embedder = ClipTextEmbedder(
        model: _toyClip,
        tokenizer: toyClipTokenizer(),
        runtime: runtime,
      );
      final EmbeddingVector vector = await embedder.embed('HI', chunkId: 'q1');
      expect(vector.space, EmbeddingSpace.clipShared);
      expect(vector.dim, 2);
      expect(vector.modelId, 'clip-toy');
      expect(vector.normalized, isTrue);
      expect(vector.chunkId, 'q1');
      expect(vector.values[0], closeTo(0.6, 1e-9));
      expect(clipTextModel.maxInputLength, 77);
      expect(clipTextModel.dim, 512);
    },
  );

  test('over-long clip text is not truncated', () async {
    final _Runtime runtime = _Runtime(
      (Map<String, Tensor> inputs) => Float32List(2),
    );
    final ClipTextEmbedder embedder = ClipTextEmbedder(
      model: const ModelInfo(
        modelId: 'clip-toy',
        space: EmbeddingSpace.clipShared,
        dim: 2,
        pooling: 'none',
        normalized: true,
        maxInputLength: 2,
      ),
      tokenizer: toyClipTokenizer(),
      runtime: runtime,
    );
    await expectLater(
      () => embedder.embed('hi'),
      throwsA(isA<TextOverBudgetException>()),
    );
    expect(runtime.calls, 0);
    runtime.available = false;
    final ClipTextEmbedder unavailable = ClipTextEmbedder(
      model: _toyClip,
      tokenizer: toyClipTokenizer(),
      runtime: runtime,
    );
    await expectLater(
      () => unavailable.embed('hi'),
      throwsA(isA<RuntimeUnavailableException>()),
    );
    await expectLater(() => embedder.embed(''), throwsArgumentError);
  });
}
