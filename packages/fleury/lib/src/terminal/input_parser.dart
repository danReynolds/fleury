// Byte-level input parser: turns a stream of raw bytes from stdin into
// typed [TuiEvent]s.
//
// What the parser handles in P0:
//   - Printable ASCII / Unicode (multi-byte UTF-8) → TextInputEvent.
//   - CR (\r, 0x0D) / LF (\n, 0x0A) → KeyEvent(KeyCode.enter).
//   - Tab (0x09) → KeyEvent(KeyCode.tab).
//   - Backspace (0x7F or 0x08) → KeyEvent(KeyCode.backspace).
//   - Ctrl+letter (0x01..0x1A, excluding the ones above) →
//     KeyEvent(char: 'a'..'z', modifiers: {ctrl}).
//   - Lone ESC → KeyEvent(KeyCode.escape), emitted on [flush].
//   - CSI sequences `ESC [ ... <final>`:
//       A/B/C/D → arrowUp/Down/Right/Left
//       H → home, F → end
//       1~/2~/3~/4~/5~/6~ → home/insert/delete/end/pageUp/pageDown
//       11~..15~, 17~..21~, 23~/24~ → F1..F12
//       Modifier params (`CSI 1;<mod> <final>` etc.) populate the
//       Ctrl/Alt/Shift flags. The standard mod values are
//       2=shift, 3=alt, 4=alt+shift, 5=ctrl, 6=ctrl+shift,
//       7=ctrl+alt, 8=ctrl+alt+shift.
//   - SS3 sequences `ESC O <final>`: A/B/C/D map to arrows; some
//     terminals report F1..F4 here.
//   - ESC followed by a printable byte → emitted as Alt+<char>.
//   - Bracketed paste markers (`CSI 200~` / `CSI 201~`).
//   - SGR mouse encoding (`CSI < ... M|m`).
//   - Kitty keyboard protocol (CSI-u): `CSI codepoint ; mods[:event] u`
//     plus the event-type sub-param on the legacy cursor/function-key
//     forms. This disambiguates chords the legacy encoding can't (Ctrl+I
//     vs Tab, Ctrl+M vs Enter, lone Esc), resolves super/meta modifiers,
//     and — when requested — distinguishes press/repeat/release. The
//     driver negotiates it with the terminal; the parser handles the
//     reports it elicits (and ignores them harmlessly otherwise).
//
// What is intentionally NOT handled:
//   - Focus in / out events.

import 'dart:convert';

import '../input/events.dart';

/// Sink interface used by the parser to emit events. The terminal
/// driver supplies the real implementation (typically a
/// `StreamController.add` adapter); tests use an in-memory list.
abstract interface class TuiEventSink {
  void add(TuiEvent event);
}

/// State machine that consumes raw bytes and emits typed input events.
///
/// Usage:
///
/// ```dart
/// final parser = InputParser();
/// parser.feed([0x1B, 0x5B, 0x41], sink); // ESC [ A → arrowUp
/// parser.flush(sink);                     // emits any pending events
/// ```
///
/// `feed` may be called repeatedly with byte fragments; the parser
/// preserves state between calls. `flush` is called when the input
/// goes idle (in practice, scheduled as a microtask after each batch);
/// it lets the parser emit a pending lone-ESC as `KeyCode.escape`
/// rather than waiting forever for a CSI continuation that isn't
/// coming.
class InputParser {
  _State _state = _State.ground;
  final List<int> _pendingUtf8 = <int>[];

  // CSI parameters, modelled as semicolon-separated groups, each holding
  // one or more colon-separated sub-parameters. The classic forms use a
  // single sub-param per group (`CSI 1 ; 5 A`); the Kitty protocol adds
  // sub-params for the event type (`mods:event`), the shifted/base key
  // codepoints, and associated text.
  final List<List<int>> _csiGroups = <List<int>>[];
  List<int> _csiGroup = <int>[];
  bool _csiHasIntermediate = false;
  bool _csiMouseSgr = false; // saw the SGR-mouse private marker '<'
  int _csiCurrentParam = 0;
  bool _csiAccumulating = false;

