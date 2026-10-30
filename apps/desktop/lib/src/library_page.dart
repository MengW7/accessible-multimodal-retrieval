import 'package:flutter/material.dart';

import 'application/app_controller.dart';
import 'application/library_models.dart';
import 'accessibility_widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.app});
  final AppController app;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final TextEditingController _directory;
  final _clearFocus = FocusNode(debugLabel: '清除全部索引');
  AppController get app => widget.app;
  @override
  void initState() {
    super.initState();
    _directory = TextEditingController(text: app.directoryDraft);
    app.addListener(_syncDirectory);
  }

  void _syncDirectory() {
    if (_directory.text != app.directoryDraft) {
      _directory.text = app.directoryDraft;
    }
  }

  @override
  void dispose() {
    app.removeListener(_syncDirectory);
    _directory.dispose();
    _clearFocus.dispose();
    super.dispose();
  }

  Future<void> _confirmClear() async {
    final route = DialogRoute<bool>(
      context: context,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (context) => AlertDialog(
        title: const Text('清除全部索引？'),
        content: SingleChildScrollView(
          child: Text(
            '将清除当前应用的全部索引和已保存目录记录。所有源文件保留，不会删除。\n\n'
            '索引位置：${app.runtime?.config.databasePath ?? '当前应用数据目录'}\n\n'
            '之后需要重新添加目录建立索引。',
          ),
        ),
        actions: [
          AccessibleControl(
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留索引'),
            ),
          ),
          AccessibleControl(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认清除索引'),
            ),
          ),
        ],
      ),
    );
    final confirmed = await Navigator.of(context).push(route);
    await route.completed;
    if (confirmed == true && mounted) await app.clearLibrary();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && app.canClear) _clearFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = app.librarySnapshot?.stats;
    final progress = app.libraryProgress;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '当前索引：${stats?.documents ?? app.runtime?.documents ?? '待检查'} 份文档，'
            '${stats?.chunks ?? app.runtime?.chunks ?? '待检查'} 个内容块',
          ),
          if (app.shuttingDown)
            Semantics(child: const Text('正在结束后台任务并关闭应用，请等待当前安全点。')),
          const SizedBox(height: 16),
          TextField(
            key: const Key('directory-field'),
            controller: _directory,
            enabled: app.canIndex,
            onChanged: app.updateDirectory,
            onSubmitted: app.canIndex ? (_) => app.indexDirectory() : null,
            decoration: const InputDecoration(
              labelText: '目录的绝对路径',
              hintText: '选择文件夹，或直接输入完整路径',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: app.canIndex && app.directoryPicker != null
                    ? app.chooseDirectory
                    : null,
                icon: const Icon(Icons.folder_open),
                label: Text(app.choosingDirectory ? '正在选择…' : '选择目录'),
              ),
              FilledButton.icon(
                onPressed: app.canIndex ? () => app.indexDirectory() : null,
                icon: const Icon(Icons.add),
                label: const Text('建立 / 增量更新索引'),
              ),
              OutlinedButton.icon(
                focusNode: _clearFocus,
                onPressed: app.canClear ? _confirmClear : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除全部索引'),
              ),
            ].map((child) => AccessibleControl(child: child)).toList(),
          ),
          const SizedBox(height: 12),
          const Text(
            '支持 TXT、Markdown、PDF、DOCX、JPG、PNG。增量更新会复用未改变的内容。'
            '相同内容共用一份索引文档；源文件不会被修改。',
          ),
          if (app.libraryLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(semanticsLabel: '正在读取文件库'),
            ),
          if (app.libraryError != null) ...[
            const SizedBox(height: 12),
            Semantics(
              child: Text(
                app.libraryError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AccessibleControl(
                child: TextButton(
                  onPressed: !app.libraryBusy && !app.libraryLoading
                      ? app.refreshLibrary
                      : null,
                  child: const Text('重新读取文件库'),
                ),
              ),
            ),
          ],
          if (app.libraryNotice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(app.libraryNotice!),
            ),
          if (app.libraryBusy && progress != null) ...[
            const SizedBox(height: 16),
            Semantics(
              child: Text(
                app.cancelling
                    ? '正在取消，请等待当前安全点；已提交的索引将保留。'
                    : '${switch (progress.stage) {
                        LibraryStage.preparing => '准备本地运行时',
                        LibraryStage.parsing => '扫描与解析',
                        LibraryStage.indexing => '嵌入与建库',
                        LibraryStage.saving => '保存目录记录',
                      }}${progress.total == null ? '' : '：${progress.processed} / ${progress.total}'}',
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.total != null && progress.total! > 0
                  ? (progress.processed / progress.total!).clamp(0, 1)
                  : null,
              semanticsLabel: '索引任务进度',
            ),
            if (progress.currentPath != null)
              SelectableText(progress.currentPath!),
            Align(
              alignment: Alignment.centerLeft,
              child: AccessibleControl(
                child: OutlinedButton(
                  onPressed: app.cancelling ? null : app.cancelIndexing,
                  child: const Text('取消索引任务'),
                ),
              ),
            ),
          ],
          if (app.currentFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            accessibleHeading(
              context,
              '本次文件状态',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            LibraryFiles(files: app.currentFiles.values.toList()),
          ],
          const SizedBox(height: 24),
          accessibleHeading(context, '已添加目录'),
          if (app.librarySnapshot?.roots.isEmpty ?? true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('尚未添加目录。先选择目录，再建立索引。'),
            ),
          for (final root in app.librarySnapshot?.roots ?? <LibraryRun>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(root.root),
                    Text(
                      '${root.label} · 新写入 ${root.written} · 复用 ${root.reused} · '
                      '失败 ${root.failed} · 跳过 ${root.skipped} · 警告 ${root.warnings}',
                    ),
                    Text('最近处理：${root.finishedAt.toLocal()}'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AccessibleControl(
                        child: OutlinedButton(
                          onPressed: app.canIndex
                              ? () => app.indexDirectory(root.root)
                              : null,
                          child: Text(
                            '增量重建此目录',
                            semanticsLabel: '增量重建目录 ${root.root}',
                          ),
                        ),
                      ),
                    ),
                    AccessibleControl(
                      child: ExpansionTile(
                        title: Text(
                          '查看上次文件状态',
                          semanticsLabel: '查看目录 ${root.root} 的上次文件状态',
                        ),
                        children: [LibraryFiles(files: root.files)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ].map((child) => child is TextField ? AccessibleControl(child: child) : child).toList(),
      ),
    );
  }
}

