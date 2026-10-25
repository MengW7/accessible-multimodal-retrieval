import 'model/storage_filter.dart';

class SqlClause {
  const SqlClause(this.sql, this.args);

  final String sql;

  final List<Object?> args;

  static const SqlClause empty = SqlClause('', <Object?>[]);
}

SqlClause filterClause(StorageFilter? filter) {
  if (filter == null) {
    return SqlClause.empty;
  }
  final List<String> parts = <String>[];
  final List<Object?> args = <Object?>[];
  final Set<String>? extensions = filter.extensions;
  if (extensions != null) {
    if (extensions.isEmpty) {
      parts.add('0');
    } else {
      final String marks = List<String>.filled(extensions.length, '?').join(', ');
      parts.add('extension IN ($marks)');
      args.addAll(extensions.map((String item) => item.toLowerCase()));
    }
  }
  final String? prefix = filter.pathPrefix;
  if (prefix != null && prefix.isNotEmpty) {
    final String normalized = prefix.replaceAll('\\', '/');
    parts.add("(relative_path = ? OR relative_path LIKE ? ESCAPE '\\')");
    args
      ..add(normalized)
      ..add('${_escapeLike(normalized)}/%');
  }
  final DateTime? modifiedAfter = filter.modifiedAfter;
  if (modifiedAfter != null) {
    parts.add('modified_at IS NOT NULL AND modified_at > ?');
    args.add(modifiedAfter.toUtc().toIso8601String());
  }
  if (filter.modality != null) {
    parts.add('modality = ?');
    args.add(filter.modality!.name);
  }
  if (parts.isEmpty) {
    return SqlClause.empty;
  }
  return SqlClause(parts.join(' AND '), args);
}

String _escapeLike(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
