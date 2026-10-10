import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cancellation_token.dart';
import 'process_runner.dart';

/// [ProcessRunner] that starts a real subprocess.
///
/// This is the only type in the package that calls `Process.start`.
class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    CancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final Stopwatch stopwatch = Stopwatch()..start();
    final Stopwatch phase = Stopwatch()..start();
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } on ProcessException catch (error) {
      throw ProcessStartException(executable, error.message);
    }
    final Duration processStart = phase.elapsed;

    final StringBuffer stdoutBuffer = StringBuffer();
    final StringBuffer stderrBuffer = StringBuffer();
    final Completer<void> stdoutDone = Completer<void>();
    final Completer<void> stderrDone = Completer<void>();
    final StreamSubscription<String> stdoutSubscription = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          stdoutBuffer.write,
          onDone: () {
            if (!stdoutDone.isCompleted) {
              stdoutDone.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!stdoutDone.isCompleted) {
              stdoutDone.completeError(error, stackTrace);
            }
          },
        );
    final StreamSubscription<String> stderrSubscription = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          stderrBuffer.write,
          onDone: () {
            if (!stderrDone.isCompleted) {
              stderrDone.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!stderrDone.isCompleted) {
              stderrDone.completeError(error, stackTrace);
            }
          },
        );

    void stopProcess() {
      process.kill();
    }

    cancel?.addListener(stopProcess);
    phase
      ..reset()
      ..start();
    try {
      final int exitCode;
      if (timeout == null) {
        exitCode = await process.exitCode;
      } else {
        exitCode = await process.exitCode.timeout(
          timeout,
          onTimeout: () {
            stopProcess();
            throw ProcessTimeoutException(executable, timeout);
          },
        );
      }
      if (cancel?.isCancelled ?? false) {
        throw const CancelledException();
      }
      final Duration processWait = phase.elapsed;
      phase
        ..reset()
        ..start();
      await stdoutDone.future;
      await stderrDone.future;
      return ProcessRunResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        duration: stopwatch.elapsed,
        processStart: processStart,
        processWait: processWait,
        streamDrain: phase.elapsed,
      );
    } finally {
      cancel?.removeListener(stopProcess);
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }
}
