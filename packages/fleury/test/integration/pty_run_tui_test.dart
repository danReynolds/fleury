import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final skipPty = Platform.isWindows
      ? 'PTY capture uses POSIX openpty and posix_spawnp.'
      : null;

  group('runTui over a real PTY', tags: ['integration'], () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('fleury_pty_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'boots, renders first frame, resizes, and restores on SIGINT',
      () async {
        final capture = await _capturePty(
          tempDir,
          'clean-exit',
          extraArgs: const [
            '--cols',
            '40',
            '--rows',
            '8',
            '--resize-sequence',
            '50x10',
            '--resize-interval-ms',
            '300',
            '--interrupt-after-output-ms',
            '700',
            '--allow-exit-code',
            '130',
          ],
        );
        if (capture == null) return;

        expect(capture.metadata['timedOut'], isFalse);
        expect(capture.metadata['exitCode'], 130);
        expect(capture.output, contains('PTY-FIRST-FRAME'));
        expect(capture.output, contains('SIZE 50x10'));
        _expectTerminalRestored(capture.output);
      },
      skip: skipPty,
    );

    test('restores terminal modes when SIGTERM lands mid-session', () async {
      final capture = await _capturePty(
        tempDir,
        'sigterm',
        extraArgs: const [
          '--cols',
          '40',
          '--rows',
          '8',
          '--terminate-after-output-ms',
          '700',
          '--allow-exit-code',
          '143',
        ],
      );
      if (capture == null) return;

      expect(capture.metadata['timedOut'], isFalse);
      expect(capture.metadata['exitCode'], 143);
      expect(capture.output, contains('PTY-FIRST-FRAME'));
      _expectTerminalRestored(capture.output);
    }, skip: skipPty);
  });
}

Future<({Map<String, Object?> metadata, String output})?> _capturePty(
  Directory tempDir,
  String name, {
  required List<String> extraArgs,
}) async {
  final packageRoot = Directory.current;
  final repoRoot = _findRepoRoot(packageRoot);
  final profilingRoot = Directory('${repoRoot.path}/profiling');
  final fixtureApp = '${packageRoot.path}/test/fixtures/pty_run_tui_app.dart';
  final outBase = '${tempDir.path}/$name';
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'capture_pty.dart',
    '--out',
    outBase,
    '--timeout',
    '8',
    ...extraArgs,
    '--',
    Platform.resolvedExecutable,
    fixtureApp,
  ], workingDirectory: profilingRoot.path);

  if (result.exitCode != 0 &&
      result.stderr.toString().contains('openpty failed')) {
    markTestSkipped(
      'PTY capture helper could not allocate a pseudo-terminal: '
      '${result.stderr.toString().trim()}',
    );
    return null;
  }

  expect(
    result.exitCode,
    0,
    reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );

  final metadata =
      jsonDecode(File('$outBase.json').readAsStringSync())
          as Map<String, Object?>;
  final output = latin1.decode(File('$outBase.bin').readAsBytesSync());
  return (metadata: metadata, output: output);
}

Directory _findRepoRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/profiling/capture_pty.dart').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find repo root from ${start.path}.');
    }
    current = parent;
  }
}

void _expectTerminalRestored(String output) {
  expect(output, contains('\x1B[?1006l'));
  expect(output, contains('\x1B[?1003l'));
  expect(output, contains('\x1B[?1002l'));
  expect(output, contains('\x1B[?1000l'));
  expect(output, contains('\x1B[<u'));
  expect(output, contains('\x1B[?2004l'));
  expect(output, contains('\x1B[?25h'));
  expect(output, contains('\x1B[?1049l'));
}
