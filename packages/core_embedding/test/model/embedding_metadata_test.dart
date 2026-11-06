import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

void main() {
  test('model manifest records space, token budget and prefix policy', () {
    const model = ModelInfo(
      modelId: 'local-text',
      space: EmbeddingSpace.documentText,
      dim: 2,
      pooling: 'mean',
      normalized: true,
      maxInputLength: 8,
      queryPrefix: 'query: ',
      documentPrefix: 'document: ',
    );
    final copy = ModelInfo(
      modelId: model.modelId,
      space: model.space,
      dim: model.dim,
      pooling: model.pooling,
      normalized: model.normalized,
      maxInputLength: model.maxInputLength,
      queryPrefix: model.queryPrefix,
      documentPrefix: model.documentPrefix,
    );
    expect(copy, model);
    expect(copy.hashCode, model.hashCode);
    expect(model, isNot(clipVisionModel));
    expect(model.toString(), contains('documentText'));
    expect(model.toJson(), {
      'modelId': 'local-text',
      'space': 'documentText',
      'dim': 2,
      'pooling': 'mean',
      'normalized': true,
      'maxInputLength': 8,
      'queryPrefix': 'query: ',
      'documentPrefix': 'document: ',
    });
    expect(clipVisionModel.toJson()['maxInputLength'], isNull);
  });

  test(
    'embedding equality distinguishes model provenance and actual values',
    () {
      EmbeddingVector vector(
        List<double> values, {
        String model = 'local-text',
      }) => EmbeddingVector(
        values: values,
        space: EmbeddingSpace.documentText,
        dim: 2,
        modelId: model,
        normalized: true,
        chunkId: 'text-1',
      );
      final stored = vector([1, 0]);
      final restored = vector([1, 0]);
      expect(restored, stored);
      expect(restored.hashCode, stored.hashCode);
      expect(vector([0, 1]), isNot(stored));
      expect(vector([1, 0], model: 'new-export'), isNot(stored));
      expect(stored.toJson()['valuesHead'], [1.0, 0.0]);
      expect(stored.toString(), contains('local-text'));
    },
  );
}
