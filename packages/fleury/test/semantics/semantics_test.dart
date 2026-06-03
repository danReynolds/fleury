import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('Text contributes a text semantic node', (tester) {
    tester.pumpWidget(const Text('Hello semantics'));

    final tree = tester.semantics();
    final node = tree.single(role: SemanticRole.text, label: 'Hello semantics');

    expect(node.value, 'Hello semantics');
    expect(node.children, isEmpty);
  });

  testWidgets('Semantics wrapper contributes app-authored node', (tester) {
    tester.pumpWidget(
      const Semantics(
        id: SemanticNodeId('save-button'),
        role: SemanticRole.button,
        label: 'Save',
        actions: {SemanticAction.activate},
        child: Text('Save'),
      ),
    );

    final tree = tester.semantics();
    final button = tree.single(
      role: SemanticRole.button,
      label: 'Save',
      action: SemanticAction.activate,
    );

    expect(button.id, const SemanticNodeId('save-button'));
    expect(button.children.map((node) => node.role), [SemanticRole.text]);
    expect(tree.nodeById(const SemanticNodeId('save-button')), same(button));
  });

  testWidgets('IndexedStack contributes only visible child semantics', (
    tester,
  ) {
    tester.pumpWidget(
      const IndexedStack(
        index: 1,
        children: [
          Semantics(
            role: SemanticRole.button,
            label: 'Hidden',
            child: Text('A'),
          ),
          Semantics(
            role: SemanticRole.button,
            label: 'Visible',
            child: Text('B'),
          ),
        ],
      ),
    );

    final tree = tester.semantics();

    expect(tree.where(role: SemanticRole.button, label: 'Hidden'), isEmpty);
    expect(tree.single(role: SemanticRole.button, label: 'Visible'), isNotNull);
  });

  testWidgets('tester invokes app-authored semantic actions', (tester) async {
    var calls = 0;
    tester.pumpWidget(
      Semantics(
        id: const SemanticNodeId('save-button'),
        role: SemanticRole.button,
        label: 'Save',
        actions: const {SemanticAction.activate},
        onAction: (action) {
          expect(action, SemanticAction.activate);
          calls += 1;
        },
        child: const Text('Save'),
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Save',
    );

    expect(result.status, SemanticActionInvocationStatus.completed);
    expect(result.node?.id, const SemanticNodeId('save-button'));
    expect(calls, 1);
  });

  testWidgets('semantic action reports unsupported when no handler exists', (
    tester,
  ) async {
    tester.pumpWidget(
      const Semantics(
        id: SemanticNodeId('static-button'),
        role: SemanticRole.button,
        label: 'Static',
        actions: {SemanticAction.activate},
        child: Text('Static'),
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Static',
    );

    expect(result.status, SemanticActionInvocationStatus.unsupported);
  });

  testWidgets('semantic queries can filter by state', (tester) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.table,
        label: 'Runs',
        selected: true,
        state: SemanticState({
          'collectionRowCount': 100000,
          'visibleRangeStart': 0,
          'visibleRangeEnd': 23,
          'selectedKey': 'run-00042',
        }),
        child: Text('table'),
      ),
    );

    final table = tester.semantics().single(
      role: SemanticRole.table,
      label: 'Runs',
      selected: true,
    );

    expect(table.state.collectionRowCount, 100000);
    expect(table.state.visibleRangeStart, 0);
    expect(table.state.visibleRangeEnd, 23);
    expect(table.state.selectedKey, 'run-00042');
  });

  testWidgets('semantic queries can filter validation and capability state', (
    tester,
  ) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.region,
        label: 'Image preview',
        validationError: 'Unsupported terminal',
        busy: true,
        state: SemanticState({
          'capabilityRequirement': 'inlineImages',
          'activeFallback': 'halfBlockImage',
        }),
        child: Text('fallback'),
      ),
    );

    final node = tester.semantics().single(
      role: SemanticRole.region,
      label: 'Image preview',
      busy: true,
      validationError: 'Unsupported terminal',
      capabilityRequirement: 'inlineImages',
      activeFallback: 'halfBlockImage',
    );

    expect(node.validationError, 'Unsupported terminal');
    expect(node.state.capabilityRequirement, 'inlineImages');
    expect(node.state.activeFallback, 'halfBlockImage');
  });

  testWidgets('TextInput exposes value, focus, and submit semantics', (tester) {
    final controller = TextEditingController(text: 'deploy');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
        onSubmit: (_) {},
      ),
    );

    final field = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Command',
      focused: true,
      action: SemanticAction.submit,
    );

    expect(field.value, 'deploy');
    expect(field.actions, contains(SemanticAction.focus));
    expect(field.actions, contains(SemanticAction.clear));
    expect(field.state['selectionBase'], 6);
    expect(field.state['selectionExtent'], 6);
    expect(field.state.selectionBase, 6);
    expect(field.state.selectionExtent, 6);
  });

  testWidgets('semantic actions can focus, clear, and submit TextInput', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'deploy');
    final submitted = <String>[];
    tester.pumpWidget(
      TextInput(
        controller: controller,
        placeholder: 'Command',
        onSubmit: submitted.add,
      ),
    );

    var result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.textField,
      label: 'Command',
    );
    expect(result.completed, isTrue);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Command')
          .focused,
      isTrue,
    );

    result = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.textField,
      label: 'Command',
    );
    expect(result.completed, isTrue);
    expect(submitted, ['deploy']);

    result = await tester.invokeSemanticAction(
      SemanticAction.clear,
      role: SemanticRole.textField,
      label: 'Command',
    );
    expect(result.completed, isTrue);
    expect(controller.text, '');
  });

  testWidgets('TextInput exposes non-collapsed selection semantics', (tester) {
    final controller = TextEditingController(text: 'deploy')
      ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 4);
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    final field = tester.semantics().single(role: SemanticRole.textField);

    expect(field.state['selectionBase'], 1);
    expect(field.state['selectionExtent'], 4);
  });

  testWidgets('TextInput exposes composing range semantics', (tester) {
    final controller = TextEditingController(text: 'git ')
      ..updateComposingText('che', singleLine: true);
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    final field = tester.semantics().single(role: SemanticRole.textField);

    expect(field.value, 'git che');
    expect(field.state.composingActive, isTrue);
    expect(field.state.composingStart, 4);
    expect(field.state.composingEnd, 7);
  });

  testWidgets('TextInput exposes copy action for copyable selections', (
    tester,
  ) {
    final controller = TextEditingController(text: 'deploy')
      ..textSelection = const TextSelection(baseOffset: 1, extentOffset: 4);
    tester.pumpWidget(TextInput(controller: controller, autofocus: true));

    final field = tester.semantics().single(
      role: SemanticRole.textField,
      action: SemanticAction.copy,
    );

    expect(field.actions, contains(SemanticAction.copy));
    expect(field.state.clipboardPolicy, 'allowed');
    expect(field.state.clipboardCapability, 'clipboardWrite');
    expect(field.state.clipboardCapabilityResolution, 'available');
    expect(field.state.clipboardRedacted, isFalse);
  });

  testWidgets('TextInput exposes validation and read-only semantics', (tester) {
    final controller = TextEditingController(text: 'draft');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        placeholder: 'Name',
        readOnly: true,
        validationError: 'Name is locked',
        clipboardPolicy: TextClipboardPolicy.disabled,
      ),
    );

    final field = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Name',
      validationError: 'Name is locked',
      focused: true,
    );

    expect(field.value, 'draft');
    expect(field.enabled, isTrue);
    expect(field.state.readOnly, isTrue);
    expect(field.state.clipboardPolicy, 'disabled');
    expect(field.state.clipboardCapability, 'clipboardWrite');
    expect(field.state.clipboardCapabilityResolution, 'disabledByPolicy');
    expect(field.state.clipboardFallback, 'in-process register');
    expect(field.actions, contains(SemanticAction.focus));
    expect(field.actions, isNot(contains(SemanticAction.clear)));
    expect(field.actions, isNot(contains(SemanticAction.copy)));
  });

  testWidgets('obscured TextInput redacts semantic value', (tester) {
    final controller = TextEditingController(text: 'super-secret');
    tester.pumpWidget(
      TextInput(controller: controller, autofocus: true, obscureText: true),
    );

    final field = tester.semantics().single(role: SemanticRole.textField);

    expect(field.value, isNull);
    expect(field.state.obscureText, isTrue);
    expect(field.state.redactedValue, isTrue);
    expect(field.state.clipboardPolicy, 'redacted');
    expect(field.state.clipboardCapability, 'clipboardWrite');
    expect(field.state.clipboardCapabilityResolution, 'available');
    expect(field.state.clipboardRedacted, isTrue);
  });

  testWidgets('redacted TextInput clipboard policy redacts semantic value', (
    tester,
  ) {
    final controller = TextEditingController(text: 'api-token-123');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        clipboardPolicy: TextClipboardPolicy.redacted,
      ),
    );

    final field = tester.semantics().single(role: SemanticRole.textField);

    expect(field.value, isNull);
    expect(field.state.redactedValue, isTrue);
    expect(field.state.obscureText, isFalse);
    expect(field.state.clipboardPolicy, 'redacted');
    expect(field.state.clipboardRedacted, isTrue);
  });

  testWidgets('TextInput exposes history navigation state', (tester) {
    final controller = TextEditingController(text: 'draft');
    final history = TextHistoryController(entries: ['one', 'two']);
    tester.pumpWidget(
      TextInput(
        controller: controller,
        historyController: history,
        autofocus: true,
      ),
    );

    var field = tester.semantics().single(role: SemanticRole.textField);
    expect(field.state.historyCount, 2);
    expect(field.state.historyIndex, isNull);
    expect(field.state.historyBrowsing, isFalse);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));

    field = tester.semantics().single(role: SemanticRole.textField);
    expect(field.value, 'two');
    expect(field.state.historyCount, 2);
    expect(field.state.historyIndex, 1);
    expect(field.state.historyBrowsing, isTrue);
  });

  testWidgets('TextInput exposes completion state', (tester) {
    final controller = TextEditingController(text: 'git che');
    final completions = TextCompletionController()
      ..open(
        range: const TextRange(start: 4, end: 7),
        query: 'che',
        options: const [
          TextCompletionOption(label: 'checkout'),
          TextCompletionOption(label: 'cherry-pick'),
        ],
        selectedIndex: 1,
      );
    tester.pumpWidget(
      TextInput(
        controller: controller,
        completionController: completions,
        autofocus: true,
      ),
    );

    final field = tester.semantics().single(role: SemanticRole.textField);

    expect(field.state.completionActive, isTrue);
    expect(field.state.completionQuery, 'che');
    expect(field.state.completionRangeStart, 4);
    expect(field.state.completionRangeEnd, 7);
    expect(field.state.completionOptionCount, 2);
    expect(field.state.completionSelectedIndex, 1);
  });

  testWidgets('TextInput exposes paste progress state', (tester) {
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

    final field = tester.semantics().single(role: SemanticRole.textField);
    expect(field.state.pasteInProgress, isTrue);
    expect(field.state.pasteInsertedLength, 2);
    expect(field.state.pasteTotalLength, 6);
  });

  testWidgets('disabled TextInput exposes disabled semantics', (tester) {
    final controller = TextEditingController(text: 'locked');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        enabled: false,
        validationError: 'Unavailable',
      ),
    );

    final field = tester.semantics().single(
      role: SemanticRole.textField,
      enabled: false,
      validationError: 'Unavailable',
    );

    expect(field.focused, isFalse);
    expect(field.actions, isEmpty);
  });

  testWidgets('TextArea exposes multiline value and focus semantics', (tester) {
    final controller = TextEditingController(text: 'one\ntwo');
    tester.pumpWidget(
      TextArea(
        controller: controller,
        autofocus: true,
        placeholder: 'Composer',
      ),
    );

    final area = tester.semantics().single(
      role: SemanticRole.textArea,
      label: 'Composer',
      focused: true,
      action: SemanticAction.clear,
    );

    expect(area.value, 'one\ntwo');
    expect(area.actions, contains(SemanticAction.focus));
    expect(area.state['selectionBase'], controller.selection);
    expect(area.state['selectionExtent'], controller.selection);
  });

  testWidgets('semantic actions can focus and clear TextArea', (tester) async {
    final controller = TextEditingController(text: 'one\ntwo');
    tester.pumpWidget(
      TextArea(controller: controller, placeholder: 'Composer'),
    );

    var result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.textArea,
      label: 'Composer',
    );
    expect(result.completed, isTrue);
    expect(
      tester.semantics().single(role: SemanticRole.textArea).focused,
      isTrue,
    );

    result = await tester.invokeSemanticAction(
      SemanticAction.clear,
      role: SemanticRole.textArea,
      label: 'Composer',
    );
    expect(result.completed, isTrue);
    expect(controller.text, '');
  });

  testWidgets('TextArea exposes composing range semantics', (tester) {
    final controller = TextEditingController(text: 'one\n')
      ..updateComposingText('two');
    tester.pumpWidget(TextArea(controller: controller, autofocus: true));

    final area = tester.semantics().single(role: SemanticRole.textArea);

    expect(area.value, 'one\ntwo');
    expect(area.state.composingActive, isTrue);
    expect(area.state.composingStart, 4);
    expect(area.state.composingEnd, 7);
  });

  testWidgets('TextArea exposes validation, read-only, and clipboard policy', (
    tester,
  ) {
    final controller = TextEditingController(text: 'readonly');
    tester.pumpWidget(
      TextArea(
        controller: controller,
        autofocus: true,
        readOnly: true,
        validationError: 'Read-only area',
        clipboardPolicy: TextClipboardPolicy.disabled,
      ),
    );

    final area = tester.semantics().single(
      role: SemanticRole.textArea,
      focused: true,
      validationError: 'Read-only area',
    );

    expect(area.value, 'readonly');
    expect(area.state.readOnly, isTrue);
    expect(area.state.clipboardPolicy, 'disabled');
    expect(area.state.clipboardCapability, 'clipboardWrite');
    expect(area.state.clipboardCapabilityResolution, 'disabledByPolicy');
    expect(area.state.clipboardFallback, 'in-process register');
    expect(area.actions, contains(SemanticAction.focus));
    expect(area.actions, isNot(contains(SemanticAction.clear)));
  });

  testWidgets('redacted TextArea clipboard policy redacts semantic value', (
    tester,
  ) {
    final controller = TextEditingController(text: 'secret\nnotes');
    tester.pumpWidget(
      TextArea(
        controller: controller,
        autofocus: true,
        clipboardPolicy: TextClipboardPolicy.redacted,
      ),
    );

    final area = tester.semantics().single(role: SemanticRole.textArea);

    expect(area.value, isNull);
    expect(area.state.redactedValue, isTrue);
    expect(area.state.clipboardPolicy, 'redacted');
    expect(area.state.clipboardRedacted, isTrue);
  });
}
