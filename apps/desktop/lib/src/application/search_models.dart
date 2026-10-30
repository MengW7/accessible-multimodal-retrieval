import 'package:core_retrieval/core_retrieval.dart';

enum SearchPhase {
  idle,
  loading,
  matches,
  emptyLibrary,
  noMatches,
  invalid,
  failed,
  cancelled,
}

enum FileTypeChoice { all, txt, markdown, pdf, docx, images }

extension FileTypeDescription on FileTypeChoice {
  String get label => switch (this) {
    FileTypeChoice.all => '所有类型',
    FileTypeChoice.txt => 'TXT',
    FileTypeChoice.markdown => 'Markdown',
    FileTypeChoice.pdf => 'PDF',
    FileTypeChoice.docx => 'DOCX',
    FileTypeChoice.images => '图片（JPG / PNG）',
  };
  Set<String>? get extensions => switch (this) {
    FileTypeChoice.all => null,
    FileTypeChoice.txt => {'.txt'},
    FileTypeChoice.markdown => {'.md'},
    FileTypeChoice.pdf => {'.pdf'},
    FileTypeChoice.docx => {'.docx'},
    FileTypeChoice.images => {'.jpg', '.jpeg', '.png'},
  };
}

final class SearchRequest {
  SearchRequest({
    required String query,
    SearchFilters filters = const SearchFilters(),
    this.topK = 20,
  }) : query = query.trim(),
       filters = SearchFilters(
         extensions: filters.extensions == null
             ? null
             : Set.unmodifiable(filters.extensions!),
         pathPrefix: filters.pathPrefix,
         modifiedAfter: filters.modifiedAfter,
         modality: filters.modality,
       ) {
    if (this.query.isEmpty) throw const FormatException('请输入查询内容。');
    if (topK < 1 || topK > 100) {
      throw const FormatException('结果条数应在 1 到 100 之间。');
    }
  }
  factory SearchRequest.fromDraft({
    required String query,
    FileTypeChoice type = FileTypeChoice.all,
    String path = '',
    String modifiedAfter = '',
  }) {
    var normalized = path.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      throw const FormatException(
        '路径筛选使用导入目录内的相对路径，例如 notes 或 notes/file.pdf。',
      );
    }
    final parts = normalized
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (parts.contains('..')) throw const FormatException('相对路径筛选不能包含 ..。');
    normalized = parts.join('/');
    DateTime? date;
    final value = modifiedAfter.trim();
    if (value.isNotEmpty) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        throw const FormatException('修改日期请使用 YYYY-MM-DD，例如 2026-10-30。');
      }
      final fields = value.split('-').map(int.parse).toList();
      date = DateTime(fields[0], fields[1], fields[2]);
      if (date.year != fields[0] ||
          date.month != fields[1] ||
          date.day != fields[2]) {
        throw const FormatException('修改日期不存在，请检查年月日。');
      }
    }
    return SearchRequest(
      query: query,
      filters: SearchFilters(
        extensions: type.extensions,
        pathPrefix: normalized.isEmpty ? null : normalized,
        modifiedAfter: date,
      ),
    );
  }
  final String query;
  final SearchFilters filters;
  final int topK;
  Map<String, Object?> toJson() => {
    'query': query,
    'topK': topK,
    'extensions': filters.extensions?.toList(),
    'pathPrefix': filters.pathPrefix,
    'modifiedAfter': filters.modifiedAfter?.toIso8601String(),
    'modality': filters.modality?.name,
  };
}

final class SearchPage {
  const SearchPage({
    required this.request,
    required this.hits,
    required this.indexedDocuments,
  });
  final SearchRequest request;
  final List<SearchResult> hits;
  final int indexedDocuments;
}

final class SearchCancelledException implements Exception {
  const SearchCancelledException();
  @override
  String toString() => '查询已取消或已被更新的查询替代。';
}

abstract interface class SearchService {
  Future<SearchPage> search(SearchRequest request);
  void cancelSearch();
}

enum FileOpenStatus { requested, missing, invalidPath, failed }

final class FileOpenOutcome {
  const FileOpenOutcome(this.status, this.message);
  final FileOpenStatus status;
  final String message;
}

abstract interface class FileOpener {
  Future<FileOpenOutcome> open(String? absolutePath);
}
