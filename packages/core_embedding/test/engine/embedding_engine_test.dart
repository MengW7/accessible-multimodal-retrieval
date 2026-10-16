import 'dart:typed_data';

import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

import '../text/toy_clip.dart';
import '../text/toy_tokenizer.dart';

const ModelInfo _toyVision = ModelInfo(
  modelId: 'vision-toy',
  space: EmbeddingSpace.clipShared,
  dim: 2,
  pooling: 'none',
  normalized: true,
);

const ModelInfo _toyClip = ModelInfo(
  modelId: 'clip-toy',
  space: EmbeddingSpace.clipShared,
  dim: 2,
  pooling: 'none',
  normalized: true,
  maxInputLength: 6,
);

const ModelInfo _toyText = ModelInfo(
  modelId: 'text-toy',
  space: EmbeddingSpace.documentText,
  dim: 2,
  pooling: 'mean',
  normalized: true,
  maxInputLength: 8,
);

final class _Runtime implements EmbeddingRuntime {
  _Runtime(this._values);

  final Float32List _values;
  var calls = 0;
  Map<String, Tensor>? last;

  @override
  bool get isAvailable => true;

  @override
  Future<Float32List> run(String modelId, Map<String, Tensor> inputs) async {
    calls += 1;
    last = inputs;
    return _values;
  }
}

Float32List _textHidden() {
  return Float32List.fromList(<double>[
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
}

DefaultEmbeddingEngine _engine({
  ModelInfo textModel = _toyText,
  ClipTextEmbedder? clipText,
  bool withClip = true,
  _Runtime? textRuntime,
}) {
  final _Runtime text = textRuntime ?? _Runtime(_textHidden());
  final _Runtime imageRuntime = _Runtime(Float32List.fromList(<double>[3, 4]));
  final _Runtime clipRuntime = _Runtime(Float32List.fromList(<double>[0, 5]));
  return DefaultEmbeddingEngine(
    text: TextEmbedder(
      model: textModel,
      tokenizer: toyTokenizer(),
      runtime: text,
    ),
    image: ImageEmbedder(
      model: _toyVision,
      runtime: imageRuntime,
      preprocessor: const ImagePreprocessor(edge: 1),
    ),
    clipText: withClip
        ? (clipText ??
              ClipTextEmbedder(
                model: _toyClip,
                tokenizer: toyClipTokenizer(),
                runtime: clipRuntime,
              ))
        : null,
  );
}

void main() {
  test(
    'document text, clip text, and an image stay in their own spaces',
    () async {
      final DefaultEmbeddingEngine engine = _engine();
      final EmbeddingVector text = await engine.embed(
        EmbeddingInput.text('a', chunkId: 'c1'),
      );
      expect(text.space, EmbeddingSpace.documentText);
      expect(text.dim, 2);
      expect(text.modelId, 'text-toy');
      expect(text.normalized, isTrue);
      expect(text.chunkId, 'c1');

      final EmbeddingVector clip = await engine.embed(
        EmbeddingInput.text(
          'hi',
          space: EmbeddingSpace.clipShared,
          chunkId: 'q',
        ),
      );
      expect(clip.space, EmbeddingSpace.clipShared);
      expect(clip.modelId, 'clip-toy');
      expect(clip.values[1], closeTo(1, 1e-9));

      final EmbeddingVector image = await engine.embed(
        EmbeddingInput.image(
          bytes: Uint8List.fromList(<int>[255, 0, 0]),
          width: 1,
          height: 1,
        ),
      );
      expect(image.space, EmbeddingSpace.clipShared);
      expect(image.modelId, 'vision-toy');
      expect(image.values[0], closeTo(0.6, 1e-9));
      expect(engine.models.map((ModelInfo model) => model.modelId), <String>[
        'text-toy',
        'vision-toy',
        'clip-toy',
      ]);
      expect(engine.models.first.toJson()['space'], 'documentText');
    },
  );

  test(
    'clip text without a text tower throws instead of using the document model',
    () async {
      final _Runtime textRuntime = _Runtime(_textHidden());
      final DefaultEmbeddingEngine engine = _engine(
        withClip: false,
        textRuntime: textRuntime,
      );
      await expectLater(
        () => engine.embed(
          EmbeddingInput.text('hi', space: EmbeddingSpace.clipShared),
        ),
        throwsA(
          isA<EmbeddingSpaceMismatchException>()
              .having(
                (EmbeddingSpaceMismatchException error) => error.requested,
                'requested',
                EmbeddingSpace.clipShared,
              )
              .having(
                (EmbeddingSpaceMismatchException error) => error.actual,
                'actual',
                EmbeddingSpace.documentText,
              )
              .having(
                (EmbeddingSpaceMismatchException error) => error.toString(),
                'toString',
                allOf(contains('clipShared'), contains('documentText')),
              ),
        ),
      );
      expect(textRuntime.calls, 0);
    },
  );

  test(
    'a document request is rejected when the text model is in another space',
    () async {
      final _Runtime textRuntime = _Runtime(_textHidden());
      final DefaultEmbeddingEngine engine = _engine(
        textModel: const ModelInfo(
          modelId: 'wrong-space',
          space: EmbeddingSpace.clipShared,
          dim: 2,
          pooling: 'mean',
          normalized: true,
          maxInputLength: 8,
        ),
        withClip: false,
        textRuntime: textRuntime,
      );
      await expectLater(
        () => engine.embed(EmbeddingInput.text('a')),
        throwsA(
          isA<EmbeddingSpaceMismatchException>()
              .having(
                (EmbeddingSpaceMismatchException error) => error.requested,
                'requested',
                EmbeddingSpace.documentText,
              )
              .having(
                (EmbeddingSpaceMismatchException error) => error.actual,
                'actual',
                EmbeddingSpace.clipShared,
              ),
        ),
      );
      expect(textRuntime.calls, 0);
    },
  );

  test('image input rejects a document space and a bad byte length', () {
    expect(
      () => EmbeddingInput.image(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        width: 1,
        height: 1,
        space: EmbeddingSpace.documentText,
      ),
      throwsArgumentError,
    );
    expect(
      () => EmbeddingInput.image(bytes: Uint8List(1), width: 1, height: 1),
      throwsArgumentError,
    );
    expect(EmbeddingInput.text('').toString(), contains('documentText'));
    expect(
      EmbeddingInput.image(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        width: 1,
        height: 1,
      ).toString(),
      contains('1x1'),
    );
    expect(() => EmbeddingInput.text('a', chunkId: ''), throwsArgumentError);
  });
}
