import 'library_models.dart';

abstract interface class LibraryService {
  Stream<LibraryProgress> get progress;
  Future<LibrarySnapshot> load();
  Future<LibraryResult> index(String path, {bool force = false});
  void cancel();
  Future<LibrarySnapshot> clear();
  Future<void> close();
}

abstract interface class DirectoryPicker {
  Future<String?> choose();
}
