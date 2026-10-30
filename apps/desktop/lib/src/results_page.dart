import 'package:core_parsing/core_parsing.dart';
import 'package:core_retrieval/core_retrieval.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';

import 'application/app_controller.dart';
import 'application/search_models.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final request = app.submittedSearch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (request != null) ...[
          SelectableText('本次查询：${request.query}'),
          Text(
            '类型：${request.filters.extensions?.join('、') ?? '全部'}；'
            '相对路径：${request.filters.pathPrefix ?? '不限'}；'
            '修改时间晚于：${request.filters.modifiedAfter?.toLocal() ?? '不限'}',
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => app.navigate(AppSection.search),
            child: const Text('修改搜索条件'),
          ),
        ),
        if (app.searchPhase == SearchPhase.loading) ...[
          Semantics(liveRegion: true, child: const Text('正在检索本地索引…')),
          const LinearProgressIndicator(semanticsLabel: '正在搜索'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: app.cancelCurrentSearch,
              child: const Text('取消当前搜索'),
            ),
          ),
        ] else if (app.searchPhase == SearchPhase.emptyLibrary) ...[
          const Text('索引库为空。请先添加目录并完成建库，再重新搜索。'),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => app.navigate(AppSection.library),
              child: const Text('前往文件库'),
            ),
          ),
        ] else if (app.searchPhase == SearchPhase.noMatches)
          Semantics(
            liveRegion: true,
            child: const Text('当前条件下没有检索结果。请修改查询或清除筛选后重试。'),
          )
        else if (app.searchPhase == SearchPhase.failed ||
            app.searchPhase == SearchPhase.invalid)
          Semantics(
            liveRegion: true,
            child: Text(app.searchError ?? '搜索失败，请返回搜索页面重试。'),
          )
        else if (app.searchPhase == SearchPhase.cancelled)
          const Text('搜索已取消。后台会在当前安全点结束，可重新提交查询。')
        else if (app.searchPhase == SearchPhase.idle) ...[
          Text(app.query.isEmpty ? '尚未提交查询。' : '查询草稿：${app.query}'),
          if (app.searchNotice != null) Text(app.searchNotice!),
        ] else ...[
          Semantics(
            liveRegion: true,
            child: Text('找到 ${app.results.length} 条结果。'),
          ),
          const Text('结果按相关性排序，排序分值不代表正确概率。'),
          for (var i = 0; i < app.results.length; i++)
            _result(context, app.results[i], i + 1),
        ],
      ],
    );
  }

  Widget _result(BuildContext context, SearchResult hit, int rank) {
    final image = hit.modality == Modality.image;
    final asset = hit.imageAsset;
    final description = asset is ImageAsset
        ? '${asset.format.toUpperCase()}，${asset.width} × ${asset.height} 像素'
        : '无可用的图像尺寸元数据';
    final key = hit.documentKey ?? hit.relativePath;
    final outcome = app.fileOpenOutcomes[key];
    final opening = app.openingPaths.contains(key);
    return Card(
      key: ValueKey('result-$rank-${hit.chunkId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$rank. ${hit.fileName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('类型：${image ? '图片' : hit.mimeType ?? '文本'}'),
            if (image) ...[
              Icon(
                Icons.image_outlined,
                semanticLabel: '图片文件：${hit.fileName}，$description',
              ),
              Text(description),
              const Text('此结果显示文件元数据，未生成图像内容描述。'),
            ] else
              SelectableText(hit.snippet),
            SelectableText('来源路径：${hit.documentKey ?? '索引未提供绝对来源路径'}'),
            SelectableText('相对路径：${hit.relativePath}'),
            Text(
              hit.pageNumber == null ? '此结果无物理页码。' : '出处：第 ${hit.pageNumber} 页',
            ),
            if (!image)
              Text(
                '命中块字符偏移：${hit.startOffset}–${hit.endOffset}（UTF-16，含首不含尾）。'
                '片段可包含相邻上下文，偏移仅对应命中块。',
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: opening || app.fileOpener == null || app.shuttingDown
                    ? null
                    : () => app.openResult(hit),
                icon: const Icon(Icons.open_in_new),
                label: Text(opening ? '正在请求打开…' : '打开原文件'),
              ),
            ),
            const Text('系统查看器可能无法直接定位到上述页或片段。'),
            if (outcome != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  outcome.message,
                  style: outcome.status == FileOpenStatus.requested
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
