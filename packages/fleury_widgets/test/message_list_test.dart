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
  group('MessageListController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = MessageListController(
        selectedIndex: 2,
        followTail: false,
      );

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 2);
      expect(controller.followTail, isFalse);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = MessageListController(followTail: true)..dispose();

      const message = 'MessageListController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.followTail = false, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
      expect(() => controller.scrollToBottom(), _stateError(message));
    });
  });

  testWidgets('renders messages with sanitized semantic state', (tester) {
    final controller = MessageListController(
      selectedIndex: 0,
      followTail: false,
    );
    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(
            id: 'm1',
            role: MessageRole.user,
            author: 'Operator',
            text: 'Deploy prod?',
          ),
          MessageEntry(
            id: 'm2',
            role: MessageRole.assistant,
            status: MessageStatus.streaming,
            author: 'Agent',
            text: 'Checking\x1b]52;c;secret\x07\nnow',
          ),
        ],
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(72, 5),
      emptyMark: ' ',
    );

    expect(output, contains('[user Operator] Deploy prod?'));
    expect(output, contains('[assistant Agent] Checking'));
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('\x1b]52')));

    final tree = tester.semantics();
    final list = tree.single(role: SemanticRole.messageList);
    expect(list.label, 'Conversation');
    expect(list.state.collectionRowCount, 2);
    expect(list.state['totalMessageCount'], 2);
    expect(list.state['followTail'], isFalse);
    expect(list.state.selectedKey, 'm1');
    expect(list.state['messageRole'], 'user');

    final row = tree
        .byRole(SemanticRole.message)
        .singleWhere((node) => node.state['rowKey'] == 'm2');
    expect(row.label, contains(replacementCharacter));
    expect(row.label, contains('now'));
    expect(row.label, isNot(contains('secret')));
    expect(row.state['messageRole'], 'assistant');
    expect(row.state['messageStatus'], 'streaming');
    expect(row.state['author'], 'Agent');
    expect(row.state.outputSanitized, isTrue);
  });

  testWidgets('showTimestamp prefixes rows with a local HH:mm:ss clock', (
    tester,
  ) {
    tester.pumpWidget(
      MessageList(
        controller: MessageListController(followTail: false),
        showTimestamp: true,
        messages: [
          MessageEntry(
            role: MessageRole.user,
            text: 'hi',
            timestamp: DateTime(2026, 6, 16, 9, 4, 5),
          ),
          // No timestamp → no clock prefix (and no spacer).
          const MessageEntry(role: MessageRole.assistant, text: 'hello'),
        ],
      ),
    );
    final output = tester.renderToString(
      size: const CellSize(72, 4),
      emptyMark: ' ',
    );
    expect(output, contains('09:04:05 [user] hi'));
    expect(output, contains('[assistant] hello'));
    expect(output, isNot(contains('09:04:05 [assistant]')));
  });

  testWidgets('semantic activate selects a message row', (tester) async {
    final controller = MessageListController(
      selectedIndex: 0,
      followTail: false,
    );
    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(
            id: 'm2',
            role: MessageRole.assistant,
            author: 'Agent',
            text: 'answer',
          ),
        ],
      ),
    );

    tester.render(size: const CellSize(60, 5));
    var row = tester.semantics().single(
      role: SemanticRole.message,
      label: 'answer',
      action: SemanticAction.activate,
    );
    expect(row.selected, isFalse);

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.message,
      label: 'answer',
    );

    expect(result.completed, isTrue);
    expect(controller.selectedIndex, 1);

    tester.render(size: const CellSize(60, 5));
    row = tester.semantics().single(
      role: SemanticRole.message,
      label: 'answer',
      selected: true,
      action: SemanticAction.copy,
    );
    expect(row.state['rowKey'], 'm2');
  });

  testWidgets('semantic focus and activation focus the message list', (
    tester,
  ) async {
    final controller = MessageListController(
      selectedIndex: 0,
      followTail: false,
    );
    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(
            id: 'm2',
            role: MessageRole.assistant,
            author: 'Agent',
            text: 'answer',
          ),
        ],
      ),
    );

    tester.render(size: const CellSize(60, 5));
    var list = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Conversation',
      action: SemanticAction.focus,
    );
    expect(list.focused, isFalse);
    expect(list.actions, contains(SemanticAction.navigate));

    var result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.messageList,
      label: 'Conversation',
    );
    expect(result.completed, isTrue);

    tester.render(size: const CellSize(60, 5));
    list = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Conversation',
      focused: true,
    );
    expect(list.state.selectedMessageId, 'm1');

    result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.message,
      label: 'answer',
    );
    expect(result.completed, isTrue);
    expect(controller.selectedIndex, 1);
    expect(controller.followTail, isFalse);

    tester.render(size: const CellSize(60, 5));
    final row = tester.semantics().single(
      role: SemanticRole.message,
      label: 'answer',
      selected: true,
      action: SemanticAction.copy,
    );
    expect(row.state.messageId, 'm2');

    list = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Conversation',
      focused: true,
    );
    expect(list.state.selectedMessageId, 'm2');
    expect(list.state['selectedIndex'], 1);
  });

  testWidgets('synchronously preserves selected identity across prepend', (
    tester,
  ) {
    final controller = MessageListController(
      selectedIndex: 2,
      followTail: false,
    );
    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(id: 'm2', role: MessageRole.tool, text: 'lookup'),
          MessageEntry(id: 'm3', role: MessageRole.assistant, text: 'answer'),
        ],
      ),
    );
    tester.render(size: const CellSize(60, 5));

    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(id: 'm0', role: MessageRole.system, text: 'inserted'),
          MessageEntry(id: 'm2', role: MessageRole.tool, text: 'lookup'),
          MessageEntry(
            id: 'm3',
            role: MessageRole.assistant,
            status: MessageStatus.streaming,
            text: 'updated answer',
          ),
        ],
      ),
    );

    expect(
      controller.selectedIndex,
      3,
      reason: 'selection remaps during the rebuild, without a deferred pump',
    );
    tester.render(size: const CellSize(60, 5));
    final list = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Conversation',
    );
    expect(list.state.selectedMessageId, 'm3');
    expect(list.state['messageStatus'], 'streaming');

    final selected = tester.semantics().single(
      role: SemanticRole.message,
      label: 'updated answer',
      selected: true,
    );
    expect(selected.state.messageId, 'm3');
  });

  testWidgets('reorder preserves selection and refreshed message state', (
    tester,
  ) {
    final controller = MessageListController(
      selectedIndex: 1,
      followTail: false,
    );
    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(id: 'm2', role: MessageRole.assistant, text: 'working'),
          MessageEntry(id: 'm3', role: MessageRole.tool, text: 'lookup'),
        ],
      ),
    );
    tester.render(size: const CellSize(60, 5));

    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(
            id: 'm2',
            role: MessageRole.assistant,
            status: MessageStatus.complete,
            text: 'finished',
          ),
          MessageEntry(id: 'm3', role: MessageRole.tool, text: 'lookup'),
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
        ],
      ),
    );

    expect(
      controller.selectedIndex,
      0,
      reason: 'the selected m2 row moves synchronously with its stable id',
    );
    expect(controller.followTail, isFalse);
    tester.render(size: const CellSize(60, 5));
    final selected = tester.semantics().single(
      role: SemanticRole.message,
      label: 'finished',
      selected: true,
    );
    expect(selected.state.messageId, 'm2');
    expect(selected.state['messageStatus'], 'complete');
  });

  testWidgets('id-less entries retain identity when their instances move', (
    tester,
  ) {
    final first = MessageEntry(role: MessageRole.user, text: 'first');
    final selectedEntry = MessageEntry(
      role: MessageRole.assistant,
      status: MessageStatus.streaming,
      text: 'selected',
      metadata: const {'attempt': 7},
    );
    final last = MessageEntry(role: MessageRole.tool, text: 'last');
    final prepended = MessageEntry(role: MessageRole.system, text: 'prepended');
    final controller = MessageListController(
      selectedIndex: 1,
      followTail: false,
    );

    tester.pumpWidget(
      MessageList(
        controller: controller,
        messages: [first, selectedEntry, last],
      ),
    );
    tester.render(size: const CellSize(60, 5));

    tester.pumpWidget(
      MessageList(
        controller: controller,
        messages: [prepended, last, first, selectedEntry],
      ),
    );

    expect(
      controller.selectedIndex,
      3,
      reason: 'the same id-less MessageEntry instance is its fallback key',
    );
    tester.render(size: const CellSize(60, 5));
    final selected = tester.semantics().single(
      role: SemanticRole.message,
      label: 'selected',
      selected: true,
    );
    expect(selected.state['messageStatus'], 'streaming');
    expect(selected.state['attempt'], 7);
  });

  testWidgets('repairs its key index after an in-place list reorder', (tester) {
    final messages = <MessageEntry>[
      const MessageEntry(id: 'm1', text: 'first'),
      const MessageEntry(id: 'm2', text: 'selected'),
      const MessageEntry(id: 'm3', text: 'third'),
    ];
    final controller = MessageListController(
      selectedIndex: 1,
      followTail: false,
    );
    tester.pumpWidget(MessageList(controller: controller, messages: messages));
    tester.render(size: const CellSize(60, 5));

    final reordered = <MessageEntry>[messages[2], messages[0], messages[1]];
    messages
      ..clear()
      ..addAll(reordered);
    tester.pumpWidget(MessageList(controller: controller, messages: messages));

    expect(controller.selectedIndex, 2);
    tester.render(size: const CellSize(60, 5));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.message, label: 'selected', selected: true)
          .state
          .messageId,
      'm2',
    );
  });

  testWidgets('clears selection synchronously when the list becomes empty', (
    tester,
  ) {
    final controller = MessageListController(
      selectedIndex: 1,
      followTail: false,
    );
    tester.pumpWidget(
      MessageList(
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', text: 'first'),
          MessageEntry(id: 'm2', text: 'second'),
        ],
      ),
    );
    tester.render(size: const CellSize(60, 5));

    tester.pumpWidget(MessageList(controller: controller, messages: const []));

    expect(controller.selectedIndex, isNull);
  });

  testWidgets('preserves tail-follow selection on append', (tester) {
    final controller = MessageListController(followTail: true);
    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(id: 'm2', role: MessageRole.assistant, text: 'answer'),
        ],
      ),
    );
    tester.render(size: const CellSize(60, 5));
    expect(controller.selectedIndex, 1);

    tester.pumpWidget(
      MessageList(
        semanticLabel: 'Conversation',
        controller: controller,
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'question'),
          MessageEntry(id: 'm2', role: MessageRole.assistant, text: 'answer'),
          MessageEntry(id: 'm3', role: MessageRole.log, text: 'tail event'),
        ],
      ),
    );
    tester.render(size: const CellSize(60, 5));

    expect(controller.followTail, isTrue);
    expect(controller.selectedIndex, 2);
    final list = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Conversation',
    );
    expect(list.state.selectedMessageId, 'm3');
  });

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected message', (tester) async {
      final controller = MessageListController(
        selectedIndex: 1,
        followTail: false,
      );
      MessageListCopyResult? copied;
      tester.pumpWidget(
        MessageList(
          controller: controller,
          autofocus: true,
          messages: const [
            MessageEntry(role: MessageRole.user, text: 'question'),
            MessageEntry(
              id: 'm2',
              role: MessageRole.assistant,
              author: 'Agent',
              text: 'answer',
            ),
          ],
          copyOptions: const MessageListCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(60, 5));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '[assistant Agent] answer');
      expect(copied, isNotNull);
      expect(copied!.messageIndex, 1);
      expect(copied!.message.id, 'm2');
      expect(copied!.report.policy.name, 'inProcessOnly');
    });

    testWidgets('semantic copy copies the selected message', (tester) async {
      final controller = MessageListController(
        selectedIndex: 1,
        followTail: false,
      );
      MessageListCopyResult? copied;
      tester.pumpWidget(
        MessageList(
          controller: controller,
          messages: const [
            MessageEntry(role: MessageRole.user, text: 'question'),
            MessageEntry(
              id: 'm2',
              role: MessageRole.assistant,
              author: 'Agent',
              text: 'answer',
            ),
          ],
          copyOptions: const MessageListCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(60, 5));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.message,
        selected: true,
      );

      expect(result.completed, isTrue);
      expect(tester.clipboard.readInProcess(), '[assistant Agent] answer');
      expect(copied?.messageIndex, 1);
    });

    test('exportMessages sanitizes, truncates, and preserves order', () {
      final result = exportMessages(
        const [
          MessageEntry(role: MessageRole.system, text: 'boot'),
          MessageEntry(
            role: MessageRole.tool,
            author: 'runner',
            text: 'abcdef\nx',
          ),
          MessageEntry(role: MessageRole.assistant, text: 'done'),
        ],
        options: const MessageListExportOptions(
          startIndex: 1,
          maxMessages: 1,
          maxLineLength: 5,
        ),
      );

      expect(result.text, '[tool runner] abcde');
      expect(result.messageCount, 1);
      expect(result.startIndex, 1);
      expect(result.truncated, isTrue);
    });
  });

  testWidgets('accessibility snapshot describes message roles and status', (
    tester,
  ) {
    tester.pumpWidget(
      const MessageList(
        messages: [
          MessageEntry(
            id: 'm1',
            role: MessageRole.assistant,
            status: MessageStatus.streaming,
            author: 'Agent',
            text: 'Working',
          ),
        ],
      ),
    );

    tester.render(size: const CellSize(60, 4));

    final snapshot = tester.accessibilitySnapshot();
    final row = snapshot.single(role: SemanticRole.message);
    expect(
      row.states,
      contains('message role assistant, status streaming, author Agent, id m1'),
    );
  });
}
