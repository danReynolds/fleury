import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final skipPty = Platform.isWindows
      ? 'PTY capture uses POSIX openpty and posix_spawnp.'
      : null;

  // `pty` tag: needs a real openpty-capable environment — exclude with
  // `dart test -x pty` in sandboxes/CI where PTY allocation fails.
  group('runApp over a real PTY', tags: ['integration', 'pty'], () {
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

    test('stray print + raw native write(1) never corrupt the frame; '
        'both replay after exit', () async {
      final capture = await _capturePty(
        tempDir,
        'stray-output',
        extraArgs: const [
          '--cols',
          '60',
          '--rows',
          '12',
          '--resize-sequence',
          '61x12',
          '--resize-interval-ms',
          '3000',
        ],
        fixtureArgs: const ['--stray-output'],
      );
      if (capture == null) return;

      expect(capture.metadata['timedOut'], isFalse);
      expect(capture.output, contains('PTY-STRAY-MODE'));

      // The session region is everything up to the alt-screen pop; the
      // replay region is what follows. The stray lines (a Dart print AND a
      // raw native write(1) that zones/IOOverrides cannot see) must appear
      // ONLY in the replay region — one mid-frame marker means fd capture
      // failed and the frame was corrupted.
      final pop = capture.output.lastIndexOf('\x1B[?1049l');
      expect(
        pop,
        greaterThanOrEqualTo(0),
        reason: 'alt-screen pop missing — terminal not restored',
      );
      final session = capture.output.substring(0, pop);
      final replay = capture.output.substring(pop);
      for (final marker in const [
        'STRAY-PRINT-MARKER',
        'STRAY-NATIVE-MARKER',
      ]) {
        expect(
          session,
          isNot(contains(marker)),
          reason: '$marker leaked into the live frame region',
        );
        expect(
          replay,
          contains(marker),
          reason: '$marker was not replayed after exit',
        );
      }

      // The replay is SANITIZED terminal-bound text: the hostile OSC
      // payload a stray line carried must not survive to the real
      // terminal (runApp constructs OutputCapture with
      // sanitizeForTerminal: true — this pins that wiring end-to-end).
      expect(replay, contains('STRAY-HOSTILE'));
      expect(
        replay,
        isNot(contains('\x1B]0;pwned')),
        reason: 'hostile OSC must be neutralized in the replay',
      );
    }, skip: skipPty);

    test('onStrayOutput takes ownership: lines reach the hook tagged, '
        'nothing replays', () async {
      final hookFile = File('${tempDir.path}/stray_hook.txt');
      final capture = await _capturePty(
        tempDir,
        'stray-hook',
        extraArgs: const [
          '--cols',
          '60',
          '--rows',
          '12',
          '--resize-sequence',
          '61x12',
          '--resize-interval-ms',
          '3000',
        ],
        fixtureArgs: ['--stray-hook=${hookFile.path}'],
      );
      if (capture == null) return;

      expect(capture.metadata['timedOut'], isFalse);
      expect(capture.output, contains('PTY-HOOK-MODE'));
      final hooked = hookFile.existsSync() ? hookFile.readAsStringSync() : '';
      expect(hooked, contains('stdout:HOOKED-PRINT'));
      expect(hooked, contains('stdout:HOOKED-NATIVE'));
      // A hook takes ownership of disposition — nothing replays on exit.
      expect(capture.output, isNot(contains('HOOKED-PRINT')));
      expect(capture.output, isNot(contains('HOOKED-NATIVE')));
    }, skip: skipPty);

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

    test('startup SIGTERM after terminal entry still restores modes', () async {
      final capture = await _capturePty(
        tempDir,
        'startup-sigterm',
        extraArgs: const [
          '--cols',
          '40',
          '--rows',
          '8',
          '--terminate-after-output-ms',
          '1',
          '--allow-exit-code',
          '143',
        ],
      );
      if (capture == null) return;

      expect(capture.metadata['timedOut'], isFalse);
      expect(capture.metadata['exitCode'], 143);
      expect(
        capture.output,
        contains('\x1B[?1049h'),
        reason: 'SIGTERM must land after the first terminal mutation',
      );
      _expectTerminalRestored(capture.output);
      expect(
        capture.output.lastIndexOf('\x1B[?1049l'),
        greaterThan(capture.output.indexOf('\x1B[?1049h')),
      );
    }, skip: skipPty);

    test(
      'raw Ctrl+Z restores, self-stops, and re-enters after SIGCONT',
      () async {
        final capture = await _capturePty(
          tempDir,
          'suspend-resume',
          extraArgs: const [
            '--cols',
            '40',
            '--rows',
            '8',
            '--input-hex',
            '1a',
            '--input-after-output-ms',
            '700',
            '--continue-after-input-ms',
            '300',
            '--interrupt-after-output-ms',
            '1500',
            '--allow-exit-code',
            '130',
          ],
        );
        if (capture == null) return;

        expect(capture.metadata['timedOut'], isFalse);
        expect(capture.metadata['exitCode'], 130);
        expect(capture.output, contains('PTY-FIRST-FRAME'));
        final signals = _signalNames(capture.metadata);
        expect(signals, containsAll(['sigcont', 'sigint']));
        expect(
          signals,
          isNot(contains('sigtstp')),
          reason: 'the proof must exercise the parsed Ctrl+Z byte path',
        );
        _expectTerminalRestored(capture.output);
        _expectTerminalReentered(capture.output);
      },
      skip: skipPty,
    );

    test('terminal handoff restores, runs operation, and re-enters', () async {
      final capture = await _capturePty(
        tempDir,
        'handoff',
        extraArgs: const [
          '--cols',
          '40',
          '--rows',
          '8',
          '--input-hex',
          '03',
          // Key input from the first emitted byte, not process start: a cold
          // Dart launch can take longer than a fixed delay, in which case
          // Ctrl+C lands in cooked mode, is echoed, and never reaches Fleury.
          '--input-after-output-ms',
          '600',
        ],
        fixtureArgs: const ['--handoff'],
      );
      if (capture == null) return;

      expect(capture.metadata['timedOut'], isFalse);
      expect(capture.metadata['exitCode'], 0);
      expect(capture.output, contains('PTY-HANDOFF-MODE'));
      expect(capture.output, contains('PTY-HANDOFF'));
      _expectTerminalRestored(capture.output);
      _expectTerminalReentered(capture.output);
    }, skip: skipPty);

    // DELIBERATE INVERSION (pipeline-program PR6): a render crash used to
    // be fatal; containment keeps the session alive on the error
    // presentation. The process now exits via SIGINT (130), not the crash,
    // and the terminal still restores exactly as before.
    test('a contained render crash keeps the session; SIGINT still '
        'restores terminal modes', () async {
      final capture = await _capturePty(
        tempDir,
        'layout-crash',
        extraArgs: const [
          '--cols',
          '40',
          '--rows',
          '8',
          '--interrupt-after-output-ms',
          '700',
          '--allow-exit-code',
          '130',
        ],
        fixtureArgs: const ['--layout-crash'],
      );
      if (capture == null) return;

      expect(capture.metadata['timedOut'], isFalse);
      expect(
        capture.metadata['exitCode'],
        130,
        reason: 'the session survived the crash and exited on SIGINT',
      );
      expect(
        capture.output,
        contains('layout-boom'),
        reason: 'the error presentation/banner reached the terminal',
      );
      _expectTerminalRestored(capture.output);
    }, skip: skipPty);
  });
}

