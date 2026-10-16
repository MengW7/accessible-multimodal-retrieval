import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'precompiled_normalizer.dart';
import 'unigram_model.dart';

/// `tokenizer.json` 里的一个 added token。
///
/// [normalized] 为 false 时在归一化之前按原文切出。MiniLM 的五个特殊标记都是
/// 这样。[lstrip] 会把紧挨在标记左边的空白吃进这个标记，不再单独成词。
@immutable
class AddedToken {
  const AddedToken({
    required this.content,
    required this.id,
    this.lstrip = false,
    this.rstrip = false,
    this.special = false,
    this.normalized = false,
  });

  final String content;
  final int id;
  final bool lstrip;
  final bool rstrip;
  final bool special;
  final bool normalized;

  @override
  bool operator ==(Object other) =>
      other is AddedToken &&
      other.content == content &&
      other.id == id &&
      other.lstrip == lstrip &&
      other.rstrip == rstrip &&
      other.special == special &&
      other.normalized == normalized;

  @override
  int get hashCode =>
      Object.hash(content, id, lstrip, rstrip, special, normalized);
}

/// 一次分词结果。不含 padding。
///
/// [ids] 与 [tokens] 等长。默认在两端加上 `<s>` 和 `</s>`，不截断。
@immutable
class TokenEncoding {
  const TokenEncoding({required this.ids, required this.tokens});

  final List<int> ids;
  final List<String> tokens;

  int get length => ids.length;

