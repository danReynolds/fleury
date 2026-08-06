// What does THIS terminal actually send, and can its answers be trusted?
//
// `diagnose --probe` answers neither question. It asks `CSI ? u`, which is
// specified as reporting the flags CURRENTLY IN FORCE — so a terminal that
// stores what you pushed and echoes it back would report full support while
// implementing none of it. Two checks, in one run:
//
//   1. Does this terminal MASK unsupported flags? Push an undefined bit and
//      see whether it comes back. Kitty masks; a blind store echoes. Only a
//      masking terminal's capability answers mean anything.
//   2. What actually arrives for a real keystroke — and do releases ever
//      show up?
//
// Pass --alt to run the second check inside the alternate screen, which is
// where every real TUI lives. Warp routes alt-screen apps down a different
// input path from its inline block mode, so the two can disagree and only
// the alt-screen answer describes what an app will see.
import 'dart:async';
import 'dart:io';

/// Bit 32 is not defined by the protocol (1|2|4|8|16 = 31 is everything). A
/// terminal that reports it back is echoing our request, not describing
/// itself — which makes its answer to any capability question worthless.
const _undefinedFlag = 32;

late final bool _lineMode;
late final bool _echoMode;

/// Where incoming bytes go. ONE stdin subscription serves the whole run: the
/// first draft cancelled after the probe and re-listened for the trace, and a
/// broadcast stream whose last listener cancels can close for good — which
/// silently ate the entire second phase.
enum _Phase { probe, trace }

var _phase = _Phase.probe;
final _probeReply = StringBuffer();
final _trace = <String>[];
var _sawRelease = false;
var _sawRepeat = false;
Completer<void>? _probeDone;
Completer<void>? _traceDone;

void main(List<String> args) async {
  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    stderr.writeln('keytrace needs a real terminal (not a pipe).');
    exit(2);
  }
  final alt = args.contains('--alt');
  _lineMode = stdin.lineMode;
  _echoMode = stdin.echoMode;
  stdin.lineMode = false;
  stdin.echoMode = false;

  // Restore on every exit path. Without this a signal leaves the terminal in
  // raw mode with Kitty flags still pushed, outliving the process.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) => _restore(alt: alt, exitCode: 130));
  }

  final sub = stdin.listen(_onBytes);
  await _reportMasking();
  await _traceKeys(alt: alt);
  await sub.cancel();
  _restore(alt: alt, exitCode: 0);
}

void _onBytes(List<int> chunk) {
  final text = String.fromCharCodes(chunk);
  switch (_phase) {
    case _Phase.probe:
      _probeReply.write(text);
      // DA1's reply ends with 'c' — the bracket meaning everything before it
      // has been answered or ignored.
      if (text.contains('c') && !(_probeDone?.isCompleted ?? true)) {
        _probeDone!.complete();
      }
    case _Phase.trace:
      final hex = chunk
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final release = RegExp(r'\x1B\[[0-9;:]*:3[u~]').hasMatch(text);
      final repeat = RegExp(r'\x1B\[[0-9;:]*:2[u~]').hasMatch(text);
      _sawRelease |= release;
      _sawRepeat |= repeat;
      // Recorded, not merely printed: under --alt these lines go to a screen
      // discarded on exit, so printing alone loses the trace and leaves the
      // verdict with nothing to corroborate it.
      final line =
          '  $hex   ${text.replaceAll('\x1B', '<ESC>')}'
          '${release
              ? '   <- RELEASE'
              : repeat
              ? '   <- repeat'
              : ''}';
      _trace.add(line);
      stdout.write('$line\r\n');
      // 'q' in any encoding — bare byte, or CSI-u once flag 8 makes every
      // key an escape sequence.
      final quit = text == 'q' || RegExp(r'\x1B\[113[;:u]').hasMatch(text);
      if (quit && !(_traceDone?.isCompleted ?? true)) _traceDone!.complete();
  }
}

/// Push an undefined flag, ask what stuck, pop. Bracketed by primary DA so we
/// know the exchange is over even when the terminal ignores the query.
Future<void> _reportMasking() async {
  _probeDone = Completer<void>();
  stdout.write('\x1B[>${_undefinedFlag}u\x1B[?u\x1B[<1u\x1B[c');
  await _probeDone!.future.timeout(
    const Duration(seconds: 2),
    onTimeout: () => null,
  );

  final reply = RegExp(r'\x1B\[\?(\d+)u').firstMatch(_probeReply.toString());
  stdout.write('\r\n=== 1. can this terminal be trusted? ===\r\n');
  if (reply == null) {
    stdout.write(
      '  No reply to the Kitty query — this terminal does not implement the\r\n'
      '  protocol at all. An honest answer, and a usable one.\r\n',
    );
    return;
  }
  final reported = int.parse(reply.group(1)!);
  final echoed = reported & _undefinedFlag != 0;
  stdout.write(
    '  Pushed undefined flag $_undefinedFlag, terminal reported: $reported\r\n'
    '${echoed ? '  ECHOES BLINDLY. It reported back a flag the protocol does not\r\n'
              '  define, so it repeats what we asked for rather than what it\r\n'
              '  implements. Its capability answers are worthless.\r\n' : '  MASKS correctly — it dropped the undefined bit, so what it\r\n'
              '  reports is what it honours. Its answers can be trusted.\r\n'}',
  );
}

Future<void> _traceKeys({required bool alt}) async {
  stdout.write(
    '\r\n=== 2. what arrives for a real keystroke? ===\r\n'
    '  HOLD a letter for a second, then let go. Press q when done.\r\n'
    '  A lifecycle-reporting terminal shows repeats (:2) and a release (:3).'
    '\r\n\r\n',
  );
  _traceDone = Completer<void>();
  _phase = _Phase.trace;
  if (alt) stdout.write('\x1B[?1049h\x1B[2J\x1B[H');
  stdout.write('\x1B[>31u'); // ask for everything, including event types
  if (alt) {
    stdout.write('  alt screen — hold a letter, release, then press q\r\n');
  }
  await _traceDone!.future;
  stdout.write('\x1B[<1u');
  if (alt) stdout.write('\x1B[?1049l');

  stdout.write(
    '\r\n=== trace (${alt ? 'ALT SCREEN' : 'inline'}) — '
    '${_trace.length} events ===\r\n'
    '${_trace.map((l) => '$l\r\n').join()}'
    '\r\n=== verdict ===\r\n'
    '  repeats  (:2) seen: $_sawRepeat\r\n'
    '  releases (:3) seen: $_sawRelease\r\n'
    '${_sawRelease ? '  Held-key controls work on this terminal.\r\n' : '  No releases arrive, so nothing can know a key is still down.\r\n'
              '  Held-key controls cannot work here, whatever the query '
              'says.\r\n'}',
  );
}

Never _restore({required bool alt, required int exitCode}) {
  stdout.write('\x1B[<1u');
  if (alt) stdout.write('\x1B[?1049l');
  stdin.lineMode = _lineMode;
  stdin.echoMode = _echoMode;
  exit(exitCode);
}
