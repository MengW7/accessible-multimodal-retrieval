import 'dart:async';

import 'package:core_retrieval/core_retrieval.dart';
import 'package:flutter/foundation.dart';

import 'desktop_service.dart';
import 'library_models.dart';
import 'library_service.dart';
import 'search_models.dart';
import 'display_settings.dart';

enum AppSection { library, search, results, settings }

enum StartupPhase { checking, ready, blocked }

/// Shared application state survives navigation. Widgets own no core resources.
/// B adds import progress/cancellation and C adds latest-request search state.
final class AppController extends ChangeNotifier {
  AppController(
    this.service, {
    this.library,
    this.directoryPicker,
    this.searchService,
    this.fileOpener,
    this.settingsStore,
  }) {
    _progressSubscription = library?.progress.listen((progress) {
      if (_disposed) return;
      libraryProgress = progress;
      for (final file in progress.files) {
        currentFiles[file.path] = file;
      }
      notifyListeners();
    });
  }
  final DesktopService service;
  final LibraryService? library;
  final DirectoryPicker? directoryPicker;
  final SearchService? searchService;
  final FileOpener? fileOpener;
  final DisplaySettingsStore? settingsStore;
  DisplaySettings displaySettings = const DisplaySettings();
  String? settingsError;
  bool settingsLoading = false;
  bool settingsSaving = false;
  Future<void>? _settingsLoad;
  Future<void> _settingsWrite = Future<void>.value();
  int _settingsRevision = 0;

