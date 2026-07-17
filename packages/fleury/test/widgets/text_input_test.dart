// TextInput integration tests. Driven by FleuryTester so input
// dispatch + focus + scheduler are wired uniformly with every other
// widget test in the suite.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

KeyEvent _code(KeyCode kc) => KeyEvent(keyCode: kc);
KeyEvent _shiftCode(KeyCode kc) =>
    KeyEvent(keyCode: kc, modifiers: const {KeyModifier.shift});
KeyEvent _ctrlChar(String c) =>
    KeyEvent(char: c, modifiers: const {KeyModifier.ctrl});

final class _DispatcherSink implements TuiEventSink {
  const _DispatcherSink(this.dispatcher);

  final InputDispatcher dispatcher;

  @override
  void add(TuiEvent event) {
    dispatcher.dispatch(event);
  }
}

void main() {
  group('TextInput receives insertable text', () {
    testWidgets('typing letters accumulates into the controller', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.type('h');
      tester.type('i');
      expect(controller.text, 'hi');
      expect(controller.caretOffset, 2);
    });

    testWidgets('cursor advances with every character', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.type('a');
      expect(controller.caretOffset, 1);
      tester.type('b');
      expect(controller.caretOffset, 2);
    });
  });

  group('special chords', () {
    testWidgets('backspace deletes the previous character', (tester) {
      final controller = TextEditingController(text: 'hello');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.sendKey(_code(KeyCode.backspace));
      expect(controller.text, 'hell');
      expect(controller.caretOffset, 4);
    });

    testWidgets('arrow chords move the cursor', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));
      expect(controller.caretOffset, 3);

      tester.sendKey(_code(KeyCode.arrowLeft));
      expect(controller.caretOffset, 2);
      tester.sendKey(_code(KeyCode.home));
      expect(controller.caretOffset, 0);
      tester.sendKey(_code(KeyCode.end));
      expect(controller.caretOffset, 3);
    });

    testWidgets('horizontal arrows bubble at text edges for focus traversal', (
      tester,
    ) {
      final controller = TextEditingController(text: 'abc');
      final next = FocusNode(debugLabel: 'next');
      addTearDown(next.dispose);

      tester.pumpWidget(
        FocusTraversalGroup(
          child: Row(
            children: [
              SizedBox(
                width: 6,
                child: TextInput(controller: controller, autofocus: true),
              ),
              const SizedBox(width: 2),
              Focus(focusNode: next, child: const Text('Next')),
            ],
          ),
        ),
      );

      tester.render(size: const CellSize(20, 3));
      expect(controller.caretOffset, 3);

      tester.sendKey(_code(KeyCode.arrowRight));
      tester.pump();

      expect(next.hasFocus, isTrue);
    });

    testWidgets('backspace and arrows respect grapheme clusters', (tester) {
      final controller = TextEditingController(text: 'a🙂b');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.sendKey(_code(KeyCode.arrowLeft));
      expect(controller.caretOffset, 3);
      tester.sendKey(_code(KeyCode.backspace));
      expect(controller.text, 'ab');
      expect(controller.caretOffset, 1);
    });

    testWidgets('Shift+arrows extend and render a selection range', (tester) {
      final controller = TextEditingController(text: 'abcd')..caretOffset = 1;
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
      );

      tester.sendKey(_shiftCode(KeyCode.arrowRight));
      tester.sendKey(_shiftCode(KeyCode.arrowRight));

      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );
      final buf = tester.render(size: const CellSize(6, 1));
      expect(buf.atColRow(0, 0).style.inverse, isFalse);
      expect(buf.atColRow(1, 0).style.inverse, isTrue);
      expect(buf.atColRow(2, 0).style.inverse, isTrue);
      expect(buf.atColRow(3, 0).style.inverse, isFalse);

      tester.type('X');
      expect(controller.text, 'aXd');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
    });

    testWidgets('keymap presets can add Emacs-style movement', (tester) {
      final controller = TextEditingController(text: 'abc')..caretOffset = 3;
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          keymap: TextEditingKeymap.emacsSingleLine,
        ),
      );

      tester.sendKey(_ctrlChar('a'));
      expect(controller.caretOffset, 0);

      tester.sendKey(_ctrlChar('e'));
      expect(controller.caretOffset, 3);
    });

    testWidgets('emacs kill ring: Ctrl+K kills to end, Ctrl+Y yanks back', (
      tester,
    ) {
      final controller = TextEditingController(text: 'hello world')
        ..caretOffset = 5;
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          keymap: TextEditingKeymap.emacsSingleLine,
        ),
      );
      tester.sendKey(_ctrlChar('k')); // kill " world"
      expect(controller.text, 'hello');
      expect(TextEditingModel.killRing, ' world');
      tester.sendKey(_ctrlChar('y')); // yank it back at the caret
      expect(controller.text, 'hello world');
      expect(controller.caretOffset, 11);
    });

    testWidgets('emacs Ctrl+W kills the previous word; Ctrl+U to line start', (
      tester,
    ) {
      final controller = TextEditingController(text: 'one two three')
        ..caretOffset = 13;
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          keymap: TextEditingKeymap.emacsSingleLine,
        ),
      );
      tester.sendKey(_ctrlChar('w')); // kill "three"
      expect(controller.text, 'one two ');
      tester.sendKey(_ctrlChar('u')); // kill from line start to caret
      expect(controller.text, '');
    });

    testWidgets('Ctrl+arrows move by word through the default keymap', (
      tester,
    ) {
      final controller = TextEditingController(text: 'run deploy now')
        ..caretOffset = 14;
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowLeft,
          modifiers: {KeyModifier.ctrl},
        ),
      );
      expect(controller.caretOffset, 11);

      tester.sendKey(
        const KeyEvent(
          keyCode: KeyCode.arrowLeft,
          modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        ),
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 11, extentOffset: 4),
      );
    });

    testWidgets('Enter fires onSubmit with the current text', (tester) {
      String? submitted;
      final controller = TextEditingController(text: 'send me');
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          onSubmit: (t) => submitted = t,
        ),
      );

      tester.sendKey(_code(KeyCode.enter));
      expect(submitted, 'send me');
    });

    testWidgets('Ctrl+Z and Ctrl+Y undo and redo edits', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.type('a');
      tester.type('b');
      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');

      tester.sendKey(_ctrlChar('y'));
      expect(controller.text, 'ab');
    });

    testWidgets('Escape calls onEscape when provided', (tester) {
      var escapes = 0;
      tester.pumpWidget(
        TextInput(autofocus: true, onEscape: () => escapes += 1),
      );

      tester.sendKey(_code(KeyCode.escape));
      expect(escapes, 1);
    });

    testWidgets('Escape with no onEscape bubbles up to ancestor '
        'bindings', (tester) {
      var escapes = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.key(KeyCode.escape),
              onEvent: (_) => escapes += 1,
            ),
          ],
          child: const TextInput(autofocus: true),
        ),
      );

      tester.sendKey(_code(KeyCode.escape));
      expect(escapes, 1);
    });
  });

  group('history navigation', () {
    testWidgets('Up and Down browse opt-in submission history', (tester) {
      final controller = TextEditingController(text: 'draft');
      final history = TextHistoryController(entries: ['one', 'two']);
      tester.pumpWidget(
        TextInput(
          controller: controller,
          historyController: history,
          autofocus: true,
        ),
      );

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(controller.text, 'two');
      expect(controller.caretOffset, 3);
      expect(history.isBrowsing, isTrue);
      expect(history.selectedIndex, 1);

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(controller.text, 'one');
      expect(history.selectedIndex, 0);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.text, 'two');
      expect(history.selectedIndex, 1);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.text, 'draft');
      expect(history.isBrowsing, isFalse);
    });

    testWidgets('history snapshots the complete accepted paste draft', (
      tester,
    ) {
      final controller = TextEditingController();
      final history = TextHistoryController(entries: ['previous']);
      tester.pumpWidget(
        TextInput(
          controller: controller,
          historyController: history,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 0,
            chunkSize: 2,
          ),
        ),
      );

      tester.paste('abcdef');
      expect(controller.text, 'ab');

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(controller.text, 'previous');
      tester.sendKey(_code(KeyCode.arrowDown));
      expect(
        controller.text,
        'abcdef',
        reason: 'history must retain the full accepted draft, not its prefix',
      );
    });

    testWidgets('Up bubbles when no history controller is provided', (tester) {
      var ancestorUps = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyChord.up, onEvent: (_) => ancestorUps += 1)],
          child: const TextInput(autofocus: true),
        ),
      );

      tester.sendKey(_code(KeyCode.arrowUp));

      expect(ancestorUps, 1);
    });

    testWidgets('Enter commits submitted text before onSubmit runs', (tester) {
      final controller = TextEditingController(text: 'deploy');
      final history = TextHistoryController();
      String? submitted;
      tester.pumpWidget(
        TextInput(
          controller: controller,
          historyController: history,
          autofocus: true,
          onSubmit: (text) {
            submitted = text;
            controller.clear();
          },
        ),
      );

      tester.sendKey(_code(KeyCode.enter));

      expect(submitted, 'deploy');
      expect(history.entries, ['deploy']);
      expect(controller.text, '');
    });

    testWidgets('typing while browsing history restores normal Down bubbling', (
      tester,
    ) {
      var ancestorDowns = 0;
      final controller = TextEditingController(text: 'draft');
      final history = TextHistoryController(entries: ['one', 'two']);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.down, onEvent: (_) => ancestorDowns += 1),
          ],
          child: TextInput(
            controller: controller,
            historyController: history,
            autofocus: true,
          ),
        ),
      );

      tester.sendKey(_code(KeyCode.arrowUp));
      expect(controller.text, 'two');
      expect(history.isBrowsing, isTrue);

      tester.type('x');
      expect(controller.text, 'twox');
      expect(history.isBrowsing, isFalse);

      tester.sendKey(_code(KeyCode.arrowDown));
      expect(controller.text, 'twox');
      expect(ancestorDowns, 1);
    });
  });

  group('completion scaffolding', () {
    testWidgets('Tab accepts the selected completion', (tester) {
      final controller = TextEditingController(text: 'git che');
      final completions = TextCompletionController()
        ..open(
          range: const TextRange(start: 4, end: 7),
          query: 'che',
          options: const [
            TextCompletionOption(
              label: 'checkout branch',
              replacement: 'checkout',
            ),
          ],
        );
      tester.pumpWidget(
        TextInput(
          controller: controller,
          completionController: completions,
          autofocus: true,
        ),
      );

      tester.sendKey(_code(KeyCode.tab));

      expect(controller.text, 'git checkout');
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
      expect(completions.isOpen, isFalse);

      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, 'git che');
    });

    testWidgets('completion reads its range after the accepted paste tail', (
      tester,
    ) {
      final controller = TextEditingController();
      final completions = TextCompletionController()
        ..open(
          range: TextRange.empty,
          options: const [TextCompletionOption(label: 'initial')],
        );
      tester.pumpWidget(
        TextInput(
          controller: controller,
          completionController: completions,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 0,
            chunkSize: 2,
          ),
          onChanged: (text) {
            completions.update(
              range: TextRange(start: 0, end: text.length),
              options: [
                TextCompletionOption(label: text, replacement: '<$text>'),
              ],
            );
          },
        ),
      );

      tester.paste('abcdef');
      expect(controller.text, 'ab');

      tester.sendKey(_code(KeyCode.tab));

      expect(
        controller.text,
        '<abcdef>',
        reason: 'completion must not apply a prefix-derived range or option',
      );
    });

    testWidgets('Up and Down move completion selection before history', (
      tester,
    ) {
      final controller = TextEditingController(text: 'git che');
      final history = TextHistoryController(entries: ['git status']);
      final completions = TextCompletionController()
        ..open(
          range: const TextRange(start: 4, end: 7),
          query: 'che',
          options: const [
            TextCompletionOption(
              label: 'checkout branch',
              replacement: 'checkout',
            ),
            TextCompletionOption(
              label: 'cherry-pick commit',
              replacement: 'cherry-pick',
            ),
          ],
        );
      tester.pumpWidget(
        TextInput(
          controller: controller,
          historyController: history,
          completionController: completions,
          autofocus: true,
        ),
      );

      tester.sendKey(_code(KeyCode.arrowDown));

      expect(completions.selectedIndex, 1);
      expect(history.isBrowsing, isFalse);
      expect(controller.text, 'git che');

      tester.sendKey(_code(KeyCode.tab));

      expect(controller.text, 'git cherry-pick');
      expect(completions.isOpen, isFalse);
    });

    testWidgets('Escape closes completion before calling onEscape', (tester) {
      var escapes = 0;
      final completions = TextCompletionController()
        ..open(
          range: const TextRange.collapsed(0),
          options: const [TextCompletionOption(label: 'one')],
        );
      tester.pumpWidget(
        TextInput(
          completionController: completions,
          autofocus: true,
          onEscape: () => escapes += 1,
        ),
      );

      tester.sendKey(_code(KeyCode.escape));

      expect(completions.isOpen, isFalse);
      expect(escapes, 0);

      tester.sendKey(_code(KeyCode.escape));
      expect(escapes, 1);
    });

    testWidgets('Tab bubbles when completion has no selected option', (tester) {
      var tabs = 0;
      final completions = TextCompletionController()
        ..open(range: const TextRange.collapsed(0));
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyChord.tab, onEvent: (_) => tabs += 1)],
          child: TextInput(completionController: completions, autofocus: true),
        ),
      );

      tester.sendKey(_code(KeyCode.tab));

      expect(tabs, 1);
      expect(completions.isOpen, isTrue);
    });
  });

  group('modifier chord bypass', () {
    testWidgets('Ctrl+S reaches ancestor KeyBindings, NOT the text '
        'input', (tester) {
      // Per RFC 0008 §6.7: modifier chords are KeyEvents and travel
      // through the focus chain. They do NOT get claimed by the
      // text input.
      var saves = 0;
      final controller = TextEditingController();
      tester.pumpWidget(
        KeyBindings(
          bindings: [KeyBinding(KeyChord.ctrl.s, onEvent: (_) => saves += 1)],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      tester.sendKey(_ctrlChar('s'));
      expect(saves, 1);
      // Text input did NOT receive 's' as a character.
      expect(controller.text, '');
    });
  });

  group('external focusNode', () {
    testWidgets('uses the supplied node and still claims text input', (tester) {
      final focusNode = FocusNode(debugLabel: 'external');
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(controller: controller, focusNode: focusNode),
      );
      focusNode.requestFocus();

      tester.type('x');
      expect(controller.text, 'x');
    });
  });

  group('text input precedence over leader sequences', () {
    testWidgets('typing space when a Space-leader sequence is bound '
        'elsewhere goes into the text input', (tester) {
      // Acceptance test #16 from RFC 0008 §9 — text input wins over
      // ancestor sequences.
      var paletteOpens = 0;
      final controller = TextEditingController();
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.space.p, onEvent: (_) => paletteOpens += 1),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      // Space arrives as a TextInputEvent (parser converts printable
      // ASCII this way). Text input claims it first; the ancestor
      // sequence binding never starts pending state.
      tester.type(' ');
      expect(controller.text, ' ');
      expect(paletteOpens, 0);
      expect(tester.dispatcher.hasPendingSequence, isFalse);
    });
  });

  group('bracketed paste', () {
    testWidgets(
      'a multi-line paste collapses to one line and does not submit',
      (tester) {
        final controller = TextEditingController();
        var submits = 0;
        tester.pumpWidget(
          TextInput(
            controller: controller,
            autofocus: true,
            onSubmit: (_) => submits++,
          ),
        );
        tester.paste('one\ntwo\nthree');
        expect(controller.text, 'one two three', reason: 'newlines → spaces');
        expect(submits, 0, reason: 'paste must never submit');
      },
    );

    testWidgets('paste is one undoable transaction', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.paste('one\ntwo');
      expect(controller.text, 'one two');

      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');

      tester.sendKey(_ctrlChar('y'));
      expect(controller.text, 'one two');
    });

    testWidgets('large paste is chunked over post-frame pumps', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 3,
            chunkSize: 2,
          ),
        ),
      );

      tester.paste('abcdef');

      expect(controller.text, 'ab');
      var field = tester.semantics().single(role: SemanticRole.textField);
      expect(field.state.pasteInProgress, isTrue);
      expect(field.state.pasteInsertedLength, 2);
      expect(field.state.pasteTotalLength, 6);

      tester.pump();
      expect(controller.text, 'abcd');

      tester.pump();
      expect(controller.text, 'abcdef');

      tester.pump();
      field = tester.semantics().single(role: SemanticRole.textField);
      expect(field.state.pasteInProgress, isFalse);
      expect(field.state.pasteInsertedLength, 0);
      expect(field.state.pasteTotalLength, 0);

      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');
    });

    testWidgets(
      'a rapid second paste preserves the first tail as a separate undo',
      (tester) {
        final controller = TextEditingController();
        tester.pumpWidget(
          TextInput(
            controller: controller,
            autofocus: true,
            pastePolicy: const TextPastePolicy(
              largePasteThreshold: 0,
              chunkSize: 2,
            ),
          ),
        );

        tester.paste('abcdef');
        expect(
          controller.text,
          'ab',
          reason: 'the first paste is still active',
        );
        tester.paste('XY');

        for (var i = 0; i < 8; i++) {
          tester.pump();
        }
        expect(
          controller.text,
          'abcdefXY',
          reason: 'accepting a second paste must not discard the first tail',
        );

        tester.sendKey(_ctrlChar('z'));
        expect(controller.text, 'abcdef', reason: 'undo only the second paste');
        tester.sendKey(_ctrlChar('z'));
        expect(controller.text, '', reason: 'undo the complete first paste');

        tester.sendKey(_ctrlChar('y'));
        expect(controller.text, 'abcdef');
        tester.sendKey(_ctrlChar('y'));
        expect(controller.text, 'abcdefXY');
      },
    );

    testWidgets('parser-segmented paste is lossless and one undo transaction', (
      tester,
    ) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 100,
            chunkSize: 2,
          ),
        ),
      );

      final parser = InputParser(maxPasteBytes: 4);
      final sink = _DispatcherSink(tester.dispatcher);
      parser.feed('\x1B[200~abcd'.codeUnits, sink);
      expect(controller.text, 'abcd');

      // Each parser segment is below the widget's own chunking threshold and
      // arrives in a separate read. Phase/id, not timing or size heuristics,
      // must keep these inserts in one paste transaction.
      parser.feed('efgh'.codeUnits, sink);
      parser.feed('ijkl'.codeUnits, sink);
      parser.feed('\x1B[201~'.codeUnits, sink);
      expect(controller.text, 'abcdefghijkl');

      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');
    });

    testWidgets('segmented paste queue drains iteratively under burst input', (
      tester,
    ) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 0,
            chunkSize: 1,
          ),
        ),
      );

      const pasteId = 73;
      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'abcdefghij',
          pasteId: pasteId,
          phase: PasteEventPhase.start,
        ),
      );
      for (var i = 0; i < 2000; i++) {
        tester.dispatcher.dispatch(
          const PasteEvent.segment(
            'x',
            pasteId: pasteId,
            phase: PasteEventPhase.continuation,
          ),
        );
      }
      tester.dispatcher.dispatch(
        const PasteEvent.segment(
          'z',
          pasteId: pasteId,
          phase: PasteEventPhase.end,
        ),
      );

      for (var i = 0; i < 300; i++) {
        tester.pump();
      }
      expect(controller.text, 'abcdefghij${List.filled(2000, 'x').join()}z');
      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');
    });

    testWidgets(
      'segmented queue pressure performs bounded synchronous controller edits',
      (tester) {
        final controller = TextEditingController();
        tester.pumpWidget(
          TextInput(
            controller: controller,
            autofocus: true,
            pastePolicy: const TextPastePolicy(
              largePasteThreshold: 0,
              chunkSize: 1,
            ),
          ),
        );

        var notifications = 0;
        controller.addListener(() => notifications++);
        const pasteId = 991;
        tester.dispatcher.dispatch(
          PasteEvent.segment(
            List.filled(600, 'x').join(),
            pasteId: pasteId,
            phase: PasteEventPhase.start,
          ),
        );
        expect(notifications, 1, reason: 'the first chunk applies immediately');

        final beforePressure = notifications;
        tester.dispatcher.dispatch(
          PasteEvent.segment(
            List.filled(64 * 1024 + 1, 'y').join(),
            pasteId: pasteId,
            phase: PasteEventPhase.end,
          ),
        );
        final synchronousPressureEdits = notifications - beforePressure;

        expect(
          synchronousPressureEdits,
          lessThan(32),
          reason:
              'one over-bound segment must not synchronously drain hundreds '
              'of one-code-unit controller edits',
        );
      },
    );

    testWidgets('single-line large paste normalizes before chunking', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 3,
            chunkSize: 20,
          ),
        ),
      );

      tester.paste('one\r\ntwo\nthree');

      expect(controller.text, 'one two three');
    });

    testWidgets('undo during a scheduled paste preserves the full redo value', (
      tester,
    ) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 3,
            chunkSize: 2,
          ),
        ),
      );

      tester.paste('abcdef');
      expect(controller.text, 'ab');

      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');

      tester.pump();
      tester.pump();
      expect(controller.text, '');

      tester.sendKey(_ctrlChar('y'));
      expect(
        controller.text,
        'abcdef',
        reason:
            'undo must finish the accepted paste tail before recording redo',
      );
    });

    testWidgets('Escape callback observes the complete accepted paste', (
      tester,
    ) {
      final controller = TextEditingController();
      String? escapedValue;
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          onEscape: () => escapedValue = controller.text,
          pastePolicy: const TextPastePolicy(
            largePasteThreshold: 0,
            chunkSize: 2,
          ),
        ),
      );

      tester.paste('abcdef');
      expect(controller.text, 'ab');

      tester.sendKey(_code(KeyCode.escape));

      expect(escapedValue, 'abcdef');
      expect(controller.text, 'abcdef');
      tester.sendKey(_ctrlChar('z'));
      expect(controller.text, '');
    });
  });

  group('enabled and readOnly', () {
    testWidgets('semanticLabel and semanticState customize field semantics', (
      tester,
    ) {
      tester.pumpWidget(
        const TextInput(
          placeholder: 'example text',
          semanticLabel: 'Search query',
          semanticState: SemanticState({'fieldType': 'search'}),
        ),
      );

      final field = tester.semantics().single(
        role: SemanticRole.textField,
        label: 'Search query',
      );
      expect(field.state['fieldType'], 'search');
    });

    testWidgets('readOnly field consumes edits without mutating', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, readOnly: true),
      );

      tester.type('X');
      tester.paste('YZ');
      tester.sendKey(_code(KeyCode.backspace));
      expect(controller.text, 'abc');
      expect(controller.caretOffset, 3);

      tester.sendKey(_code(KeyCode.arrowLeft));
      expect(controller.caretOffset, 2);
    });

    testWidgets('disabled field does not autofocus or edit', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enabled: false),
      );

      tester.type('x');
      tester.paste('y');
      expect(controller.text, '');

      final field = tester.semantics().single(
        role: SemanticRole.textField,
        enabled: false,
      );
      expect(field.focused, isFalse);
    });

    testWidgets('a caller-provided focusNode keeps its own canRequestFocus '
        '(not clobbered by enabled)', (tester) {
      // TextInput's enabled↔focusable sync is only for a node it OWNS; a
      // provided node's flags belong to the caller. TextInput must not pass a
      // non-null canRequestFocus to its inner Focus (which would re-impose it
      // on the caller's node every rebuild).
      final controller = TextEditingController();
      final node = FocusNode(debugLabel: 'provided', canRequestFocus: false);
      addTearDown(node.dispose);

      tester.pumpWidget(TextInput(controller: controller, focusNode: node));
      tester.render(size: const CellSize(20, 1));
      expect(
        node.canRequestFocus,
        isFalse,
        reason: 'mount must not overwrite the provided flag',
      );

      // A rebuild (enabled defaults true) must not re-enable it either.
      tester.pumpWidget(
        TextInput(controller: controller, focusNode: node, placeholder: 'x'),
      );
      tester.render(size: const CellSize(20, 1));
      expect(
        node.canRequestFocus,
        isFalse,
        reason: 'rebuild must not re-impose enabled→focusable',
      );
    });
  });

  group('copy and cut', () {
    testWidgets('Ctrl+C copies selected text', (tester) async {
      final controller = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), 'bcd');
      expect(controller.text, 'abcdef');
    });

    testWidgets('Ctrl+X cuts selected text when editable', (tester) async {
      final controller = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));

      tester.sendKey(_ctrlChar('x'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), 'bcd');
      expect(controller.text, 'aef');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
    });

    testWidgets('Ctrl+C bubbles when there is no field selection', (tester) {
      var ancestorCopies = 0;
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.ctrl.c, onEvent: (_) => ancestorCopies += 1),
          ],
          child: TextInput(controller: controller, autofocus: true),
        ),
      );

      tester.sendKey(_ctrlChar('c'));

      expect(ancestorCopies, 1);
      expect(tester.clipboard.readInProcess(), isNull);
    });

    testWidgets('Ctrl+C bubbles only after completing an accepted paste', (
      tester,
    ) {
      var ancestorCopies = 0;
      final controller = TextEditingController();
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.ctrl.c, onEvent: (_) => ancestorCopies += 1),
          ],
          child: TextInput(
            controller: controller,
            autofocus: true,
            pastePolicy: const TextPastePolicy(
              largePasteThreshold: 0,
              chunkSize: 2,
            ),
          ),
        ),
      );

      tester.paste('abcdef');
      expect(controller.text, 'ab');

      tester.sendKey(_ctrlChar('c'));

      expect(controller.text, 'abcdef');
      expect(ancestorCopies, 1);
    });

    testWidgets('disabled clipboard policy blocks copy and bubbling', (
      tester,
    ) async {
      var ancestorCopies = 0;
      final controller = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.ctrl.c, onEvent: (_) => ancestorCopies += 1),
          ],
          child: TextInput(
            controller: controller,
            autofocus: true,
            clipboardPolicy: TextClipboardPolicy.disabled,
          ),
        ),
      );

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), isNull);
      expect(ancestorCopies, 0);
    });

    testWidgets('redacted clipboard policy copies obscured text', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'secret')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          obscureText: true,
          obscuringCharacter: '*',
        ),
      );

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '******');
    });

    testWidgets('readOnly field can copy but not cut', (tester) async {
      final controller = TextEditingController(text: 'abcdef')
        ..selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, readOnly: true),
      );

      tester.sendKey(_ctrlChar('c'));
      await Future<void>.delayed(Duration.zero);
      expect(tester.clipboard.readInProcess(), 'bcd');

      tester.sendKey(_ctrlChar('x'));
      await Future<void>.delayed(Duration.zero);
      expect(tester.clipboard.readInProcess(), 'bcd');
      expect(controller.text, 'abcdef');
    });
  });

  group('horizontal scrolling', () {
    testWidgets('publishes focused caret geometry in screen cells', (tester) {
      final focusNode = FocusNode(debugLabel: 'caret');
      addTearDown(focusNode.dispose);
      final controller = TextEditingController(text: 'abcdef');
      tester.pumpWidget(
        SizedBox(
          width: 4,
          child: TextInput(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            enableBlink: false,
          ),
        ),
      );

      tester.render(size: const CellSize(4, 1));

      expect(focusNode.caretRect, CellRect.fromLTWH(3, 0, 1, 1));
    });

    testWidgets('keeps the trailing cursor visible in bounded width', (tester) {
      final controller = TextEditingController(text: 'abcdef');
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
      );

      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, 'd');
      expect(buf.atColRow(1, 0).grapheme, 'e');
      expect(buf.atColRow(2, 0).grapheme, 'f');
      expect(buf.atColRow(3, 0).grapheme, ' ');
      expect(buf.atColRow(3, 0).style.inverse, isTrue);
    });

    testWidgets('scrolls back when the cursor moves to the start', (tester) {
      final controller = TextEditingController(text: 'abcdef');
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
      );
      tester.render(size: const CellSize(4, 1));

      tester.sendKey(_code(KeyCode.home));
      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, 'a');
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
      expect(buf.atColRow(1, 0).grapheme, 'b');
      expect(buf.atColRow(2, 0).grapheme, 'c');
      expect(buf.atColRow(3, 0).grapheme, 'd');
    });

    testWidgets('does not split a wide grapheme at the scroll boundary', (
      tester,
    ) {
      final controller = TextEditingController(text: 'ab🙂cd');
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
      );

      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, 'c');
      expect(buf.atColRow(1, 0).grapheme, 'd');
      expect(buf.atColRow(2, 0).grapheme, ' ');
      expect(buf.atColRow(2, 0).style.inverse, isTrue);
      expect(buf.atColRow(3, 0).grapheme, isNull);
    });

    testWidgets('scrolls obscured fields using obscured display width', (
      tester,
    ) {
      final controller = TextEditingController(text: 'secret');
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          enableBlink: false,
          obscureText: true,
          obscuringCharacter: '*',
        ),
      );

      final buf = tester.render(size: const CellSize(4, 1));

      expect(buf.atColRow(0, 0).grapheme, '*');
      expect(buf.atColRow(1, 0).grapheme, '*');
      expect(buf.atColRow(2, 0).grapheme, '*');
      expect(buf.atColRow(3, 0).grapheme, ' ');
      expect(buf.atColRow(3, 0).style.inverse, isTrue);
    });

    testWidgets('keeps the active end of a selection visible', (tester) {
      final controller = TextEditingController(text: 'abcdefgh')
        ..selection = const TextSelection(baseOffset: 3, extentOffset: 8);
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
      );

      final buf = tester.render(size: const CellSize(5, 1));

      expect(buf.atColRow(0, 0).grapheme, 'e');
      expect(buf.atColRow(1, 0).grapheme, 'f');
      expect(buf.atColRow(2, 0).grapheme, 'g');
      expect(buf.atColRow(3, 0).grapheme, 'h');
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
      expect(buf.atColRow(3, 0).style.inverse, isTrue);
    });
  });

  group('onChanged', () {
    testWidgets('fires on each edit with the new text', (tester) {
      final changes = <String>[];
      tester.pumpWidget(TextInput(autofocus: true, onChanged: changes.add));

      tester.type('h');
      tester.type('i');
      tester.sendKey(_code(KeyCode.backspace));

      expect(changes, ['h', 'hi', 'h']);
    });

    testWidgets('does not fire on cursor-only moves', (tester) {
      final changes = <String>[];
      tester.pumpWidget(TextInput(autofocus: true, onChanged: changes.add));

      tester.type('a');
      tester.type('b');
      changes.clear();

      tester.sendKey(_code(KeyCode.arrowLeft));
      tester.sendKey(_code(KeyCode.home));
      tester.sendKey(_code(KeyCode.end));

      expect(changes, isEmpty);
    });

    testWidgets('fires for a programmatic controller edit (loop-safe)', (
      tester,
    ) {
      final changes = <String>[];
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(controller: controller, onChanged: changes.add),
      );

      controller.text = 'seed';
      tester.pump();
      controller.text = 'seed'; // same value must not re-fire
      tester.pump();

      expect(changes, ['seed']);
    });
  });

  group('placeholder', () {
    testWidgets('shows the placeholder while empty, dimmed', (tester) {
      tester.pumpWidget(const TextInput(placeholder: 'search…'));
      final out = tester.renderToString(
        size: const CellSize(10, 1),
        emptyMark: ' ',
      );
      expect(out.trimRight(), 'search…');
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(1, 0).style.dim, isTrue, reason: 'placeholder dim');
    });

    testWidgets('typing replaces the placeholder with the text', (tester) {
      final controller = TextEditingController();
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, placeholder: 'name'),
      );
      tester.type('A');
      final out = tester.renderToString(
        size: const CellSize(10, 1),
        emptyMark: ' ',
      );
      expect(out.contains('name'), isFalse, reason: 'placeholder gone');
      expect(out.trimRight(), 'A');
    });

    testWidgets('the cursor sits over the placeholder when focused', (tester) {
      tester.pumpWidget(
        const TextInput(autofocus: true, enableBlink: false, placeholder: 'go'),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      // First placeholder cell carries the cursor (inverse) merged onto dim.
      expect(buf.atColRow(0, 0).grapheme, 'g');
      expect(buf.atColRow(0, 0).style.inverse, isTrue);
      expect(buf.atColRow(1, 0).style.inverse, isFalse);
    });
  });
}
