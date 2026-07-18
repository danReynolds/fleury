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
/// parser.finish(sink);                    // resolves state at stream EOF
/// ```
///
/// `feed` may be called repeatedly with byte fragments; the parser
/// preserves state between calls. `flush` is called when the input
/// goes idle (in practice, scheduled as a microtask after each batch);
/// it lets the parser emit a pending lone-ESC as `KeyCode.escape`
/// rather than waiting forever for a CSI continuation that isn't
/// coming.
class InputParser {
  InputParser({
    this.maxCsiSequenceLength = 256,
    this.maxPasteBytes = 1024 * 1024,
  }) : assert(maxCsiSequenceLength > 0),
       assert(maxPasteBytes > 0);

  /// Maximum bytes accepted between `CSI` and its final byte.
  ///
  /// Real key/mouse reports are a few dozen bytes at most. The cap prevents a
  /// malformed terminal or legacy remote peer from growing parameter lists and
  /// arbitrary-precision integers forever without a final byte.
  final int maxCsiSequenceLength;

  /// Target bytes retained for one bracketed-paste segment.
  ///
  /// Larger pastes are emitted as multiple [PasteEvent]s, preserving all input
  /// while bounding the parser's live buffer. A trailing incomplete UTF-8
  /// scalar may carry over by at most three bytes, and a CRLF/LFCR pair by one
  /// byte, rather than splitting either unit across events.
  final int maxPasteBytes;

  _State _state = _State.ground;
  final List<int> _pendingUtf8 = <int>[];

  // CRLF collapse: a CR (0x0D) emits Enter and arms this so the LF (0x0A)
  // half of a `\r\n` pair — as delivered by piped/scripted input, LNM-mode
  // terminals, and Windows/serial PTYs — is swallowed instead of firing a
  // SECOND Enter (double form-submit). Set by CR, consumed by an immediately
  // following LF, cleared by any other byte. Only meaningful in the ground
  // state (CR doesn't change state), so it's read/reset solely there.
  bool _swallowNextLf = false;

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
  int _csiSequenceLength = 0;