  Future<void> loadDisplaySettings() =>
      _settingsLoad ??= _loadDisplaySettings();
  Future<void> _loadDisplaySettings() async {
    if (settingsStore == null) return;
    final revision = _settingsRevision;
    settingsLoading = true;
    if (!_disposed) notifyListeners();
    try {
      final settings = await settingsStore!.load();
      if (!_disposed && revision == _settingsRevision) {
        displaySettings = settings;
      }
    } catch (error) {
      if (!_disposed && revision == _settingsRevision) {
        settingsError = '无法恢复显示设置，已使用当前默认设置：$error。可恢复默认后重新保存。';
      }
    } finally {
      if (!_disposed) {
        settingsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> updateDisplaySettings(DisplaySettings value) {
    displaySettings = value;
    settingsError = null;
    final revision = ++_settingsRevision;
    settingsSaving = settingsStore != null;
    notifyListeners();
    if (settingsStore == null) return Future<void>.value();
    _settingsWrite = _settingsWrite.then((_) async {
      try {
        await settingsStore!.save(value);
      } catch (error) {
        if (!_disposed && revision == _settingsRevision) {
          settingsError = '显示设置已应用，但保存失败：$error。请检查数据目录权限后重试。';
        }
      } finally {
        if (!_disposed && revision == _settingsRevision) {
          settingsSaving = false;
          notifyListeners();
        }
      }
    });
    return _settingsWrite;
  }

  Future<void> resetDisplaySettings() =>
      updateDisplaySettings(const DisplaySettings());

  String get accessibilityStatus {
    if (shuttingDown) return '正在结束后台任务并关闭应用，请等待当前安全点。';
    if (phase == StartupPhase.checking) return '正在检查本地运行依赖。';
    if (libraryBusy) {
      if (cancelling) return '正在取消索引任务，已提交的数据会保留。';
      final progress = libraryProgress;
      if (progress == null) return '正在更新文件库。';
      final stage = switch (progress.stage) {
        LibraryStage.preparing => '准备本地运行时',
        LibraryStage.parsing => '扫描与解析',
        LibraryStage.indexing => '嵌入与建库',
        LibraryStage.saving => '保存目录记录',
      };
      final total = progress.total;
      final percent = total != null && total > 0
          ? (progress.processed / total * 10).floor().clamp(0, 10) * 10
          : null;
      return '$stage${percent == null ? '。' : '，约 $percent%。'}';
    }
    if (searchPhase == SearchPhase.loading) return '正在搜索本地索引。';
    if (settingsSaving) return '正在保存显示设置。';
    if (settingsError != null) return settingsError!;
    if (fileOpenOutcomes.isNotEmpty) {
      return fileOpenOutcomes.values.last.message;
    }
    if (section == AppSection.results || section == AppSection.search) {
      return switch (searchPhase) {
        SearchPhase.matches => '搜索完成，找到 ${results.length} 条结果。',
        SearchPhase.emptyLibrary => '索引库为空，请先添加目录建立索引。',
        SearchPhase.noMatches => '当前条件下没有检索结果，可修改查询或筛选后重试。',
        SearchPhase.invalid || SearchPhase.failed => searchError ?? '搜索失败，请重试。',
        SearchPhase.cancelled => '搜索已取消。',
        _ => phase == StartupPhase.blocked ? '运行依赖尚未就绪，请在设置中处理。' : '本地运行依赖可用。',
      };
    }
    if (libraryError != null) return libraryError!;
    if (libraryNotice != null) return libraryNotice!;
    return phase == StartupPhase.blocked
        ? startupError ?? '运行依赖尚未就绪，请在设置中处理。'
        : '本地运行依赖可用。';
  }

  SearchPhase searchPhase = SearchPhase.idle;
  SearchRequest? submittedSearch;
  FileTypeChoice fileType = FileTypeChoice.all;
  String pathFilter = '';
  String modifiedAfterFilter = '';
  String? searchError;
  String? searchNotice;
  final fileOpenOutcomes = <String, FileOpenOutcome>{};
  final openingPaths = <String>{};
  int _searchGeneration = 0;
  int _openGeneration = 0;
  int _activeSearches = 0;
  bool get canSearch =>
      searchService != null &&
      phase == StartupPhase.ready &&
      !libraryBusy &&
      !libraryLoading &&
      !choosingDirectory &&
      !shuttingDown;
  StreamSubscription<LibraryProgress>? _progressSubscription;
  LibrarySnapshot? librarySnapshot;
  LibraryProgress? libraryProgress;
  LibraryRun? lastRun;
  final currentFiles = <String, LibraryFile>{};
  String directoryDraft = '';
  String? libraryError;
  String? libraryNotice;
  bool libraryLoading = false;
  bool libraryBusy = false;
  bool choosingDirectory = false;
  bool cancelling = false;
  bool shuttingDown = false;
  Future<void>? _shutdown;
  bool get canIndex =>
      library != null &&
      phase == StartupPhase.ready &&
      !libraryBusy &&
      !libraryLoading &&
      !choosingDirectory &&
      _activeSearches == 0 &&
      !shuttingDown;
  bool get canClear =>
      library != null &&
      phase != StartupPhase.checking &&
      !libraryBusy &&
      !libraryLoading &&
      !choosingDirectory &&
      _activeSearches == 0 &&
      !shuttingDown;
  AppSection section = AppSection.library;
  StartupPhase phase = StartupPhase.checking;
  RuntimeReport? runtime;
  String? startupError;
  String query = '';
  SearchFilters filters = const SearchFilters();
  List<SearchResult> results = const [];
  int _generation = 0;
  bool _disposed = false;

  void navigate(AppSection value) {
    section = value;
    notifyListeners();
  }

  void updateQuery(String value) {
    query = value;
    notifyListeners();
  }

  void updateFileType(FileTypeChoice value) {
    fileType = value;
    notifyListeners();
  }

  void updatePathFilter(String value) {
    pathFilter = value;
  }

  void updateModifiedAfter(String value) {
    modifiedAfterFilter = value;
  }

  void clearSearchFilters() {
    fileType = FileTypeChoice.all;
    pathFilter = '';
    modifiedAfterFilter = '';
    notifyListeners();
  }

  Future<void> submitSearch() async {
    if (!canSearch) return;
    final generation = ++_searchGeneration;
    _openGeneration++;
    fileOpenOutcomes.clear();
    openingPaths.clear();
    results = const [];
    searchError = null;
    searchNotice = null;
    SearchRequest request;
    try {
      request = SearchRequest.fromDraft(
        query: query,
        type: fileType,
        path: pathFilter,
        modifiedAfter: modifiedAfterFilter,
      );
    } on FormatException catch (error) {
      searchService!.cancelSearch();
      searchPhase = SearchPhase.invalid;
      searchError = error.message;
      submittedSearch = null;
      notifyListeners();
      return;
    }
    filters = request.filters;
    submittedSearch = request;
    searchPhase = SearchPhase.loading;
    section = AppSection.results;
    _activeSearches++;
    notifyListeners();
    try {
      final page = await searchService!.search(request);
      if (_disposed || generation != _searchGeneration) return;
      results = List.unmodifiable(page.hits);
      searchPhase = page.indexedDocuments == 0
          ? SearchPhase.emptyLibrary
          : page.hits.isEmpty
          ? SearchPhase.noMatches
          : SearchPhase.matches;
    } on SearchCancelledException {
      if (_disposed || generation != _searchGeneration) return;
      searchPhase = SearchPhase.cancelled;
    } catch (error) {
      if (_disposed || generation != _searchGeneration) return;
      searchPhase = SearchPhase.failed;
      searchError = '搜索失败，请检查本地运行依赖后重试：$error';
    } finally {
      _activeSearches--;
      if (!_disposed) notifyListeners();
    }
  }

  void cancelCurrentSearch() {
    if (searchPhase != SearchPhase.loading) return;
    _searchGeneration++;
    searchService?.cancelSearch();
    searchPhase = SearchPhase.cancelled;
    results = const [];
    notifyListeners();
  }

  void _invalidateSearch(String message) {
    _searchGeneration++;
    _openGeneration++;
    searchService?.cancelSearch();
    results = const [];
    submittedSearch = null;
    fileOpenOutcomes.clear();
    openingPaths.clear();
    searchPhase = SearchPhase.idle;
    searchError = null;
    searchNotice = message;
  }

  Future<void> openResult(SearchResult result) async {
    if (fileOpener == null || shuttingDown || !results.contains(result)) return;
    final key = result.documentKey ?? result.relativePath;
    if (openingPaths.contains(key)) return;
    final generation = _openGeneration;
    openingPaths.add(key);
    fileOpenOutcomes.remove(key);
    notifyListeners();
    try {
      final outcome = await fileOpener!.open(result.documentKey);
      if (!_disposed && generation == _openGeneration) {
        fileOpenOutcomes[key] = outcome;
      }
    } catch (error) {
      if (!_disposed && generation == _openGeneration) {
        fileOpenOutcomes[key] = FileOpenOutcome(
          FileOpenStatus.failed,
          '打开失败，请检查系统查看器后重试：$error',
        );
      }
    } finally {
      if (!_disposed && generation == _openGeneration) {
        openingPaths.remove(key);
        notifyListeners();
      }
    }
  }

  Future<void> initialize() async {
    unawaited(loadDisplaySettings());
    if (libraryBusy ||
        choosingDirectory ||
        libraryLoading ||
        shuttingDown ||
        _activeSearches > 0) {
      return;
    }
    final generation = ++_generation;
    phase = StartupPhase.checking;
    startupError = null;
    notifyListeners();
    try {
      final report = await service.inspect();
      if (_disposed || generation != _generation) return;
      runtime = report;
      phase = report.ready ? StartupPhase.ready : StartupPhase.blocked;
      await refreshLibrary();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      phase = StartupPhase.blocked;
      startupError = '启动检查失败：$error';
    }
    if (_disposed || generation != _generation) return;
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    if (library == null || _disposed || libraryLoading) return;
    libraryLoading = true;
    notifyListeners();
    try {
      final snapshot = await library!.load();
      if (!_disposed) {
        librarySnapshot = snapshot;
        libraryError = null;
      }
    } catch (error) {
      if (!_disposed) libraryError = '读取文件库失败：$error';
    } finally {
      if (!_disposed) {
        libraryLoading = false;
        notifyListeners();
      }
    }
  }

  void updateDirectory(String path) {
    directoryDraft = path;
  }

  Future<void> chooseDirectory() async {
    if (!canIndex || directoryPicker == null) return;
    choosingDirectory = true;
    libraryError = null;
    notifyListeners();
    try {
      final selected = await directoryPicker!.choose();
      if (!_disposed && selected != null) directoryDraft = selected;
    } catch (error) {
      if (!_disposed) libraryError = '无法选择目录：$error';
    } finally {
      if (!_disposed) {
        choosingDirectory = false;
        notifyListeners();
      }
    }
  }

  Future<void> indexDirectory([String? path]) async {
    if (!canIndex) return;
    final root = (path ?? directoryDraft).trim();
    if (root.isEmpty) {
      libraryError = '请先选择目录或输入绝对路径。';
      notifyListeners();
      return;
    }
    directoryDraft = root;
    _invalidateSearch('之前的搜索结果已失效，请在文件库任务结束后重新查询。');
    libraryBusy = true;
    cancelling = false;
    libraryError = null;
    libraryNotice = null;
    lastRun = null;
    currentFiles.clear();
    libraryProgress = const LibraryProgress(stage: LibraryStage.preparing);
    notifyListeners();
    try {
      final result = await library!.index(root);
      if (_disposed) return;
      librarySnapshot = result.snapshot;
      lastRun = result.run;
      currentFiles
        ..clear()
        ..addEntries(result.run.files.map((f) => MapEntry(f.path, f)));
      libraryNotice =
          '${result.run.label}：新写入 ${result.run.written}，'
          '复用 ${result.run.reused}，失败 ${result.run.failed}，跳过 ${result.run.skipped}。';
    } catch (error) {
      if (!_disposed) {
        libraryError = '索引任务失败：$error。已提交数据不会因本次错误而清除。';
        await refreshLibrary();
      }
    } finally {
      if (!_disposed) {
        libraryBusy = false;
        cancelling = false;
        libraryProgress = null;
        notifyListeners();
      }
    }
  }

  void cancelIndexing() {
    if (!libraryBusy || cancelling) return;
    cancelling = true;
    library?.cancel();
    notifyListeners();
  }

  /// Called only after the UI's explicit confirmation. The worker only clears
  /// this application's database and folder history, never source files.
  Future<void> clearLibrary() async {
    if (!canClear) return;
    _invalidateSearch('索引已清除或发生变化，请重新查询。');
    libraryBusy = true;
    libraryError = null;
    libraryNotice = null;
    notifyListeners();
    try {
      final snapshot = await library!.clear();
      if (_disposed) return;
      librarySnapshot = snapshot;
      lastRun = null;
      currentFiles.clear();
      libraryNotice = '索引及目录记录已清除，源文件保留。';
    } catch (error) {
      if (!_disposed) libraryError = '清除索引失败：$error';
    } finally {
      if (!_disposed) {
        libraryBusy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _searchGeneration++;
    _openGeneration++;
    searchService?.cancelSearch();
    unawaited(_progressSubscription?.cancel());
    unawaited(library?.close().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> shutdown() => _shutdown ??= _closeForWindow();
  Future<void> _closeForWindow() async {
    shuttingDown = true;
    _searchGeneration++;
    _openGeneration++;
    searchService?.cancelSearch();
    if (!_disposed) notifyListeners();
    library?.cancel();
    await library?.close();
    await _settingsWrite;
  }
}
