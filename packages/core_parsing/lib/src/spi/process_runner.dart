import 'package:meta/meta.dart';

import 'cancellation_token.dart';

/// 一次外部进程调用的结果。
@immutable
class ProcessRunResult {
  const ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.duration = Duration.zero,
    this.processStart = Duration.zero,
    this.processWait = Duration.zero,
    this.streamDrain = Duration.zero,
  });

  /// 进程退出码；`0` 表示成功。
  final int exitCode;

  /// 捕获的标准输出。文本抽取时它就是文档正文。
  final String stdout;

  /// 捕获的标准错误。仅作诊断，绝不当正文使用。
  final String stderr;

  /// 本次调用的墙钟耗时，从进入 [ProcessRunner.run] 到返回。
  final Duration duration;

  /// `Process.start` 返回之前的耗时。这是创建进程，不是 JVM 初始化。
  final Duration processStart;

  /// 进程已启动到退出码返回的耗时。Java 这一段含 JVM 启动、扫描 classpath 和程序本体。
  final Duration processWait;

  /// 进程退出后，stdout 与 stderr 收完的耗时。
  final Duration streamDrain;

  /// 进程是否成功退出。
  bool get isSuccess => exitCode == 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'exitCode': exitCode,
    'stdoutBytes': stdout.length,
    'stderrBytes': stderr.length,
    'durationMs': duration.inMilliseconds,
    'processStartMs': processStart.inMilliseconds,
    'processWaitMs': processWait.inMilliseconds,
    'streamDrainMs': streamDrain.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is ProcessRunResult &&
      other.exitCode == exitCode &&
      other.stdout == stdout &&
      other.stderr == stderr &&
      other.duration == duration &&
      other.processStart == processStart &&
      other.processWait == processWait &&
      other.streamDrain == streamDrain;

  @override
  int get hashCode => Object.hash(
    exitCode,
    stdout,
    stderr,
    duration,
    processStart,
    processWait,
    streamDrain,
  );

  @override
  String toString() =>
      'ProcessRunResult(exitCode: $exitCode, stdout: ${stdout.length} chars)';
}

/// 可执行文件根本起不来——例如基于 Apache Tika 的抽取器缺少 JDK。
class ProcessStartException implements Exception {
  const ProcessStartException(this.executable, this.message);

  /// 启动失败的可执行文件。
  final String executable;

  /// 底层原因。
  final String message;

  @override
  String toString() => 'ProcessStartException($executable): $message';
}

/// 进程超出时间预算，已被终止。
class ProcessTimeoutException implements Exception {
  const ProcessTimeoutException(this.executable, this.timeout);

  /// 超时的可执行文件。
  final String executable;

  /// 被超出的时间预算。
  final Duration timeout;

  @override
  String toString() =>
      'ProcessTimeoutException($executable): exceeded '
      '${timeout.inMilliseconds} ms';
}

/// 本包中**唯一**允许启动外部进程的地方。
///
/// 解析器从不直接调用 `Process.run`，而是接收一个 [ProcessRunner]。
/// 正是这条规则让 W2 的 ≥80% 覆盖率门槛可达：单测注入假实现，不必安装 JDK。
abstract interface class ProcessRunner {
  /// 以 [arguments] 运行 [executable]。
  ///
  /// 可执行文件无法启动时抛 [ProcessStartException]，[timeout] 用尽时抛
  /// [ProcessTimeoutException]；请求 [cancel] 时终止进程并抛 [CancelledException]。
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    CancellationToken? cancel,
  });
}
