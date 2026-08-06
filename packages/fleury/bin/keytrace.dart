// What does THIS terminal actually send when you press a key?
//
// `diagnose --probe` answers a different question: whether the terminal
// REPLIES to the Kitty status query. A terminal can answer that truthfully and
// still never emit CSI-u for real keystrokes — which looks, from inside an
// app, exactly like the app being broken.
//
// This prints the raw bytes, so the difference is visible in one screen.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    stderr.writeln('keytrace needs a real terminal (not a pipe).');
    exit(2);
  }
  final flags = args.contains('--legacy') ? 0 : 31;
  final lineMode = stdin.lineMode;
  final echoMode = stdin.echoMode;
  stdin.lineMode = false;
  stdin.echoMode = false;
  if (flags != 0) stdout.write('\x1B[>${flags}u');

  stdout.write(
    '\r\nkeytrace — press keys. Ctrl+C to stop.\r\n'
    'Requested Kitty flags: $flags\r\n\r\n'
    'HOLD a letter down for a second, then let go. You should see:\r\n'
    '  * a PRESS event, then repeats, then a RELEASE event (:3)\r\n'
    'If you only ever see one line per keypress and nothing on release,\r\n'
    'this terminal is not reporting key lifecycles to applications.\r\n\r\n',
  );

  var sawRelease = false;
  var sawCsiU = false;
  ProcessSignal.sigint.watch().listen(
    (_) => _finish(lineMode, echoMode, flags, sawCsiU, sawRelease),
  );

  await for (final chunk in stdin) {
    final hex = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final printable = String.fromCharCodes(chunk)
        .replaceAll('\x1B', '<ESC>')
        .replaceAll('\r', '<CR>')
        .replaceAll('\n', '<LF>');
    final text = utf8.decode(chunk, allowMalformed: true);
    if (text.contains('u') && text.contains('\x1B[')) sawCsiU = true;
    // A Kitty release carries the `:3` event-type suffix.
    if (RegExp(r'\x1B\[[0-9;:]*:3[u~]').hasMatch(text)) sawRelease = true;
    final tag = sawReleaseTag(text);
    stdout.write('  $hex   $printable$tag\r\n');
    if (chunk.length == 1 && chunk.first == 3) {
      _finish(lineMode, echoMode, flags, sawCsiU, sawRelease);
    }
  }
}

String sawReleaseTag(String text) {
  if (RegExp(r'\x1B\[[0-9;:]*:3[u~]').hasMatch(text)) return '   <- RELEASE';
  if (RegExp(r'\x1B\[[0-9;:]*:2[u~]').hasMatch(text)) return '   <- repeat';
  return '';
}

Never _finish(
  bool lineMode,
  bool echoMode,
  int flags,
  bool sawCsiU,
  bool sawRelease,
) {
  if (flags != 0) stdout.write('\x1B[<1u');
  stdin.lineMode = lineMode;
  stdin.echoMode = echoMode;
  stdout.write(
    '\r\n\r\n=== verdict ===\r\n'
    'CSI-u key events seen : $sawCsiU\r\n'
    'Key RELEASES seen     : $sawRelease\r\n\r\n'
    '${sawRelease ? 'This terminal reports key lifecycles. Held-key controls '
              '(hold-to-thrust) will work here.' : 'No releases arrived, so nothing can know a key is still '
              'down.\r\nHeld-key controls cannot work on this terminal '
              'regardless of what\r\nit answers to a capability query.'}'
    '\r\n\r\n',
  );
  exit(0);
}
