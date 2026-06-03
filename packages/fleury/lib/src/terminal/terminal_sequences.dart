import 'terminal_driver.dart';

/// Builds the mode-entry escape sequence shared by native terminal drivers.
String buildTerminalEnterSequences(TerminalMode mode) {
  final buf = StringBuffer();
  if (mode.alternateScreen) buf.write('\x1B[?1049h');
  if (mode.hideCursor) buf.write('\x1B[?25l');
  if (mode.bracketedPaste) buf.write('\x1B[?2004h');
  // Push the Kitty "disambiguate escape codes" flag (1). Unknown terminals
  // drop the sequence silently.
  if (mode.kittyKeyboard) buf.write('\x1B[>1u');
  // SGR mouse: button tracking (1000) + drag (1002), plus all-motion (1003)
  // for hover when requested, all in SGR encoding (1006).
  if (mode.mouse || mode.mouseMotion) {
    buf.write('\x1B[?1000h\x1B[?1002h');
    if (mode.mouseMotion) buf.write('\x1B[?1003h');
    buf.write('\x1B[?1006h');
  }
  return buf.toString();
}

/// Builds the mode-exit escape sequence shared by native terminal drivers.
String buildTerminalExitSequences(TerminalMode mode) {
  final buf = StringBuffer();
  // Disable mouse modes unconditionally, including all-motion 1003, so none
  // leak back to the shell.
  buf.write('\x1B[?1006l\x1B[?1003l\x1B[?1002l\x1B[?1000l');
  if (mode.kittyKeyboard) buf.write('\x1B[<u');
  if (mode.bracketedPaste) buf.write('\x1B[?2004l');
  if (mode.hideCursor) buf.write('\x1B[?25h');
  if (mode.resetStyleOnExit) buf.write('\x1B[0m');
  if (mode.alternateScreen) buf.write('\x1B[?1049l');
  return buf.toString();
}
