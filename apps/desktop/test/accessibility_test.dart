import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop/src/accessibility_widgets.dart';
import 'package:desktop/src/app.dart';
import 'package:desktop/src/app_theme.dart';
import 'package:desktop/src/application/app_controller.dart';
import 'package:desktop/src/application/display_settings.dart';
import 'package:desktop/src/application/library_models.dart';
import 'package:desktop/src/application/search_models.dart';
import 'package:desktop/src/runtime/display_settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'library_test.dart' show FakeLibrary, empty;
import 'search_test.dart' show FakeSearch, FakeOpener, hit;
import 'widget_test.dart' show StubService;

class MemoryDisplayStore implements DisplaySettingsStore {
  DisplaySettings saved = const DisplaySettings();
  Completer<DisplaySettings>? loading;
  Completer<void>? writing;
  bool failLoad = false;
  bool failSave = false;
  final writes = <DisplaySettings>[];
  @override
  Future<DisplaySettings> load() async {
    if (failLoad) throw const FormatException('bad settings');
    return loading == null ? saved : await loading!.future;
  }

  @override
  Future<void> save(DisplaySettings settings) async {
    writes.add(settings);
    if (failSave) throw const FileSystemException('read-only');
    if (writing != null) await writing!.future;
    saved = settings;
  }
}

