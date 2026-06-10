import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<ContextItem> _items() => const [
  ContextItem(
    id: 'ctx.demo',
    label: 'Demo console source',
    detail: 'App shell and demo fixtures',
    kind: ContextItemKind.file,
    priority: ContextItemPriority.high,
    tokenCount: 1200,
    source: 'packages/fleury_example_console/lib/fleury_example_console.dart',
    pinned: true,
  ),
  ContextItem(
    id: 'ctx.scenario',
    label: 'Demo scenario',
    detail: 'Milestone scenario',
    kind: ContextItemKind.note,
    priority: ContextItemPriority.normal,
    tokenCount: 850,
    source: 'docs/implementation/demo-app-scenario.md',
  ),
  ContextItem(
    id: 'ctx.transcript',
    label: 'Transcript tail',
    detail: 'Recent demo events',
    kind: ContextItemKind.message,
    priority: ContextItemPriority.low,
    tokenCount: 320,
  ),
];

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('ContextPanel', () {
    group('controller lifecycle', () {
      test('dispose is idempotent and keeps final readable state', () {
        final controller = ContextPanelController(selectedIndex: 2);

        controller.dispose();
        controller.dispose();

        expect(controller.selectedIndex, 2);
        expect(controller.visibleRange, isNull);
      });

      test('mutating after dispose throws a lifecycle error', () {
        final controller = ContextPanelController()..dispose();

        const message = 'ContextPanelController has been disposed.';
        expect(() => controller.selectedIndex = 1, _stateError(message));
        expect(() => controller.jumpToIndex(1), _stateError(message));
      });
    });

    test('exportContextItem sanitizes controls and respects options', () {
      final text = exportContextItem(
        const ContextItem(
          id: 'unsafe',
          label: 'bad\x1b]52;c;secret\x07',
          detail: 'two\nlines',
          kind: ContextItemKind.file,
          priority: ContextItemPriority.critical,
          tokenCount: 50,
          source: 'src/main.dart',
          pinned: true,
        ),
      );

      expect(
        text,
        'bad$replacementCharacter | file | critical | pinned | 50 tokens | '
        'src/main.dart | two lines',
      );
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('\x1b]52')));

      expect(
        exportContextItem(
          _items().first,
          options: const ContextPanelCopyOptions(
            includeDetail: false,
            includeSource: false,
          ),
        ),
        'Demo console source | file | high | pinned | 1200 tokens',
      );
    });

    testWidgets('selects and exposes context semantics', (tester) async {
      ContextPanelSelectResult? selected;
      tester.pumpWidget(
        ContextPanel(
          label: 'Context pack',
          items: _items(),
          usage: const TokenUsage(contextUsed: 2370, contextLimit: 8000),
          autofocus: true,
          onSelect: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(100, 6));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

      expect(selected?.item.id, 'ctx.demo');
      expect(selected?.itemIndex, 0);

      final panel = tester.semantics().single(
        role: SemanticRole.contextPanel,
        label: 'Context pack',
      );
      expect(panel.value, '2370/8000');
      expect(panel.state['contextItemCount'], 3);
      expect(panel.state['contextTokenCount'], 2370);
      expect(panel.state.contextUsed, 2370);
      expect(panel.state.contextLimit, 8000);
      expect(panel.state.selectedContextItemId, 'ctx.demo');

      final row = tester.semantics().single(
        role: SemanticRole.contextItem,
        label: 'Demo console source',
      );
      expect(row.selected, isTrue);
      expect(row.actions, contains(SemanticAction.activate));
      expect(row.state.contextItemId, 'ctx.demo');
      expect(row.state.contextItemKind, 'file');
      expect(row.state.contextItemTokenCount, 1200);
      expect(row.state.contextItemPriority, 'high');
      expect(row.state['pinned'], isTrue);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.contextItem,
        label: 'Demo console source',
      );
      expect(
        fallback.states,
        contains(
          'context id ctx.demo, kind file, 1200 tokens, priority high, '
          'pinned, source packages/fleury_example_console/lib/'
          'fleury_example_console.dart',
        ),
      );
    });

    testWidgets('semantic focus and activation focus the panel', (
      tester,
    ) async {
      final controller = ContextPanelController();
      ContextPanelSelectResult? selected;
      tester.pumpWidget(
        ContextPanel(
          label: 'Context pack',
          items: _items(),
          controller: controller,
          onSelect: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(100, 6));
      var panel = tester.semantics().single(
        role: SemanticRole.contextPanel,
        label: 'Context pack',
        action: SemanticAction.focus,
      );
      expect(panel.focused, isFalse);
      expect(panel.actions, contains(SemanticAction.navigate));

      var result = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.contextPanel,
        label: 'Context pack',
      );
      expect(result.completed, isTrue);

      tester.render(size: const CellSize(100, 6));
      panel = tester.semantics().single(
        role: SemanticRole.contextPanel,
        label: 'Context pack',
        focused: true,
      );
      expect(panel.state.selectedContextItemId, 'ctx.demo');

      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.contextItem,
        label: 'Demo scenario',
      );
      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 1);
      expect(selected?.item.id, 'ctx.scenario');

      tester.render(size: const CellSize(100, 6));
      final row = tester.semantics().single(
        role: SemanticRole.contextItem,
        label: 'Demo scenario',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(row.state.contextItemId, 'ctx.scenario');

      panel = tester.semantics().single(
        role: SemanticRole.contextPanel,
        label: 'Context pack',
        focused: true,
      );
      expect(panel.state.selectedContextItemId, 'ctx.scenario');
      expect(panel.state['selectedIndex'], 1);
    });

    testWidgets('preserves selected context identity across item refresh', (
      tester,
    ) {
      final controller = ContextPanelController(selectedIndex: 2);
      tester.pumpWidget(
        ContextPanel(
          label: 'Context pack',
          items: _items(),
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(100, 6));

      tester.pumpWidget(
        ContextPanel(
          label: 'Context pack',
          items: [
            _items()[0],
            const ContextItem(
              id: 'ctx.inserted',
              label: 'Inserted context',
              kind: ContextItemKind.command,
              tokenCount: 40,
            ),
            _items()[1],
            const ContextItem(
              id: 'ctx.transcript',
              label: 'Transcript tail',
              detail: 'Updated transcript context',
              kind: ContextItemKind.message,
              priority: ContextItemPriority.normal,
              tokenCount: 500,
            ),
          ],
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(100, 6));
      tester.pump();
      tester.render(size: const CellSize(100, 6));

      expect(controller.selectedIndex, 3);
      final panel = tester.semantics().single(
        role: SemanticRole.contextPanel,
        label: 'Context pack',
      );
      expect(panel.state.selectedContextItemId, 'ctx.transcript');

      final selected = tester.semantics().single(
        role: SemanticRole.contextItem,
        label: 'Transcript tail',
        selected: true,
      );
      expect(selected.state.contextItemPriority, 'normal');
      expect(selected.state.contextItemTokenCount, 500);
      expect(selected.value, 'Updated transcript context');
    });

    testWidgets('semantic copy copies the selected context item', (
      tester,
    ) async {
      final originalClipboard = Clipboard.instance;
      final clipboard = TestClipboard();
      Clipboard.instance = clipboard;
      ContextPanelCopyResult? copied;
      try {
        tester.pumpWidget(
          ContextPanel(
            items: _items(),
            copyOptions: const ContextPanelCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        );

        tester.render(size: const CellSize(100, 6));
        final result = await tester.invokeSemanticAction(
          SemanticAction.copy,
          role: SemanticRole.contextItem,
          label: 'Demo console source',
        );

        expect(result.completed, isTrue);
        expect(
          clipboard.lastWritten,
          'Demo console source | file | high | pinned | 1200 tokens | '
          'packages/fleury_example_console/lib/fleury_example_console.dart | '
          'App shell and demo fixtures',
        );
        expect(copied?.itemIndex, 0);
        expect(copied?.report.policy.name, 'inProcessOnly');
      } finally {
        Clipboard.instance = originalClipboard;
      }
    });
  });
}
