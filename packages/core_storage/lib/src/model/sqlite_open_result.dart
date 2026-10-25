import 'package:sqlite3/sqlite3.dart';

import 'storage_failure.dart';

/// [SqliteLibraryLocator.open] 的结果。失败时 [database] 为 null。
class SqliteOpenResult {
  const SqliteOpenResult.opened(this.database) : failure = null;

  const SqliteOpenResult.failed(this.failure) : database = null;

  final Database? database;

  final StorageFailure? failure;

  bool get isOk => database != null;
}
