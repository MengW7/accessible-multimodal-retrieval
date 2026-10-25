import 'package:sqlite3/sqlite3.dart';

import 'model/sqlite_open_result.dart';
import 'model/storage_failure.dart';

/// SQLite 动态库从哪来。
///
/// 单测注入失败实现。默认实现不写死 `winsqlite3.dll` 的绝对路径，
/// 交给 `package:sqlite3` 2.x 自己的查找顺序。
abstract interface class SqliteLibraryLocator {
  SqliteOpenResult open(String databasePath);
}

final class SystemSqliteLibraryLocator implements SqliteLibraryLocator {
  const SystemSqliteLibraryLocator();

  @override
  SqliteOpenResult open(String databasePath) {
    try {
      final Database database = databasePath == ':memory:'
          ? sqlite3.openInMemory()
          : sqlite3.open(databasePath);
      return SqliteOpenResult.opened(database);
    } on ArgumentError catch (error) {
      return _failed(error);
    } on SqliteException catch (error) {
      return _failed(error);
    }
  }

  SqliteOpenResult _failed(Object error) {
    return SqliteOpenResult.failed(
      StorageFailure(
        kind: StorageFailureKind.libraryUnavailable,
        message: 'SQLite could not be opened.',
        detail: error.toString(),
      ),
    );
  }
}

/// 单测用。不加载动态库。
final class RejectingSqliteLibraryLocator implements SqliteLibraryLocator {
  const RejectingSqliteLibraryLocator({this.message = 'SQLite library is missing.'});

  final String message;

  @override
  SqliteOpenResult open(String databasePath) {
    return SqliteOpenResult.failed(
      StorageFailure(
        kind: StorageFailureKind.libraryUnavailable,
        message: message,
      ),
    );
  }
}
