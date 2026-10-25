import 'model/storage_failure.dart';
import 'sqlite_library_locator.dart';
import 'sqlite_vector_store.dart';

/// 打开产品索引。动态库缺失时 [store] 为 null，不抛未捕获异常。
class OpenedStore {
  const OpenedStore.ready(SqliteVectorStore this.store) : failure = null;

  const OpenedStore.failed(StorageFailure this.failure) : store = null;

  final SqliteVectorStore? store;

  final StorageFailure? failure;

  bool get isOk => store != null;
}

OpenedStore openStore(
  SqliteLibraryLocator locator,
  String databasePath,
) {
  final opened = locator.open(databasePath);
  final database = opened.database;
  final StorageFailure? failure = opened.failure;
  if (database == null || failure != null) {
    return OpenedStore.failed(
      failure ??
          const StorageFailure(
            kind: StorageFailureKind.libraryUnavailable,
            message: 'SQLite could not be opened.',
          ),
    );
  }
  try {
    prepareDatabase(database, wal: databasePath != ':memory:');
    return OpenedStore.ready(SqliteVectorStore(database));
  } on StorageException catch (error) {
    database.dispose();
    return OpenedStore.failed(error.failure);
  } catch (error) {
    database.dispose();
    return OpenedStore.failed(
      StorageFailure(
        kind: StorageFailureKind.unknown,
        message: 'Index schema could not be created.',
        detail: error.toString(),
      ),
    );
  }
}
