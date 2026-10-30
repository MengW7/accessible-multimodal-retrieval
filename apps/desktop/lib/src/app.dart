import 'package:flutter/material.dart';

import 'application/app_controller.dart';
import 'application/desktop_service.dart';
import 'library_page.dart';

/// Owns its controller. Services finish and close resources inside workers.
class RetrievalApp extends StatefulWidget {
  const RetrievalApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<RetrievalApp> createState() => _RetrievalAppState();
}

class _RetrievalAppState extends State<RetrievalApp> {
  late final TextEditingController _query;
  AppController get app => widget.controller;
  static const _labels = ['文件库', '搜索', '结果', '设置'];
  static const _icons = [
    Icons.folder_outlined,
    Icons.search,
    Icons.article_outlined,
    Icons.settings_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: app.query);
    app.initialize();
  }

  @override
  void dispose() {
    _query.dispose();
    app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '本地内容检索',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff235d58)),
      useMaterial3: true,
    ),
    home: AnimatedBuilder(
      animation: app,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          return Scaffold(
            appBar: AppBar(title: const Text('本地内容检索')),
            body: Row(
              children: [
                if (wide)
                  NavigationRail(
                    extended: true,
                    selectedIndex: app.section.index,
                    onDestinationSelected: (i) =>
                        app.navigate(AppSection.values[i]),
                    destinations: [
                      for (var i = 0; i < _labels.length; i++)
                        NavigationRailDestination(
                          icon: Icon(_icons[i]),
                          label: Text(_labels[i]),
                        ),
                    ],
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        _labels[app.section.index],
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      _startupStatus(context),
                      const SizedBox(height: 24),
                      ..._page(context),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: app.section.index,
                    onDestinationSelected: (i) =>
                        app.navigate(AppSection.values[i]),
                    destinations: [
                      for (var i = 0; i < _labels.length; i++)
                        NavigationDestination(
                          icon: Icon(_icons[i]),
                          label: _labels[i],
                        ),
                    ],
                  ),
          );
        },
      ),
    ),
  );

  Widget _startupStatus(BuildContext context) {
    final text = switch (app.phase) {
      StartupPhase.checking => '正在检查本地运行依赖…',
      StartupPhase.ready => '本地运行依赖可用。',
      StartupPhase.blocked => app.startupError ?? '运行依赖尚未就绪，请在设置中查看并处理。',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(liveRegion: true, child: Text(text)),
            if (app.phase == StartupPhase.checking) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (app.runtime?.config.development ?? false)
              const Text('开发模式：需要外部 Python/ONNX 环境，尚非独立发布包。'),
            if (app.phase == StartupPhase.blocked &&
                app.section != AppSection.settings)
              TextButton(
                onPressed: () => app.navigate(AppSection.settings),
                child: const Text('查看依赖详情'),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _page(BuildContext context) => switch (app.section) {
    AppSection.library => [LibraryPage(app: app)],
    AppSection.search => [
      TextField(
        key: const Key('query-field'),
        controller: _query,
        decoration: const InputDecoration(
          labelText: '搜索本地内容',
          hintText: '输入关键词或自然语言描述',
          border: OutlineInputBorder(),
        ),
        onChanged: app.updateQuery,
      ),
      const SizedBox(height: 16),
      const Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(onPressed: null, child: Text('开始搜索')),
      ),
      const Text('查询提交与筛选尚未接入，输入内容会在切换页面后保留。'),
    ],
    AppSection.results => [
      Text(app.query.isEmpty ? '尚未提交查询。' : '查询草稿：${app.query}'),
      const SizedBox(height: 12),
      const Text('尚无查询结果。提交查询后将在此显示文件、出处和内容片段。'),
    ],
    AppSection.settings => [
      SelectableText('索引位置：${app.runtime?.config.databasePath ?? '检查中'}'),
      const SizedBox(height: 12),
      const Text('显示与无障碍设置尚未接入。'),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed:
              app.phase == StartupPhase.checking ||
                  app.libraryBusy ||
                  app.choosingDirectory ||
                  app.libraryLoading
              ? null
              : app.initialize,
          icon: const Icon(Icons.refresh),
          label: const Text('重新检查依赖'),
        ),
      ),
      for (final check in app.runtime?.checks ?? <RuntimeCheck>[]) ...[
        const Divider(),
        Text(
          '${switch (check.status) {
            CheckStatus.passed => '通过',
            CheckStatus.blocked => '阻塞',
            CheckStatus.warning => '提示',
          }} · ${check.name}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SelectableText(check.detail),
      ],
    ],
  };
}
