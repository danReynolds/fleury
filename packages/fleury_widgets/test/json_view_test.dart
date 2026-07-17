import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('JsonViewController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = JsonViewController(
        expandedPointers: const {'/meta'},
        collapsedPointers: const {'/flags'},
        selectedIndex: 2,
      );

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 2);
      expect(controller.visibleRange, isNull);
      expect(controller.expandedPointers, {'/meta'});
      expect(controller.collapsedPointers, {'/flags'});
      expect(
        controller.isExpanded('/meta', depth: 1, initialExpandedDepth: 0),
        isTrue,
      );
      expect(
        controller.isExpanded('/flags', depth: 1, initialExpandedDepth: 2),
        isFalse,
      );
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = JsonViewController()..dispose();

      const message = 'JsonViewController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
      expect(() => controller.expand('/meta'), _stateError(message));
      expect(() => controller.collapse('/meta'), _stateError(message));
      expect(
        () => controller.toggle('/meta', expanded: true),
        _stateError(message),
      );
    });
  });

  testWidgets('renders collapsed JSON structure with path semantics', (tester) {
    tester.pumpWidget(
      JsonView(
        semanticLabel: 'Run payload',
        value: const {
          'name': 'fleury',
          'meta': {'version': 1, 'status': 'active'},
          'flags': [true, null],
        },
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(80, 8),
      emptyMark: ' ',
    );

    expect(output, contains(r'▾ $ {object 3}'));
    expect(output, contains('name: "fleury"'));
    expect(output, contains('▸ meta {object 2}'));
    expect(output, contains('▸ flags [array 2]'));

    final json = tester.semantics().single(
      role: SemanticRole.json,
      label: 'Run payload',
      action: SemanticAction.copy,
    );
    expect(json.state['valid'], isTrue);
    expect(json.state.collectionRowCount, 4);
    expect(json.state['rootType'], 'object');
    expect(json.state.selectedKey, '');
    expect(json.state['selectedPath'], r'$');

    final meta = tester.semantics().single(
      role: SemanticRole.jsonNode,
      label: 'meta',
    );
    expect(meta.expanded, isFalse);
    expect(meta.actions, contains(SemanticAction.open));
    expect(meta.state['jsonPointer'], '/meta');
    expect(meta.state['jsonPath'], r'$.meta');
    expect(meta.state['jsonType'], 'object');
    expect(meta.state['childCount'], 2);
    expect(meta.state['depth'], 1);
  });

  testWidgets('colors a value by type, distinct from its label', (tester) {
    tester.pumpWidget(JsonView(value: const {'name': 'fleury'}));
    final buffer = tester.render(size: const CellSize(40, 4));
    // Row 0 is the root object; row 1 is `name: "fleury"`. The label 'n' sits
    // at col 0; the string value's opening quote at col 6.
    final label = buffer.atColRow(0, 1);
    final value = buffer.atColRow(6, 1);
    expect(value.grapheme, '"');
    expect(value.style.foreground, isNotNull);
    expect(value.style.foreground, isNot(label.style.foreground));
  });

  testWidgets('Right expands a branch and Left collapses it', (tester) {
    tester.pumpWidget(
      JsonView(
        autofocus: true,
        value: const {
          'name': 'fleury',
          'meta': {'version': 1, 'status': 'active'},
          'flags': [true, null],
        },
      ),
    );

    tester.render(size: const CellSize(80, 8));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // name
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // meta
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
    tester.render(size: const CellSize(80, 8));

    var json = tester.semantics().single(role: SemanticRole.json);
    expect(json.state.collectionRowCount, 6);
    expect(json.state['expandedCount'], 2);

    final version = tester.semantics().single(
      role: SemanticRole.jsonNode,
      label: 'version',
    );
    expect(version.state['jsonPointer'], '/meta/version');
    expect(version.state['jsonPath'], r'$.meta.version');
    expect(version.value, '1');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
    tester.render(size: const CellSize(80, 8));

    json = tester.semantics().single(role: SemanticRole.json);
    expect(json.state.collectionRowCount, 4);
    final meta = tester.semantics().single(
      role: SemanticRole.jsonNode,
      label: 'meta',
    );
    expect(meta.expanded, isFalse);
  });

  testWidgets('semantic open expands a JSON branch', (tester) async {
    tester.pumpWidget(
      JsonView(
        value: const {
          'name': 'fleury',
          'meta': {'version': 1, 'status': 'active'},
        },
      ),
    );

    tester.render(size: const CellSize(80, 8));
    final result = await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.jsonNode,
      label: 'meta',
    );

    expect(result.completed, isTrue);
    tester.render(size: const CellSize(80, 8));
    final version = tester.semantics().single(
      role: SemanticRole.jsonNode,
      label: 'version',
    );
    expect(version.state['jsonPointer'], '/meta/version');
  });

  testWidgets('semantic close collapses an expanded JSON branch', (
    tester,
  ) async {
    tester.pumpWidget(
      JsonView(
        value: const {
          'name': 'fleury',
          'meta': {'version': 1, 'status': 'active'},
        },
      ),
    );
    tester.render(size: const CellSize(80, 8));
    await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.jsonNode,
      label: 'meta',
    );
    tester.render(size: const CellSize(80, 8));
    expect(
      tester.semantics().where(role: SemanticRole.jsonNode, label: 'version'),
      isNotEmpty,
    );

    // Expanded ⇒ meta offers close, not open.
    final meta = tester.semantics().single(
      role: SemanticRole.jsonNode,
      label: 'meta',
    );
    expect(meta.actions, contains(SemanticAction.close));
    expect(meta.actions, isNot(contains(SemanticAction.open)));

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.jsonNode,
      label: 'meta',
    );
    expect(result.completed, isTrue);
    tester.render(size: const CellSize(80, 8));
    expect(
      tester.semantics().where(role: SemanticRole.jsonNode, label: 'version'),
      isEmpty,
      reason: 'collapsing meta hides its children',
    );
  });

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected JSON subtree', (tester) async {
      final controller = JsonViewController(selectedIndex: 2);
      JsonViewCopyResult? copied;
      tester.pumpWidget(
        JsonView(
          autofocus: true,
          controller: controller,
          copyOptions: const JsonViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          value: const {
            'name': 'fleury',
            'meta': {'version': 1, 'status': 'active'},
          },
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 8));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(
        tester.clipboard.readInProcess(),
        '{\n'
        '  "version": 1,\n'
        '  "status": "active"\n'
        '}',
      );
      expect(copied, isNotNull);
      expect(copied!.rowIndex, 2);
      expect(copied!.row.path, r'$.meta');
      expect(copied!.report.policy.name, 'inProcessOnly');

      final selected = tester.semantics().single(
        role: SemanticRole.jsonNode,
        label: 'meta',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(selected.state['jsonPointer'], '/meta');
    });

    testWidgets('semantic copy copies the selected JSON subtree', (
      tester,
    ) async {
      final controller = JsonViewController(selectedIndex: 2);
      JsonViewCopyResult? copied;
      tester.pumpWidget(
        JsonView(
          controller: controller,
          copyOptions: const JsonViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          value: const {
            'name': 'fleury',
            'meta': {'version': 1, 'status': 'active'},
          },
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 8));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.jsonNode,
        label: 'meta',
      );

      expect(result.completed, isTrue);
      expect(tester.clipboard.readInProcess(), contains('"version": 1'));
      expect(copied?.row.path, r'$.meta');
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    test('exportJsonViewRow supports line copy mode', () {
      final rows = buildJsonViewRows(const {
        'name': 'fleury',
        'meta': {'version': 1},
      });
      final meta = rows.singleWhere((row) => row.path == r'$.meta');

      expect(
        exportJsonViewRow(
          meta,
          options: const JsonViewCopyOptions(mode: JsonViewCopyMode.line),
        ),
        contains('meta {object 1}'),
      );
    });

    testWidgets('display and copy collapse unsafe terminal payloads', (
      tester,
    ) async {
      final controller = JsonViewController(selectedIndex: 0);
      tester.pumpWidget(
        JsonView(
          autofocus: true,
          controller: controller,
          copyOptions: const JsonViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          value: const {'unsafe': 'bad\x1b]52;c;secret\x07 payload'},
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(80, 4),
        emptyMark: ' ',
      );
      expect(output, contains('unsafe: "bad'));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final unsafe = tester.semantics().single(
        role: SemanticRole.jsonNode,
        label: 'unsafe',
      );
      expect(unsafe.value, isNot(contains('secret')));
      expect(unsafe.state.outputSanitized, isTrue);

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
      expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));
      expect(tester.clipboard.readInProcess(), contains('"unsafe"'));
    });
  });

  testWidgets('invalid JSON string exposes parse error semantics', (tester) {
    tester.pumpWidget(JsonView.string('{bad', semanticLabel: 'Broken payload'));

    final output = tester.renderToString(
      size: const CellSize(80, 2),
      emptyMark: ' ',
    );
    expect(output, contains('Invalid JSON:'));

    final json = tester.semantics().single(
      role: SemanticRole.json,
      label: 'Broken payload',
    );
    expect(json.validationError, isNotNull);
    expect(json.state['valid'], isFalse);
    expect(json.state['sourceLength'], 4);
  });
}
