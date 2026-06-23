// Locks the human-factor additions: Colors named constants,
// Container.color, runTui's Widget-not-factory signature.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('Colors named constants', () {
    test('the 8 ANSI standards map to AnsiColor 0..7', () {
      expect(Colors.black, const AnsiColor(0));
      expect(Colors.red, const AnsiColor(1));
      expect(Colors.green, const AnsiColor(2));
      expect(Colors.yellow, const AnsiColor(3));
      expect(Colors.blue, const AnsiColor(4));
      expect(Colors.magenta, const AnsiColor(5));
      expect(Colors.cyan, const AnsiColor(6));
      expect(Colors.white, const AnsiColor(7));
    });

    test('bright variants map to AnsiColor 8..15', () {
      expect(Colors.brightBlack, const AnsiColor(8));
      expect(Colors.brightRed, const AnsiColor(9));
      expect(Colors.brightWhite, const AnsiColor(15));
    });

    test('gray/grey both alias brightBlack (the readable name for it)', () {
      expect(Colors.gray, Colors.brightBlack);
      expect(Colors.grey, Colors.brightBlack);
    });

    test('truecolor aliases return RgbColor', () {
      expect(Colors.pureWhite, const RgbColor(255, 255, 255));
      expect(Colors.crimson, isA<RgbColor>());
      expect(Colors.violet, isA<RgbColor>());
    });
  });

  group('Container.color', () {
    testWidgets('paints a background on every covered cell', (tester) {
      tester.pumpWidget(
        const Container(
          width: 5,
          height: 2,
          color: RgbColor(40, 80, 40),
          child: Text('hi'),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 3));
      // Top-left cell: child writes 'h' with default fg; bg should be green.
      expect(buf.atColRow(0, 0).style.background, const RgbColor(40, 80, 40));
      // A cell the child doesn't paint (col 4, row 1) still has the bg.
      expect(buf.atColRow(4, 1).style.background, const RgbColor(40, 80, 40));
      // Outside the container (col 6) is untouched.
      expect(buf.atColRow(6, 0).style.background, isNull);
    });

    testWidgets('background composes with border + padding', (tester) {
      tester.pumpWidget(
        Container(
          width: 6,
          height: 3,
          color: Colors.azure,
          border: const BoxBorder(),
          padding: const EdgeInsets.all(0),
          child: const Text('x'),
        ),
      );
      final buf = tester.render(size: const CellSize(10, 4));
      // Border glyph present.
      expect(buf.atColRow(0, 0).grapheme, '┌');
      // Cell inside the border has the background fill.
      expect(buf.atColRow(1, 1).style.background, Colors.azure);
    });

    testWidgets(
      'border uses ASCII glyphs under ASCII glyph tier',
      (tester) {
        tester.pumpWidget(
          Container(
            width: 5,
            height: 3,
            border: const BoxBorder(style: BorderStyle.rounded),
            child: const Text('x'),
          ),
        );
        final buf = tester.render(size: const CellSize(5, 3));
        expect(buf.atColRow(0, 0).grapheme, '+');
        expect(buf.atColRow(1, 0).grapheme, '-');
        expect(buf.atColRow(0, 1).grapheme, '|');
      },
      glyphTier: GlyphTier.ascii,
    );
  });

  group('runTui(Widget) accepts a direct widget', () {
    test('does not require a factory wrapper', () async {
      // Strictly a type-check: this test runs to completion only if the
      // signature accepts a Widget. (Behavior is covered exhaustively by
      // run_tui_test.dart.)
      final driver = FakeTerminalDriver();
      final future = runTui(
        const Text('hi'),
        driver: driver,
        enableHotReload: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      driver.enqueue(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await future;
      await driver.dispose();
    });
  });

  group('KeyBindings canonical form', () {
    testWidgets('fires the callback for the right key', (tester) {
      var spaceFired = 0;
      var enterFired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(KeyChord.char(' '), onEvent: (_) => spaceFired++),
            KeyBinding(
              KeyChord.key(KeyCode.enter),
              onEvent: (_) => enterFired++,
            ),
          ],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));

      tester.sendKey(const KeyEvent(char: ' '));
      tester.pump();
      expect(spaceFired, 1);
      expect(enterFired, 0);

      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      tester.pump();
      expect(enterFired, 1);
      expect(spaceFired, 1);
    });

    testWidgets('the canonical bindings: form still works', (tester) {
      var fired = 0;
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.char('q'),
              onEvent: (_) => fired++,
              label: 'quit',
            ),
          ],
          child: const Text('app'),
        ),
      );
      tester.render(size: const CellSize(10, 1));
      tester.sendKey(const KeyEvent(char: 'q'));
      tester.pump();
      expect(fired, 1);
    });
  });

  group('context.colors / context.theme extensions', () {
    testWidgets('context.colors returns the active scheme', (tester) {
      Color? captured;
      tester.pumpWidget(
        Theme(
          data: const ThemeData(colorScheme: ColorScheme(error: AnsiColor(9))),
          child: LayoutBuilder(
            builder: (context, _) {
              captured = context.colors.error;
              return const Text('x');
            },
          ),
        ),
      );
      tester.render(size: const CellSize(5, 1));
      expect(captured, const AnsiColor(9));
    });

    testWidgets('context.theme returns the full ThemeData', (tester) {
      Brightness? captured;
      tester.pumpWidget(
        Theme(
          data: const ThemeData(brightness: Brightness.light),
          child: LayoutBuilder(
            builder: (context, _) {
              captured = context.theme.brightness;
              return const Text('x');
            },
          ),
        ),
      );
      tester.render(size: const CellSize(5, 1));
      expect(captured, Brightness.light);
    });
  });

  group('FleuryError formatting', () {
    test('renders summary alone when no details/hint/docs', () {
      final e = FleuryError(summary: 'something broke');
      expect(e.toString(), 'something broke');
    });

    test('includes details + how-to-fix + docs in order', () {
      final e = FleuryError(
        summary: 'cannot do X',
        details: 'because Y was Z when it should have been W.',
        hint: 'wrap your widget in a Q.',
        docs: 'https://fleury.dev/errors/cannot-do-x',
      );
      final s = e.toString();
      expect(s, contains('cannot do X'));
      expect(s, contains('because Y was Z'));
      expect(s, contains('How to fix this: wrap your widget in a Q.'));
      expect(s, contains('See: https://fleury.dev/errors/cannot-do-x'));
      // Sections in summary → details → hint → docs order.
      expect(s.indexOf('cannot do X') < s.indexOf('because Y'), isTrue);
      expect(s.indexOf('because Y') < s.indexOf('How to fix'), isTrue);
      expect(s.indexOf('How to fix') < s.indexOf('See:'), isTrue);
    });

    test('migrated render-object constraint error carries a hint', () {
      // A render object that intentionally lies about its size to
      // trip the constraints-not-satisfied check, surfacing the
      // FleuryError migration.
      final r = _LyingRenderObject();
      try {
        r.layout(const CellConstraints(maxCols: 2, maxRows: 2));
        fail('layout should have thrown');
      } on FleuryError catch (e) {
        expect(e.toString(), contains('does not satisfy'));
        expect(e.toString(), contains('How to fix this:'));
      }
    });
  });
}

/// Returns a size that overflows whatever constraints it's given —
/// trips the framework's `constraints.isSatisfiedBy(result)` check
/// so we can verify the resulting FleuryError carries our hint text.
class _LyingRenderObject extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) => const CellSize(99, 99);

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {}
}
