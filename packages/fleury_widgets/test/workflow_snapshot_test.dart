import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('WorkflowSnapshot', () {
    test('summarizes protocol-neutral workflow state', () {
      final snapshot = WorkflowSnapshot(
        id: 'session-1',
        title: 'Proof session',
        messages: const [
          MessageEntry(id: 'm1', role: MessageRole.user, text: 'run it'),
          MessageEntry(
            id: 'm2',
            role: MessageRole.assistant,
            status: MessageStatus.streaming,
            text: 'working',
          ),
        ],
        toolCalls: const [
          ToolCallRecord(
            id: 'tool-1',
            name: 'search',
            status: ToolCallStatus.running,
          ),
        ],
        approvals: const [
          ApprovalRequest(
            id: 'approval-1',
            title: 'Deploy',
            message: 'Approve deploy?',
          ),
        ],
        tasks: const [
          TaskGraphNode(
            id: 'task-1',
            title: 'Index',
            status: TaskGraphStatus.running,
          ),
        ],
        modelStatus: const ModelStatusInfo(
          model: 'fleury-prover',
          status: ModelRuntimeStatus.streaming,
          tokenUsage: TokenUsage(input: 10, output: 5, contextLimit: 100),
        ),
        contextItems: const [
          ContextItem(id: 'ctx-1', label: 'File', tokenCount: 42),
        ],
        fileMentions: const [
          FileMentionEntry(path: 'lib/main.dart', mentionText: '@main'),
        ],
        conversations: const [
          ConversationEntry(
            id: 'thread-1',
            title: 'Main',
            unreadCount: 2,
            messageCount: 3,
          ),
        ],
        traceEvents: const [
          TraceTimelineEntry(
            id: 'trace-1',
            label: 'Task',
            status: TraceTimelineStatus.running,
          ),
        ],
        patchFiles: const [
          PatchReviewFile(
            id: 'file-1',
            path: 'lib/main.dart',
            status: PatchReviewStatus.reviewing,
          ),
        ],
        logEntries: const [
          LogEntry(message: 'warn', severity: LogSeverity.warning),
        ],
      );

      final summary = snapshot.summary;

      expect(summary.health, WorkflowHealth.needsAttention);
      expect(summary.messageCount, 2);
      expect(summary.activeMessageCount, 1);
      expect(summary.toolCallCount, 1);
      expect(summary.activeToolCallCount, 1);
      expect(summary.approvalCount, 1);
      expect(summary.taskCount, 1);
      expect(summary.activeTaskCount, 1);
      expect(summary.modelBusy, isTrue);
      expect(summary.contextItemCount, 1);
      expect(summary.contextTokenCount, 42);
      expect(summary.fileMentionCount, 1);
      expect(summary.conversationCount, 1);
      expect(summary.unreadConversationCount, 2);
      expect(summary.traceEventCount, 1);
      expect(summary.activeTraceEventCount, 1);
      expect(summary.patchFileCount, 1);
      expect(summary.reviewIssueCount, 1);
      expect(summary.warningLogEntryCount, 1);
      expect(summary.errorLogEntryCount, 0);

      final state = snapshot.toSemanticState();
      expect(state['workflowId'], 'session-1');
      expect(state['workflowTitle'], 'Proof session');
      expect(state['workflowHealth'], 'needsAttention');
      expect(state['messageCount'], 2);
      expect(state['activeTaskCount'], 1);
      expect(state['contextTokenCount'], 42);
      expect(state['unreadConversationCount'], 2);
    });

    test('reports failed health when any critical workflow surface fails', () {
      final snapshot = WorkflowSnapshot(
        messages: const [
          MessageEntry(id: 'm1', status: MessageStatus.failed, text: 'failed'),
        ],
        toolCalls: const [
          ToolCallRecord(
            id: 'tool-1',
            name: 'build',
            status: ToolCallStatus.failed,
          ),
        ],
        tasks: const [
          TaskGraphNode(
            id: 'task-1',
            title: 'Build',
            status: TaskGraphStatus.failed,
          ),
        ],
        traceEvents: const [
          TraceTimelineEntry(
            id: 'trace-1',
            label: 'Build',
            status: TraceTimelineStatus.failed,
          ),
        ],
        logEntries: const [
          LogEntry(message: 'boom', severity: LogSeverity.error),
        ],
      );

      expect(snapshot.summary.health, WorkflowHealth.failed);
      expect(snapshot.summary.failedMessageCount, 1);
      expect(snapshot.summary.failedToolCallCount, 1);
      expect(snapshot.summary.failedTaskCount, 1);
      expect(snapshot.summary.failedTraceEventCount, 1);
      expect(snapshot.summary.errorLogEntryCount, 1);
      expect(snapshot.summary.hasFailures, isTrue);
    });

    test('preserves immutable lists and provides stable lookup helpers', () {
      final sourceMessages = [const MessageEntry(id: 'm1', text: 'hello')];
      final snapshot = WorkflowSnapshot(
        messages: sourceMessages,
        toolCalls: const [ToolCallRecord(id: 'tool-1', name: 'read')],
        approvals: const [
          ApprovalRequest(
            id: 'approval-1',
            title: 'Approve',
            message: 'Continue?',
          ),
        ],
        tasks: const [TaskGraphNode(id: 'task-1', title: 'Task')],
        contextItems: const [ContextItem(id: 'ctx-1', label: 'Context')],
        fileMentions: const [FileMentionEntry(path: 'lib/app.dart')],
        conversations: const [
          ConversationEntry(id: 'thread-1', title: 'Thread'),
        ],
        traceEvents: const [TraceTimelineEntry(id: 'trace-1', label: 'Trace')],
        patchFiles: const [PatchReviewFile(id: 'file-1', path: 'lib/app.dart')],
      );

      sourceMessages.add(const MessageEntry(id: 'm2', text: 'later'));

      expect(snapshot.messages, hasLength(1));
      expect(
        () => snapshot.messages.add(
          const MessageEntry(id: 'm3', text: 'blocked'),
        ),
        throwsUnsupportedError,
      );
      expect(snapshot.messageById('m1')!.text, 'hello');
      expect(snapshot.toolCallById('tool-1')!.name, 'read');
      expect(snapshot.approvalById('approval-1')!.title, 'Approve');
      expect(snapshot.taskById('task-1')!.title, 'Task');
      expect(snapshot.contextItemById('ctx-1')!.label, 'Context');
      expect(
        snapshot.fileMentionByPath('lib/app.dart')!.displayMention,
        '@lib/app.dart',
      );
      expect(snapshot.conversationById('thread-1')!.title, 'Thread');
      expect(snapshot.traceById('trace-1')!.label, 'Trace');
      expect(snapshot.patchFileById('file-1')!.path, 'lib/app.dart');
      expect(snapshot.patchFileByPath('lib/app.dart')!.id, 'file-1');
      expect(snapshot.messageById('missing'), isNull);
    });
  });
}