  // Bracketed-paste accumulation. `_pasteEnd` is the `ESC [ 2 0 1 ~`
  // terminator; `_pasteMatch` tracks how many of its bytes have matched
  // so far so partial matches inside the pasted content are preserved.
  static const List<int> _pasteEnd = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E];
  final List<int> _pasteBytes = <int>[];
  int _pasteMatch = 0;
  bool _pasteEmittedChunk = false;
  int _nextPasteId = 1;
  int _activePasteId = 0;

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
  ///
  /// UTF-8 scalars and bracketed paste are deliberately not terminated by an
  /// idle flush. Driver reads may split either across an arbitrary boundary
  /// (and slow PTYs can exceed the ESC timeout); both states are bounded and
  /// can safely wait for their continuation bytes.
  void flush(TuiEventSink sink) {
    // An idle flush ends the "immediately after CR" window: a lone CR is the
    // normal raw-mode Enter byte, and the driver flushes on a ~30ms idle
    // debounce, so without this a much-later unrelated raw LF (Ctrl+J) would
    // be wrongly swallowed. A genuine CRLF arrives contiguous within one read,
    // far under the debounce, so no flush intervenes between its CR and LF.
    _swallowNextLf = false;
    switch (_state) {
      case _State.afterEsc:
        sink.add(const KeyEvent(keyCode: KeyCode.escape));
        _state = _State.ground;
      case _State.utf8Continuation:
        // A stream read can split a scalar and the next byte can arrive after
        // the driver's ESC-disambiguation timeout. Keep the at-most-four-byte
        // prefix; a later invalid continuation recovers through ground state.
        break;
      case _State.csi:
      case _State.csiDiscard:
      case _State.ss3:
        // Mid-sequence on flush — give up and reset.
        _resetCsi();
        _state = _State.ground;
      case _State.paste:
        // Bracketed paste can span many reads (especially over SSH). Its live
        // buffer is bounded by maxPasteBytes, so wait for the explicit 201~
        // marker instead of turning a short network pause into typed keys.
        break;
      case _State.ground:
        break;
    }
  }

  /// Resolves any pending parser state when the byte stream reaches EOF.
  ///
  /// Unlike [flush], this is a hard boundary: an incomplete UTF-8 scalar is
  /// emitted with Unicode replacement semantics, and an unterminated
  /// bracketed paste is finalized as one complete undo transaction. Partial
  /// control sequences are discarded. A driver should call this exactly once
  /// from its stdin `onDone` path; idle timeouts must continue to use [flush]
  /// so a slow but valid paste is never truncated.
  void finish(TuiEventSink sink) {
    _swallowNextLf = false;
    switch (_state) {
      case _State.afterEsc:
        sink.add(const KeyEvent(keyCode: KeyCode.escape));
      case _State.utf8Continuation:
        if (_pendingUtf8.isNotEmpty) {
          sink.add(
            TextInputEvent(utf8.decode(_pendingUtf8, allowMalformed: true)),
          );
        }
      case _State.paste:
        _finishPaste(sink);
        return;
      case _State.csi:
      case _State.csiDiscard:
      case _State.ss3:
      case _State.ground:
        break;
    }
    _pendingUtf8.clear();
    _resetCsi();
    _state = _State.ground;
  }

  /// Whether the parser is mid bracketed-paste, so the driver can arm (and
  /// re-arm) its paste-inactivity deadline that calls [flushPaste].
  bool get isPasting => _state == _State.paste;

  /// Finalizes an in-progress bracketed paste after prolonged inactivity.
  ///
  /// [flush] deliberately does NOT end a paste on the driver's ~30ms idle
  /// debounce: a slow SSH paste can pause far longer than that between reads,
  /// and splitting it into typed keys was itself an injection hazard. But an
  /// abandoned paste — the paste source dies after `ESC[200~` so the `ESC[201~`
  /// terminator never arrives — would otherwise capture ALL later input forever,
  /// including the Ctrl+C escape hatch (raw mode disables ISIG, so 0x03 is just
  /// a paste byte). The driver calls this on a separate, generous inactivity
  /// deadline (seconds, not the 30ms ESC debounce) so an abandoned paste is
  /// emitted as one [PasteEvent] and the parser returns to ground, restoring
  /// keyboard control; a merely-slow paste stays far under the deadline. No-op
  /// unless mid-paste.
  void flushPaste(TuiEventSink sink) {
    if (_state == _State.paste) _finishPaste(sink);
  }

  void _consume(int byte, TuiEventSink sink) {
    switch (_state) {
      case _State.ground:
        _consumeGround(byte, sink);
      case _State.afterEsc:
        _consumeAfterEsc(byte, sink);
      case _State.csi:
        _consumeCsi(byte, sink);
      case _State.csiDiscard:
        _consumeDiscardedCsi(byte);
      case _State.ss3:
        _consumeSs3(byte, sink);
      case _State.utf8Continuation:
        _consumeUtf8(byte, sink);
      case _State.paste:
        _consumePaste(byte, sink);
    }
  }

  void _consumeGround(int byte, TuiEventSink sink) {
    // Capture-and-clear the CRLF latch up front: only an LF *immediately*
    // after a CR is the pair's second half.
    final swallowLf = _swallowNextLf;
    _swallowNextLf = false;
    if (byte == 0x1B) {
      _state = _State.afterEsc;
      return;
    }
    if (byte == 0x0D) {
      sink.add(const KeyEvent(keyCode: KeyCode.enter));
      _swallowNextLf = true; // swallow a paired LF
      return;
    }
    if (byte == 0x0A) {
      if (swallowLf) return; // the LF half of a CRLF — already emitted Enter
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
    _csiSequenceLength++;
    if (_csiSequenceLength > maxCsiSequenceLength) {
      _resetCsi();
      _state = _State.csiDiscard;
      // This byte may itself be the final that closes the overlong sequence.
      // Consume it in discard state so the following ordinary byte is not
      // mistaken for that final and lost.
      _consumeDiscardedCsi(byte);
      return;
    }
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
        _pasteEmittedChunk = false;
        _activePasteId = _nextPasteId;
        _nextPasteId = _nextPasteId == 0x7FFFFFFF ? 1 : _nextPasteId + 1;
        _state = _State.paste;
        return;
      }
      _emitCsi(byte, sink);
      _resetCsi();
      _state = _State.ground;
      return;
    }
    if (byte == 0x1B) {
      // ESC mid-CSI aborts this sequence and BEGINS a new one (ECMA-48 / VT
      // behaviour), exactly as [_consumeDiscardedCsi] handles it. Re-entering
      // afterEsc lets the immediately-following report (e.g. `ESC [ A`) decode
      // instead of the ESC being dropped and `[ A` mis-parsed as typed text.
      _resetCsi();
      _state = _State.afterEsc;
      return;
    }
    // Unknown intermediate byte — abort sequence.
    _resetCsi();
    _state = _State.ground;
  }

  /// Discards the tail of an overlong CSI without turning attacker-controlled
  /// parameter bytes into a flood of ordinary text events. A final byte
  /// restores ground state; a fresh ESC starts a new sequence.
  void _consumeDiscardedCsi(int byte) {
    if (byte == 0x1B) {
      _state = _State.afterEsc;
      return;
    }
    if (byte >= 0x40 && byte <= 0x7E) {
      _state = _State.ground;
    }
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
    if (codepoint == null || !_isUnicodeScalar(codepoint)) return;

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
      if (!_isUnicodeScalar(cp) || !_kittyAssociatedTextIsValid()) return;
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

  bool _kittyAssociatedTextIsValid() {
    if (_csiGroups.length < 3) return true;
    return _csiGroups[2].every(_isUnicodeScalar);
  }

  bool _isUnicodeScalar(int value) =>
      value >= 0 && value <= 0x10FFFF && (value < 0xD800 || value > 0xDFFF);

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
      // Wheel. The low two bits select which wheel: 64 up, 65 down, 66 left,
      // 67 right. Only the vertical pair maps to a MouseEventKind; a horizontal
      // wheel gesture is dropped rather than mis-reported as a vertical scroll
      // (there is no horizontal scroll kind, and scrolling the wrong axis is
      // worse than ignoring the gesture).
      final kind = switch (cb & 3) {
        0 => MouseEventKind.scrollUp,
        1 => MouseEventKind.scrollDown,
        _ => null, // 66/67 — horizontal wheel-left/right.
      };
      if (kind == null) return;
      sink.add(
        MouseEvent(
          kind: kind,
          button: MouseButton.none,
          col: col,
          row: row,
          modifiers: mods,
        ),
      );
      return;
    }

    // Extended buttons 8-11 set bit 128 (back/forward/thumb buttons). We have no
    // enum member for them, so report `none` rather than letting `cb & 3` alias
    // them to left/middle/right — a thumb-button press must not activate the
    // widget under the cursor as if left-clicked.
    final button = cb & 128 != 0
        ? MouseButton.none
        : switch (cb & 3) {
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
      if (_pasteMatch == _pasteEnd.length) {
        _pasteMatch = 0;
        _finishPaste(sink);
      }
      return;
    }
    // Mismatch: the bytes we tentatively matched were real content.
    if (_pasteMatch > 0) {
      for (var i = 0; i < _pasteMatch; i++) {
        _appendPasteByte(_pasteEnd[i], sink);
      }
      _pasteMatch = 0;
    }
    // The current byte might itself start a fresh terminator.
    if (byte == _pasteEnd[0]) {
      _pasteMatch = 1;
    } else {
      _appendPasteByte(byte, sink);
    }
  }

  void _appendPasteByte(int byte, TuiEventSink sink) {
    _pasteBytes.add(byte);
    if (_pasteBytes.length < maxPasteBytes) return;
    _emitPasteChunk(sink, preserveSegmentUnits: true);
  }

  void _emitPasteChunk(TuiEventSink sink, {bool preserveSegmentUnits = false}) {
    if (_pasteBytes.isEmpty) return;
    final emitLength = preserveSegmentUnits
        ? _completePastePrefixLength(_pasteBytes, maxPasteBytes)
        : _pasteBytes.length;
    if (emitLength == 0) return;
    final text = utf8.decode(
      _pasteBytes.sublist(0, emitLength),
      allowMalformed: true,
    );
    _pasteBytes.removeRange(0, emitLength);
    final phase = _pasteEmittedChunk
        ? PasteEventPhase.continuation
        : PasteEventPhase.start;
    _pasteEmittedChunk = true;
    sink.add(PasteEvent.segment(text, pasteId: _activePasteId, phase: phase));
  }

  /// Returns a prefix near [limit] without splitting a UTF-8 scalar or a
  /// paired CRLF/LFCR newline. A complete unit may exceed the target by up to
  /// three bytes. Malformed bytes still make progress and are handled by
  /// `allowMalformed` at decode.
  int _completePastePrefixLength(List<int> bytes, int limit) {
    if (bytes.isEmpty) return 0;
    final boundary = bytes.length < limit ? bytes.length : limit;

    // TextArea canonicalizes line endings per PasteEvent. Hold a newline byte
    // at the segment edge until we know whether its partner follows, otherwise
    // splitting CR|LF or LF|CR would turn one logical newline into two.
    final edge = bytes[boundary - 1];
    if (edge == 0x0D || edge == 0x0A) {
      if (bytes.length == boundary) return boundary - 1;
      final next = bytes[boundary];
      if ((edge == 0x0D && next == 0x0A) || (edge == 0x0A && next == 0x0D)) {
        return boundary + 1;
      }
      return boundary;
    }

    var first = boundary - 1;
    while (first >= 0 && (bytes[first] & 0xC0) == 0x80) {
      first--;
    }
    if (first < 0) return boundary; // malformed continuation-only prefix

    final lead = bytes[first];
    final expected = switch (lead) {
      < 0x80 => 1,
      >= 0xC2 && < 0xE0 => 2,
      >= 0xE0 && < 0xF0 => 3,
      >= 0xF0 && < 0xF5 => 4,
      _ => 1,
    };
    final availableAtBoundary = boundary - first;
    if (availableAtBoundary >= expected) return boundary;

    // If the rest has already arrived, include it in this segment (at most
    // limit+3). Otherwise retain the incomplete scalar for the next byte.
    if (bytes.length - first >= expected) return first + expected;
    return first;
  }

  void _finishPaste(TuiEventSink sink) {
    // EOF can arrive after a partial terminator match. Those tentative
    // bytes were content unless the full marker landed, so preserve them.
    if (_pasteMatch > 0) {
      final matched = _pasteMatch;
      _pasteMatch = 0;
      for (var i = 0; i < matched; i++) {
        _appendPasteByte(_pasteEnd[i], sink);
      }
    }
    final text = utf8.decode(_pasteBytes, allowMalformed: true);
    _pasteBytes.clear();
    if (_pasteEmittedChunk) {
      sink.add(
        PasteEvent.segment(
          text,
          pasteId: _activePasteId,
          phase: PasteEventPhase.end,
        ),
      );
    } else {
      sink.add(PasteEvent(text));
    }
    _pasteEmittedChunk = false;
    _activePasteId = 0;
    _state = _State.ground;
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
    _csiSequenceLength = 0;
  }
}

enum _State { ground, afterEsc, csi, csiDiscard, ss3, utf8Continuation, paste }
