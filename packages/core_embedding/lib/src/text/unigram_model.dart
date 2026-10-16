import 'dart:convert';

import 'package:meta/meta.dart';

/// Viterbi 切出来的一片。
///
/// [text] 是这一片在输入里的原文，未知片段也保留原文，不改写成 `<unk>`。
/// [id] 在词表里找不到整片时才是 `unkId`。
@immutable
class UnigramToken {
  const UnigramToken(this.id, this.text);

  final int id;

  final String text;

  @override
  bool operator ==(Object other) =>
      other is UnigramToken && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'UnigramToken($id, $text)';
}

class _Piece {
  const _Piece(this.id, this.score);

  final int id;
  final double score;
}

class _PathNode {
  double score = 0;
  int? startsAt;
  int? id;
}

/// SentencePiece Unigram。只切已经归一化、已经加上 `▁` 的一个片段。
///
/// 算法对应 tokenizers 0.23 的 `encode_optimized`：每个码位上取分数最高的
/// 前缀，没有单码位词时用 `minScore - 10` 的未知惩罚。连续未知码位合成一片。
final class UnigramModel {
  UnigramModel._({
    required this._vocab,
    required this.unkId,
    required double minScore,
    required this._maxBytes,
  }) : _unkScore = minScore - 10;

  final Map<String, _Piece> _vocab;
  final int unkId;
  final double _unkScore;
  final int _maxBytes;

  /// [pieces] 的下标就是 token id。分数是 log 概率，可以是 0。
  factory UnigramModel({
    required List<(String, double)> pieces,
    required int unkId,
  }) {
    if (pieces.isEmpty) {
      throw ArgumentError.value(pieces, 'pieces', 'vocabulary is empty');
    }
    if (unkId < 0 || unkId >= pieces.length) {
      throw ArgumentError.value(unkId, 'unkId', 'not inside the vocabulary');
    }
    final Map<String, _Piece> vocab = <String, _Piece>{};
    var minScore = double.infinity;
    var maxBytes = 1;
    for (var id = 0; id < pieces.length; id++) {
      final (String token, double score) = pieces[id];
      vocab[token] = _Piece(id, score);
      if (score < minScore) {
        minScore = score;
      }
      final int bytes = utf8.encode(token).length;
      if (bytes > maxBytes) {
        maxBytes = bytes;
      }
    }
    return UnigramModel._(
      vocab: vocab,
      unkId: unkId,
      minScore: minScore,
      maxBytes: maxBytes,
    );
  }

  int? idOf(String token) => _vocab[token]?.id;

  String? tokenOf(int id) {
    for (final MapEntry<String, _Piece> entry in _vocab.entries) {
      if (entry.value.id == id) {
        return entry.key;
      }
    }
    return null;
  }

  /// 空串返回空列表，不抛。
  List<UnigramToken> encode(String sentence) {
    if (sentence.isEmpty) {
      return const <UnigramToken>[];
    }
    final List<int> runes = sentence.runes.toList(growable: false);
    final List<int> byteEnds = List<int>.filled(runes.length, 0);
    final List<int> stringEnds = List<int>.filled(runes.length, 0);
    var byteEnd = 0;
    var stringEnd = 0;
    for (var i = 0; i < runes.length; i++) {
      final String char = String.fromCharCodes(<int>[runes[i]]);
      byteEnd += utf8.encode(char).length;
      stringEnd += char.length;
      byteEnds[i] = byteEnd;
      stringEnds[i] = stringEnd;
    }
    final List<_PathNode> best = List<_PathNode>.generate(
      byteEnd + 1,
      (_) => _PathNode(),
      growable: false,
    );

    for (var runeIndex = 0; runeIndex < runes.length; runeIndex++) {
      final int startsAt = runeIndex == 0 ? 0 : byteEnds[runeIndex - 1];
      final int mblen = byteEnds[runeIndex] - startsAt;
      final double scoreHere = best[startsAt].score;
      final int stringStart = runeIndex == 0 ? 0 : stringEnds[runeIndex - 1];
      var hasSingle = false;
      for (var endRune = runeIndex; endRune < runes.length; endRune++) {
        final int keyPos = byteEnds[endRune];
        final int length = keyPos - startsAt;
        if (length > _maxBytes) {
          break;
        }
        final String piece = sentence.substring(stringStart, stringEnds[endRune]);
        final _Piece? hit = _vocab[piece];
        if (hit == null) {
          continue;
        }
        final double candidate = hit.score + scoreHere;
        final _PathNode node = best[keyPos];
        if (node.startsAt == null || candidate > node.score) {
          node.score = candidate;
          node.startsAt = startsAt;
          node.id = hit.id;
        }
        if (length == mblen) {
          hasSingle = true;
        }
      }
      if (!hasSingle) {
        final int keyPos = startsAt + mblen;
        final double candidate = _unkScore + scoreHere;
        final _PathNode node = best[keyPos];
        if (node.startsAt == null || candidate > node.score) {
          node.score = candidate;
          node.startsAt = startsAt;
          node.id = unkId;
        }
      }
    }

    final List<UnigramToken> backward = <UnigramToken>[];
    final List<String> unkParts = <String>[];
    var endsAt = byteEnd;
    while (endsAt > 0) {
      final _PathNode node = best[endsAt];
      final int? startsAt = node.startsAt;
      final int? id = node.id;
      if (startsAt == null || id == null) {
        throw StateError('Unigram lattice has a gap at byte $endsAt.');
      }
      final String surface = _slice(sentence, stringEnds, startsAt, endsAt, byteEnds);
      if (id == unkId) {
        unkParts.add(surface);
      } else {
        _flushUnknown(backward, unkParts);
        backward.add(UnigramToken(id, surface));
      }
      endsAt = startsAt;
    }
    _flushUnknown(backward, unkParts);
    return backward.reversed.toList(growable: false);
  }

  String _slice(
    String sentence,
    List<int> stringEnds,
    int byteStart,
    int byteEnd,
    List<int> byteEnds,
  ) {
    final int stringStart = _stringIndex(byteStart, byteEnds, stringEnds);
    final int stringStop = _stringIndex(byteEnd, byteEnds, stringEnds);
    return sentence.substring(stringStart, stringStop);
  }

  int _stringIndex(int bytePos, List<int> byteEnds, List<int> stringEnds) {
    if (bytePos == 0) {
      return 0;
    }
    for (var i = 0; i < byteEnds.length; i++) {
      if (byteEnds[i] == bytePos) {
        return stringEnds[i];
      }
    }
    throw StateError('byte offset $bytePos is not a code point boundary.');
  }

  void _flushUnknown(List<UnigramToken> backward, List<String> unkParts) {
    if (unkParts.isEmpty) {
      return;
    }
    final String surface = unkParts.reversed.join();
    unkParts.clear();
    final int id = _vocab[surface]?.id ?? unkId;
    backward.add(UnigramToken(id, surface));
  }
}
