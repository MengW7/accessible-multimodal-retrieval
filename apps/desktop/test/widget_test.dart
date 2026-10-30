import 'dart:async';

import 'package:desktop/src/app.dart';
import 'package:desktop/src/application/app_controller.dart';
import 'package:desktop/src/application/desktop_service.dart';
import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const config = RuntimeConfig(
  resourceRoot: 'C:/runtime',
  dataDirectory: 'C:/data',
  development: true,
  javaExecutable: 'java',
);
const ready = RuntimeReport(
  config: config,
  checks: [RuntimeCheck('SQLite', CheckStatus.passed, '可用')],
  documents: 2,
  chunks: 8,
);
const blocked = RuntimeReport(
  config: config,
  checks: [RuntimeCheck('Python', CheckStatus.blocked, '缺少 Python')],
);

class StubService implements DesktopService {
  Future<RuntimeReport> Function() next = () async => ready;
  @override
  Future<RuntimeReport> inspect() => next();
  @override
  Future<Map<String, Object?>> verify(String directory) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('four areas retain a query draft across navigation', (
    tester,
  ) async {
    final app = AppController(StubService());
    await tester.pumpWidget(RetrievalApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('当前索引：2 份文档，8 个内容块'), findsOneWidget);
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('query-field')), '离线资料');
    await tester.tap(find.text('结果').last);
    await tester.pumpAndSettle();
    expect(find.text('查询草稿：离线资料'), findsOneWidget);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('索引位置：'), findsOneWidget);
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('query-field')))
          .controller!
          .text,
      '离线资料',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dependency failure keeps navigation available and retry recovers',
    (tester) async {
      final service = StubService()..next = () async => blocked;
      await tester.pumpWidget(RetrievalApp(controller: AppController(service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看依赖详情'));
      await tester.pumpAndSettle();
      expect(find.text('缺少 Python'), findsOneWidget);
      service.next = () async => ready;
      await tester.tap(find.text('重新检查依赖'));
      await tester.pumpAndSettle();
      expect(find.text('通过 · SQLite'), findsOneWidget);
      expect(find.text('缺少 Python'), findsNothing);
    },
  );

  testWidgets('wide layout uses rail and permits navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RetrievalApp(controller: AppController(StubService())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('索引位置：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('late startup check cannot overwrite a newer retry', () async {
    final first = Completer<RuntimeReport>();
    final service = StubService()..next = () => first.future;
    final controller = AppController(service);
    final pending = controller.initialize();
    service.next = () async => ready;
    await controller.initialize();
    first.complete(blocked);
    await pending;
    expect(controller.phase, StartupPhase.ready);
    controller.dispose();
  });

  test('disposing during startup ignores the completion', () async {
    final pending = Completer<RuntimeReport>();
    final controller = AppController(
      StubService()..next = () => pending.future,
    );
    final loading = controller.initialize();
    controller.dispose();
    pending.complete(ready);
    await loading;
  });
}