Future<({Map<String, Object?> metadata, String output})?> _capturePty(
  Directory tempDir,
  String name, {
  required List<String> extraArgs,
  List<String> fixtureArgs = const [],
}) async {
  final packageRoot = Directory.current;
  final repoRoot = _findRepoRoot(packageRoot);
  final profilingRoot = Directory('${repoRoot.path}/profiling');
  final fixtureApp =
      '${packageRoot.path}/test/fixtures/pty_run_app_fixture.dart';
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
    ...fixtureArgs,
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

void _expectTerminalReentered(String output) {
  expect(_countOccurrences(output, '\x1B[?1049h'), greaterThanOrEqualTo(2));
  expect(_countOccurrences(output, '\x1B[?1049l'), greaterThanOrEqualTo(2));
  expect(_countOccurrences(output, '\x1B[?2004h'), greaterThanOrEqualTo(2));
  expect(_countOccurrences(output, '\x1B[?2004l'), greaterThanOrEqualTo(2));
}

List<String> _signalNames(Map<String, Object?> metadata) {
  final signals = metadata['signals'];
  if (signals is! List<Object?>) return const [];
  return <String>[
    for (final signal in signals)
      if (signal is Map<String, Object?> && signal['signal'] is String)
        signal['signal']! as String,
  ];
}

int _countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var index = 0;
  while (true) {
    index = haystack.indexOf(needle, index);
    if (index < 0) return count;
    count++;
    index += needle.length;
  }
}
