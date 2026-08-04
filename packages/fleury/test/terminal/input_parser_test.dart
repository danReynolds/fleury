import 'dart:convert';
import 'dart:math';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/input/key_tables.dart';
import 'package:test/test.dart';

/// Captures events into a list for assertion.
class _ListSink implements TuiEventSink {
  final List<TuiEvent> events = <TuiEvent>[];

  @override
  void add(TuiEvent event) {
    events.add(event);
  }
}

/// Convenience: feed a list of bytes and immediately flush.
List<TuiEvent> _parse(List<int> bytes) {
  final parser = InputParser();
  final sink = _ListSink();
  parser.feed(bytes, sink);
  parser.flush(sink);
  return sink.events;
}

void main() {
  group('Plain text input', () {
    test('printable ASCII bytes become TextInputEvents', () {
      expect(_parse([0x68, 0x69]), [
        const TextInputEvent('h'),
        const TextInputEvent('i'),
      ]);
    });

    test('multi-byte UTF-8 codepoint becomes one TextInputEvent', () {
      // 中 = U+4E2D = 0xE4 0xB8 0xAD in UTF-8.
      expect(_parse([0xE4, 0xB8, 0xAD]), [const TextInputEvent('中')]);
    });

    test('4-byte UTF-8 (emoji) becomes one TextInputEvent', () {
      // 🙂 = U+1F642 = 0xF0 0x9F 0x99 0x82.
      expect(_parse([0xF0, 0x9F, 0x99, 0x82]), [const TextInputEvent('🙂')]);
    });

    test('UTF-8 split across two feeds reassembles', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([0xE4, 0xB8], sink); // first two bytes of 中
      expect(sink.events, isEmpty);
      parser.feed([0xAD], sink);
      expect(sink.events, [const TextInputEvent('中')]);
    });

    test('idle flush does not discard a split UTF-8 scalar', () {
      final parser = InputParser();
      final sink = _ListSink();

      parser.feed([0xE4, 0xB8], sink);
      parser.flush(sink); // the driver's lone-ESC idle timeout fires
      parser.feed([0xAD], sink);

      expect(sink.events, [const TextInputEvent('中')]);
    });

    test('stream finish resolves a truncated UTF-8 scalar and recovers', () {
      final parser = InputParser();
      final sink = _ListSink();

      parser.feed([0xE4, 0xB8], sink);
      parser.finish(sink);
      parser.feed('q'.codeUnits, sink);

      expect(sink.events, [
        const TextInputEvent(replacementCharacter),
        const TextInputEvent('q'),
      ]);
    });
  });

  group('Special chords', () {
    test('lone CR and lone LF each become one Enter', () {
      expect(_parse([0x0D]), [const KeyEvent(KeyCode.enter)]);
      expect(_parse([0x0A]), [const KeyEvent(KeyCode.enter)]);
    });

    test('CRLF collapses to a single Enter (no double-submit)', () {
      // Piped/scripted input, LNM terminals, and Windows/serial PTYs deliver
      // `\r\n`; it must be ONE Enter, not two.
      expect(_parse([0x0D, 0x0A]), [const KeyEvent(KeyCode.enter)]);
      // Split across two feeds (fragmented reads) collapses the same way —
      // the latch persists across feed() boundaries.
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([0x0D], sink);
      parser.feed([0x0A], sink);
      expect(sink.events, [const KeyEvent(KeyCode.enter)]);
    });

    test('a flush ends the CR window — a later lone LF is not swallowed', () {
      // A lone CR is the normal raw-mode Enter; the driver flushes on idle.
      // A LF arriving in a LATER burst (e.g. Ctrl+J) must still be Enter, not
      // eaten as the paired half of a long-gone CR.
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([0x0D], sink); // Enter
      parser.flush(sink); // idle — ends the pairing window
      parser.feed([0x0A], sink); // a fresh, unrelated LF
      expect(sink.events, [
        const KeyEvent(KeyCode.enter),
        const KeyEvent(KeyCode.enter),
      ]);
    });

    test('LFCR and CR-x-LF do NOT swallow (only an immediate paired LF)', () {
      // `\n\r` is two Enters (LF first, then CR).
      expect(_parse([0x0A, 0x0D]), [
        const KeyEvent(KeyCode.enter),
        const KeyEvent(KeyCode.enter),
      ]);
      // CR, an intervening key, then LF → two Enters (the latch cleared on 'a').
      expect(_parse([0x0D, 0x61, 0x0A]), [
        const KeyEvent(KeyCode.enter),
        const TextInputEvent('a'),
        const KeyEvent(KeyCode.enter),
      ]);
    });

    test('Tab byte becomes KeyCode.tab', () {
      expect(_parse([0x09]), [const KeyEvent(KeyCode.tab)]);
    });

    test('DEL (0x7F) and BS (0x08) both become KeyCode.backspace', () {
      expect(_parse([0x7F]), [const KeyEvent(KeyCode.backspace)]);
      expect(_parse([0x08]), [const KeyEvent(KeyCode.backspace)]);
    });
  });

  group('Ctrl shortcuts', () {
    test('Ctrl+A through Ctrl+Z map to letters with ctrl modifier', () {
      expect(_parse([0x01]), [
        const KeyEvent(KeyCode.char('a'), modifiers: {KeyModifier.ctrl}),
      ]);
      expect(_parse([0x03]), [
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      ]);
      expect(_parse([0x1A]), [
        const KeyEvent(KeyCode.char('z'), modifiers: {KeyModifier.ctrl}),
      ]);
    });

    test('Ctrl+Tab is not produced (tab takes precedence)', () {
      // 0x09 is Tab, not Ctrl+I — terminals deliver Tab here.
      expect(_parse([0x09]), [const KeyEvent(KeyCode.tab)]);
    });

    test('NUL (0x00) becomes Ctrl+Space', () {
      expect(_parse([0x00]), [
        const KeyEvent(KeyCode.char(' '), modifiers: {KeyModifier.ctrl}),
      ]);
    });
  });

  group('Escape disambiguation', () {
    test('lone ESC after flush emits KeyCode.escape', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([0x1B], sink);
      expect(sink.events, isEmpty);
      parser.flush(sink);
      expect(sink.events, [const KeyEvent(KeyCode.escape)]);
    });

    test('two ESCs: first emits as escape, second waits for continuation', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([0x1B, 0x1B], sink);
      expect(sink.events, [const KeyEvent(KeyCode.escape)]);
      parser.flush(sink);
      expect(sink.events, [
        const KeyEvent(KeyCode.escape),
        const KeyEvent(KeyCode.escape),
      ]);
    });

    test('ESC followed by printable becomes Alt+<char>', () {
      // ESC + 'a' → Alt+a (xterm legacy convention).
      expect(_parse([0x1B, 0x61]), [
        const KeyEvent(KeyCode.char('a'), modifiers: {KeyModifier.alt}),
      ]);
    });
  });

  group('CSI cursor chords', () {
    test('CSI A/B/C/D map to arrow chords', () {
      expect(_parse([0x1B, 0x5B, 0x41]), [const KeyEvent(KeyCode.arrowUp)]);
      expect(_parse([0x1B, 0x5B, 0x42]), [const KeyEvent(KeyCode.arrowDown)]);
      expect(_parse([0x1B, 0x5B, 0x43]), [const KeyEvent(KeyCode.arrowRight)]);
      expect(_parse([0x1B, 0x5B, 0x44]), [const KeyEvent(KeyCode.arrowLeft)]);
    });

    test('CSI H is home, F is end', () {
      expect(_parse([0x1B, 0x5B, 0x48]), [const KeyEvent(KeyCode.home)]);
      expect(_parse([0x1B, 0x5B, 0x46]), [const KeyEvent(KeyCode.end)]);
    });

    test('CSI 1;5C is Ctrl+arrowRight', () {
      // ESC [ 1 ; 5 C  → arrow right with mod=5 (= ctrl).
      expect(_parse([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x43]), [
        const KeyEvent(KeyCode.arrowRight, modifiers: {KeyModifier.ctrl}),
      ]);
    });

    test('CSI 1;2A is Shift+arrowUp', () {
      // mod=2 = shift.
      expect(_parse([0x1B, 0x5B, 0x31, 0x3B, 0x32, 0x41]), [
        const KeyEvent(KeyCode.arrowUp, modifiers: {KeyModifier.shift}),
      ]);
    });

    test('CSI 1;7D is Ctrl+Alt+arrowLeft', () {
      // mod=7 = alt + ctrl.
      expect(_parse([0x1B, 0x5B, 0x31, 0x3B, 0x37, 0x44]), [
        isA<KeyEvent>()
            .having((e) => e.code, 'keyCode', KeyCode.arrowLeft)
            .having((e) => e.hasCtrl, 'hasCtrl', isTrue)
            .having((e) => e.hasAlt, 'hasAlt', isTrue),
      ]);
    });
  });

  group('back-tab (CSI Z)', () {
    test('ESC [ Z decodes as Shift+Tab', () {
      final events = _parse([0x1B, 0x5B, 0x5A]);
      final key = events.single as KeyEvent;
      expect(key.code, KeyCode.tab);
      expect(key.modifiers, {KeyModifier.shift});
    });

    test('ESC [ 1;5 Z merges ctrl with the implied shift', () {
      final events = _parse([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x5A]);
      final key = events.single as KeyEvent;
      expect(key.code, KeyCode.tab);
      expect(key.modifiers, containsAll({KeyModifier.shift, KeyModifier.ctrl}));
    });
  });

  group('CSI tilde-finalised chords', () {
    test('CSI 5~ is pageUp, 6~ is pageDown', () {
      expect(_parse([0x1B, 0x5B, 0x35, 0x7E]), [
        const KeyEvent(KeyCode.pageUp),
      ]);
      expect(_parse([0x1B, 0x5B, 0x36, 0x7E]), [
        const KeyEvent(KeyCode.pageDown),
      ]);
    });

    test('CSI 3~ is delete, 2~ is insert', () {
      expect(_parse([0x1B, 0x5B, 0x33, 0x7E]), [
        const KeyEvent(KeyCode.delete),
      ]);
      expect(_parse([0x1B, 0x5B, 0x32, 0x7E]), [
        const KeyEvent(KeyCode.insert),
      ]);
    });

    test('CSI 11~ is F1, 24~ is F12', () {
      expect(_parse([0x1B, 0x5B, 0x31, 0x31, 0x7E]), [
        const KeyEvent(KeyCode.f1),
      ]);
      expect(_parse([0x1B, 0x5B, 0x32, 0x34, 0x7E]), [
        const KeyEvent(KeyCode.f12),
      ]);
    });
  });

  group('SS3 (ESC O ...) sequences', () {
    test('ESC O A is arrowUp', () {
      expect(_parse([0x1B, 0x4F, 0x41]), [const KeyEvent(KeyCode.arrowUp)]);
    });

    test('ESC O P is F1', () {
      expect(_parse([0x1B, 0x4F, 0x50]), [const KeyEvent(KeyCode.f1)]);
    });
  });

  group('Mixed sequences', () {
    test('text mixed with key presses interleaves correctly', () {
      // 'h' + ESC[A + 'i' → text 'h', arrow up, text 'i'.
      expect(_parse([0x68, 0x1B, 0x5B, 0x41, 0x69]), [
        const TextInputEvent('h'),
        const KeyEvent(KeyCode.arrowUp),
        const TextInputEvent('i'),
      ]);
    });

    test('typing a word emits per-byte events', () {
      expect(
        _parse([0x68, 0x65, 0x6C, 0x6C, 0x6F]), // "hello"
        [
          const TextInputEvent('h'),
          const TextInputEvent('e'),
          const TextInputEvent('l'),
          const TextInputEvent('l'),
          const TextInputEvent('o'),
        ],
      );
    });
  });

  group('Malformed sequences', () {
    test(
      'malformed UTF-8 prefix stays bounded and recovers on ordinary text',
      () {
        // 0x80 is a continuation byte with no leader. Parser starts a
        // bounded UTF-8 prefix; idle flush must not turn it into an event.
        final parser = InputParser();
        final sink = _ListSink();
        parser.feed([0x80], sink);
        parser.flush(sink);
        expect(sink.events, isEmpty);

        // A non-continuation drops the malformed prefix and is reprocessed from
        // ground, so the parser cannot become wedged.
        parser.feed('q'.codeUnits, sink);
        expect(sink.events, [const TextInputEvent('q')]);
      },
    );

    test('unknown CSI final byte is ignored', () {
      // ESC [ ? — '?' starts a private sequence; we never see a final.
      // Feed a complete unknown sequence and verify nothing emits.
      final parser = InputParser();
      final sink = _ListSink();
      // ESC [ ? 1 0 0 0 h  — common terminal-mode set, we ignore.
      parser.feed([0x1B, 0x5B, 0x3F, 0x31, 0x30, 0x30, 0x30, 0x68], sink);
      parser.flush(sink);
      expect(sink.events, isEmpty);
    });

    test('an ESC aborting an in-progress CSI restarts a new sequence', () {
      // ESC [ ESC [ A in one read — e.g. Alt+[ then arrow within the flush
      // debounce, or a truncated CSI abutting the next report on a lossy link.
      // The aborting ESC must restart a sequence (ECMA-48), so the trailing
      // ESC [ A decodes as arrowUp — not swallowed and re-parsed as the typed
      // text "[" then "A".
      expect(_parse([0x1B, 0x5B, 0x1B, 0x5B, 0x41]), [
        const KeyEvent(KeyCode.arrowUp),
      ]);
    });

    test('an ESC aborting a CSI can restart a lone-ESC keypress', () {
      // ESC [ ESC then idle: the first CSI is aborted by the ESC, which is then
      // resolved as the escape key on flush (not discarded).
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([0x1B, 0x5B, 0x1B], sink);
      expect(sink.events, isEmpty);
      parser.flush(sink);
      expect(sink.events, [const KeyEvent(KeyCode.escape)]);
    });
  });

  group('Bracketed paste', () {
    // ESC [ 200 ~ ... ESC [ 201 ~
    List<int> start() => [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E];
    List<int> end() => [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E];

    test('wraps multi-line content into one PasteEvent (no Enter chords)', () {
      final events = _parse([...start(), ...'a\nb\nc'.codeUnits, ...end()]);
      expect(events, [const PasteEvent('a\nb\nc')]);
      // Crucially the embedded newlines did NOT become enter key events.
      expect(events.whereType<KeyEvent>(), isEmpty);
    });

    test('content that contains partial terminator bytes is preserved', () {
      // "x" + a near-miss of the terminator ("ESC[201" without the ~) + "y".
      final near = [0x1B, 0x5B, 0x32, 0x30, 0x31]; // ESC [ 2 0 1  (no ~)
      final events = _parse([...start(), 0x78, ...near, 0x79, ...end()]);
      expect(events.single, isA<PasteEvent>());
      expect((events.single as PasteEvent).text, 'x\x1B[201y');
    });

    test('paste split across feeds reassembles', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([...start(), ...'hel'.codeUnits], sink);
      expect(sink.events, isEmpty); // still mid-paste
      parser.feed([...'lo'.codeUnits, ...end()], sink);
      expect(sink.events, [const PasteEvent('hello')]);
    });

    test('idle flush does not terminate a fragmented bracketed paste', () {
      final parser = InputParser();
      final sink = _ListSink();

      parser.feed([...start(), ...'ab'.codeUnits], sink);
      parser.flush(sink); // a slow PTY pauses longer than the ESC timeout
      parser.feed([...'cd'.codeUnits, ...end()], sink);

      expect(sink.events, [const PasteEvent('abcd')]);
      expect(sink.events.whereType<KeyEvent>(), isEmpty);
      expect(sink.events.whereType<TextInputEvent>(), isEmpty);
    });

    test('stream finish finalizes a truncated bracketed paste', () {
      final parser = InputParser(maxPasteBytes: 4);
      final sink = _ListSink();

      parser.feed([...start(), ...'abcdef'.codeUnits], sink);
      parser.finish(sink);

      final paste = sink.events.whereType<PasteEvent>().toList();
      expect(paste.map((event) => event.text), ['abcd', 'ef']);
      expect(paste.map((event) => event.phase), [
        PasteEventPhase.start,
        PasteEventPhase.end,
      ]);
      expect(paste.map((event) => event.pasteId).toSet(), hasLength(1));
    });

    test('stream finish preserves a partial paste terminator as content', () {
      final parser = InputParser();
      final sink = _ListSink();

      parser.feed([...start(), ...'ab\x1B[20'.codeUnits], sink);
      parser.finish(sink);

      expect(sink.events, [const PasteEvent('ab\x1B[20')]);
    });

    test('idle flush never terminates a paste (anti-split fix preserved)', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([...start(), ...'ab'.codeUnits], sink);
      expect(parser.isPasting, isTrue);
      // Many 30ms ESC-debounce flushes must NOT split the paste into keys.
      for (var i = 0; i < 100; i++) {
        parser.flush(sink);
      }
      expect(sink.events, isEmpty);
      expect(parser.isPasting, isTrue);
    });

    test('flushPaste finalizes an abandoned paste and restores control', () {
      // The paste source died after ESC[200~ (the ESC[201~ terminator never
      // arrives), so the parser is stuck in paste state and would swallow every
      // later key — including Ctrl+C (ISIG is off in raw mode). A prolonged
      // inactivity finalize emits the pending paste and returns to ground.
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([...start(), ...'hello'.codeUnits], sink);
      expect(sink.events, isEmpty);
      expect(parser.isPasting, isTrue);

      parser.flushPaste(sink);
      expect(sink.events, [const PasteEvent('hello')]);
      expect(parser.isPasting, isFalse);

      // Keyboard control is back: Ctrl+C is now delivered, not eaten as paste.
      parser.feed([0x03], sink);
      expect(
        sink.events.last,
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
    });

    test('flushPaste is a no-op when not mid-paste', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed('hi'.codeUnits, sink);
      parser.flushPaste(sink);
      expect(sink.events, [
        const TextInputEvent('h'),
        const TextInputEvent('i'),
      ]);
    });
  });

  group('SGR mouse', () {
    // CSI < Cb ; Cx ; Cy (M=press/down, m=release).
    List<int> sgr(int cb, int cx, int cy, String fin) => [
      0x1B,
      0x5B,
      0x3C,
      ...'$cb;$cx;$cy$fin'.codeUnits,
    ];

    test('left button press decodes to a down at 0-based coords', () {
      expect(_parse(sgr(0, 10, 5, 'M')), [
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 9,
          row: 4,
        ),
      ]);
    });

    test('release (m) decodes to an up', () {
      expect(
        _parse(sgr(0, 3, 3, 'm')).single,
        isA<MouseEvent>().having((e) => e.kind, 'kind', MouseEventKind.up),
      );
    });

    test('wheel up/down decode (Cb 64/65)', () {
      expect(
        (_parse(sgr(64, 1, 1, 'M')).single as MouseEvent).kind,
        MouseEventKind.scrollUp,
      );
      expect(
        (_parse(sgr(65, 1, 1, 'M')).single as MouseEvent).kind,
        MouseEventKind.scrollDown,
      );
    });

    test('drag (motion bit 32 + button) decodes', () {
      final e = _parse(sgr(32, 2, 2, 'M')).single as MouseEvent;
      expect(e.kind, MouseEventKind.drag);
      expect(e.button, MouseButton.left);
    });

    test('modifier bits populate shift/alt/ctrl', () {
      // Cb = left(0) + shift(4) + ctrl(16) = 20.
      final e = _parse(sgr(20, 1, 1, 'M')).single as MouseEvent;
      expect(e.hasShift, isTrue);
      expect(e.hasCtrl, isTrue);
      expect(e.hasAlt, isFalse);
    });

    test('horizontal wheel (Cb 66/67) is not reported as vertical scroll', () {
      // SGR encodes wheel-left as 66 and wheel-right as 67. The decoder must
      // NOT treat them as scrollUp/scrollDown (a horizontal trackpad swipe
      // scrolling a ListView vertically). With no horizontal MouseEventKind,
      // the correct behaviour is to drop them rather than mis-report the axis.
      expect(
        _parse(sgr(66, 1, 1, 'M')).whereType<MouseEvent>(),
        isEmpty,
        reason: 'wheel-left must not become a vertical scroll',
      );
      expect(
        _parse(sgr(67, 1, 1, 'M')).whereType<MouseEvent>(),
        isEmpty,
        reason: 'wheel-right must not become a vertical scroll',
      );
      // Vertical wheel (64/65) is unaffected.
      expect(
        (_parse(sgr(64, 1, 1, 'M')).single as MouseEvent).kind,
        MouseEventKind.scrollUp,
      );
      expect(
        (_parse(sgr(65, 1, 1, 'M')).single as MouseEvent).kind,
        MouseEventKind.scrollDown,
      );
    });

    test('extended buttons 8-11 (Cb 128+) do not alias to left/middle/right', () {
      // SGR button 8 (mouse back/thumb) is cb=128. It must not decode as a left
      // click that activates whatever widget is under the cursor. We have no
      // back/forward button, so it reports MouseButton.none.
      final down = _parse(sgr(128, 3, 4, 'M')).single as MouseEvent;
      expect(down.button, MouseButton.none);
      expect(down.kind, MouseEventKind.down);
      expect(down.col, 2);
      expect(down.row, 3);
      // Buttons 9/10/11 (cb 129/130/131) likewise are not middle/right/none aliases.
      for (final cb in [128, 129, 130, 131]) {
        expect(
          (_parse(sgr(cb, 1, 1, 'M')).single as MouseEvent).button,
          MouseButton.none,
          reason: 'extended button cb=$cb must not alias to a primary button',
        );
      }
    });
  });

  group('Kitty keyboard protocol (CSI-u)', () {
    // CSI <params> u, where params are ';'-separated groups of ':'-separated
    // sub-params.
    List<int> csiu(String params) => [0x1B, 0x5B, ...'${params}u'.codeUnits];

    test('Ctrl+I is distinct from Tab', () {
      // mods = 1 + ctrl(4) = 5; 'i' = 105.
      expect(
        _parse(csiu('105;5')).single,
        const KeyEvent(KeyCode.char('i'), modifiers: {KeyModifier.ctrl}),
      );
      // Raw Tab still reads as the Tab key — the two are no longer conflated.
      expect(_parse([0x09]).single, const KeyEvent(KeyCode.tab));
    });

    test('lone Esc reports as the escape key without waiting for a flush', () {
      expect(_parse(csiu('27')).single, const KeyEvent(KeyCode.escape));
    });

    test('Ctrl+M is distinct from Enter', () {
      // 'm' = 109, ctrl.
      expect(
        _parse(csiu('109;5')).single,
        const KeyEvent(KeyCode.char('m'), modifiers: {KeyModifier.ctrl}),
      );
    });

    test('Ctrl+Enter maps to the Enter key with the ctrl modifier', () {
      // codepoint 13 is Enter even in CSI-u form.
      expect(
        _parse(csiu('13;5')).single,
        const KeyEvent(KeyCode.enter, modifiers: {KeyModifier.ctrl}),
      );
    });

    test('Ctrl+Shift+A carries both modifiers', () {
      // mods = 1 + shift(1) + ctrl(4) = 6; 'a' = 97.
      expect(
        _parse(csiu('97;6')).single,
        const KeyEvent(
          KeyCode.char('a'),
          modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        ),
      );
    });

    test('Super and Meta modifiers decode (cmd/meta chords)', () {
      // mods = 1 + super(8) = 9.
      expect(
        _parse(csiu('107;9')).single,
        const KeyEvent(KeyCode.char('k'), modifiers: {KeyModifier.superKey}),
      );
      // mods = 1 + meta(32) = 33.
      expect(
        _parse(csiu('107;33')).single,
        const KeyEvent(KeyCode.char('k'), modifiers: {KeyModifier.meta}),
      );
    });

    test('Alt+key decodes via the protocol', () {
      // mods = 1 + alt(2) = 3.
      expect(
        _parse(csiu('97;3')).single,
        const KeyEvent(KeyCode.char('a'), modifiers: {KeyModifier.alt}),
      );
    });

    group('event types', () {
      test('release sets type=up', () {
        // mods 5 (ctrl), event 3 (release).
        expect(
          _parse(csiu('97;5:3')).single,
          const KeyEvent(
            KeyCode.char('a'),
            modifiers: {KeyModifier.ctrl},
            type: KeyEventType.up,
          ),
        );
      });

      test('repeat sets type=repeat', () {
        expect(
          _parse(csiu('97;5:2')).single,
          const KeyEvent(
            KeyCode.char('a'),
            modifiers: {KeyModifier.ctrl},
            type: KeyEventType.repeat,
          ),
        );
      });

      test('a release of an unmodified text key is a key event, not text', () {
        // Phase retention (RFC 0020 §8.7): the printable's release carries
        // the key identity with no text. The dispatcher fences `up` from
        // commands; the regularizer and observation lanes consume it.
        expect(
          _parse(csiu('97;1:3')).single,
          const KeyEvent(KeyCode.char('a'), type: KeyEventType.up),
        );
      });

      test('event types thread through the legacy cursor-key form', () {
        // CSI 1 ; <mods:event> A → arrowUp.
        expect(
          _parse([0x1B, 0x5B, ...'1;5:3A'.codeUnits]).single,
          const KeyEvent(
            KeyCode.arrowUp,
            modifiers: {KeyModifier.ctrl},
            type: KeyEventType.up,
          ),
        );
      });
    });

    group('text-producing chords (flag 8 / report-all scenarios)', () {
      // A CSI-u printable is one physical report carrying key identity AND
      // text — it parses to a correlated InputBatch (RFC 0020 §5), so the
      // key half (with its position) survives alongside the committed text.
      test('an unmodified printable in CSI-u form is a correlated batch', () {
        expect(
          _parse(csiu('97')).single,
          const InputBatch(
            key: KeyEvent(KeyCode.char('a')),
            committedText: 'a',
          ),
        );
      });

      test('Shift + letter prefers the reported shifted codepoint', () {
        // key group "97:65" (a→A); mods 2 (shift).
        expect(
          _parse(csiu('97:65;2')).single,
          const InputBatch(
            key: KeyEvent(
              KeyCode.char('a'),
              modifiers: {KeyModifier.shift},
            ),
            committedText: 'A',
          ),
        );
      });

      test('the associated-text field is used when present', () {
        // codepoint 97, no modifiers, associated text 233 (é).
        expect(
          _parse(csiu('97;1;233')).single,
          const InputBatch(
            key: KeyEvent(KeyCode.char('a')),
            committedText: 'é',
          ),
        );
      });

      test('an empty shifted sub-param never becomes NUL text', () {
        // `97::119;2` — shift held, shifted field absent (empty → 0), base
        // present. The 0 means "absent", not codepoint 0.
        expect(
          _parse(csiu('97::119;2')).single,
          const InputBatch(
            key: KeyEvent(
              KeyCode.char('a'),
              modifiers: {KeyModifier.shift},
              position: KeyPosition.w,
            ),
            committedText: 'a',
          ),
        );
      });

      test('a printable down keeps its base-layout position in the batch', () {
        // AZERTY 'z' cap at QWERTY-W: primary 122, base 119, text 'z'.
        expect(
          _parse(csiu('122::119')).single,
          const InputBatch(
            key: KeyEvent(KeyCode.char('z'), position: KeyPosition.w),
            committedText: 'z',
          ),
        );
      });

      test('a printable repeat is a batch whose key half says repeat', () {
        // P2's repeat-without-down repair keys off exact phase retention.
        expect(
          _parse(csiu('97;1:2')).single,
          const InputBatch(
            key: KeyEvent(KeyCode.char('a'), type: KeyEventType.repeat),
            committedText: 'a',
          ),
        );
      });

      test('a shift-only release retains its modifiers', () {
        // Release A while Shift held: `97:65;2:3` — the up must carry
        // {shift} so P2's press records see symmetric down/up state.
        expect(
          _parse(csiu('97:65;2:3')).single,
          const KeyEvent(
            KeyCode.char('a'),
            modifiers: {KeyModifier.shift},
            type: KeyEventType.up,
          ),
        );
      });

      test('a key-0 repeat re-emits its text (auto-repeat types)', () {
        expect(_parse(csiu('0;1:2;233')).single, const TextInputEvent('é'));
      });

      test('control codes in associated text are rejected', () {
        // The spec forbids control codes in the text field; CR/ESC must not
        // smuggle into the text lane (`0;1;13` would otherwise type "\r").
        expect(_parse(csiu('0;1;13')), isEmpty);
        expect(_parse(csiu('97;1;27')), isEmpty);
      });

      test('a batch report fragmented across feeds parses whole', () {
        final parser = InputParser();
        final sink = _ListSink();
        final bytes = [0x1B, 0x5B, ...'122::119;1u'.codeUnits];
        for (final b in bytes) {
          parser.feed([b], sink);
        }
        expect(
          sink.events.single,
          const InputBatch(
            key: KeyEvent(KeyCode.char('z'), position: KeyPosition.w),
            committedText: 'z',
          ),
        );
      });

      test('the unmapped-PUA drop holds across the whole block', () {
        // Sweep the functional PUA block: every mapped codepoint yields a
        // KeyEvent; every unmapped one yields nothing — never text.
        for (var cp = 0xE000; cp <= 0xF8FF; cp += 7) {
          final events = _parse(csiu('$cp'));
          if (kittyFunctionalKeys.containsKey(cp) ||
              cp == 13 ||
              cp == 9 ||
              cp == 27 ||
              cp == 8 ||
              cp == 127) {
            expect(events.single, isA<KeyEvent>(), reason: 'cp $cp');
          } else {
            expect(events, isEmpty, reason: 'cp $cp');
          }
        }
      });
    });

    group('alternate keys (flag 4 — base-layout positions)', () {
      test('a modified chord carries its base-layout position', () {
        // AZERTY Ctrl+Z: primary 'z'(122), shifted absent, base 'w'(119).
        expect(
          _parse(csiu('122::119;5')).single,
          const KeyEvent(
            KeyCode.char('z'),
            modifiers: {KeyModifier.ctrl},
            position: KeyPosition.w,
          ),
        );
      });

      test('a printable release carries its base-layout position', () {
        expect(
          _parse(csiu('122::119;1:3')).single,
          const KeyEvent(
            KeyCode.char('z'),
            type: KeyEventType.up,
            position: KeyPosition.w,
          ),
        );
      });

      test('the Cyrillic chord case: Ctrl+С carries base c', () {
        // с = U+0441 (1089); base-layout 'c' = 99 (the spec's own example).
        expect(
          _parse(csiu('1089::99;5')).single,
          const KeyEvent(
            KeyCode.char('с'),
            modifiers: {KeyModifier.ctrl},
            position: KeyPosition.c,
          ),
        );
      });

      test('an unmapped base codepoint leaves position null, never guessed', () {
        // Base 233 ('é') is no US-101 key.
        expect(
          _parse(csiu('101::233;5')).single,
          const KeyEvent(KeyCode.char('e'), modifiers: {KeyModifier.ctrl}),
        );
      });
    });

    group('functional vocabulary (PUA table)', () {
      test('extended function keys decode', () {
        expect(_parse(csiu('57376')).single, const KeyEvent(KeyCode.f13));
        expect(
          _parse(csiu('57398;5')).single,
          const KeyEvent(KeyCode.f35, modifiers: {KeyModifier.ctrl}),
        );
      });

      test('KP Enter is distinct from Enter — nothing silently folded', () {
        expect(
          _parse(csiu('57414')).single,
          const KeyEvent(KeyCode.keypadEnter),
        );
      });

      test('lone modifier keys decode with phases', () {
        expect(_parse(csiu('57441')).single, const KeyEvent(KeyCode.leftShift));
        expect(
          _parse(csiu('57441;1:3')).single,
          const KeyEvent(KeyCode.leftShift, type: KeyEventType.up),
        );
      });

      test('media and lock keys decode', () {
        expect(
          _parse(csiu('57428')).single,
          const KeyEvent(KeyCode.mediaPlay),
        );
        expect(_parse(csiu('57358')).single, const KeyEvent(KeyCode.capsLock));
      });

      test('an unmapped PUA codepoint is dropped, never emitted as text', () {
        expect(_parse(csiu('57500')), isEmpty);
        expect(_parse(csiu('58000;5')), isEmpty);
      });
    });

    group('key number 0 (text with no key identity)', () {
      test('emits the associated text alone', () {
        // key 0, no mods, text 'é'.
        expect(_parse(csiu('0;1;233')).single, const TextInputEvent('é'));
      });

      test('with no text, emits nothing', () {
        expect(_parse(csiu('0')), isEmpty);
        expect(_parse(csiu('0;1')), isEmpty);
      });

      test('a release with text emits nothing', () {
        expect(_parse(csiu('0;1:3;233')), isEmpty);
      });
    });

    test('a protocol flags reply (CSI ? flags u) is ignored', () {
      expect(_parse([0x1B, 0x5B, ...'?5u'.codeUnits]), isEmpty);
    });

    test('invalid Unicode scalars fail closed and the parser recovers', () {
      for (final params in <String>[
        '1114112', // one above Unicode max
        '55296', // leading surrogate, not a Unicode scalar
        '97:1114112;2', // invalid shifted codepoint
        '97;1;1114112', // invalid associated text
        '0;1;55296', // key-0 report with a surrogate in its text
      ]) {
        expect(
          _parse([...csiu(params), 0x71]),
          [const TextInputEvent('q')],
          reason: 'invalid CSI $params u must be ignored without throwing',
        );
      }
    });
  });

  group('Fuzzing', () {
    test('seeded byte soup never throws and produces bounded events', () {
      final rng = Random(0xF1EAF00D);

      for (var caseIndex = 0; caseIndex < 250; caseIndex += 1) {
        final parser = InputParser();
        final sink = _ListSink();
        final bytes = _randomInputBytes(rng);
        var offset = 0;

        while (offset < bytes.length) {
          final remaining = bytes.length - offset;
          final chunkLength = 1 + rng.nextInt(remaining.clamp(1, 12).toInt());
          parser.feed(bytes.sublist(offset, offset + chunkLength), sink);
          offset += chunkLength;
          if (rng.nextInt(4) == 0) parser.flush(sink);
        }
        parser.flush(sink);

        expect(
          sink.events.length,
          lessThanOrEqualTo(bytes.length + 1),
          reason: 'fuzz case $caseIndex should not amplify input bytes',
        );
      }
    });

    test('large unterminated paste remains bounded across idle flush', () {
      final parser = InputParser();
      final sink = _ListSink();
      parser.feed([
        0x1B,
        0x5B,
        ...'200~'.codeUnits,
        ...List<int>.filled(4096, 0x78),
      ], sink);

      expect(sink.events, isEmpty);
      parser.flush(sink);
      expect(sink.events, isEmpty);

      parser.feed('\x1B[201~'.codeUnits, sink);
      expect(sink.events, hasLength(1));
      expect((sink.events.single as PasteEvent).text.length, 4096);
    });

    test('oversized paste is emitted in bounded segments', () {
      final parser = InputParser(maxPasteBytes: 4);
      final sink = _ListSink();

      parser.feed([
        ...'\x1B[200~'.codeUnits,
        ...'abcdefghij'.codeUnits,
        ...'\x1B[201~'.codeUnits,
      ], sink);

      expect(sink.events.whereType<PasteEvent>().map((event) => event.text), [
        'abcd',
        'efgh',
        'ij',
      ]);
      final segments = sink.events.whereType<PasteEvent>().toList();
      expect(segments.map((event) => event.phase), [
        PasteEventPhase.start,
        PasteEventPhase.continuation,
        PasteEventPhase.end,
      ]);
      expect(segments.map((event) => event.pasteId).toSet(), hasLength(1));
    });

    test('an exact-cap paste emits an empty final phase marker', () {
      final parser = InputParser(maxPasteBytes: 4);
      final sink = _ListSink();

      parser.feed('\x1B[200~abcd\x1B[201~'.codeUnits, sink);

      final paste = sink.events.whereType<PasteEvent>().toList();
      expect(paste.map((event) => event.text), ['abcd', '']);
      expect(paste.map((event) => event.phase), [
        PasteEventPhase.start,
        PasteEventPhase.end,
      ]);
      expect(paste[0].pasteId, paste[1].pasteId);
    });

    test('consecutive segmented pastes receive distinct identities', () {
      final parser = InputParser(maxPasteBytes: 2);
      final sink = _ListSink();

      parser.feed('\x1B[200~abc\x1B[201~'.codeUnits, sink);
      parser.feed('\x1B[200~def\x1B[201~'.codeUnits, sink);

      final starts = sink.events
          .whereType<PasteEvent>()
          .where((event) => event.phase == PasteEventPhase.start)
          .toList();
      expect(starts, hasLength(2));
      expect(starts[0].pasteId, isNot(starts[1].pasteId));
    });

    test('paste segmentation never splits a UTF-8 scalar', () {
      final parser = InputParser(maxPasteBytes: 4);
      final sink = _ListSink();
      const text = 'abcé🙂tail';

      parser.feed([
        ...'\x1B[200~'.codeUnits,
        ...utf8.encode(text),
        ...'\x1B[201~'.codeUnits,
      ], sink);

      final segments = sink.events
          .whereType<PasteEvent>()
          .map((event) => event.text)
          .toList();
      expect(segments.join(), text);
      expect(segments.join(), isNot(contains(replacementCharacter)));
    });

    test('paste segmentation never splits paired newline encodings', () {
      for (final lineEnding in ['\r\n', '\n\r']) {
        final parser = InputParser(maxPasteBytes: 4);
        final sink = _ListSink();
        final text = 'abc${lineEnding}def';

        parser.feed([
          ...'\x1B[200~'.codeUnits,
          ...text.codeUnits,
          ...'\x1B[201~'.codeUnits,
        ], sink);

        expect(sink.events.whereType<PasteEvent>().map((event) => event.text), [
          'abc',
          '${lineEnding}de',
          'f',
        ]);
      }
    });
  });

  group('resource bounds', () {
    test('overlong CSI is discarded through its final byte', () {
      final parser = InputParser(maxCsiSequenceLength: 4);
      final sink = _ListSink();

      // The first byte over the cap is itself the final `A`; `q` must be
      // processed from ground rather than swallowed as the discard final.
      parser.feed('\x1B[1234Aq'.codeUnits, sink);

      expect(
        sink.events.whereType<TextInputEvent>().map((event) => event.text),
        ['q'],
        reason: 'discarded CSI parameters must not become text events',
      );
      expect(sink.events.whereType<KeyEvent>(), isEmpty);
    });
  });
}

