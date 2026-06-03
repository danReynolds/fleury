import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _commands = [
  TextCompletionOption(label: 'checkout', detail: 'Switch branches'),
  TextCompletionOption(label: 'cherry-pick', detail: 'Apply commits'),
  TextCompletionOption(label: 'status'),
];

Iterable<TextCompletionOption> _commandProvider(TextCompletionRequest request) {
  final query = request.query.toLowerCase();
  return _commands.where((option) => option.label.startsWith(query));
}

String _screen(FleuryTester tester, {int cols = 32, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  testWidgets('typing opens a provider-backed completion menu', (tester) {
    TextCompletionRequest? lastRequest;
    tester.pumpWidget(
      CompletionTextInput(
        provider: (request) {
          lastRequest = request;
          return _commandProvider(request);
        },
        autofocus: true,
      ),
    );

    tester.type('ch');

    final out = _screen(tester);
    expect(lastRequest?.query, 'ch');
    expect(lastRequest?.range, const TextRange(start: 0, end: 2));
    expect(out.contains('checkout'), isTrue);
    expect(out.contains('cherry-pick'), isTrue);
    expect(out.contains('status'), isFalse);
    expect(tester.overlay.entries.length, 2);
  });

  testWidgets('Down and Tab accept the selected completion', (tester) {
    final controller = TextEditingController();
    TextCompletionOption? accepted;
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        onCompletionAccepted: (option) => accepted = option,
      ),
    );

    tester.type('ch');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));

    expect(controller.text, 'cherry-pick');
    expect(controller.textSelection, const TextSelection.collapsed(11));
    expect(accepted?.label, 'cherry-pick');
    expect(tester.overlay.entries.length, 1);

    tester.sendKey(const KeyEvent(char: 'z', modifiers: {KeyModifier.ctrl}));
    expect(controller.text, 'ch');
  });

  testWidgets('completion range targets the current word', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
      ),
    );

    tester.type('git ch');
    tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));

    expect(controller.text, 'git checkout');
    expect(controller.textSelection, const TextSelection.collapsed(12));
  });

  testWidgets('Escape closes completion before calling onEscape', (tester) {
    var escapes = 0;
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        autofocus: true,
        onEscape: () => escapes += 1,
      ),
    );

    tester.type('ch');
    expect(tester.overlay.entries.length, 2);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    expect(tester.overlay.entries.length, 1);
    expect(escapes, 0);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    expect(escapes, 1);
  });

  testWidgets('Tab bubbles when the completion menu is closed', (tester) {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CompletionTextInput(
              provider: _commandProvider,
              focusNode: a,
              autofocus: true,
            ),
            TextInput(focusNode: b),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(32, 4));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));

    expect(b.hasFocus, isTrue);
  });

  testWidgets('completion menu contributes semantic rows', (tester) {
    tester.pumpWidget(
      CompletionTextInput(provider: _commandProvider, autofocus: true),
    );

    tester.type('ch');
    _screen(tester);

    final menu = tester.semantics().single(
      role: SemanticRole.menu,
      label: 'Completions',
    );
    expect(menu.focused, isTrue);
    expect(menu.expanded, isTrue);
    expect(menu.actions, contains(SemanticAction.close));
    expect(menu.state.filterText, 'ch');
    expect(menu.state.collectionRowCount, 2);

    final selected = tester.semantics().single(
      role: SemanticRole.menuItem,
      label: 'checkout',
      selected: true,
    );
    expect(selected.hint, 'Switch branches');
    expect(selected.value, 'checkout');
    expect(selected.focused, isTrue);
    expect(selected.actions, contains(SemanticAction.activate));
    expect(selected.state.completionQuery, 'ch');
    expect(selected.state.menuItemPosition, 1);
    expect(selected.state.menuItemCount, 2);
  });

  testWidgets('semantic activation accepts a completion option', (
    tester,
  ) async {
    final controller = TextEditingController();
    TextCompletionOption? accepted;
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
        onCompletionAccepted: (option) => accepted = option,
      ),
    );

    tester.type('ch');
    _screen(tester);

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.menuItem,
      label: 'cherry-pick',
    );

    expect(result.completed, isTrue);
    expect(controller.text, 'cherry-pick');
    expect(controller.textSelection, const TextSelection.collapsed(11));
    expect(accepted?.label, 'cherry-pick');
    expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Command')
          .value,
      'cherry-pick',
    );
  });

  testWidgets('semantic close hides completions without clearing text', (
    tester,
  ) async {
    final controller = TextEditingController();
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
      ),
    );

    tester.type('ch');
    _screen(tester);

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.menu,
      label: 'Completions',
    );

    expect(result.completed, isTrue);
    expect(controller.text, 'ch');
    expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
  });
}
