import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart';

import 'unigram_tokenizer.dart';

/// MobileCLIP 文本塔的字节级 BPE。
///
/// 归一化顺序跟 `tokenizer.json`：NFC、空白压成一个空格、小写。
/// 预切分保留 CLIP 的词块正则，再把 UTF-8 字节映射成词表里的字符。
/// 词尾加 `</w>` 后按 merge 表合并。编码本身不截断、不补齐；补齐在嵌入器里。
final class ClipBpeTokenizer {
  ClipBpeTokenizer({
    required Map<String, int> vocab,
    required List<String> merges,
    String endOfWordSuffix = '</w>',
    String bosToken = '<|startoftext|>',
    String eosToken = '<|endoftext|>',
    String padToken = '!',
    int? bosId,
    int? eosId,
    int? padId,
    int? unkId,
  }) : vocab = Map<String, int>.unmodifiable(vocab),
       endOfWordSuffix = endOfWordSuffix,
       bosToken = bosToken,
       eosToken = eosToken,
       padToken = padToken,
       bosId = bosId ?? vocab[bosToken] ?? 49406,
       eosId = eosId ?? vocab[eosToken] ?? 49407,
       padId = padId ?? vocab[padToken] ?? 0,
       unkId = unkId ?? vocab[eosToken] ?? 49407 {
    if (endOfWordSuffix.isEmpty) {
      throw ArgumentError.value(endOfWordSuffix, 'endOfWordSuffix', 'must not be empty');
    }
    if (vocab.isEmpty) {
      throw ArgumentError.value(vocab, 'vocab', 'must not be empty');
    }
    var rank = 0;
    for (final String merge in merges) {
      final int space = merge.indexOf(' ');
      if (space <= 0 || space >= merge.length - 1) {
        throw ArgumentError.value(merge, 'merges', 'must be two tokens separated by a space');
      }
      _ranks[(merge.substring(0, space), merge.substring(space + 1))] = rank;
      rank += 1;
    }
  }

