import 'dart:io';

import 'package:desktop/src/runtime/runtime_config.dart';
import 'package:desktop/src/runtime/runtime_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('default resources follow executable and data follows user profile', () {
    final config = RuntimeConfig.fromEnvironment(
      environment: {'LOCALAPPDATA': r'C:\Users\Tester\AppData\Local'},
      executable: r'D:\Installed\amr.exe',
      operatingSystem: 'windows',
    );
    expect(config.development, isFalse);
    expect(config.resourceRoot, p.normalize(r'D:\Installed\runtime'));
    expect(
      config.databasePath,
      p.normalize(
        r'C:\Users\Tester\AppData\Local\AccessibleMultimodalRetrieval\library.sqlite',
      ),
    );
    expect(config.databasePath, isNot(contains('reports')));
  });

  test('development resources and data can be configured independently', () {
    final config = RuntimeConfig.fromEnvironment(
      environment: {
        'AMR_DEV_ROOT': r'E:\source',
        'AMR_DATA_DIR': r'D:\demo-index',
      },
      executable: r'C:\app\amr.exe',
      operatingSystem: 'windows',
    );
    expect(config.development, isTrue);
    expect(config.resourceRoot, p.normalize(r'E:\source'));
    expect(config.databasePath, p.normalize(r'D:\demo-index\library.sqlite'));
    expect(config.configurationErrors, isEmpty);
  });

  test(
    'relative overrides are blocked instead of following current directory',
    () {
      final config = RuntimeConfig.fromEnvironment(
        environment: {
          'AMR_DEV_ROOT': '../repo',
          'AMR_DATA_DIR': '.index',
          'AMR_JAVA': 'jdk/java',
        },
        executable: r'C:\app\amr.exe',
        operatingSystem: 'windows',
      );
      expect(config.configurationErrors, hasLength(3));
    },
  );

  test(
    'missing resources and Java produce actionable blocked checks',
    () async {
      final dir = await Directory.systemTemp.createTemp('amr-missing-');
      addTearDown(() => dir.delete(recursive: true));
      final report = await inspectRuntime(
        RuntimeConfig(
          resourceRoot: p.join(dir.path, 'absent'),
          dataDirectory: dir.path,
          development: true,
          javaExecutable: p.join(dir.path, 'no-java.exe'),
        ),
      );
      expect(report.ready, isFalse);
      expect(
        report.checks.where((c) => c.name == '文本模型').single.detail,
        contains('缺少文件'),
      );
      expect(
        report.checks.where((c) => c.name == 'Java').single.status.name,
        'blocked',
      );
    },
  );

  test(
    'release runtime gap is explicit and never falls back to repository Python',
    () async {
      final dir = await Directory.systemTemp.createTemp('amr-release-');
      addTearDown(() => dir.delete(recursive: true));
      final report = await inspectRuntime(
        RuntimeConfig(
          resourceRoot: dir.path,
          dataDirectory: dir.path,
          development: false,
          javaExecutable: 'java',
        ),
      );
      expect(report.ready, isFalse);
      expect(report.checks.any((c) => c.name == '生产嵌入运行时'), isTrue);
      expect(report.checks.any((c) => c.name == 'Python 模块'), isFalse);
    },
  );
}
