import 'dart:io';

import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

void main() {
  const IoProcessRunner runner = IoProcessRunner();
  const String hold =
      "import 'dart:io';\n"
      'void main() {\n'
      '  sleep(const Duration(minutes: 5));\n'
      '}\n';

  test('captures stdout from a short command', () async {
    final String script = _writeScript(
      "void main() { print('hello-runner'); }\n",
    );
    final ProcessRunResult result = await runner.run(
      Platform.resolvedExecutable,
      <String>[script],
    );
    expect(result.isSuccess, isTrue);
    expect(result.stdout, contains('hello-runner'));
  });

  test('a missing executable throws ProcessStartException', () async {
    expect(
      runner.run('core-parsing-missing-exe', const <String>[]),
      throwsA(isA<ProcessStartException>()),
    );
  });

  test('timeout kills a long command', () async {
    final String script = _writeScript(hold);
    expect(
      runner.run(Platform.resolvedExecutable, <String>[
        script,
      ], timeout: const Duration(milliseconds: 200)),
      throwsA(isA<ProcessTimeoutException>()),
    );
  });

  test('an already cancelled token does not start the process', () async {
    final CancellationTokenSource source = CancellationTokenSource()..cancel();
    expect(
      runner.run(Platform.resolvedExecutable, const <String>[
        '--version',
      ], cancel: source.token),
      throwsA(isA<CancelledException>()),
    );
  });

  test('cancel during a run stops the process', () async {
    final String script = _writeScript(hold);
    final CancellationTokenSource source = CancellationTokenSource();
    final Future<ProcessRunResult> pending = runner.run(
      Platform.resolvedExecutable,
      <String>[script],
      cancel: source.token,
      timeout: const Duration(seconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    source.cancel();
    expect(pending, throwsA(isA<CancelledException>()));
  });
}

String _writeScript(String source) {
  final Directory directory = Directory.systemTemp.createTempSync(
    'core_parsing_proc_',
  );
  addTearDown(() => _deleteWhenReleased(directory));
  final File file = File('${directory.path}${Platform.pathSeparator}main.dart');
  file.writeAsStringSync(source);
  return file.path;
}

/// Windows keeps the script open for a moment after [Process.kill].
/// Error 32 is a sharing violation, and it clears once that handle drops.
Future<void> _deleteWhenReleased(Directory directory) async {
  const int attempts = 25;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (!directory.existsSync()) {
      return;
    }
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException catch (error) {
      final bool stillOpen = error.osError?.errorCode == 32;
      if (!stillOpen || attempt == attempts - 1) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
