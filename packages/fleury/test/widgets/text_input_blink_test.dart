// Tests for TextInput cursor blink (RFC 0010 follow-up #1).
//
// Migrated to the FleuryTester API as a reference example. Compare
// against the original `_Harness`-based version in git history to
// see what the new helpers buy you: no per-file harness class, no
// hand-rolled renderRow, no hand-rolled cursorVisibleAt, no
// manual scheduler/owner plumbing.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// True when the cell at [col] of the first row paints with the
/// inverse style — the cue we render the cursor with.
bool _cursorVisibleAt(FleuryTester tester, int col) {
  final buffer = tester.render(size: const CellSize(20, 1));
  return buffer.atColRow(col, 0).style.inverse == true;
}

void main() {
  group('cursor visibility', () {
    testWidgets('unfocused TextInput shows no cursor', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(TextInput(controller: controller));
      expect(
        _cursorVisibleAt(tester, 3),
        isFalse,
        reason: 'unfocused: no cursor at past-EOL position',
      );
    });

    testWidgets('focused TextInput shows a visible cursor on '
        'first build', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));
      expect(
        _cursorVisibleAt(tester, 3),
        isTrue,
        reason: 'focused, blink-on by default at first build',
      );
    });

    testWidgets('cursor blinks between visible and invisible at the '
        'configured interval', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          blinkInterval: const Duration(milliseconds: 500),
        ),
      );
      expect(_cursorVisibleAt(tester, 3), isTrue);

      tester.pump(const Duration(milliseconds: 500));
      expect(_cursorVisibleAt(tester, 3), isFalse);

      tester.pump(const Duration(milliseconds: 500));
      expect(_cursorVisibleAt(tester, 3), isTrue);
    });

    testWidgets('enableBlink: false keeps the cursor solid when '
        'focused', (tester) {
      final controller = TextEditingController(text: 'abc');
      tester.pumpWidget(
        TextInput(controller: controller, autofocus: true, enableBlink: false),
      );
      expect(_cursorVisibleAt(tester, 3), isTrue);

      tester.pump(const Duration(seconds: 5));
      expect(_cursorVisibleAt(tester, 3), isTrue);
    });

    testWidgets('typing while in the OFF blink phase snaps the cursor '
        'back to visible', (tester) {
      final controller = TextEditingController(text: 'a');
      tester.pumpWidget(
        TextInput(
          controller: controller,
          autofocus: true,
          blinkInterval: const Duration(milliseconds: 500),
        ),
      );
      tester.pump(const Duration(milliseconds: 500));
      expect(_cursorVisibleAt(tester, 1), isFalse);

      tester.type('b');
      expect(
        _cursorVisibleAt(tester, 2),
        isTrue,
        reason: 'typing should reset blink to ON',
      );
    });
  });

  group('scheduler integration', () {
    testWidgets('focused TextInput registers exactly one FrameTicker', (
      tester,
    ) {
      tester.pumpWidget(TextInput(autofocus: true));
      expect(tester.scheduler.activeTickerCount, 1);
    });

    testWidgets('unfocused TextInput registers no ticker', (tester) {
      tester.pumpWidget(const TextInput());
      expect(tester.scheduler.activeTickerCount, 0);
    });

    testWidgets('unmounting disposes the blink ticker', (tester) {
      tester.pumpWidget(TextInput(autofocus: true));
      expect(tester.scheduler.activeTickerCount, 1);
      tester.root!.unmount();
      expect(tester.scheduler.activeTickerCount, 0);
    });

    testWidgets(
      'AnimationPolicy.disabled mutes the blink (cursor solid)',
      (tester) {
        tester.pumpWidget(TextInput(autofocus: true));
        expect(_cursorVisibleAt(tester, 0), isTrue);
        tester.pump(const Duration(milliseconds: 500));
        expect(
          _cursorVisibleAt(tester, 0),
          isTrue,
          reason: 'AnimationPolicy.disabled keeps cursor solid',
        );
      },
      animationPolicy: AnimationPolicy.disabled,
    );
  });
}
