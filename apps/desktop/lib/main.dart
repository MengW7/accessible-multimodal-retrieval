import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/application/app_controller.dart';
import 'src/application/desktop_service.dart';
import 'src/runtime/runtime_config.dart';
import 'src/runtime/directory_picker.dart';
import 'src/runtime/library_worker.dart';
import 'src/runtime/library_smoke.dart';
import 'src/runtime/window_lifecycle.dart';
import 'src/runtime/file_opener.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = RuntimeConfig.fromEnvironment();
  final service = LocalDesktopService(config);
  // The release executable exercises the same composition as the application.
  // Explicit paths keep evaluation data out of this engineering smoke test.
  if (args.contains('--runtime-smoke') || args.contains('--library-smoke')) {
    final output = Platform.environment['AMR_SMOKE_OUTPUT'];
    final fixtures = Platform.environment['AMR_SMOKE_FIXTURES'];
    if (output == null ||
        !File(output).isAbsolute ||
        fixtures == null ||
        !Directory(fixtures).isAbsolute) {
      stderr.writeln('Set absolute AMR_SMOKE_OUTPUT and AMR_SMOKE_FIXTURES.');
      exit(64);
    }
    final report = args.contains('--library-smoke')
        ? await verifyLibrary(config, fixtures)
        : await service.verify(fixtures);
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    exit(report['ok'] == true ? 0 : 1);
  }
  final worker = WorkerLibraryService(config);
  final controller = AppController(
    service,
    library: worker,
    searchService: worker,
    fileOpener: NativeFileOpener(),
    directoryPicker: const NativeDirectoryPicker(),
  );
  bindWindowLifecycle(controller);
  runApp(RetrievalApp(controller: controller));
}
