import 'dart:convert';
import 'dart:io';

import '../foundation/geometry.dart';
import '../rendering/ansi_render_target.dart';
import '../terminal/terminal_driver.dart';
import '../terminal/terminal_sequences.dart';
import '../terminal/pointer_shapes.dart';

/// Private child/supervisor recovery channel. A lease contains typed state,
/// never executable escape bytes, and lives in a supervisor-owned temp dir.
const inlineTerminalLeaseEnvironment = 'FLEURY_DEV_INLINE_LEASE';

void writeInlineTerminalLease(
  String? path, {
  required TerminalMode mode,
  required bool active,
  CellSize? terminal,
  int? top,
  int? rows,
  bool pointerStackOwned = false,
  bool stackStateUnknown = false,
}) {
  if (path == null) return;
  final pending = File('$path.pending');
  pending.writeAsStringSync(
    jsonEncode({
      'version': 1,
      'active': active,
      'inline': mode.inlineRows != null,
      // Keep the private recovery wire format readable by older supervisors.
      'alternateScreen': mode.isFullScreen,
      'stackStateUnknown': stackStateUnknown,
      'keyboard': mode.keyboardProtocol.name,
      'hideCursor': mode.hideCursor,
      'resetStyle': mode.resetStyleOnExit,
      'paste': mode.bracketedPaste,
      'focus': mode.focusReporting,
      'pointer': pointerStackOwned,
      if (terminal != null && top != null && rows != null)
        'region': {
          'cols': terminal.cols,
          'terminalRows': terminal.rows,
          'top': top,
          'rows': rows,
        },
    }),
  );
  pending.renameSync(path);
}

/// Null means this child never registered terminal ownership. An inactive
/// lease returns no bytes: the child has already handed the terminal back.
String? inlineTerminalRecovery(String? path, CellSize terminal) {
  if (path == null || !File(path).existsSync()) return null;
  try {
    final file = File(path);
    if (file.lengthSync() > 4096) {
      throw const FormatException('oversized lease');
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('unknown lease');
    if (data['active'] == false) return '';
    if (data['active'] != true) throw const FormatException('invalid lease');
    // Older leases represented only inline sessions. Both native modes now
    // record their actual ownership, so a handled uncertain stack operation
    // cannot make the supervisor guess a second keyboard or pointer pop.
    final inline = data['inline'] as bool? ?? true;
    final stackStateUnknown = data['stackStateUnknown'] as bool? ?? false;
    final keyboard = stackStateUnknown
        ? KeyboardProtocolMode.legacy
        : KeyboardProtocolMode.values.byName(data['keyboard'] as String);
    // A pre-migration lease could describe an unbounded main-buffer session.
    // Restore its input modes without guessing an alternate-screen exit.
    if (!inline && data['alternateScreen'] is! bool) {
      throw const FormatException('missing screen ownership');
    }
    final mode = inline || data['alternateScreen'] == false
        ? TerminalMode.inline(
            rows: 1,
            keyboardProtocol: keyboard,
            hideCursor: data['hideCursor'] as bool,
            resetStyleOnExit: data['resetStyle'] as bool,
            bracketedPaste: data['paste'] as bool,
            focusReporting: data['focus'] as bool,
          )
        : TerminalMode.fullScreen(
            keyboardProtocol: keyboard,
            hideCursor: data['hideCursor'] as bool,
            resetStyleOnExit: data['resetStyle'] as bool,
            bracketedPaste: data['paste'] as bool,
            focusReporting: data['focus'] as bool,
          );
    final bytes = StringBuffer();
    final region = data['region'];
    final top = region is Map ? region['top'] as Object? : null;
    final rows = region is Map ? region['rows'] as Object? : null;
    if (inline &&
        region is Map &&
        region['cols'] == terminal.cols &&
        region['terminalRows'] == terminal.rows &&
        top is int &&
        rows is int &&
        top >= 0 &&
        rows > 0 &&
        top + rows <= terminal.rows) {
      final target = AnsiRenderTarget.inline(top: top);
      bytes.write(target.clearSequence(CellSize(terminal.cols, rows)));
      bytes.write('\x1B[${target.top + 1};1H');
    } else if (inline && region != null) {
      // The terminal resized after the last committed allocation. Preserve
      // unknown content instead of clearing at a stale absolute origin.
      bytes.write('\r\n');
    }
    if (!stackStateUnknown && data['pointer'] == true) {
      bytes.write(popPointerShape);
    }
    bytes.write(buildTerminalExitSequences(mode));
    return bytes.toString();
  } catch (_) {
    // Corrupt metadata must never become arbitrary output or a guessed
    // alternate-screen/keyboard-stack pop. Restore common input modes only.
    return buildTerminalExitSequences(
      const TerminalMode.inline(
        rows: 1,
        keyboardProtocol: KeyboardProtocolMode.legacy,
      ),
    );
  }
}