/// Bound widget count while keeping every file reachable through pagination.
class LibraryFiles extends StatefulWidget {
  const LibraryFiles({super.key, required this.files});
  final List<LibraryFile> files;
  @override
  State<LibraryFiles> createState() => _LibraryFilesState();
}

class _LibraryFilesState extends State<LibraryFiles> {
  int page = 0;
  static const pageSize = 30;
  @override
  Widget build(BuildContext context) {
    final pages = ((widget.files.length + pageSize - 1) ~/ pageSize).clamp(
      1,
      1 << 30,
    );
    if (page >= pages) page = pages - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final file in widget.files.skip(page * pageSize).take(pageSize))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${switch (file.status) {
                    LibraryFileStatus.queued => '等待建库',
                    LibraryFileStatus.indexed => '已建库',
                    LibraryFileStatus.reused => '已复用',
                    LibraryFileStatus.failed => '失败',
                    LibraryFileStatus.skipped => '已跳过',
                    LibraryFileStatus.cancelled => '未处理（已取消）',
                  }}${file.warning ? '（有警告）' : ''} · ${file.path}',
                ),
                if (file.detail != null) Text(file.detail!),
              ],
            ),
          ),
        if (pages > 1)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AccessibleControl(
                child: TextButton(
                  onPressed: page > 0 ? () => setState(() => page--) : null,
                  child: const Text('上一页'),
                ),
              ),
              Text('第 ${page + 1} / $pages 页，共 ${widget.files.length} 个文件'),
              AccessibleControl(
                child: TextButton(
                  onPressed: page + 1 < pages
                      ? () => setState(() => page++)
                      : null,
                  child: const Text('下一页'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
