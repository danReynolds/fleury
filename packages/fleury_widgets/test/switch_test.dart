import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('Switch', () {
    testWidgets('off state: handle on the left, track muted', (tester) {
      tester.pumpWidget(Switch(value: false, onChanged: (_) {}));
      final out = tester
          .renderToString(size: const CellSize(8, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('[●━━━]'), isTrue);
    });

    testWidgets('on state: handle on the right, track tinted', (tester) {
      tester.pumpWidget(Switch(value: true, onChanged: (_) {}));
      final out = tester
          .renderToString(size: const CellSize(8, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('[━━━●]'), isTrue);
    });

    testWidgets('Enter toggles when focused', (tester) {
      bool? received;
      tester.pumpWidget(
        Switch(value: false, autofocus: true, onChanged: (v) => received = v),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(received, true);
    });

    testWidgets('Space toggles when focused', (tester) {
      bool? received;
      tester.pumpWidget(
        Switch(value: true, autofocus: true, onChanged: (v) => received = v),
      );
      tester.type(' ');
      expect(received, false);
    });

    testWidgets('on-state track uses the theme primary color', (tester) {
      tester.pumpWidget(Switch(value: true, onChanged: (_) {}));
      final buf = tester.render(size: const CellSize(8, 1));
      // Look at the first track cell after the opening bracket; the
      // foreground should be the theme primary (AnsiColor(4) default).
      // Index 0 is '[', index 1 is the first track glyph.
      expect(buf.atColRow(1, 0).style.foreground, const AnsiColor(4));
    });

    testWidgets('label renders after the track', (tester) {
      tester.pumpWidget(
        Switch(value: false, label: 'verbose', onChanged: (_) {}),
      );
      final out = tester.renderToString(size: const CellSize(16, 1));
      expect(out.contains('verbose'), isTrue);
    });

    testWidgets('null onChanged disables switch', (tester) async {
      tester.pumpWidget(
        const Switch(value: true, label: 'verbose', onChanged: null),
      );

      final node = tester.semantics().single(
        role: SemanticRole.toggle,
        label: 'verbose',
        enabled: false,
      );
      expect(node.actions, isEmpty);
      expect(node.checked, isTrue);

      final buf = tester.render(size: const CellSize(16, 1));
      expect(buf.atColRow(1, 0).style.dim, isTrue);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        node: node,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });
  });
}
