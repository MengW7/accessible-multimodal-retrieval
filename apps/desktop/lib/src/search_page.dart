import 'package:flutter/material.dart';

import 'application/app_controller.dart';
import 'application/search_models.dart';
import 'accessibility_widgets.dart';

class SearchForm extends StatefulWidget {
  const SearchForm({
    super.key,
    required this.app,
    required this.queryController,
    this.queryFocusNode,
  });
  final AppController app;
  final TextEditingController queryController;
  final FocusNode? queryFocusNode;
  @override
  State<SearchForm> createState() => _SearchFormState();
}

class _SearchFormState extends State<SearchForm> {
  late final TextEditingController _path;
  late final TextEditingController _date;
  AppController get app => widget.app;
  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: app.pathFilter);
    _date = TextEditingController(text: app.modifiedAfterFilter);
    app.addListener(_syncFilters);
  }

  void _syncFilters() {
    if (_path.text != app.pathFilter) _path.text = app.pathFilter;
    if (_date.text != app.modifiedAfterFilter) {
      _date.text = app.modifiedAfterFilter;
    }
  }

  @override
  void dispose() {
    app.removeListener(_syncFilters);
    _path.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children:
          [
                TextField(
                  key: const Key('query-field'),
                  controller: widget.queryController,
                  focusNode: widget.queryFocusNode,
                  onChanged: app.updateQuery,
                  textInputAction: TextInputAction.search,
                  onSubmitted: app.canSearch ? (_) => app.submitSearch() : null,
                  decoration: const InputDecoration(
                    labelText: '搜索本地内容',
                    hintText: '输入关键词或自然语言描述',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<FileTypeChoice>(
                  key: const Key('file-type-filter'),
                  initialValue: app.fileType,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(
                    labelText: '文件类型',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final type in FileTypeChoice.values)
                      DropdownMenuItem(value: type, child: Text(type.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) app.updateFileType(value);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('path-filter-field'),
                  controller: _path,
                  onChanged: app.updatePathFilter,
                  decoration: const InputDecoration(
                    labelText: '相对目录或文件路径',
                    helperText: '相对于导入目录，例如 notes 或 notes/file.pdf；目录包含其子目录。',
                    helperMaxLines: 8,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('date-filter-field'),
                  controller: _date,
                  onChanged: app.updateModifiedAfter,
                  decoration: const InputDecoration(
                    labelText: '修改时间晚于日期',
                    hintText: 'YYYY-MM-DD（可留空）',
                    helperText: '晚于该日期的本地时间零点，不含该时刻。',
                    helperMaxLines: 4,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: app.canSearch ? app.submitSearch : null,
                      icon: const Icon(Icons.search),
                      label: const Text('开始搜索'),
                    ),
                    OutlinedButton(
                      onPressed: app.clearSearchFilters,
                      child: const Text('清除筛选'),
                    ),
                    if (app.searchPhase == SearchPhase.loading)
                      OutlinedButton(
                        onPressed: app.cancelCurrentSearch,
                        child: const Text('取消当前搜索'),
                      ),
                  ].map((child) => AccessibleControl(child: child)).toList(),
                ),
                if (app.searchPhase == SearchPhase.invalid &&
                    app.searchError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      child: Text(
                        app.searchError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (app.libraryBusy) const Text('文件库任务正在执行，请等待或取消后再搜索。'),
                const SizedBox(height: 12),
                const Text('搜索本地索引，每次最多显示前 20 条结果。清除筛选后需重新提交搜索。'),
              ]
              .map(
                (child) =>
                    child is TextField ||
                        child is DropdownButtonFormField<FileTypeChoice>
                    ? AccessibleControl(child: child)
                    : child,
              )
              .toList(),
    ),
  );
}