  factory ClipBpeTokenizer.fromJsonString(String jsonText) {
    final Object? decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('CLIP tokenizer JSON is not an object.');
    }
    final Map<String, Object?> root = Map<String, Object?>.from(decoded);
    _expectNormalizer(root['normalizer']);
    _expectPreTokenizer(root['pre_tokenizer']);
    final (int, int) specials = _processorIds(root['post_processor']);
    final Object? modelRaw = root['model'];
    if (modelRaw is! Map) {
      throw const FormatException('CLIP model section is missing.');
    }
    final Map<String, Object?> model = Map<String, Object?>.from(modelRaw);
    if (model['type'] != 'BPE') {
      throw FormatException('CLIP model type is ${model['type']}, expected BPE.');
    }
    if (model['byte_fallback'] == true) {
      throw const FormatException('CLIP byte_fallback is not used by this tokenizer.');
    }
    final Object? prefix = model['continuing_subword_prefix'];
    if (prefix != null && prefix != '') {
      throw const FormatException('CLIP continuing prefix is not used by this tokenizer.');
    }
    final Object? suffix = model['end_of_word_suffix'];
    if (suffix is! String || suffix.isEmpty) {
      throw const FormatException('CLIP end_of_word_suffix is missing.');
    }
    final Object? vocabRaw = model['vocab'];
    if (vocabRaw is! Map) {
      throw const FormatException('CLIP vocab is missing.');
    }
    final Map<String, int> vocab = <String, int>{};
    vocabRaw.forEach((Object? key, Object? value) {
      if (key is! String || value is! int) {
        throw const FormatException('CLIP vocab entry is not a string id.');
      }
      vocab[key] = value;
    });
    final Object? mergesRaw = model['merges'];
    if (mergesRaw is! List) {
      throw const FormatException('CLIP merges are missing.');
    }
    final List<String> merges = <String>[];
    for (final Object? item in mergesRaw) {
      if (item is! String) {
        throw const FormatException('CLIP merge is not a string.');
      }
      merges.add(item);
    }
    final Object? unk = model['unk_token'];
    return ClipBpeTokenizer(
      vocab: vocab,
      merges: merges,
      endOfWordSuffix: suffix,
      bosId: specials.$1,
      eosId: specials.$2,
      unkId: unk is String ? vocab[unk] : null,
    );
  }

  final Map<String, int> vocab;

  final String endOfWordSuffix;

  final String bosToken;

  final String eosToken;

  final String padToken;

  final int bosId;

  final int eosId;

  final int padId;

  final int unkId;

  final Map<(String, String), int> _ranks = <(String, String), int>{};

  static final Map<int, String> _bytes = _byteMap();

  static final RegExp _pieces = RegExp(
    r"'s|'t|'re|'ve|'m|'ll|'d|\p{L}+|\p{N}|[^\s\p{L}\p{N}]+",
    unicode: true,
  );

  /// 含起止标记，不含补齐。空文本是 `[bos, eos]`。
  TokenEncoding encode(String text) {
    final List<String> tokens = <String>[];
    for (final _Seg raw in _split(text, eosToken)) {
      if (raw.special) {
        tokens.add(raw.text);
        continue;
      }
      final String normalized = _normalize(raw.text);
      for (final _Seg piece in _split(normalized, bosToken)) {
        if (piece.special) {
          tokens.add(piece.text);
          continue;
        }
        for (final Match match in _pieces.allMatches(piece.text)) {
          final String surface = match.group(0)!;
          tokens.addAll(_bpe(_byteEncode(surface)));
        }
      }
    }
    return TokenEncoding(
      ids: <int>[bosId, for (final String token in tokens) vocab[token] ?? unkId, eosId],
      tokens: <String>[bosToken, ...tokens, eosToken],
    );
  }

  String _normalize(String text) {
    return nfc(text).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  List<_Seg> _split(String text, String marker) {
    if (marker.isEmpty || !text.contains(marker)) {
      return <_Seg>[_Seg(text, special: false)];
    }
    final List<_Seg> pieces = <_Seg>[];
    var start = 0;
    while (start <= text.length) {
      final int at = text.indexOf(marker, start);
      if (at < 0) {
        if (start < text.length) {
          pieces.add(_Seg(text.substring(start), special: false));
        }
        break;
      }
      if (at > start) {
        pieces.add(_Seg(text.substring(start, at), special: false));
      }
      pieces.add(_Seg(marker, special: true));
      start = at + marker.length;
      if (start == text.length) {
        break;
      }
    }
    if (pieces.isEmpty) {
      return <_Seg>[_Seg('', special: false)];
    }
    return pieces;
  }

  String _byteEncode(String text) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in utf8.encode(text)) {
      final String? mapped = _bytes[byte];
      if (mapped == null) {
        throw StateError('Byte $byte has no CLIP mapping.');
      }
      buffer.write(mapped);
    }
    return buffer.toString();
  }

  List<String> _bpe(String token) {
    if (token.isEmpty) {
      return const <String>[];
    }
    final List<int> runes = token.runes.toList(growable: false);
    final List<String> word = <String>[];
    for (var i = 0; i < runes.length; i++) {
      final String char = String.fromCharCode(runes[i]);
      word.add(i == runes.length - 1 ? '$char$endOfWordSuffix' : char);
    }
    while (word.length >= 2) {
      (String, String)? best;
      var bestRank = 1 << 30;
      for (var i = 0; i < word.length - 1; i++) {
        final (String, String) pair = (word[i], word[i + 1]);
        final int? rank = _ranks[pair];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          best = pair;
        }
      }
      final (String, String)? chosen = best;
      if (chosen == null) {
        break;
      }
      final List<String> next = <String>[];
      var i = 0;
      while (i < word.length) {
        if (i < word.length - 1 && word[i] == chosen.$1 && word[i + 1] == chosen.$2) {
          next.add('${chosen.$1}${chosen.$2}');
          i += 2;
        } else {
          next.add(word[i]);
          i += 1;
        }
      }
      word
        ..clear()
        ..addAll(next);
    }
    return word;
  }

  static Map<int, String> _byteMap() {
    final List<int> bytes = <int>[
      for (var i = 33; i <= 126; i++) i,
      for (var i = 0xA1; i <= 0xAC; i++) i,
      for (var i = 0xAE; i <= 0xFF; i++) i,
    ];
    final List<int> chars = List<int>.from(bytes);
    final Set<int> seen = bytes.toSet();
    var extra = 0;
    for (var value = 0; value < 256; value++) {
      if (seen.contains(value)) {
        continue;
      }
      bytes.add(value);
      chars.add(256 + extra);
      extra += 1;
    }
    final Map<int, String> map = <int, String>{};
    for (var i = 0; i < bytes.length; i++) {
      map[bytes[i]] = String.fromCharCode(chars[i]);
    }
    return map;
  }

  static void _expectNormalizer(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CLIP normalizer is missing.');
    }
    final Map<String, Object?> normalizer = Map<String, Object?>.from(raw);
    if (normalizer['type'] != 'Sequence') {
      throw const FormatException('CLIP normalizer is not a sequence.');
    }
    final Object? stepsRaw = normalizer['normalizers'];
    if (stepsRaw is! List || stepsRaw.length != 3) {
      throw const FormatException('CLIP normalizer steps are not NFC, whitespace, lowercase.');
    }
    final Object? nfcStep = stepsRaw[0];
    final Object? replaceStep = stepsRaw[1];
    final Object? lowerStep = stepsRaw[2];
    if (nfcStep is! Map || nfcStep['type'] != 'NFC') {
      throw const FormatException('CLIP normalizer does not start with NFC.');
    }
    if (replaceStep is! Map || replaceStep['type'] != 'Replace') {
      throw const FormatException('CLIP normalizer does not collapse whitespace.');
    }
    final Object? pattern = replaceStep['pattern'];
    if (pattern is! Map || pattern['Regex'] != r'\s+') {
      throw const FormatException('CLIP whitespace pattern is not \\s+.');
    }
    if (replaceStep['content'] != ' ') {
      throw const FormatException('CLIP whitespace replacement is not a single space.');
    }
    if (lowerStep is! Map || lowerStep['type'] != 'Lowercase') {
      throw const FormatException('CLIP normalizer does not lowercase.');
    }
  }

  static void _expectPreTokenizer(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CLIP pre-tokenizer is missing.');
    }
    final Map<String, Object?> pre = Map<String, Object?>.from(raw);
    if (pre['type'] != 'Sequence') {
      throw const FormatException('CLIP pre-tokenizer is not a sequence.');
    }
    final Object? stepsRaw = pre['pretokenizers'];
    if (stepsRaw is! List || stepsRaw.length != 2) {
      throw const FormatException('CLIP pre-tokenizer steps are not split then bytes.');
    }
    final Object? splitRaw = stepsRaw[0];
    final Object? byteRaw = stepsRaw[1];
    if (splitRaw is! Map) {
      throw const FormatException('CLIP split step is missing.');
    }
    final Map<String, Object?> split = Map<String, Object?>.from(splitRaw);
    if (split['type'] != 'Split' || split['behavior'] != 'Removed' || split['invert'] != true) {
      throw const FormatException('CLIP split step does not keep matched pieces.');
    }
    final Object? pattern = split['pattern'];
    if (pattern is! Map ||
        pattern['Regex'] != r"'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+") {
      throw const FormatException('CLIP split regex does not match the model card.');
    }
    if (byteRaw is! Map || byteRaw['type'] != 'ByteLevel') {
      throw const FormatException('CLIP byte-level step is missing.');
    }
  }

  static (int, int) _processorIds(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('CLIP post-processor is missing.');
    }
    final Map<String, Object?> processor = Map<String, Object?>.from(raw);
    if (processor['type'] != 'RobertaProcessing') {
      throw const FormatException('CLIP post-processor is not RobertaProcessing.');
    }
    return (_specialId(processor['cls'], 'cls'), _specialId(processor['sep'], 'sep'));
  }

  static int _specialId(Object? raw, String name) {
    if (raw is! List || raw.length != 2 || raw[1] is! int) {
      throw FormatException('CLIP $name special is missing an id.');
    }
    return raw[1] as int;
  }
}

final class _Seg {
  const _Seg(this.text, {required this.special});

  final String text;
  final bool special;
}
