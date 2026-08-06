// What does THIS terminal actually send, and can its answers be trusted?
//
// `diagnose --probe` answers neither question. It asks `CSI ? u`, which is
// specified as reporting the flags CURRENTLY IN FORCE — so a terminal that
// stores what you pushed and echoes it back reports full support while
// implementing none of it. Warp answers 31 (every flag) and then emits bare
// `CSI 97;1;97 u` for presses and repeats alike, with no event types at all.
//
// Two checks, in one run:
//   1. Does the terminal MASK unsupported flags? Push an undefined bit and
//      see whether it comes back. Kitty masks; a blind store echoes.
//   2. What arrives for a real keystroke — and do releases ever show up?
import 'dart:async';
import 'dart:io';

/// Bit 32 is not defined by the protocol (1|2|4|8|16 = 31 is everything).
/// A terminal that reports it back is echoing state, not capability — which
/// means its answer to any capability question is worth nothing.
const _undefinedFlag = 32;

late final bool _lineMode;
late final bool _echoMode;

void main() async {
  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    stderr.writeln('keytrace needs a real terminal (not a pipe).');
    exit(2);
  }
  _lineMode = stdin.lineMode;
  _echoMode = stdin.echoMode;
  stdin.lineMode = false;
  stdin.echoMode = false;

  // ONE subscription for the whole run: stdin is single-subscription, so the
  // probe and the key trace share it and a phase flag routes the bytes.
  final incoming = StreamController<List<int>>();
  final sub = stdin.listen(incoming.add);
  final bytes = incoming.stream.asBroadcastStream();

  // Restore on every exit path. Without this a signal leaves the terminal in
  // raw mode with Kitty flags still pushed, which outlives the process.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      stdout.write('\x1B[<1u');
      _restore();
      exit(130);
    });
  }

  await _reportMasking(bytes);
  await _traceKeys(bytes);

  await sub.cancel();
  _restore();
  exit(0);
}

/// Push an undefined flag, ask what stuck, pop. Bracketed by primary DA so we
/// know the exchange is over even when the terminal ignores the query.
Future<void> _reportMasking(Stream<List<int>> bytes) async {
  final buffer = StringBuffer();
  final done = Completer<void>();
  final sub = bytes.listen((chunk) {
    buffer.write(String.fromCharCodes(chunk));
    // DA1's reply ends with 'c' — the bracket that means "everything before
    // this has been answered or ignored".
    if (buffer.toString().contains('c') && !done.isCompleted) done.complete();
  });
  stdout.write('\x1B[>${_undefinedFlag}u\x1B[?u\x1B[<1u\x1B[c');
  await done.future.timeout(const Duration(seconds: 2), onTimeout: () => null);
  await sub.cancel();

  final reply = RegExp(r'\x1B\[\?(\d+)u').firstMatch(buffer.toString());
  stdout.write('\r\n=== 1. can this terminal be trusted? ===\r\n');
  if (reply == null) {
    stdout.write(
      '  No reply to the Kitty query — this terminal does not implement the\r\n'
      '  protocol. That is an honest answer, and a usable one.\r\n',
    );
    return;
  }
  final reported = int.parse(reply.group(1)!);
  final echoed = reported & _undefinedFlag != 0;
  stdout.write(
    '  Pushed undefined flag $_undefinedFlag, terminal reported: $reported\r\n'
    '${echoed ? '  ECHOES BLINDLY. It reported back a flag the protocol does not\r\n'
              '  define, so it is repeating what we asked for, not what it can do.\r\n'
              '  Its answer to ANY capability question is worthless.\r\n' : '  MASKS correctly — it dropped the undefined bit, so what it reports\r\n'
              '  is what it honours. Its capability answers can be trusted.\r\n'}',
  );
}

Future<void> _traceKeys(Stream<List<int>> bytes) async {
  stdout.write(
    '\r\n=== 2. what arrives for a real keystroke? ===\r\n'
    '  HOLD a letter for a second, then let go. Press q when done.\r\n'
    '  A lifecycle-reporting terminal shows repeats (:2) and a release (:3).\r\n\r\n',
  );
  stdout.write('\x1B[>31u'); // ask for everything, including event types

  var sawRelease = false;
  var sawRepeat = false;
  final done = Completer<void>();
  final sub = bytes.listen((chunk) {
    final text = String.fromCharCodes(chunk);
    final hex = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final release = RegExp(r'\x1B\[[0-9;:]*:3[u~]').hasMatch(text);
    final repeat = RegExp(r'\x1B\[[0-9;:]*:2[u~]').hasMatch(text);
    sawRelease |= release;
    sawRepeat |= repeat;
    stdout.write(
      '  $hex   ${text.replaceAll('\x1B', '<ESC>')}'
      '${release
          ? '   <- RELEASE'
          : repeat
          ? '   <- repeat'
          : ''}\r\n',
    );
    // 'q' in any encoding — bare byte, or CSI-u once flag 8 makes every key
    // an escape sequence. The first draft watched for a raw 0x03 that flag 8
    // guarantees never arrives, so Ctrl+C killed the process through SIGINT
    // before the verdict printed AND before the terminal was restored.
    final quit = text == 'q' || RegExp(r'\x1B\[113[;:u]').hasMatch(text);
    if (quit && !done.isCompleted) done.complete();
  });
  await done.future;
  await sub.cancel();
  stdout.write('\x1B[<1u');

  stdout.write(
    '\r\n=== verdict ===\r\n'
    '  repeats  (:2) seen: $sawRepeat\r\n'
    '  releases (:3) seen: $sawRelease\r\n'
    '${sawRelease ? '  Held-key controls work on this terminal.\r\n' : '  No releases arrive, so nothing can know a key is still down.\r\n'
              '  Held-key controls cannot work here, whatever the query says.\r\n'}',
  );
}

void _restore() {
  stdin.lineMode = _lineMode;
  stdin.echoMode = _echoMode;
}
