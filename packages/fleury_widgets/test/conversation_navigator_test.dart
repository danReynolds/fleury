import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<ConversationEntry> _entries() => const [
  ConversationEntry(
    id: 'ops-main',
    title: 'Ops thread',
    subtitle: 'Primary operator conversation',
    status: ConversationStatus.active,
    latestMessage: 'Ready for launch',
    author: 'Operator',
    unreadCount: 1,
    messageCount: 12,
    pinned: true,
  ),
  ConversationEntry(
    id: 'deploy-review',
    title: 'Deploy review',
    subtitle: 'Production approval',
    status: ConversationStatus.waiting,
    latestMessage: 'Needs human approval',
    author: 'Agent',
    unreadCount: 2,
    messageCount: 5,
  ),
  ConversationEntry(
    id: 'diagnostics',
    title: 'Diagnostics',
    subtitle: 'Terminal capability notes',
    status: ConversationStatus.idle,
    latestMessage: 'Probe complete',
    author: 'CLI',
    messageCount: 4,
  ),
];

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('ConversationNavigator', () {
    group('controller lifecycle', () {
      test('dispose is idempotent and keeps final readable state', () {
        final controller = ConversationNavigatorController(selectedIndex: 2);

        controller.dispose();
        controller.dispose();

        expect(controller.selectedIndex, 2);
        expect(controller.visibleRange, isNull);
      });

      test('mutating after dispose throws a lifecycle error', () {
        final controller = ConversationNavigatorController()..dispose();

        const message = 'ConversationNavigatorController has been disposed.';
        expect(() => controller.selectedIndex = 1, _stateError(message));
        expect(() => controller.jumpToIndex(1), _stateError(message));
      });
    });

    test('buildConversationOrder ranks by exact, prefix, contains, fuzzy', () {
      expect(buildConversationOrder(_entries(), query: 'deploy-review'), [1]);
      expect(buildConversationOrder(_entries(), query: 'terminal notes'), [2]);
    });

    test('exportConversation sanitizes controls and respects options', () {
      final text = exportConversation(
        const ConversationEntry(
          id: 'unsafe',
          title: 'bad\x1b]52;c;secret\x07',
          latestMessage: 'two\nlines',
          status: ConversationStatus.failed,
          unreadCount: 3,
          messageCount: 9,
          pinned: true,
        ),
      );

      expect(
        text,
        'bad$replacementCharacter | failed | 3 unread | 9 messages | '
        'pinned | two lines',
      );
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('\x1b]52')));

      expect(
        exportConversation(
          _entries().first,
          options: const ConversationNavigatorCopyOptions(
            includeStatus: false,
            includeLatestMessage: false,
          ),
        ),
        'Ops thread | 1 unread | 12 messages | pinned',
      );
    });

    testWidgets('showTimestamp prefixes rows with the entry clock', (tester) {
      tester.pumpWidget(
        ConversationNavigator(
          conversations: [
            ConversationEntry(
              id: 'c1',
              title: 'Ops thread',
              status: ConversationStatus.active,
              timestamp: DateTime.utc(2026, 6, 16, 8, 7, 6),
            ),
          ],
          showTimestamp: true,
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(90, 6),
        emptyMark: ' ',
      );
      expect(out, contains('08:07:06 Ops thread'));
    });

    testWidgets('filters, selects, and exposes conversation semantics', (
      tester,
    ) async {
      ConversationNavigatorSelectResult? selected;
      tester.pumpWidget(
        ConversationNavigator(
          label: 'Threads',
          conversations: _entries(),
          autofocus: true,
          onSelect: (result) => selected = result,
        ),
      );

      tester.type('deploy-review');
      tester.pump();
      tester.render(size: const CellSize(90, 6));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

      expect(selected?.entry.id, 'deploy-review');
      expect(selected?.entryIndex, 1);
      expect(selected?.viewIndex, 0);

      final navigator = tester.semantics().single(
        role: SemanticRole.conversationNavigator,
        label: 'Threads',
      );
      expect(navigator.state.filterText, 'deploy-review');
      expect(navigator.state['totalConversationCount'], 3);
      expect(navigator.state['filteredConversationCount'], 1);
      expect(navigator.state.selectedConversationId, 'deploy-review');
      expect(navigator.state['unreadConversationCount'], 2);

      final row = tester.semantics().single(
        role: SemanticRole.conversation,
        label: 'Deploy review',
        value: 'Needs human approval',
      );
      expect(row.selected, isTrue);
      expect(row.actions, contains(SemanticAction.activate));
      expect(row.state.conversationId, 'deploy-review');
      expect(row.state.conversationStatus, 'waiting');
      expect(row.state.conversationUnreadCount, 2);
      expect(row.state.conversationMessageCount, 5);

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.conversation,
        label: 'Deploy review',
      );
      expect(
        fallback.states,
        contains(
          'conversation id deploy-review, status waiting, 2 unread, '
          '5 messages',
        ),
      );
    });

    testWidgets('semantic navigate and row activation focus conversations', (
      tester,
    ) async {
      final controller = ConversationNavigatorController();
      ConversationNavigatorSelectResult? selected;
      tester.pumpWidget(
        ConversationNavigator(
          label: 'Threads',
          conversations: _entries(),
          controller: controller,
          onSelect: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(90, 7));
      var navigator = tester.semantics().single(
        role: SemanticRole.conversationNavigator,
        label: 'Threads',
        action: SemanticAction.focus,
      );
      expect(navigator.focused, isFalse);
      expect(navigator.actions, contains(SemanticAction.navigate));

      var result = await tester.invokeSemanticAction(
        SemanticAction.navigate,
        role: SemanticRole.conversationNavigator,
        label: 'Threads',
      );
      expect(result.completed, isTrue);

      tester.render(size: const CellSize(90, 7));
      navigator = tester.semantics().single(
        role: SemanticRole.conversationNavigator,
        label: 'Threads',
        focused: true,
      );
      expect(navigator.state.selectedConversationId, 'ops-main');

      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.conversation,
        label: 'Deploy review',
      );
      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 1);
      expect(selected?.entry.id, 'deploy-review');

      tester.render(size: const CellSize(90, 7));
      final row = tester.semantics().single(
        role: SemanticRole.conversation,
        label: 'Deploy review',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(row.state.conversationId, 'deploy-review');

      navigator = tester.semantics().single(
        role: SemanticRole.conversationNavigator,
        label: 'Threads',
        focused: true,
      );
      expect(navigator.state.selectedConversationId, 'deploy-review');
      expect(navigator.state['selectedIndex'], 1);
    });

    testWidgets('preserves selected conversation identity across refresh', (
      tester,
    ) {
      final controller = ConversationNavigatorController(selectedIndex: 2);
      tester.pumpWidget(
        ConversationNavigator(
          label: 'Threads',
          conversations: _entries(),
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(90, 7));

      tester.pumpWidget(
        ConversationNavigator(
          label: 'Threads',
          conversations: [
            _entries()[0],
            const ConversationEntry(
              id: 'new-review',
              title: 'New review',
              status: ConversationStatus.waiting,
              latestMessage: 'Fresh review',
              unreadCount: 1,
              messageCount: 1,
            ),
            _entries()[1],
            const ConversationEntry(
              id: 'diagnostics',
              title: 'Diagnostics',
              subtitle: 'Terminal capability notes',
              status: ConversationStatus.streaming,
              latestMessage: 'Probe streaming',
              author: 'CLI',
              unreadCount: 1,
              messageCount: 6,
            ),
          ],
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(90, 8));
      tester.pump();
      tester.render(size: const CellSize(90, 8));

      expect(controller.selectedIndex, 3);
      final navigator = tester.semantics().single(
        role: SemanticRole.conversationNavigator,
        label: 'Threads',
      );
      expect(navigator.state.selectedConversationId, 'diagnostics');
      expect(navigator.state['selectedConversationStatus'], 'streaming');

      final row = tester.semantics().single(
        role: SemanticRole.conversation,
        label: 'Diagnostics',
        selected: true,
      );
      expect(row.state.conversationStatus, 'streaming');
      expect(row.state.conversationMessageCount, 6);
      expect(row.busy, isTrue);
    });

    testWidgets('semantic copy copies the selected conversation', (
      tester,
    ) async {
      final originalClipboard = Clipboard.instance;
      final clipboard = TestClipboard();
      Clipboard.instance = clipboard;
      ConversationNavigatorCopyResult? copied;
      try {
        tester.pumpWidget(
          ConversationNavigator(
            conversations: _entries(),
            queryController: TextEditingController(text: 'ops-main'),
            copyOptions: const ConversationNavigatorCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        );

        tester.render(size: const CellSize(90, 6));
        final result = await tester.invokeSemanticAction(
          SemanticAction.copy,
          role: SemanticRole.conversation,
          label: 'Ops thread',
        );

        expect(result.completed, isTrue);
        expect(
          clipboard.lastWritten,
          'Ops thread | active | 1 unread | 12 messages | pinned | '
          'Ready for launch',
        );
        expect(copied?.entryIndex, 0);
        expect(copied?.viewIndex, 0);
        expect(copied?.report.policy.name, 'inProcessOnly');
      } finally {
        Clipboard.instance = originalClipboard;
      }
    });
  });
}