List<int> _randomInputBytes(Random rng) {
  final bytes = <int>[];
  final targetLength = rng.nextInt(180);
  while (bytes.length < targetLength) {
    switch (rng.nextInt(8)) {
      case 0:
        bytes.add(rng.nextInt(256));
        break;
      case 1:
        bytes.addAll([0x1B, 0x5B]);
        final paramBytes = 1 + rng.nextInt(12);
        for (var i = 0; i < paramBytes; i += 1) {
          bytes.add([0x30 + rng.nextInt(10), 0x3B, 0x3A, 0x3F][rng.nextInt(4)]);
        }
        if (rng.nextBool()) bytes.add(0x40 + rng.nextInt(0x3F));
        break;
      case 2:
        bytes.addAll([0x1B, 0x5D]);
        for (var i = 0; i < rng.nextInt(24); i += 1) {
          bytes.add(0x20 + rng.nextInt(0x5F));
        }
        if (rng.nextBool()) bytes.add(0x07);
        break;
      case 3:
        bytes.addAll([0x1B, 0x5B, ...'200~'.codeUnits]);
        for (var i = 0; i < rng.nextInt(80); i += 1) {
          bytes.add(rng.nextInt(256));
        }
        if (rng.nextBool()) bytes.addAll([0x1B, 0x5B, ...'201~'.codeUnits]);
        break;
      case 4:
        bytes.addAll([0xF0, 0x9F]);
        if (rng.nextBool()) bytes.add(0x99);
        break;
      case 5:
        bytes.addAll([0x1B, 0x4F, rng.nextInt(256)]);
        break;
      case 6:
        bytes.addAll([0x1B, 0x5B, 0x3C]);
        bytes.addAll(
          '${rng.nextInt(200)};${rng.nextInt(200)};'
                  '${rng.nextInt(80)}${rng.nextBool() ? 'M' : 'm'}'
              .codeUnits,
        );
        break;
      case 7:
        final count = 1 + rng.nextInt(16);
        for (var i = 0; i < count; i += 1) {
          bytes.add(0x20 + rng.nextInt(0x5F));
        }
        break;
    }
  }
  return bytes.take(targetLength).toList(growable: false);
}
