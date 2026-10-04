import 'package:core_parsing/core_parsing.dart';
import 'package:test/test.dart';

void main() {
  const String xhtml = '''
<html><body>
<div class="page"><p>Page &amp; one</p></div>
<div class='note page'><p>第二页</p></div>
</body></html>
''';

  test('xhtml pages are split and entities are decoded', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        expect(executable, 'java');
        expect(arguments, contains('-x'));
        expect(arguments[1], contains('tika-app-4.0.0.jar'));
        expect(arguments[1], contains(';'));
        expect(arguments[1], contains('lib'));
        return ProcessRunResult(
          exitCode: 0,
          stdout: xhtml,
          stderr: 'INFO noise',
        );
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: r'C:\tools\tika-app',
      classpathSeparator: ';',
    );
    final ExtractedText text = await extractor.extract(r'C:\docs\a.pdf');
    expect(text.pages, hasLength(2));
    expect(text.pages[0].text, 'Page & one');
    expect(text.pages[1].text, '第二页');
    expect(text.pages[1].pageNumber, 2);
    expect(text.attributes['mode'], 'xhtml');
    expect(text.fullText, isNot(contains('INFO noise')));
    expect(runner.calls, hasLength(1));
  });

  test('posix classpath uses a colon', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        expect(arguments[1], contains(':'));
        expect(arguments[1], isNot(contains(';')));
        return const ProcessRunResult(
          exitCode: 0,
          stdout: '<div class="page">ok</div>',
          stderr: '',
        );
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: '/opt/tika-app',
      classpathSeparator: ':',
    );
    final ExtractedText text = await extractor.extract('/tmp/a.pdf');
    expect(text.pages.single.text, 'ok');
  });

  test('a failed xhtml run falls back to plain text', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        if (arguments.contains('-x')) {
          return const ProcessRunResult(
            exitCode: 1,
            stdout: '',
            stderr: 'bad xhtml',
          );
        }
        expect(arguments, contains('-t'));
        return const ProcessRunResult(
          exitCode: 0,
          stdout: 'plain body',
          stderr: 'still noise',
        );
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: '/opt/tika',
      classpathSeparator: ':',
    );
    final ExtractedText text = await extractor.extract('/tmp/a.pdf');
    expect(text.attributes['mode'], 'text');
    expect(text.pages.single.text, 'plain body');
    expect(runner.calls, hasLength(2));
  });

  test('xhtml without page divs falls back to plain text', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        if (arguments.contains('-x')) {
          return const ProcessRunResult(
            exitCode: 0,
            stdout: '<html><body>no pages</body></html>',
            stderr: '',
          );
        }
        return const ProcessRunResult(
          exitCode: 0,
          stdout: 'fallback',
          stderr: '',
        );
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: '/opt/tika',
      classpathSeparator: ':',
    );
    final ExtractedText text = await extractor.extract('/tmp/a.pdf');
    expect(text.pages.single.text, 'fallback');
  });

  test('both modes failing throws and keeps stderr off the message', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        return const ProcessRunResult(
          exitCode: 2,
          stdout: 'secret body',
          stderr: 'java failed',
        );
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: '/opt/tika',
      classpathSeparator: ':',
    );
    expect(
      extractor.extract('/tmp/a.pdf'),
      throwsA(
        isA<TextExtractionException>()
            .having(
              (TextExtractionException error) => error.exitCode,
              'exitCode',
              2,
            )
            .having(
              (TextExtractionException error) => error.stderr,
              'stderr',
              'java failed',
            )
            .having(
              (TextExtractionException error) => error.toString(),
              'toString',
              isNot(contains('secret body')),
            ),
      ),
    );
  });

  test('a missing java runtime is reported by the process runner', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        throw const ProcessStartException('java', 'not found');
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: '/opt/tika',
      classpathSeparator: ':',
    );
    expect(
      extractor.extract('/tmp/a.pdf'),
      throwsA(isA<ProcessStartException>()),
    );
  });

  test('a timeout is not retried as plain text', () async {
    final _ScriptedRunner runner = _ScriptedRunner(
      onRun: (String executable, List<String> arguments) async {
        throw const ProcessTimeoutException('java', Duration(seconds: 1));
      },
    );
    final TikaCliTextExtractor extractor = TikaCliTextExtractor(
      processRunner: runner,
      tikaHome: '/opt/tika',
      classpathSeparator: ':',
    );
    expect(
      extractor.extract('/tmp/a.pdf'),
      throwsA(isA<ProcessTimeoutException>()),
    );
    expect(runner.calls, hasLength(1));
  });
}

class _ScriptedRunner implements ProcessRunner {
  _ScriptedRunner({required this.onRun});

  final Future<ProcessRunResult> Function(
    String executable,
    List<String> arguments,
  )
  onRun;

  final List<List<String>> calls = <List<String>>[];

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    CancellationToken? cancel,
  }) {
    calls.add(arguments);
    return onRun(executable, arguments);
  }
}
