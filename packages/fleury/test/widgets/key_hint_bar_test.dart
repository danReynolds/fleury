// KeyHintBar honesty: hide chords a focused text field swallows, and repaint
// when a binding's label changes without a focus move.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// A screen whose binding label toggles on setState — the reveal/hide pattern.
class _TogglingLabel extends StatefulWidget {
  const _TogglingLabel();
  @override
  State<_TogglingLabel> createState() => _TogglingLabelState();
}

class _TogglingLabelState extends State<_TogglingLabel> {
  bool revealed = false;
  @override
  Widget build(BuildContext context) => KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.char('r'),
            label: revealed ? 'hide' : 'reveal',
            onEvent: (_) => setState(() => revealed = !revealed),
          ),
        ],
        child: const Focus(autofocus: true, child: Text('body')),
      );
}

void main() {
  String bar(FleuryTester tester) =>
      tester.renderToString(size: const CellSize(60, 3));

  group('shadowed-printable suppression', () {
    testWidgets('hides bare-printable hints while a text field is focused '
        'but keeps modifier/function ones', (tester) {
      tester.pumpWidget(
        Column(
          children: [
            KeyBindings(
              bindings: [
                KeyBinding(KeyChord.char('?'), label: 'help', onEvent: (_) {}),
                KeyBinding(KeyChord.char('s', ctrl: true),
                    label: 'save', onEvent: (_) {}),
                KeyBinding(KeyChord.key(KeyCode.f1),
                    label: 'manual', onEvent: (_) {}),
              ],
              child: TextInput(autofocus: true),
            ),
            const KeyHintBar(),
          ],
        ),
      );
      final out = bar(tester);
      expect(out, isNot(contains('help')),
          reason: 'bare ? is swallowed by the focused field — do not lie');
      expect(out, contains('save'), reason: 'Ctrl+S bypasses the claimant');
      expect(out, contains('manual'), reason: 'F1 bypasses the claimant');
    });

    testWidgets('bare-printable hints reappear when focus leaves the field',
        (tester) {
      final field = FocusNode(debugLabel: 'field');
      final plain = FocusNode(debugLabel: 'plain');
      tester.pumpWidget(
        Column(
          children: [
            KeyBindings(
              bindings: [
                KeyBinding(KeyChord.char('?'), label: 'help', onEvent: (_) {}),
              ],
              child: Column(
                children: [
                  TextInput(focusNode: field, autofocus: true),
                  Focus(focusNode: plain, child: const Text('view')),
                ],
              ),
            ),
            const KeyHintBar(),
          ],
        ),
      );
      expect(bar(tester), isNot(contains('help')));

      plain.requestFocus();
      tester.pump();
      expect(bar(tester), contains('help'),
          reason: '? fires again once no text claimant holds focus');
    });
  });

  group('live labels (bindingsRevision)', () {
    testWidgets('a label toggled by setState repaints the bar without a '
        'focus move', (tester) async {
      tester.pumpWidget(
        Column(
          children: const [_TogglingLabel(), KeyHintBar()],
        ),
      );
      expect(bar(tester), contains('reveal'));

      tester.sendKey(const KeyEvent(char: 'r')); // toggles the label
      // The notify is microtask-deferred (didUpdateWidget runs mid-build).
      await tester.settle();
      expect(bar(tester), contains('hide'),
          reason: 'the bar tracks binding-content changes, not just focus');
      expect(bar(tester), isNot(contains('reveal')));
    });

    testWidgets('a binding content change bumps bindingsRevision; pumping '
        'alone does not', (tester) async {
      tester.pumpWidget(const Column(
        children: [_TogglingLabel(), KeyHintBar()],
      ));
      final before = tester.focusManager.bindingsRevision;
      tester.pump();
      expect(tester.focusManager.bindingsRevision, before,
          reason: 'no rebuild, no churn');

      tester.sendKey(const KeyEvent(char: 'r'));
      await tester.settle();
      expect(tester.focusManager.bindingsRevision, greaterThan(before));
    });
  });
}