  // Bracketed-paste accumulation. `_pasteEnd` is the `ESC [ 2 0 1 ~`
  // terminator; `_pasteMatch` tracks how many of its bytes have matched
  // so far so partial matches inside the pasted content are preserved.
  static const List<int> _pasteEnd = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E];
  final List<int> _pasteBytes = <int>[];
  int _pasteMatch = 0;

  /// Feeds [bytes] to the parser and emits any complete events to
  /// [sink].
  void feed(List<int> bytes, TuiEventSink sink) {
    for (final b in bytes) {
      _consume(b, sink);
    }
  }

  /// Notifies the parser that no more bytes are arriving imminently.
  /// Used to disambiguate a lone ESC press from the start of a CSI/SS3
  /// sequence: if state is still [_State.afterEsc] when this is
  /// called, the ESC is emitted as a standalone keypress.
  void flush(TuiEventSink sink) {
    switch (_state) {
      case _State.afterEsc:
        sink.add(const KeyEvent(keyCode: KeyCode.escape));
        _state = _State.ground;
      case _State.utf8Continuation:
        // Incomplete UTF-8 sequence — discard. (Real terminals should
        // never split a codepoint across input bursts in practice.)
        _pendingUtf8.clear();
        _state = _State.ground;
      case _State.csi:
      case _State.ss3:
        // Mid-sequence on flush — give up and reset.
        _resetCsi();
        _state = _State.ground;
      case _State.paste:
        // Idle mid-paste (no terminator yet) — emit what we have so the
        // content isn't lost, rather than stranding it forever.
        _flushPaste(sink);
      case _State.ground:
        break;
    }
  }

  void _consume(int byte, TuiEventSink sink) {
    switch (_state) {
      case _State.ground:
        _consumeGround(byte, sink);
      case _State.afterEsc:
        _consumeAfterEsc(byte, sink);
      case _State.csi:
        _consumeCsi(byte, sink);
      case _State.ss3:
        _consumeSs3(byte, sink);
      case _State.utf8Continuation:
        _consumeUtf8(byte, sink);
      case _State.paste:
        _consumePaste(byte, sink);
    }
  }

  void _consumeGround(int byte, TuiEventSink sink) {
    if (byte == 0x1B) {
      _state = _State.afterEsc;
      return;
    }
    if (byte == 0x0D || byte == 0x0A) {
      sink.add(const KeyEvent(keyCode: KeyCode.enter));
      return;
    }
    if (byte == 0x09) {
      sink.add(const KeyEvent(keyCode: KeyCode.tab));
      return;
    }
    if (byte == 0x7F || byte == 0x08) {
      sink.add(const KeyEvent(keyCode: KeyCode.backspace));
      return;
    }
    if (byte == 0) {
      // Ctrl+Space / Ctrl+@ on some terminals. Emit as Ctrl+space.
      sink.add(const KeyEvent(char: ' ', modifiers: {KeyModifier.ctrl}));
      return;
    }
    if (byte >= 0x01 && byte <= 0x1A) {
      // Ctrl+letter. 0x01 = Ctrl+A, 0x1A = Ctrl+Z.
      final letter = String.fromCharCode(byte + 0x60); // 'a'..'z'
      sink.add(KeyEvent(char: letter, modifiers: const {KeyModifier.ctrl}));
      return;
    }
    if (byte >= 0x1C && byte <= 0x1F) {
      // Ctrl+\, Ctrl+], Ctrl+^, Ctrl+_. Best effort: surface as
      // Ctrl-modified printable equivalents.
      const map = {0x1C: r'\', 0x1D: ']', 0x1E: '^', 0x1F: '_'};
      sink.add(KeyEvent(char: map[byte], modifiers: const {KeyModifier.ctrl}));
      return;
    }
    if (byte < 0x80) {
      // Printable ASCII.
      sink.add(TextInputEvent(String.fromCharCode(byte)));
      return;
    }
    // Multi-byte UTF-8 start.
    _pendingUtf8
      ..clear()
      ..add(byte);
    _state = _State.utf8Continuation;
  }

  void _consumeAfterEsc(int byte, TuiEventSink sink) {
    if (byte == 0x5B) {
      // '['
      _state = _State.csi;
      _resetCsi();
      _csiAccumulating = true;
      return;
    }
    if (byte == 0x4F) {
      // 'O' — SS3 prefix
      _state = _State.ss3;
      return;
    }
    if (byte == 0x1B) {
      // Two ESCs in a row — emit the previous one as escape and stay
      // in afterEsc for the new one.
      sink.add(const KeyEvent(keyCode: KeyCode.escape));
      return;
    }
    if (byte >= 0x20 && byte < 0x7F) {
      // Alt + printable.
      sink.add(
        KeyEvent(
          char: String.fromCharCode(byte),
          modifiers: const {KeyModifier.alt},
        ),
      );
      _state = _State.ground;
      return;
    }
    // Unknown sequence — reset to ground and keep the byte.
    _state = _State.ground;
    _consumeGround(byte, sink);
  }

  void _consumeCsi(int byte, TuiEventSink sink) {
    if (byte >= 0x30 && byte <= 0x39) {
      // Digit: extend current param.
      _csiCurrentParam = _csiCurrentParam * 10 + (byte - 0x30);
      _csiAccumulating = true;
      return;
    }
    if (byte == 0x3A) {
      // ':' — sub-parameter separator. Close the current number into the
      // open group; the group stays open for more sub-params.
      _csiGroup.add(_csiCurrentParam);
      _csiCurrentParam = 0;
      _csiAccumulating = false;
      return;
    }
    if (byte == 0x3B) {
      // ';' — close the current number and group, then start a new group.
      _csiGroup.add(_csiCurrentParam);
      _csiGroups.add(_csiGroup);
      _csiGroup = <int>[];
      _csiCurrentParam = 0;
      _csiAccumulating = false;
      return;
    }
    if (byte == 0x3C) {
      // '<' — SGR mouse report marker. Parsed (not ignored).
      _csiMouseSgr = true;
      return;
    }
    if (byte == 0x3F || byte == 0x3E || byte == 0x3D) {
      // '?', '>', '=' — private-mode marker. Track but otherwise
      // pass through; we'll ignore unknown sequences.
      _csiHasIntermediate = true;
      return;
    }
    if (byte >= 0x40 && byte <= 0x7E) {
      // Final byte. Commit any in-progress number / group.
      if (_csiAccumulating || _csiGroup.isNotEmpty || _csiGroups.isNotEmpty) {
        _csiGroup.add(_csiCurrentParam);
        _csiGroups.add(_csiGroup);
        _csiGroup = <int>[];
      }
      // SGR mouse report: `CSI < Cb ; Cx ; Cy M|m`.
      if (_csiMouseSgr && (byte == 0x4D || byte == 0x6D)) {
        _emitMouse(byte, sink);
        _resetCsi();
        _state = _State.ground;
        return;
      }
      // Kitty keyboard report: `CSI codepoint ; mods[:event] u`. A '?'
      // intermediate marks a protocol-flags reply (`CSI ? flags u`), which
      // we don't emit as a key.
      if (byte == 0x75 && !_csiMouseSgr) {
        if (!_csiHasIntermediate) _emitKittyKey(sink);
        _resetCsi();
        _state = _State.ground;
        return;
      }
      // Bracketed paste start: `CSI 200 ~` → collect raw paste content.
      if (byte == 0x7E &&
          !_csiHasIntermediate &&
          _csiGroups.length == 1 &&
          _groupValue(0) == 200) {
        _resetCsi();
        _pasteBytes.clear();
        _pasteMatch = 0;
        _state = _State.paste;
        return;
      }
      _emitCsi(byte, sink);
      _resetCsi();
      _state = _State.ground;
      return;
    }
    // Unknown intermediate byte — abort sequence.
    _resetCsi();
    _state = _State.ground;
  }

  /// First sub-parameter of semicolon group [i], or null when absent.
  int? _groupValue(int i) => i < _csiGroups.length && _csiGroups[i].isNotEmpty
      ? _csiGroups[i][0]
      : null;

  void _consumeSs3(int byte, TuiEventSink sink) {
    // SS3 is a single final byte.
    switch (byte) {
      case 0x41: // 'A'
        sink.add(const KeyEvent(keyCode: KeyCode.arrowUp));
      case 0x42: // 'B'
        sink.add(const KeyEvent(keyCode: KeyCode.arrowDown));
      case 0x43: // 'C'
        sink.add(const KeyEvent(keyCode: KeyCode.arrowRight));
      case 0x44: // 'D'
        sink.add(const KeyEvent(keyCode: KeyCode.arrowLeft));
      case 0x48: // 'H'
        sink.add(const KeyEvent(keyCode: KeyCode.home));
      case 0x46: // 'F'
        sink.add(const KeyEvent(keyCode: KeyCode.end));
      case 0x50: // 'P' — F1
        sink.add(const KeyEvent(keyCode: KeyCode.f1));
      case 0x51:
        sink.add(const KeyEvent(keyCode: KeyCode.f2));
      case 0x52:
        sink.add(const KeyEvent(keyCode: KeyCode.f3));
      case 0x53:
        sink.add(const KeyEvent(keyCode: KeyCode.f4));
    }
    _state = _State.ground;
  }

  void _emitCsi(int finalByte, TuiEventSink sink) {
    if (_csiHasIntermediate) {
      // Private-mode sequences (e.g. mode resets the framework might
      // accidentally echo back); ignore.
      return;
    }
    // CSI sequences may carry a modifier param. The common shape is
    // `CSI 1;<mod> <final>` for cursor chords, or `CSI <p1>;<mod>~` for
    // tilde-finalised chords. The Kitty protocol adds an event-type
    // sub-param on the modifier group: `CSI 1 ; <mod>:<event> <final>`.
    final p1 = _groupValue(0);
    var modifiers = const <KeyModifier>{};
    var type = KeyEventType.down;
    if (_csiGroups.length >= 2 && _csiGroups[1].isNotEmpty) {
      modifiers = _decodeModifiers(_csiGroups[1][0]);
      if (_csiGroups[1].length >= 2) type = _eventType(_csiGroups[1][1]);
    }

    if (finalByte == 0x7E) {
      // '~' — tilde-finalised chords, p1 selects which.
      final kc = _tildeKey(p1 ?? 0);
      if (kc != null) {
        sink.add(KeyEvent(keyCode: kc, modifiers: modifiers, type: type));
      }
      return;
    }

    if (finalByte == 0x5A) {
      // 'Z' — back-tab: how legacy (non-kitty) terminals send Shift+Tab.
      // The shift is implied by the final byte itself; merge it with any
      // explicit modifier param (xterm sends `CSI 1;5Z` for Ctrl+Shift+Tab).
      sink.add(
        KeyEvent(
          keyCode: KeyCode.tab,
          modifiers: {...modifiers, KeyModifier.shift},
          type: type,
        ),
      );
      return;
    }

    // Letter finals.
    final kc = switch (finalByte) {
      0x41 => KeyCode.arrowUp,
      0x42 => KeyCode.arrowDown,
      0x43 => KeyCode.arrowRight,
      0x44 => KeyCode.arrowLeft,
      0x48 => KeyCode.home,
      0x46 => KeyCode.end,
      0x50 => KeyCode.f1,
      0x51 => KeyCode.f2,
      0x52 => KeyCode.f3,
      0x53 => KeyCode.f4,
      _ => null,
    };
    if (kc != null) {
      sink.add(KeyEvent(keyCode: kc, modifiers: modifiers, type: type));
    }
  }

  /// Decodes a Kitty keyboard report (`CSI codepoint ; mods[:event] [; text] u`)
  /// into the matching key or text event.
  void _emitKittyKey(TuiEventSink sink) {
    final codepoint = _groupValue(0);
    if (codepoint == null) return;

    var modifiers = const <KeyModifier>{};
    var type = KeyEventType.down;
    if (_csiGroups.length >= 2 && _csiGroups[1].isNotEmpty) {
      modifiers = _decodeModifiers(_csiGroups[1][0]);
      if (_csiGroups[1].length >= 2) type = _eventType(_csiGroups[1][1]);
    }

    // Special chords carry their classic control codepoint even in CSI-u
    // form — this is the disambiguation win (lone Esc, Ctrl+I vs Tab,
    // Ctrl+M vs Enter all become distinct, modifier-bearing events).
    final kc = _kittyFunctionalKey(codepoint);
    if (kc != null) {
      sink.add(KeyEvent(keyCode: kc, modifiers: modifiers, type: type));
      return;
    }

    // A text-producing key with no actionable modifier (only Shift, or
    // none) is plain input. Releases never produce text.
    final actionable = modifiers.any((m) => m != KeyModifier.shift);
    if (!actionable) {
      if (type == KeyEventType.up) return;
      var cp = codepoint;
      // Prefer the shifted codepoint the terminal reports (group 0's
      // second sub-param) when Shift is held.
      if (modifiers.contains(KeyModifier.shift) && _csiGroups[0].length >= 2) {
        cp = _csiGroups[0][1];
      }
      final text = _kittyAssociatedText() ?? String.fromCharCode(cp);
      sink.add(TextInputEvent(text));
      return;
    }

    // A modified key (Ctrl/Alt/Super/Meta + key): report the base
    // character so bindings like Ctrl+C match regardless of layout.
    sink.add(
      KeyEvent(
        char: String.fromCharCode(codepoint),
        modifiers: modifiers,
        type: type,
      ),
    );
  }

  KeyEventType _eventType(int code) => switch (code) {
    2 => KeyEventType.repeat,
    3 => KeyEventType.up,
    _ => KeyEventType.down,
  };

  KeyCode? _kittyFunctionalKey(int cp) => switch (cp) {
    13 || 57414 => KeyCode.enter, // Enter, KP Enter
    9 => KeyCode.tab,
    27 => KeyCode.escape,
    8 || 127 => KeyCode.backspace,
    _ => null,
  };

  /// The associated-text field (group 2, colon-separated codepoints), only
  /// present when the terminal was asked to report text. Null otherwise.
  String? _kittyAssociatedText() {
    if (_csiGroups.length < 3 || _csiGroups[2].isEmpty) return null;
    return String.fromCharCodes(_csiGroups[2]);
  }

  Set<KeyModifier> _decodeModifiers(int code) {
    // Modifier param is `1 + bitmask`. The low three bits (shift/alt/ctrl)
    // are the classic xterm encoding; the Kitty protocol reuses the same
    // field and adds super (8) and meta (32). Hyper / caps-lock / num-lock
    // bits exist but don't map to an actionable modifier here.
    final bits = code - 1;
    if (bits <= 0) return const <KeyModifier>{};
    final out = <KeyModifier>{};
    if (bits & 1 != 0) out.add(KeyModifier.shift);
    if (bits & 2 != 0) out.add(KeyModifier.alt);
    if (bits & 4 != 0) out.add(KeyModifier.ctrl);
    if (bits & 8 != 0) out.add(KeyModifier.superKey);
    if (bits & 32 != 0) out.add(KeyModifier.meta);
    return out;
  }

  KeyCode? _tildeKey(int param) {
    return switch (param) {
      1 || 7 => KeyCode.home,
      2 => KeyCode.insert,
      3 => KeyCode.delete,
      4 || 8 => KeyCode.end,
      5 => KeyCode.pageUp,
      6 => KeyCode.pageDown,
      11 => KeyCode.f1,
      12 => KeyCode.f2,
      13 => KeyCode.f3,
      14 => KeyCode.f4,
      15 => KeyCode.f5,
      17 => KeyCode.f6,
      18 => KeyCode.f7,
      19 => KeyCode.f8,
      20 => KeyCode.f9,
      21 => KeyCode.f10,
      23 => KeyCode.f11,
      24 => KeyCode.f12,
      _ => null,
    };
  }

  void _emitMouse(int finalByte, TuiEventSink sink) {
    if (_csiGroups.length < 3) return;
    final cb = _groupValue(0) ?? 0;
    final cx = _groupValue(1) ?? 0;
    final cy = _groupValue(2) ?? 0;
    final col = cx - 1 < 0 ? 0 : cx - 1; // 1-based → 0
    final row = cy - 1 < 0 ? 0 : cy - 1;
    final mods = <KeyModifier>{};
    if (cb & 4 != 0) mods.add(KeyModifier.shift);
    if (cb & 8 != 0) mods.add(KeyModifier.alt);
    if (cb & 16 != 0) mods.add(KeyModifier.ctrl);

    if (cb & 64 != 0) {
      // Wheel: low bit selects direction.
      sink.add(
        MouseEvent(
          kind: cb & 1 == 0
              ? MouseEventKind.scrollUp
              : MouseEventKind.scrollDown,
          button: MouseButton.none,
          col: col,
          row: row,
          modifiers: mods,
        ),
      );
      return;
    }

    final button = switch (cb & 3) {
      0 => MouseButton.left,
      1 => MouseButton.middle,
      2 => MouseButton.right,
      _ => MouseButton.none,
    };
    final motion = cb & 32 != 0;
    final MouseEventKind kind;
    if (finalByte == 0x6D) {
      kind = MouseEventKind.up;
    } else if (motion) {
      kind = button == MouseButton.none
          ? MouseEventKind.moved
          : MouseEventKind.drag;
    } else {
      kind = MouseEventKind.down;
    }
    sink.add(
      MouseEvent(
        kind: kind,
        button: button,
        col: col,
        row: row,
        modifiers: mods,
      ),
    );
  }

  void _consumePaste(int byte, TuiEventSink sink) {
    // Watch for the `ESC [ 2 0 1 ~` terminator while buffering content.
    if (byte == _pasteEnd[_pasteMatch]) {
      _pasteMatch++;
      if (_pasteMatch == _pasteEnd.length) _flushPaste(sink);
      return;
    }
    // Mismatch: the bytes we tentatively matched were real content.
    if (_pasteMatch > 0) {
      _pasteBytes.addAll(_pasteEnd.sublist(0, _pasteMatch));
      _pasteMatch = 0;
    }
    // The current byte might itself start a fresh terminator.
    if (byte == _pasteEnd[0]) {
      _pasteMatch = 1;
    } else {
      _pasteBytes.add(byte);
    }
  }

  void _flushPaste(TuiEventSink sink) {
    final text = utf8.decode(_pasteBytes, allowMalformed: true);
    _pasteBytes.clear();
    _pasteMatch = 0;
    _state = _State.ground;
    sink.add(PasteEvent(text));
  }

  void _consumeUtf8(int byte, TuiEventSink sink) {
    if ((byte & 0xC0) != 0x80) {
      // Not a continuation byte — bail and re-process from ground.
      _pendingUtf8.clear();
      _state = _State.ground;
      _consumeGround(byte, sink);
      return;
    }
    _pendingUtf8.add(byte);
    if (!_isUtf8Complete(_pendingUtf8)) return;
    final decoded = utf8.decode(_pendingUtf8, allowMalformed: true);
    _pendingUtf8.clear();
    _state = _State.ground;
    sink.add(TextInputEvent(decoded));
  }

  bool _isUtf8Complete(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final lead = bytes.first;
    final expected = switch (lead) {
      < 0x80 => 1, // ASCII
      < 0xC0 => 1, // Lone continuation byte — treat as malformed
      < 0xE0 => 2,
      < 0xF0 => 3,
      _ => 4,
    };
    return bytes.length >= expected;
  }

  void _resetCsi() {
    _csiGroups.clear();
    _csiGroup = <int>[];
    _csiHasIntermediate = false;
    _csiMouseSgr = false;
    _csiCurrentParam = 0;
    _csiAccumulating = false;
  }
}

enum _State { ground, afterEsc, csi, ss3, utf8Continuation, paste }