  @override
  bool operator ==(Object other) {
    if (other is! TokenEncoding ||
        other.ids.length != ids.length ||
        other.tokens.length != tokens.length) {
      return false;
    }
    for (var i = 0; i < ids.length; i++) {
      if (other.ids[i] != ids[i] || other.tokens[i] != tokens[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(ids), Object.hashAll(tokens));

  @override
  String toString() => 'TokenEncoding(${ids.length} tokens)';
}

class _Hit {
  const _Hit(this.start, this.end, this.token);

  final int start;
  final int end;
  final AddedToken token;
}

/// 多语言 MiniLM 的纯 Dart 分词器。
///
/// 计划里的文件名写成了 WordPiece。ADR 0003 选定的模型是 Unigram，词表在
/// `tokenizer.json`，没有 `vocab.txt`，也没有 `##` 续接。`##` 只是普通正文。
///
/// 顺序与 tokenizers 0.23 相同：先按 added token 切开，再做 Precompiled
/// 归一化，再按 Unicode 空白切开，再给每段加上 `▁`，最后做 Unigram。
/// 单句模板是 `<s> … </s>`。本类默认不截断；超长由 [TextInputBuilder] 退回
/// 重切，不在这里悄悄丢掉后半句。
final class UnigramTokenizer {
  UnigramTokenizer({
    required List<(String, double)> pieces,
    required int unkId,
    required List<AddedToken> addedTokens,
    this._normalizer,
    String bosContent = '<s>',
    String eosContent = '</s>',
    String padContent = '<pad>',
    this.metaspace = '▁',
    this.addPrefixSpace = true,
  }) : _model = UnigramModel(pieces: pieces, unkId: unkId),
       _added = List<AddedToken>.unmodifiable(addedTokens),
       bosContent = bosContent,
       eosContent = eosContent,
       padContent = padContent,
       bosId = _requiredId(addedTokens, bosContent),
       eosId = _requiredId(addedTokens, eosContent),
       padId = _requiredId(addedTokens, padContent) {
    for (final AddedToken token in _added) {
      if (token.normalized) {
        throw ArgumentError.value(
          token.content,
          'addedTokens',
          'normalized added tokens are not used by this model',
        );
      }
    }
  }

  final UnigramModel _model;
  final List<AddedToken> _added;
  final PrecompiledNormalizer? _normalizer;

  final int bosId;
  final int eosId;
  final int padId;
  final String bosContent;
  final String eosContent;
  final String padContent;
  final String metaspace;
  final bool addPrefixSpace;

  static int _requiredId(List<AddedToken> added, String content) {
    for (final AddedToken token in added) {
      if (token.content == content) {
        return token.id;
      }
    }
    throw ArgumentError.value(content, 'addedTokens', 'missing added token');
  }

  /// 读 MiniLM 这种 `tokenizer.json`。文件大约十几 MB，只在集成测试和真推理时读。
  factory UnigramTokenizer.fromFile(String path) {
    return UnigramTokenizer.fromJsonString(File(path).readAsStringSync());
  }

  factory UnigramTokenizer.fromJsonString(String jsonText) {
    final Object? decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('tokenizer.json must be an object.');
    }
    return UnigramTokenizer.fromJson(Map<String, Object?>.from(decoded));
  }

  factory UnigramTokenizer.fromJson(Map<String, Object?> json) {
    final Object? model = json['model'];
    if (model is! Map || model['type'] != 'Unigram') {
      throw const FormatException('tokenizer model must be Unigram.');
    }
    final Object? unk = model['unk_id'];
    final Object? vocab = model['vocab'];
    if (unk is! int || vocab is! List) {
      throw const FormatException('Unigram vocab or unk_id is missing.');
    }
    final List<(String, double)> pieces = <(String, double)>[];
    for (final Object? item in vocab) {
      if (item is! List || item.length < 2 || item[0] is! String) {
        throw const FormatException('Unigram vocab entry must be [token, score].');
      }
      pieces.add((item[0] as String, _asDouble(item[1])));
    }
    final List<AddedToken> added = <AddedToken>[];
    final Object? addedRaw = json['added_tokens'];
    if (addedRaw is List) {
      for (final Object? item in addedRaw) {
        if (item is! Map) {
          throw const FormatException('added token must be an object.');
        }
        final Object? content = item['content'];
        final Object? id = item['id'];
        if (content is! String || id is! int) {
          throw const FormatException('added token needs content and id.');
        }
        added.add(
          AddedToken(
            content: content,
            id: id,
            lstrip: item['lstrip'] == true,
            rstrip: item['rstrip'] == true,
            special: item['special'] == true,
            normalized: item['normalized'] == true,
          ),
        );
      }
    }
    return UnigramTokenizer(
      pieces: pieces,
      unkId: unk,
      addedTokens: added,
      normalizer: _normalizerFrom(json['normalizer']),
      bosContent: '<s>',
      eosContent: '</s>',
      padContent: '<pad>',
    );
  }

  /// 只做 Precompiled 归一化，不做分词。没有归一化表时原样返回。
  String normalize(String input) => _normalizer?.normalize(input) ?? input;

  /// 分词。[truncateTo] 只给和 Python 对照用。
  ///
  /// 传入 [truncateTo] 时，从右侧丢掉多余的正文，但保留末尾那一串特殊标记。
  /// 产品路径不要传它。
  TokenEncoding encode(String text, {int? truncateTo}) {
    final List<int> ids = <int>[bosId];
    final List<String> tokens = <String>[bosContent];
    var cursor = 0;
    while (cursor < text.length) {
      final _Hit? hit = _nextAdded(text, cursor);
      if (hit == null) {
        _encodeNormal(text.substring(cursor), ids, tokens);
        break;
      }
      if (hit.start > cursor) {
        _encodeNormal(text.substring(cursor, hit.start), ids, tokens);
      }
      ids.add(hit.token.id);
      tokens.add(text.substring(hit.start, hit.end));
      cursor = hit.end;
    }
    ids.add(eosId);
    tokens.add(eosContent);
    if (truncateTo != null) {
      return _truncate(ids, tokens, truncateTo);
    }
    return TokenEncoding(
      ids: List<int>.unmodifiable(ids),
      tokens: List<String>.unmodifiable(tokens),
    );
  }

  void _encodeNormal(String segment, List<int> ids, List<String> tokens) {
    final String normalized = normalize(segment);
    for (final String word in _splitWhitespace(normalized)) {
      for (final String piece in _metaspace(word)) {
        for (final UnigramToken token in _model.encode(piece)) {
          ids.add(token.id);
          tokens.add(token.text);
        }
      }
    }
  }

  _Hit? _nextAdded(String text, int index) {
    _Hit? best;
    for (final AddedToken token in _added) {
      final int at = text.indexOf(token.content, index);
      if (at < 0) {
        continue;
      }
      var start = at;
      if (token.lstrip) {
        while (start > index && _whitespaceBefore(text, start)) {
          start = _previousRuneStart(text, start);
        }
      }
      var end = at + token.content.length;
      if (token.rstrip) {
        while (end < text.length && _whitespaceAt(text, end)) {
          end += _runeWidth(text, end);
        }
      }
      final _Hit hit = _Hit(start, end, token);
      if (best == null ||
          hit.start < best.start ||
          (hit.start == best.start && hit.end - hit.start > best.end - best.start)) {
        best = hit;
      }
    }
    return best;
  }

  List<String> _metaspace(String word) {
    var text = word.replaceAll(' ', metaspace);
    if (addPrefixSpace && !text.startsWith(metaspace)) {
      text = '$metaspace$text';
    }
    if (text.isEmpty) {
      return const <String>[];
    }
    final List<int> marks = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (text.startsWith(metaspace, i)) {
        marks.add(i);
        i += metaspace.length - 1;
      }
    }
    if (marks.isEmpty) {
      return <String>[text];
    }
    final List<String> parts = <String>[];
    if (marks.first > 0) {
      parts.add(text.substring(0, marks.first));
    }
    for (var i = 0; i < marks.length; i++) {
      final int start = marks[i];
      final int end = i + 1 < marks.length ? marks[i + 1] : text.length;
      if (end > start) {
        parts.add(text.substring(start, end));
      }
    }
    return parts;
  }

  TokenEncoding _truncate(List<int> ids, List<String> tokens, int maxLength) {
    if (maxLength < 2) {
      throw ArgumentError.value(maxLength, 'truncateTo', 'must keep <s> and </s>');
    }
    if (ids.length <= maxLength) {
      return TokenEncoding(
        ids: List<int>.unmodifiable(ids),
        tokens: List<String>.unmodifiable(tokens),
      );
    }
    final Set<int> specials = <int>{
      for (final AddedToken token in _added)
        if (token.special) token.id,
    };
    var trailing = 0;
    while (trailing < ids.length && specials.contains(ids[ids.length - 1 - trailing])) {
      trailing += 1;
    }
    final int keepTail = trailing > maxLength ? maxLength : trailing;
    final int keepHead = maxLength - keepTail;
    return TokenEncoding(
      ids: List<int>.unmodifiable(<int>[
        ...ids.take(keepHead),
        ...ids.sublist(ids.length - keepTail),
      ]),
      tokens: List<String>.unmodifiable(<String>[
        ...tokens.take(keepHead),
        ...tokens.sublist(tokens.length - keepTail),
      ]),
    );
  }

  static PrecompiledNormalizer? _normalizerFrom(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map || raw['type'] != 'Precompiled') {
      throw const FormatException('normalizer must be Precompiled.');
    }
    final Object? blob = raw['precompiled_charsmap'];
    if (blob is! String || blob.isEmpty) {
      throw const FormatException('precompiled_charsmap is missing.');
    }
    return PrecompiledNormalizer.fromBytes(base64Decode(blob));
  }