void main() {
  test(
    'display settings persist, bad records are preserved until explicit reset',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'amr-display-settings-',
      );
      try {
        final store = FileDisplaySettingsStore(dir.path);
        expect((await store.load()).fontSize, FontSizeMode.system);
        const changed = DisplaySettings(
          theme: DisplayTheme.dark,
          highContrast: true,
          fontSize: FontSizeMode.percent200,
        );
        await store.save(changed);
        final restored = await FileDisplaySettingsStore(dir.path).load();
        expect(restored.toJson(), changed.toJson());
        await store.file.writeAsString('invalid JSON');
        await expectLater(store.load(), throwsFormatException);
        expect(await store.file.readAsString(), 'invalid JSON');
        await store.save(const DisplaySettings());
        expect((await store.load()).toJson(), const DisplaySettings().toJson());
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('late settings load cannot overwrite user changes; writes keep the latest value', () async {
    final store = MemoryDisplayStore()..loading = Completer<DisplaySettings>();
    final app = AppController(StubService(), settingsStore: store);
    await app.initialize();
    final first = app.updateDisplaySettings(
      const DisplaySettings(highContrast: true),
    );
    final latest = app.updateDisplaySettings(
      const DisplaySettings(fontSize: FontSizeMode.percent200),
    );
    store.loading!.complete(const DisplaySettings(theme: DisplayTheme.dark));
    await app.loadDisplaySettings();
    await first;
    await latest;
    expect(app.displaySettings.fontSize, FontSizeMode.percent200);
    expect(store.saved.fontSize, FontSizeMode.percent200);
    expect(store.writes, hasLength(2));
    app.dispose();
  });
  test('settings errors remain actionable and reset recovers', () async {
    final store = MemoryDisplayStore()..failLoad = true;
    final app = AppController(StubService(), settingsStore: store);
    await app.initialize();
    await app.loadDisplaySettings();
    expect(app.settingsError, contains('无法恢复'));
    store.failSave = true;
    await app.updateDisplaySettings(const DisplaySettings(highContrast: true));
    expect(app.displaySettings.highContrast, isTrue);
    expect(app.settingsError, contains('保存失败'));
    store.failSave = false;
    await app.resetDisplaySettings();
    expect(app.settingsError, isNull);
    expect(store.saved.theme, DisplayTheme.system);
    app.dispose();
  });
  test('normal shutdown waits for a pending settings write', () async {
    final store = MemoryDisplayStore()..writing = Completer<void>();
    final app = AppController(StubService(), settingsStore: store);
    await app.initialize();
    final save = app.updateDisplaySettings(
      const DisplaySettings(highContrast: true),
    );
    var closed = false;
    final close = app.shutdown().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    store.writing!.complete();
    await save;
    await close;
    expect(store.saved.highContrast, isTrue);
    app.dispose();
  });

  testWidgets(
    'Ctrl+L focuses query, Tab and Shift+Tab follow the input order',
    (tester) async {
      final app = AppController(StubService(), searchService: FakeSearch());
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      app.navigate(AppSection.settings);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(app.section, AppSection.search);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('query-field')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final pathEditable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('path-filter-field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(pathEditable.focusNode.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('query-field')))
            .focusNode!
            .hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'dialog traps focus, ignores search shortcut, Esc restores the clear button',
    (tester) async {
      final app = AppController(
        StubService(),
        library: FakeLibrary(),
        searchService: FakeSearch(),
      );
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      final buttonFinder = find.widgetWithText(OutlinedButton, '清除全部索引');
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();
      final clear = tester.widget<OutlinedButton>(buttonFinder);
      clear.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<AlertDialog>(),
          isNotNull,
        );
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(app.section, AppSection.library);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(clear.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets(
    'offscreen navigation remains in the keyboard order with a visible focus outline',
    (tester) async {
      final app = AppController(StubService());
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      app.navigate(AppSection.settings);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重新检查依赖'));
      await tester.pumpAndSettle();
      final nav = find.byKey(const ValueKey('nav-library'));
      expect(
        nav,
        findsOneWidget,
        reason: 'scrolling must not dispose earlier tab stops',
      );
      // Start from a visible control and reach the navigation with Shift+Tab.
      await tester.tap(find.text('重新检查依赖'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      var reached = false;
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<TextButton>()
                ?.key ==
            const ValueKey('nav-library')) {
          reached = true;
          break;
        }
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(reached, isTrue);
      expect(nav.hitTestable(), findsOneWidget);
      final wrapper = find
          .ancestor(of: nav, matching: find.byType(AccessibleControl))
          .first;
      final outline = tester
          .widgetList<Container>(
            find.descendant(of: wrapper, matching: find.byType(Container)),
          )
          .firstWhere((w) => w.decoration is BoxDecoration);
      final border = (outline.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, 3);
      expect(
        border.top.color,
        Theme.of(tester.element(nav)).colorScheme.primary,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(app.section, AppSection.library);
    },
  );

  testWidgets(
    'system brightness and high contrast are respected without persisting an override',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final app = AppController(StubService());
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.text('本地内容检索')));
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface, Colors.black);
      expect(theme.colorScheme.onSurface, Colors.white);
      expect(app.displaySettings.highContrast, isFalse);
    },
  );

  testWidgets(
    'settings controls apply and save keyboard changes, dropdown choices and reset',
    (tester) async {
      final store = MemoryDisplayStore();
      final app = AppController(StubService(), settingsStore: store);
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      app.navigate(AppSection.settings);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // theme
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // contrast switch
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(app.displaySettings.highContrast, isTrue);
      expect(store.saved.highContrast, isTrue);
      final font = find.byKey(const Key('font-size-setting'));
      await tester.ensureVisible(font);
      await tester.tap(font);
      await tester.pumpAndSettle();
      await tester.tap(find.text('200%').last);
      await tester.pumpAndSettle();
      expect(store.saved.fontSize, FontSizeMode.percent200);
      final theme = find.byKey(const Key('theme-setting'));
      await tester.ensureVisible(theme);
      await tester.pumpAndSettle();
      await tester.tap(theme);
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色').last);
      await tester.pumpAndSettle();
      expect(store.saved.theme, DisplayTheme.dark);
      expect(Theme.of(tester.element(theme)).brightness, Brightness.dark);
      final reset = find.text('恢复默认显示设置');
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(store.saved.toJson(), const DisplaySettings().toJson());
      expect(
        tester.widget<DropdownButtonFormField<FontSizeMode>>(font).initialValue,
        FontSizeMode.system,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'semantic names isolate fields and identify each result open action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final search = FakeSearch();
        final app = AppController(
          StubService(),
          searchService: search,
          fileOpener: FakeOpener(),
        );
        await tester.pumpWidget(RetrievalApp(controller: app));
        await tester.pumpAndSettle();
        app.navigate(AppSection.search);
        await tester.pumpAndSettle();
        final field = tester
            .getSemantics(find.byKey(const Key('query-field')))
            .getSemanticsData();
        expect(field.flagsCollection.isTextField, isTrue);
        expect(field.label, contains('搜索本地内容'));
        expect(field.label, isNot(contains('本地运行依赖')));
        app.updateQuery('q');
        final job = app.submitSearch();
        search.complete(0, [hit('one.pdf'), hit('two.png', image: true)]);
        await job;
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('打开原文件：one.pdf'), findsOneWidget);
        expect(find.bySemanticsLabel('打开原文件：two.png'), findsOneWidget);
        final button = tester
            .getSemantics(find.bySemanticsLabel('打开原文件：one.pdf'))
            .getSemanticsData();
        expect(button.flagsCollection.isButton, isTrue);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.header == true,
          ),
          findsWidgets,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'live status stays inside the viewport when the page is scrolled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final store = MemoryDisplayStore();
        final app = AppController(StubService(), settingsStore: store);
        await tester.pumpWidget(RetrievalApp(controller: app));
        await tester.pumpAndSettle();
        app.navigate(AppSection.settings);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('重新检查依赖'));
        await tester.pumpAndSettle();
        store.failSave = true;
        await app.updateDisplaySettings(
          const DisplaySettings(highContrast: true),
        );
        await tester.pumpAndSettle();
        final live = find.byKey(const Key('application-live-status'));
        final viewport =
            Offset.zero &
            (tester.view.physicalSize / tester.view.devicePixelRatio);
        expect(
          tester.getRect(live).overlaps(viewport),
          isTrue,
          reason: 'a clipped live region cannot reliably announce background changes',
        );
        final data = tester.getSemantics(live).getSemanticsData();
        expect(data.flagsCollection.isLiveRegion, isTrue);
        expect(data.label, contains('保存失败'));
      } finally {
        semantics.dispose();
      }
    },
  );

  test('progress live status changes by stage or ten percent bands', () async {
    final library = FakeLibrary();
    final app = AppController(StubService(), library: library);
    await app.initialize();
    final job = app.indexDirectory(
      p.join(Directory.systemTemp.path, 'fixtures'),
    );
    library.updates.add(
      const LibraryProgress(
        stage: LibraryStage.parsing,
        processed: 2,
        total: 100,
      ),
    );
    final first = app.accessibilityStatus;
    library.updates.add(
      const LibraryProgress(
        stage: LibraryStage.parsing,
        processed: 3,
        total: 100,
      ),
    );
    expect(app.accessibilityStatus, first);
    library.updates.add(
      const LibraryProgress(
        stage: LibraryStage.parsing,
        processed: 14,
        total: 100,
      ),
    );
    expect(app.accessibilityStatus, contains('10%'));
    final run = LibraryRun(
      root: 'fixtures',
      finishedAt: DateTime(2026),
      written: 0,
      reused: 0,
      cancelled: true,
      files: const [],
    );
    library.pending.complete(LibraryResult(run: run, snapshot: empty));
    await job;
    expect(app.accessibilityStatus, contains('已取消'));
    app.dispose();
  });

  testWidgets(
    'system text scale and device pixel ratio are not multiplied into app font size',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(StubService());
      await tester.pumpWidget(RetrievalApp(controller: app));
      await tester.pumpAndSettle();
      final label = find.byKey(const Key('directory-field'));
      // The platform can provide a nonlinear scaler: preserve it exactly.
      final systemScaler = MediaQueryData.fromView(tester.view).textScaler;
      expect(
        MediaQuery.textScalerOf(tester.element(label)).scale(10),
        systemScaler.scale(10),
      );
      expect(
        MediaQuery.textScalerOf(tester.element(label)).scale(24),
        systemScaler.scale(24),
      );
      await app.updateDisplaySettings(
        const DisplaySettings(fontSize: FontSizeMode.percent200),
      );
      await tester.pumpAndSettle();
      expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), 20);
      expect(
        tester.widget<Text>(find.text('本地内容检索')).textScaler!.scale(22),
        44,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 112);
      await app.updateDisplaySettings(
        const DisplaySettings(fontSize: FontSizeMode.percent100),
      );
      await tester.pumpAndSettle();
      expect(MediaQuery.textScalerOf(tester.element(label)).scale(10), 10);
    },
  );

  for (final dark in [false, true]) {
    for (final size in [
      FontSizeMode.percent100,
      FontSizeMode.percent150,
      FontSizeMode.percent200,
    ]) {
      testWidgets(
        'all pages and clear dialog remain reachable at ${size.label}, dark=$dark, narrow high contrast',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = AppController(
            StubService(),
            library: FakeLibrary(),
            searchService: FakeSearch(),
            fileOpener: FakeOpener(),
          );
          await app.updateDisplaySettings(
            DisplaySettings(
              theme: dark ? DisplayTheme.dark : DisplayTheme.light,
              highContrast: true,
              fontSize: size,
            ),
          );
          await tester.pumpWidget(RetrievalApp(controller: app));
          await tester.pumpAndSettle();
          for (final section in AppSection.values) {
            app.navigate(section);
            await tester.pumpAndSettle();
            if (section == AppSection.results) {
              app.results = [hit('${'very-long-file-name-' * 8}.pdf')];
              app.searchPhase = SearchPhase.matches;
              app.navigate(section);
              await tester.pumpAndSettle();
            }
            expect(
              tester.takeException(),
              isNull,
              reason: 'layout $section at ${size.label}',
            );
          }
          await tester.ensureVisible(find.text('恢复默认显示设置'));
          await tester.pumpAndSettle();
          expect(find.text('恢复默认显示设置').hitTestable(), findsOneWidget);
          app.navigate(AppSection.library);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('清除全部索引'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('清除全部索引'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('保留索引'));
          await tester.pumpAndSettle();
          expect(find.text('保留索引').hitTestable(), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        },
      );
    }
  }

  test('configured theme text and focus pairs meet contrast targets', () async {
    final measurements = <Map<String, Object?>>[];
    for (final brightness in Brightness.values) {
      for (final highContrast in [false, true]) {
        final theme = retrievalTheme(brightness, highContrast: highContrast);
        final c = theme.colorScheme;
        for (final pair in <String, (Color, Color, double)>{
          'body': (c.onSurface, c.surface, 4.5),
          'secondaryText': (c.onSurfaceVariant, c.surface, 4.5),
          'filledButton': (c.onPrimary, c.primary, 4.5),
          'errorText': (c.error, c.surface, 4.5),
          'disabledText': (theme.disabledColor, c.surface, 4.5),
          'fieldOutline': (c.outline, c.surface, 3),
          'focusOutline': (c.primary, c.surface, 3),
        }.entries) {
          final a = pair.value.$1.computeLuminance();
          final b = pair.value.$2.computeLuminance();
          final ratio = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
          measurements.add({
            'brightness': brightness.name,
            'highContrast': highContrast,
            'pair': pair.key,
            'foreground': pair.value.$1.toARGB32().toRadixString(16),
            'background': pair.value.$2.toARGB32().toRadixString(16),
            'ratio': ratio,
            'minimum': pair.value.$3,
          });
          expect(
            ratio,
            greaterThanOrEqualTo(pair.value.$3),
            reason: '${brightness.name}/$highContrast/${pair.key}',
          );
        }
      }
    }
    final target = Platform.environment['AMR_D_CONTRAST_REPORT'];
    if (target != null) {
      await File(
        target,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(measurements));
    }
  });
}
