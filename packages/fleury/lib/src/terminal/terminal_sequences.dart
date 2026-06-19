import 'terminal_driver.dart';

/// Builds the mode-entry escape sequence shared by native terminal drivers.
String buildTerminalEnterSequences(TerminalMode mode) {
  final buf = StringBuffer();
  if (mode.alternateScreen) buf.write('\x1B[?1049h');
  // Disable autowrap (DECAWM) while we own the screen. The diff renderer paints
  // full-width rows and positions the cursor with `\r\n`/relative moves that
  // assume writing the last column does NOT advance the cursor. With autowrap
  // left on, a row whose content reaches the last column wraps the cursor an
  // extra line, and the following `\r\n` over-advances — desyncing every row
  // below it (persistent garble, most visible once long content scrolls into
  // view). Restored on exit.
  if (mode.alternateScreen) buf.write('\x1B[?7l');
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
  // leak back to the shell. This stays unconditional even when the session
  // never enabled mouse: suspend (Ctrl+Z) and subprocess handoff let foreign
  // code write to the terminal, and a subprocess that enabled mouse and
  // crashed would otherwise leave the user's shell spewing mouse reports.
  // The cost is 32 bytes once per exit/suspend — measured and accepted
  // (classified as session lifecycle in AnsiByteBreakdown, not frame
  // overhead).
  buf.write('\x1B[?1006l\x1B[?1003l\x1B[?1002l\x1B[?1000l');
  if (mode.kittyKeyboard) buf.write('\x1B[<u');
  if (mode.bracketedPaste) buf.write('\x1B[?2004l');
  if (mode.hideCursor) buf.write('\x1B[?25h');
  if (mode.resetStyleOnExit) buf.write('\x1B[0m');
  // Restore autowrap (DECAWM) before leaving the alt screen, so the shell we
  // hand back behaves normally.
  if (mode.alternateScreen) buf.write('\x1B[?7h');
  if (mode.alternateScreen) buf.write('\x1B[?1049l');
  return buf.toString();
}
