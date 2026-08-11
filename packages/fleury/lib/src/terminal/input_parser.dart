// Byte-level input parser: turns a stream of raw bytes from stdin into
// typed [TuiEvent]s.
//
// What the parser handles in P0:
//   - Printable ASCII / Unicode (multi-byte UTF-8) → TextInputEvent.
//   - CR (\r, 0x0D) / LF (\n, 0x0A) → KeyEvent(KeyCode.enter).
//   - Tab (0x09) → KeyEvent(KeyCode.tab).
//   - Backspace (0x7F or 0x08) → KeyEvent(KeyCode.backspace).
//   - Ctrl+letter (0x01..0x1A, excluding the ones above) →
//     KeyEvent(KeyCode.char('a'..'z'), modifiers: {ctrl}).
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
import 'dart:convert';

import '../input/events.dart';
import '../input/key_tables.dart';
import 'legacy_key_sequences.dart';
import 'terminal_response.dart';

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
    this.maxControlStringLength = 64 * 1024,
    this.maxPasteBytes = 1024 * 1024,
    Iterable<LegacyKeySequence> additionalLegacyKeySequences =
        const <LegacyKeySequence>[],
  }) : _legacySequences = _LegacySequenceTable(<LegacyKeySequence>[
         ...builtInLegacyKeySequences,
         ...additionalLegacyKeySequences,
       ]),
       assert(maxCsiSequenceLength > 0),
       assert(maxControlStringLength > 0),
       assert(maxPasteBytes > 0);

  /// Maximum bytes accepted between `CSI` and its final byte.
  ///
  /// Real key/mouse reports are a few dozen bytes at most. The cap prevents a
  /// malformed terminal or legacy remote peer from growing parameter lists and
  /// arbitrary-precision integers forever without a final byte.
  final int maxCsiSequenceLength;

  /// Maximum bytes retained for one OSC, DCS, or APC terminal response.
  ///
  /// Capability replies are normally tiny. The larger bound accommodates
  /// palette-style replies without allowing a malformed peer to retain input
  /// without limit while a query is active.
  final int maxControlStringLength;

  /// Response forms currently expected by the driver's single-flight query.
  ///
  /// The driver leaves this at [TerminalResponseExpectation.none] outside a
  /// query and during ordinary application input. Private CSI responses remain
  /// recognizable because they do not collide with valid input encodings.
  TerminalResponseExpectation responseExpectation =
      TerminalResponseExpectation.none;

  /// Monotonic receipt clock and per-source counter for [InputBatch]
  /// stamping. Timing is diagnostics data, excluded from batch equality.
  final Stopwatch _clock = Stopwatch()..start();
  int _nextSequence = 0;

  /// Target bytes retained for one bracketed-paste segment.
  ///
  /// Larger pastes are emitted as multiple [PasteEvent]s, preserving all input
  /// while bounding the parser's live buffer. A trailing incomplete UTF-8
  /// scalar may carry over by at most three bytes, and a CRLF/LFCR pair by one
  /// byte, rather than splitting either unit across events.
  final int maxPasteBytes;

  _State _state = _State.ground;
  final List<int> _pendingUtf8 = <int>[];
  final List<int> _escapeBytes = <int>[];
  final _LegacySequenceTable _legacySequences;
  final List<int> _legacyCandidate = <int>[];

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
  int? _csiPrivateMarker;
  final List<int> _csiIntermediates = <int>[];
  bool _csiMouseSgr = false; // saw the SGR-mouse private marker '<'
  int _csiCurrentParam = 0;
  bool _csiAccumulating = false;
  int _csiSequenceLength = 0;

  // OSC/DCS/APC response framing. `_controlSawEsc` permits the ST terminator
  // (`ESC \\`) to span input reads. BEL terminates OSC only.
  TerminalResponseKind? _controlKind;
  bool _controlSawEsc = false;
  TerminalResponseSink? _responseSink;

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
  void feed(
    List<int> bytes,
    TuiEventSink sink, {
    TerminalResponseSink? responseSink,
  }) {
    _responseSink = responseSink;
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
    _replayLegacyCandidate(sink);
    // An idle flush ends the "immediately after CR" window: a lone CR is the
    // normal raw-mode Enter byte, and the driver flushes on a ~30ms idle
    // debounce, so without this a much-later unrelated raw LF (Ctrl+J) would
    // be wrongly swallowed. A genuine CRLF arrives contiguous within one read,
    // far under the debounce, so no flush intervenes between its CR and LF.
    _swallowNextLf = false;
    switch (_state) {
      case _State.afterEsc:
        if (responseExpectation.hasControlStrings) {
          break;
        }
        sink.add(const KeyEvent(KeyCode.escape));
        _clearEscapeSequence();
        _state = _State.ground;
      case _State.utf8Continuation:
        // A stream read can split a scalar and the next byte can arrive after
        // the driver's ESC-disambiguation timeout. Keep the at-most-four-byte
        // prefix; a later invalid continuation recovers through ground state.
        break;
      case _State.csi:
        // A query response may be fragmented across a gap longer than the
        // lone-ESC debounce. Preserve response-shaped CSI only while the
        // driver owns an active expectation; ordinary incomplete key CSI is
        // still discarded on idle exactly as before.
        if (_couldStillBeExpectedCsiResponse) break;
        _resetCsi();
        _clearEscapeSequence();
        _state = _State.ground;
      case _State.controlString:
      case _State.controlStringDiscard:
        // Control strings are entered only while explicitly expected. Their
        // query deadline, not the key debounce, owns their lifetime.
        break;
      case _State.csiDiscard:
      case _State.ss3:
        // Mid-sequence on flush — give up and reset.
        _resetCsi();
        _clearEscapeSequence();
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

  /// Ends query ownership of ambiguous terminal-response prefixes.
  ///
  /// A Device Attributes sentinel establishes a clean response boundary, so
  /// [discardIncompleteResponses] is false on normal completion and a pending
  /// lone Escape is returned to the app. When a late-reply quarantine expires
  /// without that sentinel, response-shaped prefixes are unsafe to replay:
  /// their eventual tails could otherwise become phantom key presses. A bare
  /// Escape has no response-specific evidence, so it is released as input once
  /// the bounded quarantine itself has expired.
  void endResponseExpectation(
    TuiEventSink sink, {
    bool discardIncompleteResponses = false,
  }) {
    _replayLegacyCandidate(sink);
    final ownedIncompleteResponse = switch (_state) {
      _State.afterEsc => false,
      _State.csi => _couldStillBeExpectedCsiResponse,
      _State.csiDiscard ||
      _State.controlString ||
      _State.controlStringDiscard => true,
      _ => false,
    };
    responseExpectation = TerminalResponseExpectation.none;
    if (discardIncompleteResponses && ownedIncompleteResponse) {
      _resetCsi();
      _clearEscapeSequence();
      _state = _State.ground;
      return;
    }
    flush(sink);
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
    _replayLegacyCandidate(sink);
    _swallowNextLf = false;
    switch (_state) {
      case _State.afterEsc:
        sink.add(const KeyEvent(KeyCode.escape));
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
      case _State.controlString:
      case _State.controlStringDiscard:
      case _State.ground:
        break;
    }
    _pendingUtf8.clear();
    _resetCsi();
    _clearEscapeSequence();
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
    if (_legacyCandidate.isEmpty && _state == _State.ground && byte == 0x1B) {
      _legacyCandidate.add(byte);
      return;
    }
    if (_legacyCandidate.isNotEmpty) {
      _legacyCandidate.add(byte);
      final match = _legacySequences.match(_legacyCandidate);
      if (match.prefix) return;
      final sequence = match.exact;
      if (sequence != null) {
        sink.add(
          KeyEvent(
            sequence.key,
            modifiers: sequence.modifiers,
            position: _positionFor(sequence.key),
          ),
        );
        _legacyCandidate.clear();
        return;
      }
      _replayLegacyCandidate(sink);
      return;
    }
    _consumeDecoded(byte, sink);
  }

  void _replayLegacyCandidate(TuiEventSink sink) {
    if (_legacyCandidate.isEmpty) return;
    final bytes = List<int>.of(_legacyCandidate);
    _legacyCandidate.clear();
    for (final byte in bytes) {
      _consumeDecoded(byte, sink);
    }
  }

  void _consumeDecoded(int byte, TuiEventSink sink) {
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
      case _State.controlString:
      case _State.controlStringDiscard:
        _consumeControlString(byte);
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
      _escapeBytes
        ..clear()
        ..add(byte);
      _state = _State.afterEsc;
      return;
    }
    if (byte == 0x0D) {
      sink.add(const KeyEvent(KeyCode.enter));
      _swallowNextLf = true; // swallow a paired LF
      return;
    }
    if (byte == 0x0A) {
      if (swallowLf) return; // the LF half of a CRLF — already emitted Enter
      sink.add(const KeyEvent(KeyCode.enter));
      return;
    }
    if (byte == 0x09) {
      sink.add(const KeyEvent(KeyCode.tab));
      return;
    }
    if (byte == 0x7F || byte == 0x08) {
      sink.add(const KeyEvent(KeyCode.backspace));
      return;
    }
    if (byte == 0) {
      // Ctrl+Space / Ctrl+@ on some terminals. Emit as Ctrl+space.
      sink.add(
        const KeyEvent(KeyCode.char(' '), modifiers: {KeyModifier.ctrl}),
      );
      return;
    }
    if (byte >= 0x01 && byte <= 0x1A) {
      // Ctrl+letter. 0x01 = Ctrl+A, 0x1A = Ctrl+Z.
      final letter = String.fromCharCode(byte + 0x60); // 'a'..'z'
      sink.add(
        KeyEvent(KeyCode.char(letter), modifiers: const {KeyModifier.ctrl}),
      );
      return;
    }
    if (byte >= 0x1C && byte <= 0x1F) {
      // Ctrl+\, Ctrl+], Ctrl+^, Ctrl+_. Best effort: surface as
      // Ctrl-modified printable equivalents.
      const map = {0x1C: r'\', 0x1D: ']', 0x1E: '^', 0x1F: '_'};
      sink.add(
        KeyEvent(KeyCode.char(map[byte]!), modifiers: const {KeyModifier.ctrl}),
      );
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
    _escapeBytes.add(byte);
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
    final controlKind = switch (byte) {
      0x5D when responseExpectation.operatingSystemCommand =>
        TerminalResponseKind.operatingSystemCommand, // ']': OSC
      0x50 when responseExpectation.deviceControlString =>
        TerminalResponseKind.deviceControlString, // 'P': DCS
      0x5F when responseExpectation.applicationProgramCommand =>
        TerminalResponseKind.applicationProgramCommand, // '_': APC
      _ => null,
    };
    if (controlKind != null) {
      _controlKind = controlKind;
      _controlSawEsc = false;
      _state = _State.controlString;
      return;
    }
    if (byte == 0x1B) {
      // Two ESCs in a row — emit the previous one as escape and stay
      // in afterEsc for the new one.
      sink.add(const KeyEvent(KeyCode.escape));
      _escapeBytes
        ..clear()
        ..add(byte);
      return;
    }
    if (byte >= 0x20 && byte < 0x7F) {
      // Alt + printable.
      sink.add(
        KeyEvent(
          KeyCode.forCharacter(String.fromCharCode(byte)),
          modifiers: const {KeyModifier.alt},
        ),
      );
      _clearEscapeSequence();
      _state = _State.ground;
      return;
    }
    // Unknown sequence — reset to ground and keep the byte.
    _clearEscapeSequence();
    _state = _State.ground;
    _consumeGround(byte, sink);
  }

  void _consumeCsi(int byte, TuiEventSink sink) {
    _escapeBytes.add(byte);
    _csiSequenceLength++;
    if (_csiSequenceLength > maxCsiSequenceLength) {
      _resetCsi();
      _clearEscapeSequence();
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
      _csiPrivateMarker ??= byte;
      return;
    }
    if (byte == 0x3F || byte == 0x3E || byte == 0x3D) {
      // '?', '>', '=' — private-mode marker. Track but otherwise
      // pass through; we'll ignore unknown sequences.
      _csiHasIntermediate = true;
      _csiPrivateMarker ??= byte;
      return;
    }
    if (byte >= 0x20 && byte <= 0x2F) {
      // ECMA-48 intermediate bytes. Mode reports use `$` before their final
      // `y`; retaining the exact intermediates lets response classification
      // happen before a sequence can be mistaken for input.
      _csiHasIntermediate = true;
      _csiIntermediates.add(byte);
      return;
    }
    if (byte >= 0x40 && byte <= 0x7E) {
      // Final byte. Commit any in-progress number / group.
      if (_csiAccumulating || _csiGroup.isNotEmpty || _csiGroups.isNotEmpty) {
        _csiGroup.add(_csiCurrentParam);
        _csiGroups.add(_csiGroup);
        _csiGroup = <int>[];
      }
      final response = _classifyCsiResponse(byte);
      if (response != null) {
        _responseSink?.addTerminalResponse(response);
        _resetCsi();
        _clearEscapeSequence();
        _state = _State.ground;
        return;
      }
      // SGR mouse report: `CSI < Cb ; Cx ; Cy M|m`.
      if (_csiMouseSgr && (byte == 0x4D || byte == 0x6D)) {
        _emitMouse(byte, sink);
        _resetCsi();
        _clearEscapeSequence();
        _state = _State.ground;
        return;
      }
      // Kitty keyboard report: `CSI codepoint ; mods[:event] u`. A '?'
      // intermediate marks a protocol-flags reply (`CSI ? flags u`), which
      // we don't emit as a key.
      if (byte == 0x75 && !_csiMouseSgr) {
        if (!_csiHasIntermediate) _emitKittyKey(sink);
        _resetCsi();
        _clearEscapeSequence();
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
        _clearEscapeSequence();
        return;
      }
      _emitCsi(byte, sink);
      _resetCsi();
      _clearEscapeSequence();
      _state = _State.ground;
      return;
    }
    if (byte == 0x1B) {
      // ESC mid-CSI aborts this sequence and BEGINS a new one (ECMA-48 / VT
      // behaviour), exactly as [_consumeDiscardedCsi] handles it. Re-entering
      // afterEsc lets the immediately-following report (e.g. `ESC [ A`) decode
      // instead of the ESC being dropped and `[ A` mis-parsed as typed text.
      _resetCsi();
      _escapeBytes
        ..clear()
        ..add(byte);
      _state = _State.afterEsc;
      return;
    }
    // Unknown intermediate byte — abort sequence.
    _resetCsi();
    _clearEscapeSequence();
    _state = _State.ground;
  }

  /// Discards the tail of an overlong CSI without turning attacker-controlled
  /// parameter bytes into a flood of ordinary text events. A final byte
  /// restores ground state; a fresh ESC starts a new sequence.
  void _consumeDiscardedCsi(int byte) {
    if (byte == 0x1B) {
      _escapeBytes
        ..clear()
        ..add(byte);
      _state = _State.afterEsc;
      return;
    }
    if (byte >= 0x40 && byte <= 0x7E) {
      _clearEscapeSequence();
      _state = _State.ground;
    }
  }

  TerminalResponse? _classifyCsiResponse(int finalByte) {
    final privateMarker = _csiPrivateMarker;
    final hasDollar = _csiIntermediates.contains(0x24);
    final kind = switch (finalByte) {
      0x63
          when privateMarker == 0x3F ||
              privateMarker == 0x3E ||
              privateMarker == 0x3D =>
        TerminalResponseKind.deviceAttributes,
      0x75 when privateMarker == 0x3F => TerminalResponseKind.keyboardStatus,
      0x52 when responseExpectation.cursorPosition && privateMarker == null =>
        TerminalResponseKind.cursorPosition,
      0x79 when hasDollar => TerminalResponseKind.modeReport,
      0x74 when responseExpectation.windowOperation =>
        TerminalResponseKind.windowOperation,
      _ => null,
    };
    return kind == null ? null : TerminalResponse(kind, _escapeBytes);
  }

  /// Whether an incomplete CSI can still be a reply whose lifecycle belongs
  /// to the active query deadline rather than the key debounce.
  bool get _couldStillBeExpectedCsiResponse {
    if (_csiPrivateMarker == 0x3F ||
        _csiPrivateMarker == 0x3E ||
        _csiPrivateMarker == 0x3D) {
      return responseExpectation.privateCsiPrefix;
    }
    if (_csiIntermediates.contains(0x24)) {
      return responseExpectation.modeReport;
    }
    return responseExpectation.cursorPosition ||
        responseExpectation.windowOperation;
  }

  void _consumeControlString(int byte) {
    final retaining = _state == _State.controlString;
    if (retaining) _escapeBytes.add(byte);
    final kind = _controlKind;
    if (kind == null) {
      _clearEscapeSequence();
      _state = _State.ground;
      return;
    }

    final bellTerminated =
        kind == TerminalResponseKind.operatingSystemCommand && byte == 0x07;
    final stringTerminated = _controlSawEsc && byte == 0x5C;
    if (bellTerminated || stringTerminated) {
      if (retaining) {
        _responseSink?.addTerminalResponse(
          TerminalResponse(kind, _escapeBytes),
        );
      }
      _clearEscapeSequence();
      _state = _State.ground;
      return;
    }

    _controlSawEsc = byte == 0x1B;
    if (retaining && _escapeBytes.length > maxControlStringLength) {
      // Keep discarding through the terminator. Returning to ground here would
      // reinterpret the response payload as user input.
      _escapeBytes.clear();
      _state = _State.controlStringDiscard;
    }
  }

  /// First sub-parameter of semicolon group [i], or null when absent.
  int? _groupValue(int i) => i < _csiGroups.length && _csiGroups[i].isNotEmpty
      ? _csiGroups[i][0]
      : null;

  void _consumeSs3(int byte, TuiEventSink sink) {
    // SS3 is a single final byte.
    final key = switch (byte) {
      0x41 => KeyCode.arrowUp,
      0x42 => KeyCode.arrowDown,
      0x43 => KeyCode.arrowRight,
      0x44 => KeyCode.arrowLeft,
      0x45 => KeyCode.keypadBegin,
      0x48 => KeyCode.home,
      0x46 => KeyCode.end,
      0x50 => KeyCode.f1,
      0x51 => KeyCode.f2,
      0x52 => KeyCode.f3,
      0x53 => KeyCode.f4,
      0x70 => KeyCode.keypad0,
      0x71 => KeyCode.keypad1,
      0x72 => KeyCode.keypad2,
      0x73 => KeyCode.keypad3,
      0x74 => KeyCode.keypad4,
      0x75 => KeyCode.keypad5,
      0x76 => KeyCode.keypad6,
      0x77 => KeyCode.keypad7,
      0x78 => KeyCode.keypad8,
      0x79 => KeyCode.keypad9,
      0x6A => KeyCode.keypadMultiply,
      0x6B => KeyCode.keypadAdd,
      0x6C => KeyCode.keypadSeparator,
      0x6D => KeyCode.keypadSubtract,
      0x6E => KeyCode.keypadDecimal,
      0x6F => KeyCode.keypadDivide,
      0x4D => KeyCode.keypadEnter,
      0x58 => KeyCode.keypadEqual,
      _ => null,
    };
    if (key != null) {
      sink.add(KeyEvent(key, position: _positionFor(key)));
    }
    _clearEscapeSequence();
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
      if (p1 == 27) {
        _emitModifyOtherKey(sink);
        return;
      }
      final kc = _tildeKey(p1 ?? 0);
      if (kc != null) {
        sink.add(
          KeyEvent(
            kc,
            modifiers: modifiers,
            type: type,
            position: _positionFor(kc),
          ),
        );
      }
      return;
    }

    // Focus reporting (DECSET 1004): `CSI I` in, `CSI O` out. Parameterless
    // by definition, so a params-bearing sequence with the same final is
    // something else and falls through.
    if ((finalByte == 0x49 || finalByte == 0x4F) && _csiGroups.length <= 1) {
      final p = _groupValue(0);
      if (p == null || p == 0) {
        sink.add(TerminalFocusEvent(focused: finalByte == 0x49));
        return;
      }
    }

    if (finalByte == 0x5A) {
      // 'Z' — back-tab: how legacy (non-kitty) terminals send Shift+Tab.
      // The shift is implied by the final byte itself; merge it with any
      // explicit modifier param (xterm sends `CSI 1;5Z` for Ctrl+Shift+Tab).
      sink.add(
        KeyEvent(
          KeyCode.tab,
          modifiers: {...modifiers, KeyModifier.shift},
          type: type,
          position: _positionFor(KeyCode.tab),
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
      0x45 => KeyCode.keypadBegin, // KP_BEGIN's legacy form (`CSI 1 E`)
      0x48 => KeyCode.home,
      0x46 => KeyCode.end,
      0x50 => KeyCode.f1,
      0x51 => KeyCode.f2,
      0x52 => KeyCode.f3,
      0x53 => KeyCode.f4,
      _ => null,
    };
    if (kc != null) {
      sink.add(
        KeyEvent(
          kc,
          modifiers: modifiers,
          type: type,
          position: _positionFor(kc),
        ),
      );
    }
  }

  /// Decodes xterm's default modifyOtherKeys form:
  /// `CSI 27 ; modifier ; codepoint ~`.
  void _emitModifyOtherKey(TuiEventSink sink) {
    if (_csiGroups.length < 3) return;
    final modifier = _groupValue(1);
    final codepoint = _groupValue(2);
    if (modifier == null || codepoint == null || !_isUnicodeScalar(codepoint)) {
      return;
    }
    final modifiers = _decodeModifiers(modifier);
    final special = switch (codepoint) {
      9 => KeyCode.tab,
      13 => KeyCode.enter,
      27 => KeyCode.escape,
      8 || 127 => KeyCode.backspace,
      _ => null,
    };
    if (special != null) {
      sink.add(
        KeyEvent(
          special,
          modifiers: modifiers,
          position: _positionFor(special),
        ),
      );
      return;
    }
    if (codepoint < 0x20 || (codepoint >= 0x7F && codepoint <= 0x9F)) return;
    final text = String.fromCharCode(codepoint);
    final key = KeyCode.forCharacter(text);
    final actionable = modifiers.any(
      (modifier) => modifier != KeyModifier.shift,
    );
    if (actionable) {
      sink.add(KeyEvent(key, modifiers: modifiers));
      return;
    }
    sink.add(
      InputBatch(
        key: KeyEvent(key, modifiers: modifiers),
        committedText: text,
        timeStamp: _clock.elapsed,
        sequence: _nextSequence++,
      ),
    );
  }

  /// Decodes a full Kitty keyboard report
  /// (`CSI key[:shifted[:base]] ; mods[:event] [; text] u`) into the
  /// matching key or text event (RFC 0020 §8.7 — the complete grammar, not
  /// a showcase subset).
  void _emitKittyKey(TuiEventSink sink) {
    final codepoint = _groupValue(0);
    if (codepoint == null || !_isUnicodeScalar(codepoint)) return;

    var modifiers = const <KeyModifier>{};
    var type = KeyEventType.down;
    if (_csiGroups.length >= 2 && _csiGroups[1].isNotEmpty) {
      modifiers = _decodeModifiers(_csiGroups[1][0]);
      if (_csiGroups[1].length >= 2) type = _eventType(_csiGroups[1][1]);
    }

    // Base-layout alternate (flag 4): third sub-param of the key group.
    // Empty sub-params parse as 0, which the protocol also uses for
    // "absent" — never a real key. Positional identity is per-event data;
    // an unmapped base codepoint leaves it null rather than guessing.
    KeyPosition? position;
    if (_csiGroups[0].length >= 3 && _csiGroups[0][2] > 0) {
      position = positionByUsCodepoint[_csiGroups[0][2]];
    }

    // Key number 0: text with no key identity (IME/OS-produced text).
    // Emit the associated text alone — no invented KeyCode, no state
    // (RFC 0020 §6, text-only batches).
    if (codepoint == 0) {
      if (!_kittyAssociatedTextIsValid()) return;
      final text = _kittyAssociatedText();
      if (text != null && text.isNotEmpty && type != KeyEventType.up) {
        sink.add(TextInputEvent(text));
      }
      return;
    }

    // Special chords carry their classic control codepoint even in CSI-u
    // form — this is the disambiguation win (lone Esc, Ctrl+I vs Tab,
    // Ctrl+M vs Enter all become distinct, modifier-bearing events). The
    // functional PUA table extends this to the complete vocabulary,
    // including lone modifier keys and the keypad — KP Enter is
    // [KeyCode.keypadEnter], deliberately distinct from Enter (§8.7:
    // nothing silently folded).
    final kc = _kittyFunctionalKey(codepoint);
    if (kc != null) {
      // Flag-4 data still wins when present (kitty could someday remap).
      position ??= _positionFor(kc);
      sink.add(
        KeyEvent(kc, modifiers: modifiers, type: type, position: position),
      );
      return;
    }

    // A well-formed functional codepoint outside the mapped table (the PUA
    // block 57344–63743) is diagnosable unsupported input — never text
    // (§8.7). Dropping beats emitting private-use garbage as typing.
    if (codepoint >= 0xE000 && codepoint <= 0xF8FF) return;

    // A text-producing key with no actionable modifier (only Shift, or
    // none) is plain input on down/repeat. Its release is a key event with
    // no text — phase retention (§8.7): the dispatcher fences `up` from
    // commands; the regularizer and observation lanes consume it.
    final actionable = modifiers.any((m) => m != KeyModifier.shift);
    if (!actionable) {
      if (type == KeyEventType.up) {
        sink.add(
          KeyEvent(
            KeyCode.forCharacter(String.fromCharCode(codepoint)),
            modifiers: modifiers,
            type: KeyEventType.up,
            position: position,
          ),
        );
        return;
      }
      var cp = codepoint;
      // Prefer the shifted codepoint the terminal reports (group 0's
      // second sub-param) when Shift is held. 0 means absent.
      if (modifiers.contains(KeyModifier.shift) &&
          _csiGroups[0].length >= 2 &&
          _csiGroups[0][1] > 0) {
        cp = _csiGroups[0][1];
      }
      if (!_isUnicodeScalar(cp) || !_kittyAssociatedTextIsValid()) return;
      final text = _kittyAssociatedText() ?? String.fromCharCode(cp);
      // The report carried key identity AND produced text — one physical
      // fact, one correlated batch (RFC 0020 §5). This is where positional
      // identity survives for printables; the pre-batch pipeline threw the
      // key half away.
      sink.add(
        InputBatch(
          key: KeyEvent(
            KeyCode.forCharacter(String.fromCharCode(codepoint)),
            modifiers: modifiers,
            type: type,
            position: position,
          ),
          committedText: text,
          timeStamp: _clock.elapsed,
          sequence: _nextSequence++,
        ),
      );
      return;
    }

    // A modified key (Ctrl/Alt/Super/Meta + key): report the base
    // character so bindings like Ctrl+C match regardless of layout. The
    // base-layout position rides along — it is the §13.3 non-Latin
    // matching fallback's data source (Ctrl+С carrying base 'c').
    sink.add(
      KeyEvent(
        KeyCode.forCharacter(String.fromCharCode(codepoint)),
        modifiers: modifiers,
        type: type,
        position: position,
      ),
    );
  }

  KeyEventType _eventType(int code) => switch (code) {
    2 => KeyEventType.repeat,
    3 => KeyEventType.up,
    _ => KeyEventType.down,
  };

  /// Positional identity for a functional key: layout-independent, so the
  /// parsed special IS the physical key — no flag-4 data needed. This is
  /// [positionBySpecial]'s whole purpose, and it is what keeps positional
  /// selectors matching identically on the terminal and DOM surfaces
  /// (§13.3 parity): the DOM backend has always reported ArrowLeft's
  /// position, while these paths used to emit arrows position-less.
  KeyPosition? _positionFor(KeyCode kc) {
    final special = kc.special;
    return special == null ? null : positionBySpecial[special];
  }

  KeyCode? _kittyFunctionalKey(int cp) {
    switch (cp) {
      case 13:
        return KeyCode.enter;
      case 9:
        return KeyCode.tab;
      case 27:
        return KeyCode.escape;
      case 8 || 127:
        return KeyCode.backspace;
    }
    final special = kittyFunctionalKeys[cp];
    return special == null ? null : KeyCode.forSpecial(special);
  }

  /// The associated-text field (group 2, colon-separated codepoints), only
  /// present when the terminal was asked to report text. Null otherwise.
  String? _kittyAssociatedText() {
    if (_csiGroups.length < 3 || _csiGroups[2].isEmpty) return null;
    return String.fromCharCodes(_csiGroups[2]);
  }

  bool _kittyAssociatedTextIsValid() {
    if (_csiGroups.length < 3) return true;
    // The spec forbids control codes in associated text; a terminal (or
    // spoofed peer) sending them must not smuggle CR/ESC into the text lane.
    // That means C1 (0x80–0x9F) too, not just C0/DEL: 0x9B is a one-byte CSI,
    // and letting it through as "text" hands re-interpretable control bytes
    // to whatever renders or forwards the string.
    return _csiGroups[2].every(
      (cp) =>
          _isUnicodeScalar(cp) &&
          cp >= 0x20 &&
          cp != 0x7F &&
          !(cp >= 0x80 && cp <= 0x9F),
    );
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
      25 => KeyCode.f13,
      26 => KeyCode.f14,
      28 => KeyCode.f15,
      29 => KeyCode.f16,
      31 => KeyCode.f17,
      32 => KeyCode.f18,
      33 => KeyCode.f19,
      34 => KeyCode.f20,
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
    _csiPrivateMarker = null;
    _csiIntermediates.clear();
    _csiMouseSgr = false;
    _csiCurrentParam = 0;
    _csiAccumulating = false;
    _csiSequenceLength = 0;
  }

  void _clearEscapeSequence() {
    _escapeBytes.clear();
    _controlKind = null;
    _controlSawEsc = false;
  }
}

enum _State {
  ground,
  afterEsc,
  csi,
  csiDiscard,
  ss3,
  controlString,
  controlStringDiscard,
  utf8Continuation,
  paste,
}

final class _LegacySequenceTable {
  static const _maxSequenceLength = 256;

  _LegacySequenceTable(Iterable<LegacyKeySequence> sequences)
    : _entries = <({List<int> bytes, LegacyKeySequence sequence})>[
        for (final sequence in sequences)
          (bytes: sequence.sequence.codeUnits, sequence: sequence),
      ] {
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final bytes = entry.bytes;
      if (bytes.length < 2 ||
          bytes.length > _maxSequenceLength ||
          bytes.first != 0x1B ||
          bytes.any((byte) => byte > 0x7F)) {
        throw ArgumentError.value(
          entry.sequence.sequence,
          'additionalLegacyKeySequences',
          'Fixed terminal key sequences must be 2–256 ASCII bytes and start '
              'with ESC.',
        );
      }
      for (var j = 0; j < i; j++) {
        final other = _entries[j].bytes;
        if (_startsWith(bytes, other) || _startsWith(other, bytes)) {
          throw ArgumentError(
            'Legacy key sequences must be unique and prefix-free.',
          );
        }
      }
    }
  }

  final List<({List<int> bytes, LegacyKeySequence sequence})> _entries;

  ({LegacyKeySequence? exact, bool prefix}) match(List<int> candidate) {
    for (final entry in _entries) {
      if (!_startsWith(entry.bytes, candidate)) continue;
      return (
        exact: entry.bytes.length == candidate.length ? entry.sequence : null,
        prefix: entry.bytes.length > candidate.length,
      );
    }
    return (exact: null, prefix: false);
  }
}

bool _startsWith(List<int> value, List<int> prefix) {
  if (prefix.length > value.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (value[i] != prefix[i]) return false;
  }
  return true;
}