  static double _asDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    throw FormatException('vocab score is not a number: $value');
  }
}

/// Rust `char::is_whitespace` 的 White_Space 集合。U+000B 也在里面。
bool _unicodeWhitespace(int rune) {
  return rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0B ||
      rune == 0x0C ||
      rune == 0x0D ||
      rune == 0x20 ||
      rune == 0x85 ||
      rune == 0xA0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000;
}

List<String> _splitWhitespace(String input) {
  final List<String> parts = <String>[];
  final StringBuffer buffer = StringBuffer();
  for (final int rune in input.runes) {
    if (_unicodeWhitespace(rune)) {
      if (buffer.isNotEmpty) {
        parts.add(buffer.toString());
        buffer.clear();
      }
    } else {
      buffer.write(String.fromCharCodes(<int>[rune]));
    }
  }
  if (buffer.isNotEmpty) {
    parts.add(buffer.toString());
  }
  return parts;
}

bool _whitespaceAt(String text, int index) {
  if (index < 0 || index >= text.length) {
    return false;
  }
  return _unicodeWhitespace(_runeAt(text, index));
}

bool _whitespaceBefore(String text, int index) {
  if (index <= 0) {
    return false;
  }
  final int start = _previousRuneStart(text, index);
  return _unicodeWhitespace(_runeAt(text, start));
}

int _runeAt(String text, int index) {
  final int unit = text.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
    final int next = text.codeUnitAt(index + 1);
    if (next >= 0xDC00 && next <= 0xDFFF) {
      return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
    }
  }
  return unit;
}

int _runeWidth(String text, int index) {
  final int unit = text.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF) {
    return 2;
  }
  return 1;
}

int _previousRuneStart(String text, int index) {
  if (index <= 1) {
    return 0;
  }
  final int previous = text.codeUnitAt(index - 1);
  if (previous >= 0xDC00 && previous <= 0xDFFF) {
    final int lead = text.codeUnitAt(index - 2);
    if (lead >= 0xD800 && lead <= 0xDBFF) {
      return index - 2;
    }
  }
  return index - 1;
}
