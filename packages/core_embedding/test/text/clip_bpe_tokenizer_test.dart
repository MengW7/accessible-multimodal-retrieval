import 'dart:convert';

import 'package:core_embedding/core_embedding.dart';
import 'package:test/test.dart';

import 'toy_clip.dart';

Map<String, Object?> _jsonModel({String type = 'BPE', bool byteFallback = false}) {
  return <String, Object?>{
    'normalizer': <String, Object?>{
      'type': 'Sequence',
      'normalizers': <Object?>[
        <String, Object?>{'type': 'NFC'},
        <String, Object?>{
          'type': 'Replace',
          'pattern': <String, Object?>{'Regex': r'\s+'},
          'content': ' ',
        },
        <String, Object?>{'type': 'Lowercase'},
      ],
    },
    'pre_tokenizer': <String, Object?>{
      'type': 'Sequence',
      'pretokenizers': <Object?>[
        <String, Object?>{
          'type': 'Split',
          'pattern': <String, Object?>{
            'Regex': r"'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+",
          },
          'behavior': 'Removed',
          'invert': true,
        },
        <String, Object?>{'type': 'ByteLevel'},
      ],
    },
    'post_processor': <String, Object?>{
      'type': 'RobertaProcessing',
      'cls': <Object?>['<|startoftext|>', 10],
      'sep': <Object?>['<|endoftext|>', 11],
    },
    'model': <String, Object?>{
      'type': type,
      'byte_fallback': byteFallback,
      'continuing_subword_prefix': null,
      'end_of_word_suffix': '</w>',
      'unk_token': '<|endoftext|>',
      'vocab': <String, int>{
        'h': 0,
        'i': 1,
        'h</w>': 2,
        'i</w>': 3,
        'hi</w>': 4,
        '!': 5,
        '<|startoftext|>': 10,
        '<|endoftext|>': 11,
      },
      'merges': <String>['h i</w>'],
    },
  };
}

void main() {
  test('lowercase words merge and wrap the clip specials', () {
    final ClipBpeTokenizer tokenizer = toyClipTokenizer();
    expect(tokenizer.encode('HI').ids, <int>[10, 4, 11]);
    expect(tokenizer.encode('h i').ids, <int>[10, 2, 3, 11]);
    expect(tokenizer.encode('').ids, <int>[10, 11]);
    expect(tokenizer.padId, 5);
  });

  test('fromJson reads the toy clip model', () {
    final ClipBpeTokenizer tokenizer = ClipBpeTokenizer.fromJsonString(
      jsonEncode(_jsonModel()),
    );
    expect(tokenizer.encode('hi').ids, <int>[10, 4, 11]);
    expect(tokenizer.encode('hi').tokens, <String>['<|startoftext|>', 'hi</w>', '<|endoftext|>']);
  });

  test('a non-bpe model and a bad merge are rejected', () {
    expect(
      () => ClipBpeTokenizer.fromJsonString(jsonEncode(_jsonModel(type: 'WordPiece'))),
      throwsFormatException,
    );
    expect(
      () => ClipBpeTokenizer.fromJsonString(jsonEncode(_jsonModel(byteFallback: true))),
      throwsFormatException,
    );
    expect(
      () => ClipBpeTokenizer(vocab: const <String, int>{'a': 1}, merges: const <String>['a']),
      throwsArgumentError,
    );
    expect(() => ClipBpeTokenizer.fromJsonString('[]'), throwsFormatException);
  });
}
