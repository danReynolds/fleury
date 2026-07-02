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

  group('per-chord suppression (review regressions)', () {
    testWidgets('a multi-chord binding stays visible via its non-shadowed '
        'alias while typing', (tester) {
      tester.pumpWidget(
        Column(
          children: [
            KeyBindings(
              bindings: [
                KeyBinding.list(
                  [KeyChord.char('j'), KeyChord.key(KeyCode.arrowDown)],
                  label: 'next',
                  onEvent: (_) {},
                ),
              ],
              child: TextInput(autofocus: true),
            ),
            const KeyHintBar(),
          ],
        ),
      );
      final out = bar(tester);
      expect(out, contains('next'),
          reason: 'the Down alias still fires — hiding the whole binding '
              'would conceal live functionality exactly while typing');
      expect(out, contains('[↓]'),
          reason: 'advertise the alias that works, not the shadowed j');
      expect(out, isNot(contains('[j]')));
    });

    testWidgets('a disabled field with an app-provided node does not '
        'suppress printables that still fire', (tester) {
      final node = FocusNode(debugLabel: 'app-node');
      var fired = 0;
      tester.pumpWidget(
        Column(
          children: [
            KeyBindings(
              bindings: [
                KeyBinding(KeyChord.char('?'),
                    label: 'help', onEvent: (_) => fired++),
              ],
              child: TextInput(focusNode: node, enabled: false),
            ),
            const KeyHintBar(),
          ],
        ),
      );
      node.requestFocus();
      tester.pump();
      expect(bar(tester), contains('help'),
          reason: 'a disabled field declines text (no claimant), so ? '
              'falls through to chord matching and must stay advertised');
      tester.type('?');
      expect(fired, 1, reason: 'and it really does fire');
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

    testWidgets('a plain pump (no binding change) does not repaint the '
        'label', (tester) async {
      tester.pumpWidget(const Column(
        children: [_TogglingLabel(), KeyHintBar()],
      ));
      expect(bar(tester), contains('reveal'));
      tester.pump();
      expect(bar(tester), contains('reveal'),
          reason: 'no rebuild, no content change → label unchanged');

      tester.sendKey(const KeyEvent(char: 'r')); // real content change
      await tester.settle();
      expect(bar(tester), contains('hide'));
    });
  });
}
