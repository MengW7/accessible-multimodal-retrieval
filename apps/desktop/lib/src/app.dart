import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import 'accessibility_widgets.dart';
import 'app_theme.dart';
import 'application/app_controller.dart';
import 'application/display_settings.dart';
import 'application/search_models.dart';
import 'library_page.dart';
import 'search_page.dart';
import 'results_page.dart';
import 'settings_page.dart';

class RetrievalApp extends StatefulWidget {
  const RetrievalApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<RetrievalApp> createState() => _RetrievalAppState();
}

class _RetrievalAppState extends State<RetrievalApp> {
  late final TextEditingController _query;
  final _searchFocus = FocusNode(debugLabel: '搜索输入');
  final _headingFocus = FocusNode(debugLabel: '页面标题', skipTraversal: true);
  final _navigator = GlobalKey<NavigatorState>();
  late AppSection _lastSection;
  late SearchPhase _lastSearchPhase;
  AppController get app => widget.controller;
  static const labels = ['文件库', '搜索', '结果', '设置'];
  static const icons = [
    Icons.folder_outlined,
    Icons.search,
    Icons.article_outlined,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: app.query);
    _lastSection = app.section;
    _lastSearchPhase = app.searchPhase;
    app.addListener(_onAppChanged);
    app.initialize();
  }

  void _onAppChanged() {
    final changed = _lastSection != app.section;
    final completed =
        _lastSearchPhase == SearchPhase.loading &&
        app.searchPhase != SearchPhase.loading;
    _lastSection = app.section;
    _lastSearchPhase = app.searchPhase;
    if (changed || (completed && app.section == AppSection.results)) {
      final expected = app.section;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            app.section != expected ||
            (_navigator.currentState?.canPop() ?? false)) {
          return;
        }
        if (expected == AppSection.search) {
          _searchFocus.requestFocus();
        } else {
          _headingFocus.requestFocus();
          final headingContext = _headingFocus.context;
          if (headingContext != null) {
            Scrollable.ensureVisible(headingContext, alignment: 0);
          }
        }
      });
    }
  }

  void _focusSearch() {
    app.navigate(AppSection.search);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && app.section == AppSection.search) {
        _searchFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    _query.dispose();
    _searchFocus.dispose();
    _headingFocus.dispose();
    app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final settings = app.displaySettings;
      return MaterialApp(
        navigatorKey: _navigator,
        title: '本地内容检索',
        themeMode: switch (settings.theme) {
          DisplayTheme.system => ThemeMode.system,
          DisplayTheme.light => ThemeMode.light,
          DisplayTheme.dark => ThemeMode.dark,
        },
        theme: retrievalTheme(
          Brightness.light,
          highContrast: settings.highContrast,
        ),
        darkTheme: retrievalTheme(
          Brightness.dark,
          highContrast: settings.highContrast,
        ),
        highContrastTheme: retrievalTheme(Brightness.light, highContrast: true),
        highContrastDarkTheme: retrievalTheme(
          Brightness.dark,
          highContrast: true,
        ),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final factor = settings.fontSize.scale;
          final mac = defaultTargetPlatform == TargetPlatform.macOS;
          return MediaQuery(
            data: media.copyWith(
              textScaler: factor == null
                  ? media.textScaler
                  : TextScaler.linear(factor),
            ),
            child: Shortcuts(
              shortcuts: {
                SingleActivator(
                  LogicalKeyboardKey.keyL,
                  control: !mac,
                  meta: mac,
                ): const _FocusSearchIntent(),
              },
              child: Actions(
                actions: {
                  _FocusSearchIntent: _FocusSearchAction(
                    _navigator,
                    _focusSearch,
                  ),
                },
                child: child!,
              ),
            ),
          );
        },
        home: Builder(
          builder: (context) => LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final navigation = _navigation(context, vertical: wide);
              final content = Semantics(
                container: true,
                explicitChildNodes: true,
                sortKey: const OrdinalSortKey(1),
                child: SingleChildScrollView(
                  key: ValueKey(app.section),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!wide) navigation,
                      Focus(
                        focusNode: _headingFocus,
                        child: accessibleHeading(
                          context,
                          labels[app.section.index],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _status(context),
                      const SizedBox(height: 16),
                      ...switch (app.section) {
                        AppSection.library => [LibraryPage(app: app)],
                        AppSection.search => [
                          SearchForm(
                            app: app,
                            queryController: _query,
                            queryFocusNode: _searchFocus,
                          ),
                        ],
                        AppSection.results => [ResultsPage(app: app)],
                        AppSection.settings => [SettingsPage(app: app)],
                      },
                    ],
                  ),
                ),
              );
              return Scaffold(
                appBar: AppBar(
                  // AppBar otherwise caps its title scaling at 1.34. Grow the
                  // toolbar with the requested text size instead of clipping it.
                  toolbarHeight:
                      kToolbarHeight *
                      (MediaQuery.textScalerOf(context).scale(22) / 22).clamp(
                        1.0,
                        double.infinity,
                      ),
                  title: Text(
                    '本地内容检索',
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
                body: FocusTraversalGroup(
                  policy: ReadingOrderTraversalPolicy(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Row(
                        children: [
                          if (wide)
                            SizedBox(
                              width: 208,
                              child: SingleChildScrollView(child: navigation),
                            ),
                          Expanded(child: content),
                        ],
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: LiveStatus(
                          key: const Key('application-live-status'),
                          message: app.accessibilityStatus,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );

  Widget _navigation(BuildContext context, {required bool vertical}) {
    final buttons = [
      for (var i = 0; i < labels.length; i++)
        Semantics(
          selected: i == app.section.index,
          child: AccessibleControl(
            child: TextButton.icon(
              key: ValueKey('nav-${AppSection.values[i].name}'),
              onPressed: () => app.navigate(AppSection.values[i]),
              icon: Icon(icons[i]),
              label: Text(labels[i]),
              style: i == app.section.index
                  ? TextButton.styleFrom(
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    )
                  : null,
            ),
          ),
        ),
    ];
    return Semantics(
      key: const Key('app-navigation'),
      container: true,
      explicitChildNodes: true,
      sortKey: const OrdinalSortKey(0),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: vertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              )
            : Wrap(spacing: 4, runSpacing: 4, children: buttons),
      ),
    );
  }

  Widget _status(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(app.accessibilityStatus)),
          if (app.runtime?.config.development ?? false)
            const Text('开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。'),
          if (app.phase == StartupPhase.checking)
            const LinearProgressIndicator(semanticsLabel: '检查本地依赖'),
          if (app.phase == StartupPhase.blocked &&
              app.section != AppSection.settings)
            AccessibleControl(
              child: TextButton(
                onPressed: () => app.navigate(AppSection.settings),
                child: const Text('查看依赖详情'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _FocusSearchAction extends Action<_FocusSearchIntent> {
  _FocusSearchAction(this.navigator, this.focus);
  final GlobalKey<NavigatorState> navigator;
  final VoidCallback focus;
  @override
  bool isEnabled(_FocusSearchIntent intent) =>
      !(navigator.currentState?.canPop() ?? false);
  @override
  Object? invoke(_FocusSearchIntent intent) {
    focus();
    return null;
  }
}
