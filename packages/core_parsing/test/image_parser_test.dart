import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

import 'support/repo_files.dart';

void main() {
  const ImageParser parser = ImageParser();

  test('sample.png reports size, format, and rgb', () async {
    final ParseResult result = await parser.parse(
      repoFile('datasets/samples/sample.png'),
    );
    final ImageAsset? asset = result.document?.imageAsset;
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.fullText, isEmpty);
    expect(result.document?.isImageOnly, isTrue);
    expect(asset?.format, 'png');
    expect(asset?.width, 1186);
    expect(asset?.height, 1137);
    expect(asset?.colorMode, 'rgb');
    expect(asset?.orientation, isNull);
  });

  test('a jpeg reports format and a positive size', () async {
    final ParseResult result = await parser.parse(fixturePath('tiny.jpg'));
    final ImageAsset? asset = result.document?.imageAsset;
    expect(result.outcome, ParseOutcome.ok);
    expect(asset?.format, 'jpeg');
    expect(asset?.width, greaterThan(0));
    expect(asset?.height, greaterThan(0));
    expect(asset?.colorMode, isNotNull);
  });

  // The coco jpeg is gitignored. The in-package tiny.jpg covers the same branch.
  test('a coco val jpeg decodes', () async {
    final ParseResult result = await parser.parse(
      repoFile('datasets/coco/val_sample/images/000000006818.jpg'),
    );
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.imageAsset?.format, 'jpeg');
  }, tags: 'integration');

  test('a non-image with an image extension fails', () async {
    final ParseResult result = await parser.parse(fixturePath('fake.png'));
    expect(result.outcome, ParseOutcome.failed);
    expect(result.failure?.kind, ParseFailureKind.corruptedInput);
  });

  test('a missing image is a failure, not an exception', () async {
    final ParseResult result = await parser.parse('missing-image.png');
    expect(result.failure?.kind, ParseFailureKind.unknown);
  });

  test('tiny.png decodes and does not require exif', () async {
    final ParseResult result = await parser.parse(fixturePath('tiny.png'));
    expect(result.outcome, ParseOutcome.ok);
    expect(result.document?.imageAsset?.orientation, isNull);
    expect(result.document?.imageAsset?.width, greaterThan(0));
  });
}
