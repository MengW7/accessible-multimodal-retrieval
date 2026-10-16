import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'toy_tokenizer.dart';

const ModelInfo _toyModel = ModelInfo(
  modelId: 'toy',
  space: EmbeddingSpace.documentText,
  dim: 2,
  pooling: 'mean',
  normalized: true,
  maxInputLength: 8,
);

final class _ScriptedRuntime implements EmbeddingRuntime {
  _ScriptedRuntime(this._handle);

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

Float32List _hidden(List<double> values) => Float32List.fromList(values);

void main() {
  test('mean pool ignores masked rows', () {
    expect(
      TextEmbedder.meanPool(<double>[1, 2, 3, 4, 5, 6], <int>[1, 1, 0], 2),
      <double>[2, 3],
    );
  });

  test('l2 normalize maps 3,4 to 0.6,0.8', () {
    final List<double> values = TextEmbedder.l2Normalize(<double>[3, 4]);
    expect(values[0], closeTo(0.6, 1e-12));
    expect(values[1], closeTo(0.8, 1e-12));
  });

  test('embed pools the masked rows and then normalizes', () async {
    final _ScriptedRuntime runtime = _ScriptedRuntime((
      Map<String, Tensor> inputs,
    ) {
      final Int64List mask = inputs['attention_mask']!.data as Int64List;
      expect(mask.sublist(0, 3), <int>[1, 1, 1]);
      return _hidden(<double>[3, 4, 3, 4, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    });
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: runtime,
    );
    final EmbeddingVector vector = await embedder.embed(
      'a',
      chunkId: 'chunk-1',
    );
    expect(runtime.calls, 1);
    expect(vector.dim, 2);
    expect(vector.normalized, isTrue);
    expect(vector.modelId, 'toy');
    expect(vector.space, EmbeddingSpace.documentText);
    expect(vector.chunkId, 'chunk-1');
    expect(vector.values[0], closeTo(0.6, 1e-6));
    expect(vector.values[1], closeTo(0.8, 1e-6));
  });

  test('an over-long sentence does not call the runtime', () async {
    final _ScriptedRuntime runtime = _ScriptedRuntime(
      (_) => _hidden(<double>[0]),
    );
    final TextEmbedder embedder = TextEmbedder(
      model: const ModelInfo(
        modelId: 'toy',
        space: EmbeddingSpace.documentText,
        dim: 2,
        pooling: 'mean',
        normalized: true,
        maxInputLength: 4,
      ),
      tokenizer: toyTokenizer(),
      runtime: runtime,
    );
    await expectLater(
      () => embedder.embed('a a a'),
      throwsA(
        isA<TextOverBudgetException>().having(
          (TextOverBudgetException error) => error.tokenCount,
          'tokenCount',
          5,
        ),
      ),
    );
    expect(runtime.calls, 0);
  });

  test('a missing runtime is reported before inference', () async {
    final _ScriptedRuntime runtime = _ScriptedRuntime(
      (_) => _hidden(<double>[0]),
    );
    runtime.available = false;
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: runtime,
    );
    await expectLater(
      () => embedder.embed('a'),
      throwsA(isA<RuntimeUnavailableException>()),
    );
    expect(runtime.calls, 0);
  });

  test('a missing tensor from the runtime surfaces', () async {
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: _ScriptedRuntime((_) {
        throw const MissingTensorException('attention_mask');
      }),
    );
    await expectLater(
      () => embedder.embed('a'),
      throwsA(isA<MissingTensorException>()),
    );
  });

  test('a runtime timeout surfaces', () async {
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: _ScriptedRuntime((_) {
        throw const EmbeddingTimeoutException('budget');
      }),
    );
    await expectLater(
      () => embedder.embed('a'),
      throwsA(isA<EmbeddingTimeoutException>()),
    );
  });

  test(
    'a hidden state with the wrong length is a dimension mismatch',
    () async {
      final TextEmbedder embedder = TextEmbedder(
        model: _toyModel,
        tokenizer: toyTokenizer(),
        runtime: _ScriptedRuntime((_) => _hidden(<double>[1, 2, 3])),
      );
      await expectLater(
        () => embedder.embed('a'),
        throwsA(isA<DimensionMismatchException>()),
      );
    },
  );

  test('a zero vector cannot be normalized', () async {
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: _ScriptedRuntime((_) => _hidden(List<double>.filled(16, 0))),
    );
    await expectLater(
      () => embedder.embed('a'),
      throwsA(isA<BadOutputException>()),
    );
  });

  test('cancellation is checked before the runtime', () async {
    final CancellationTokenSource source = CancellationTokenSource();
    source.cancel();
    final _ScriptedRuntime runtime = _ScriptedRuntime(
      (_) => _hidden(<double>[0]),
    );
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: runtime,
    );
    await expectLater(
      () => embedder.embed('a', cancel: source.token),
      throwsA(isA<CancelledException>()),
    );
    expect(runtime.calls, 0);
  });

  test('an empty string is a caller error', () async {
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: _ScriptedRuntime((_) => _hidden(<double>[1])),
    );
    await expectLater(() => embedder.embed(''), throwsArgumentError);
  });

  test('a non-int64 attention mask is a missing tensor', () async {
    final _ScriptedRuntime runtime = _ScriptedRuntime(
      (_) => _hidden(List<double>.filled(16, 1)),
    );
    final TextEmbedder embedder = TextEmbedder(
      model: _toyModel,
      tokenizer: toyTokenizer(),
      runtime: runtime,
      inputs: _ByteMaskInputs(),
    );
    await expectLater(
      () => embedder.embed('a'),
      throwsA(
        isA<MissingTensorException>().having(
          (MissingTensorException error) => error.message,
          'message',
          'attention_mask is not int64.',
        ),
      ),
    );
    expect(runtime.calls, 1);
  });
}

final class _ByteMaskInputs extends TextInputBuilder {
  _ByteMaskInputs() : super(tokenizer: toyTokenizer(), maxLength: 8);

  @override
  TextInputResult build(String text) {
    final TextInputResult built = super.build(text);
    if (built is! TextInputTensors) {
      return built;
    }
    final Map<String, Tensor> tensors = Map<String, Tensor>.of(built.tensors);
    tensors['attention_mask'] = Tensor(
      dtype: TensorDType.int64,
      shape: built.tensors['attention_mask']!.shape,
      data: Uint8List(built.maxLength),
    );
    return TextInputTensors(
      tensors: tensors,
      ids: built.ids,
      tokens: built.tokens,
      maxLength: built.maxLength,
    );
  }
}
