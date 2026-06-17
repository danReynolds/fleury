import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordInput', () {
    testWidgets('renders typed characters as • not the real text', (tester) {
      tester.pumpWidget(const PasswordInput(autofocus: true));
      tester.type('secret');
      final out = tester
          .renderToString(size: const CellSize(10, 1), emptyMark: ' ')
          .trimRight();
      // Six dots for the six typed characters; the real text should not
      // appear anywhere.
      expect(out.contains('••••••'), isTrue);
      expect(out.contains('secret'), isFalse);
    });

    testWidgets('controller still holds the real text', (tester) {
      final ctrl = TextEditingController();
      tester.pumpWidget(PasswordInput(controller: ctrl, autofocus: true));
      tester.type('hunter2');
      expect(
        ctrl.text,
        'hunter2',
        reason: 'controller is the source of truth — only display is masked',
      );
    });

    testWidgets('onSubmit fires with the real text on Enter', (tester) {
      String? submitted;
      tester.pumpWidget(
        PasswordInput(autofocus: true, onSubmit: (t) => submitted = t),
      );
      tester.type('p@ss');
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(submitted, 'p@ss');
    });

    testWidgets('placeholder shows when empty (not masked)', (tester) {
      tester.pumpWidget(const PasswordInput(placeholder: 'API token'));
      final out = tester
          .renderToString(size: const CellSize(16, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('API token'), isTrue);
    });

    testWidgets('custom obscuringCharacter is honored', (tester) {
      tester.pumpWidget(
        const PasswordInput(autofocus: true, obscuringCharacter: '*'),
      );
      tester.type('abc');
      final out = tester
          .renderToString(size: const CellSize(10, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('***'), isTrue);
    });

    testWidgets('semantics redact the real value', (tester) {
      final ctrl = TextEditingController(text: 'hunter2');
      tester.pumpWidget(PasswordInput(controller: ctrl, autofocus: true));

      final field = tester.semantics().single(
        role: SemanticRole.textField,
        focused: true,
      );

      expect(field.value, isNull);
      expect(field.state.obscureText, isTrue);
      expect(field.state.redactedValue, isTrue);
      expect(field.state.clipboardPolicy, 'redacted');
      expect(field.state['fieldType'], 'secret');
      expect(field.state['redacted'], isTrue);
    });

    testWidgets('semantic label and secret metadata are adapter friendly', (
      tester,
    ) {
      final ctrl = TextEditingController(text: 'api-secret');
      tester.pumpWidget(
        PasswordInput(
          controller: ctrl,
          autofocus: true,
          semanticLabel: 'API key',
          semanticState: const SemanticState({'credentialKind': 'apiKey'}),
        ),
      );

      final field = tester.semantics().single(
        role: SemanticRole.textField,
        label: 'API key',
        focused: true,
      );

      expect(field.value, isNull);
      expect(field.state['credentialKind'], 'apiKey');
      expect(field.state['fieldType'], 'secret');
      expect(field.state['redacted'], isTrue);
      expect(field.state.redactedValue, isTrue);
      expect(field.state.clipboardRedacted, isTrue);

      final accessibility = tester.accessibilitySnapshot();
      final node = accessibility.single(label: 'API key', valueRedacted: true);
      expect(node.states, contains('field type secret'));
      expect(node.states, contains('secret'));
      expect(accessibility.toPlainText(), isNot(contains('api-secret')));
    });

    testWidgets('Ctrl+R reveals the real text, and re-masks it', (tester) {
      final ctrl = TextEditingController(text: 'hunter2');
      tester.pumpWidget(PasswordInput(controller: ctrl, autofocus: true));
      String render() => tester
          .renderToString(size: const CellSize(12, 1), emptyMark: ' ')
          .trimRight();
      // Masked by default.
      expect(render().contains('hunter2'), isFalse);
      expect(render().contains('•••••••'), isTrue);
      // Reveal with Ctrl+R.
      tester.sendKey(const KeyEvent(char: 'r', modifiers: {KeyModifier.ctrl}));
      tester.pump();
      expect(render().contains('hunter2'), isTrue);
      // Re-mask with Ctrl+R.
      tester.sendKey(const KeyEvent(char: 'r', modifiers: {KeyModifier.ctrl}));
      tester.pump();
      expect(render().contains('hunter2'), isFalse);
    });

    testWidgets('a revealed value still redacts semantics and clipboard', (
      tester,
    ) {
      final ctrl = TextEditingController(text: 'hunter2');
      tester.pumpWidget(PasswordInput(controller: ctrl, autofocus: true));
      tester.sendKey(const KeyEvent(char: 'r', modifiers: {KeyModifier.ctrl}));
      tester.pump();
      final field = tester.semantics().single(
        role: SemanticRole.textField,
        focused: true,
      );
      expect(
        field.value,
        isNull,
        reason: 'revealing is visual only — never read the secret out',
      );
      expect(field.state.clipboardPolicy, 'redacted');
      expect(field.state['revealed'], isTrue);
    });

    testWidgets('canReveal: false leaves the field masked under Ctrl+R', (
      tester,
    ) {
      final ctrl = TextEditingController(text: 'hunter2');
      tester.pumpWidget(
        PasswordInput(controller: ctrl, autofocus: true, canReveal: false),
      );
      tester.sendKey(const KeyEvent(char: 'r', modifiers: {KeyModifier.ctrl}));
      tester.pump();
      final out = tester
          .renderToString(size: const CellSize(12, 1), emptyMark: ' ')
          .trimRight();
      expect(out.contains('hunter2'), isFalse);
    });
  });
}
