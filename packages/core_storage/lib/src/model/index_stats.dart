import 'package:meta/meta.dart';

@immutable
class IndexStats {
  const IndexStats({
    required this.chunks,
    required this.documents,
    required this.documentText,
    required this.clipShared,
    required this.keywordTerms,
  });

  final int chunks;

  final int documents;

  final int documentText;

  final int clipShared;

  final int keywordTerms;

  @override
  bool operator ==(Object other) =>
      other is IndexStats &&
      other.chunks == chunks &&
      other.documents == documents &&
      other.documentText == documentText &&
      other.clipShared == clipShared &&
      other.keywordTerms == keywordTerms;

  @override
  int get hashCode => Object.hash(chunks, documents, documentText, clipShared, keywordTerms);
}

@immutable
class WriteOutcome {
  const WriteOutcome({required this.written, required this.documents});

  final int written;

  final int documents;
}
