import 'package:flutter/material.dart';

import 'accessibility_widgets.dart';
import 'application/app_controller.dart';
import 'application/desktop_service.dart';
import 'application/display_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final settings = app.displaySettings;
    final enabled = !app.shuttingDown;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccessibleControl(
            child: DropdownButtonFormField<DisplayTheme>(
              key: const Key('theme-setting'),
              initialValue: settings.theme,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(labelText: '明暗主题'),
              items: const [
                DropdownMenuItem(
                  value: DisplayTheme.system,
                  child: Text('跟随系统'),
                ),
                DropdownMenuItem(value: DisplayTheme.light, child: Text('浅色')),
                DropdownMenuItem(value: DisplayTheme.dark, child: Text('深色')),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) {
                        app.updateDisplaySettings(
                          settings.copyWith(theme: value),
                        );
                      }
                    }
                  : null,
            ),
          ),
          AccessibleControl(
            child: SwitchListTile(
              key: const Key('contrast-setting'),
              title: const Text('高对比模式'),
              subtitle: const Text('系统要求高对比时也会自动启用。'),
              value: settings.highContrast,
              onChanged: enabled
                  ? (value) => app.updateDisplaySettings(
                      settings.copyWith(highContrast: value),
                    )
                  : null,
            ),
          ),
          AccessibleControl(
            child: DropdownButtonFormField<FontSizeMode>(
              key: const Key('font-size-setting'),
              initialValue: settings.fontSize,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(labelText: '文字大小'),
              items: [
                for (final mode in FontSizeMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: enabled
                  ? (value) {
                      if (value != null) {
                        app.updateDisplaySettings(
                          settings.copyWith(fontSize: value),
                        );
                      }
                    }
                  : null,
            ),
          ),
          const Text(
            '默认保留系统文字缩放；选择 100% / 150% / 200% 时使用该应用字号，'
            '不会再乘一次系统文字比例或屏幕像素比例。',
          ),
          if (app.settingsLoading) const Text('正在恢复显示设置…'),
          if (app.settingsSaving) const Text('正在保存显示设置…'),
          if (app.settingsError != null)
            Text(
              app.settingsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (app.settingsStore == null) const Text('未连接设置存储，当前更改仅在本次会话有效。'),
          Align(
            alignment: Alignment.centerLeft,
            child: AccessibleControl(
              child: OutlinedButton(
                onPressed: enabled ? app.resetDisplaySettings : null,
                child: const Text('恢复默认显示设置'),
              ),
            ),
          ),
          const Divider(),
          accessibleHeading(context, '键盘操作'),
          const Text(
            'Ctrl+L 聚焦搜索（macOS 使用 Command+L）；Tab / Shift+Tab 顺序移动；'
            '搜索输入框中 Enter 提交；按钮可用 Enter / Space 激活；Esc 关闭当前 Flutter 弹窗。'
            '弹窗内焦点循环，关闭后返回触发控件。系统目录对话框及文件查看器由系统管理。',
          ),
          const Divider(),
          accessibleHeading(context, '本地运行依赖'),
          SelectableText('索引位置：${app.runtime?.config.databasePath ?? '检查中'}'),
          Align(
            alignment: Alignment.centerLeft,
            child: AccessibleControl(
              child: OutlinedButton.icon(
                onPressed:
                    enabled &&
                        app.phase != StartupPhase.checking &&
                        !app.libraryBusy &&
                        !app.choosingDirectory &&
                        !app.libraryLoading
                    ? app.initialize
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('重新检查依赖'),
              ),
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
      ),
    );
  }
}
