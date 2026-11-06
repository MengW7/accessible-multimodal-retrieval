import 'dart:async';
import 'dart:io';

import 'package:core_storage/core_storage.dart';

import '../application/desktop_service.dart';
import 'native_onnx.dart';
import 'runtime_config.dart';

Future<RuntimeReport> inspectRuntime(RuntimeConfig config) async {
  final checks = <RuntimeCheck>[
    for (final error in config.configurationErrors)
      RuntimeCheck('路径配置', CheckStatus.blocked, error),
  ];
  if (config.development) {
    checks.add(
      const RuntimeCheck(
        '开发运行时',
        CheckStatus.warning,
        '当前使用外部 Python/ONNX 开发环境，不能作为独立发布包验收。',
      ),
    );
  }
  if (config.configurationErrors.isEmpty) {
    final missing = <String>{};
    for (final entry in config.requiredFiles.entries) {
      final exists = await File(entry.value).exists();
      if (!exists) missing.add(entry.value);
      checks.add(
        RuntimeCheck(
          entry.key,
          exists ? CheckStatus.passed : CheckStatus.blocked,
          '${exists ? '已找到' : '缺少文件'}：${entry.value}',
        ),
      );
    }
    if (config.development && !missing.contains(config.python)) {
      checks.add(
        await checkProcess('Python 模块', config.python, [
          '-c',
          'import numpy, onnxruntime, PIL, tokenizers; '
              'print("onnxruntime=" + onnxruntime.__version__)',
        ]),
      );
    }
    if (!config.development) {
      const name = '生产嵌入运行时';
      if (!config.supportsNativeRuntime) {
        checks.add(
          const RuntimeCheck(
            name,
            CheckStatus.blocked,
            '生产推理适配当前支持 Windows x64。',
          ),
        );
      } else if (missing.contains(config.onnxLibrary) ||
          missing.contains(config.onnxBridge)) {
        checks.add(
          RuntimeCheck(
            name,
            CheckStatus.blocked,
            '请在 ${config.resourceRoot} 放置生产资源，或设置绝对路径 AMR_RUNTIME_ROOT。',
          ),
        );
      } else {
        try {
          final runtime = NativeOnnx.load(
            config.onnxLibrary,
            config.onnxBridge,
          );
          checks.add(
            RuntimeCheck(
              name,
              CheckStatus.passed,
              'ONNX Runtime CPU ${runtime.version}（${config.onnxLibrary}）',
            ),
          );
        } catch (error) {
          checks.add(RuntimeCheck(name, CheckStatus.blocked, error.toString()));
        }
      }
    }
    checks.add(await checkProcess('Java', config.javaExecutable, ['-version']));
  }
  int? documents;
  int? chunks;
  // Invalid paths must never silently create a database at the fallback path.
  if (config.configurationErrors.isEmpty) {
    SqliteVectorStore? store;
    try {
      await Directory(config.dataDirectory).create(recursive: true);
      final opened = openStore(
        const SystemSqliteLibraryLocator(),
        config.databasePath,
      );
      store = opened.store;
      if (store == null) {
        throw StateError(
          '${opened.failure?.message} ${opened.failure?.detail}',
        );
      }
      final stats = await store.stats();
      documents = stats.documents;
      chunks = stats.chunks;
      checks.add(
        RuntimeCheck(
          'SQLite / 数据目录',
          CheckStatus.passed,
          '${config.databasePath}；文档 $documents，块 $chunks',
        ),
      );
    } catch (error) {
      checks.add(
        RuntimeCheck(
          'SQLite / 数据目录',
          CheckStatus.blocked,
          '无法打开索引，请检查目录权限和 SQLite 动态库：$error',
        ),
      );
    } finally {
      store?.close();
    }
  }
  return RuntimeReport(
    config: config,
    checks: List.unmodifiable(checks),
    documents: documents,
    chunks: chunks,
  );
}

Future<RuntimeCheck> checkProcess(
  String name,
  String executable,
  List<String> arguments,
) async {
  Process? process;
  try {
    process = await Process.start(executable, arguments);
    final stdout = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderr = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final code = await process.exitCode.timeout(const Duration(seconds: 20));
    final out = (await stdout).trim();
    final err = (await stderr).trim();
    return RuntimeCheck(
      name,
      code == 0 ? CheckStatus.passed : CheckStatus.blocked,
      '$executable；exit=$code；${out.isEmpty ? err : out}',
    );
  } catch (error) {
    return RuntimeCheck(name, CheckStatus.blocked, '无法运行 $executable：$error');
  } finally {
    process?.kill();
  }
}
