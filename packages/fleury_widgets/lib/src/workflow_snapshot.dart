import 'package:fleury/fleury_core.dart';

import 'approval_prompt.dart';
import 'context_panel.dart';
import 'conversation_navigator.dart';
import 'file_mention_picker.dart';
import 'log_region.dart';
import 'message_list.dart';
import 'model_status_bar.dart';
import 'patch_review.dart';
import 'task_graph.dart';
import 'tool_call_card.dart';
import 'trace_timeline.dart';

/// High-level health for a protocol-neutral developer workflow snapshot.
enum WorkflowHealth { idle, active, needsAttention, failed }

/// Aggregates the first-party workflow records used by developer-tool and
/// agent-style Fleury apps.
///
/// This is intentionally a data snapshot, not a transport, router, provider
/// session, persistence model, or ACP schema. Apps and adapter packages map
/// their own domain state into these protocol-neutral records, while Fleury
/// owns summaries, safe semantic state, and testable lookup behavior.
final class WorkflowSnapshot {
  WorkflowSnapshot({
    this.id,
    this.title,
    List<MessageEntry> messages = const <MessageEntry>[],
    List<ToolCallRecord> toolCalls = const <ToolCallRecord>[],
    List<ApprovalRequest> approvals = const <ApprovalRequest>[],
    List<TaskGraphNode> tasks = const <TaskGraphNode>[],
    this.modelStatus,
    List<ContextItem> contextItems = const <ContextItem>[],
    List<FileMentionEntry> fileMentions = const <FileMentionEntry>[],
    List<ConversationEntry> conversations = const <ConversationEntry>[],
    List<TraceTimelineEntry> traceEvents = const <TraceTimelineEntry>[],
    List<PatchReviewFile> patchFiles = const <PatchReviewFile>[],
    List<LogEntry> logEntries = const <LogEntry>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : messages = List<MessageEntry>.unmodifiable(messages),
       toolCalls = List<ToolCallRecord>.unmodifiable(toolCalls),
       approvals = List<ApprovalRequest>.unmodifiable(approvals),
       tasks = List<TaskGraphNode>.unmodifiable(tasks),
       contextItems = List<ContextItem>.unmodifiable(contextItems),
       fileMentions = List<FileMentionEntry>.unmodifiable(fileMentions),
       conversations = List<ConversationEntry>.unmodifiable(conversations),
       traceEvents = List<TraceTimelineEntry>.unmodifiable(traceEvents),
       patchFiles = List<PatchReviewFile>.unmodifiable(patchFiles),
       logEntries = List<LogEntry>.unmodifiable(logEntries),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  /// Optional stable workflow identity.
  final Object? id;

  /// Human-readable workflow title.
  final String? title;

  /// Conversation or transcript messages in this workflow.
  final List<MessageEntry> messages;

  /// Tool calls attached to the workflow.
  final List<ToolCallRecord> toolCalls;

  /// Pending or completed approval requests.
  final List<ApprovalRequest> approvals;

  /// Task graph nodes representing planned or running work.
  final List<TaskGraphNode> tasks;

  /// Current model/runtime status, if known.
  final ModelStatusInfo? modelStatus;

  /// Context items currently attached to the workflow.
  final List<ContextItem> contextItems;

  /// Mentionable files or paths associated with the workflow.
  final List<FileMentionEntry> fileMentions;

  /// Conversation summaries available to the workflow.
  final List<ConversationEntry> conversations;

  /// Trace or timeline events for active work.
  final List<TraceTimelineEntry> traceEvents;

  /// Patch files currently under review.
  final List<PatchReviewFile> patchFiles;

  /// Log rows associated with the workflow.
  final List<LogEntry> logEntries;

  /// App-specific semantic state carried by the snapshot.
  final Map<String, Object?> metadata;

  /// Derived aggregate health, counts, and semantic state.
  late final WorkflowSummary summary = WorkflowSummary.fromSnapshot(this);

  SemanticState toSemanticState() {
    return summary.toSemanticState().merge(<String, Object?>{
      if (id != null) 'workflowId': id.toString(),
      if (title != null) 'workflowTitle': title,
    });
  }

  MessageEntry? messageById(Object id) {
    return _firstOrNull(messages, (message) => message.id == id);
  }

  ToolCallRecord? toolCallById(String id) {
    return _firstOrNull(toolCalls, (record) => record.id == id);
  }

  ApprovalRequest? approvalById(String id) {
    return _firstOrNull(approvals, (request) => request.id == id);
  }

  TaskGraphNode? taskById(Object id) {
    return _firstOrNull(tasks, (task) => task.id == id);
  }

  ContextItem? contextItemById(Object id) {
    return _firstOrNull(contextItems, (item) => item.id == id);
  }

  FileMentionEntry? fileMentionByPath(String path) {
    return _firstOrNull(fileMentions, (entry) => entry.path == path);
  }

  ConversationEntry? conversationById(Object id) {
    return _firstOrNull(conversations, (conversation) => conversation.id == id);
  }

  TraceTimelineEntry? traceById(Object id) {
    return _firstOrNull(traceEvents, (trace) => trace.id == id);
  }

  PatchReviewFile? patchFileById(Object id) {
    return _firstOrNull(patchFiles, (file) => file.id == id);
  }

  PatchReviewFile? patchFileByPath(String path) {
    return _firstOrNull(patchFiles, (file) => file.path == path);
  }
}

/// Safe aggregate state derived from a [WorkflowSnapshot].
final class WorkflowSummary {
  const WorkflowSummary({
    required this.health,
    required this.messageCount,
    required this.activeMessageCount,
    required this.failedMessageCount,
    required this.toolCallCount,
    required this.activeToolCallCount,
    required this.failedToolCallCount,
    required this.approvalCount,
    required this.taskCount,
    required this.activeTaskCount,
    required this.failedTaskCount,
    required this.modelBusy,
    required this.modelStatus,
    required this.contextItemCount,
    required this.contextTokenCount,
    required this.fileMentionCount,
    required this.conversationCount,
    required this.unreadConversationCount,
    required this.traceEventCount,
    required this.activeTraceEventCount,
    required this.failedTraceEventCount,
    required this.warningTraceEventCount,
    required this.patchFileCount,
    required this.reviewIssueCount,
    required this.logEntryCount,
    required this.warningLogEntryCount,
    required this.errorLogEntryCount,
  });

  factory WorkflowSummary.fromSnapshot(WorkflowSnapshot snapshot) {
    final activeMessageCount = snapshot.messages
        .where((message) => _messageActive(message.status))
        .length;
    final failedMessageCount = snapshot.messages
        .where((message) => message.status == MessageStatus.failed)
        .length;
    final activeToolCallCount = snapshot.toolCalls
        .where((record) => record.busy)
        .length;
    final failedToolCallCount = snapshot.toolCalls
        .where((record) => record.status == ToolCallStatus.failed)
        .length;
    final activeTaskCount = snapshot.tasks
        .where((task) => _taskActive(task.status))
        .length;
    final failedTaskCount = snapshot.tasks
        .where((task) => task.status == TaskGraphStatus.failed)
        .length;
    final activeTraceEventCount = snapshot.traceEvents
        .where((trace) => trace.status == TraceTimelineStatus.running)
        .length;
    final failedTraceEventCount = snapshot.traceEvents
        .where((trace) => trace.status == TraceTimelineStatus.failed)
        .length;
    final warningTraceEventCount = snapshot.traceEvents
        .where((trace) => trace.status == TraceTimelineStatus.warning)
        .length;
    final reviewIssueCount = snapshot.patchFiles
        .where((file) => _patchNeedsAttention(file.status))
        .length;
    final warningLogEntryCount = snapshot.logEntries
        .where((entry) => entry.severity == LogSeverity.warning)
        .length;
    final errorLogEntryCount = snapshot.logEntries
        .where((entry) => entry.severity == LogSeverity.error)
        .length;
    final modelStatus = snapshot.modelStatus?.status;
    final modelBusy = snapshot.modelStatus?.busy ?? false;
    final hasFailures =
        failedMessageCount > 0 ||
        failedToolCallCount > 0 ||
        failedTaskCount > 0 ||
        failedTraceEventCount > 0 ||
        errorLogEntryCount > 0 ||
        snapshot.patchFiles.any(
          (file) =>
              file.status == PatchReviewStatus.failed ||
              file.status == PatchReviewStatus.rejected,
        ) ||
        modelStatus == ModelRuntimeStatus.error;
    final needsAttention =
        snapshot.approvals.isNotEmpty ||
        reviewIssueCount > 0 ||
        warningTraceEventCount > 0 ||
        warningLogEntryCount > 0 ||
        modelStatus == ModelRuntimeStatus.degraded ||
        modelStatus == ModelRuntimeStatus.offline;
    final hasActiveWork =
        activeMessageCount > 0 ||
        activeToolCallCount > 0 ||
        activeTaskCount > 0 ||
        activeTraceEventCount > 0 ||
        modelBusy;

    return WorkflowSummary(
      health: hasFailures
          ? WorkflowHealth.failed
          : needsAttention
          ? WorkflowHealth.needsAttention
          : hasActiveWork
          ? WorkflowHealth.active
          : WorkflowHealth.idle,
      messageCount: snapshot.messages.length,
      activeMessageCount: activeMessageCount,
      failedMessageCount: failedMessageCount,
      toolCallCount: snapshot.toolCalls.length,
      activeToolCallCount: activeToolCallCount,
      failedToolCallCount: failedToolCallCount,
      approvalCount: snapshot.approvals.length,
      taskCount: snapshot.tasks.length,
      activeTaskCount: activeTaskCount,
      failedTaskCount: failedTaskCount,
      modelBusy: modelBusy,
      modelStatus: modelStatus,
      contextItemCount: snapshot.contextItems.length,
      contextTokenCount: snapshot.contextItems.fold<int>(
        0,
        (total, item) => total + item.tokenCount,
      ),
      fileMentionCount: snapshot.fileMentions.length,
      conversationCount: snapshot.conversations.length,
      unreadConversationCount: snapshot.conversations.fold<int>(
        0,
        (total, conversation) => total + conversation.unreadCount,
      ),
      traceEventCount: snapshot.traceEvents.length,
      activeTraceEventCount: activeTraceEventCount,
      failedTraceEventCount: failedTraceEventCount,
      warningTraceEventCount: warningTraceEventCount,
      patchFileCount: snapshot.patchFiles.length,
      reviewIssueCount: reviewIssueCount,
      logEntryCount: snapshot.logEntries.length,
      warningLogEntryCount: warningLogEntryCount,
      errorLogEntryCount: errorLogEntryCount,
    );
  }

  final WorkflowHealth health;
  final int messageCount;
  final int activeMessageCount;
  final int failedMessageCount;
  final int toolCallCount;
  final int activeToolCallCount;
  final int failedToolCallCount;
  final int approvalCount;
  final int taskCount;
  final int activeTaskCount;
  final int failedTaskCount;
  final bool modelBusy;
  final ModelRuntimeStatus? modelStatus;
  final int contextItemCount;
  final int contextTokenCount;
  final int fileMentionCount;
  final int conversationCount;
  final int unreadConversationCount;
  final int traceEventCount;
  final int activeTraceEventCount;
  final int failedTraceEventCount;
  final int warningTraceEventCount;
  final int patchFileCount;
  final int reviewIssueCount;
  final int logEntryCount;
  final int warningLogEntryCount;
  final int errorLogEntryCount;

  bool get hasActiveWork =>
      activeMessageCount > 0 ||
      activeToolCallCount > 0 ||
      activeTaskCount > 0 ||
      activeTraceEventCount > 0 ||
      modelBusy;

  bool get hasFailures =>
      failedMessageCount > 0 ||
      failedToolCallCount > 0 ||
      failedTaskCount > 0 ||
      failedTraceEventCount > 0 ||
      errorLogEntryCount > 0 ||
      health == WorkflowHealth.failed;

  bool get needsAttention =>
      approvalCount > 0 ||
      reviewIssueCount > 0 ||
      warningTraceEventCount > 0 ||
      warningLogEntryCount > 0 ||
      health == WorkflowHealth.needsAttention;

  Map<String, Object?> toJson() => <String, Object?>{
    'health': health.name,
    'messageCount': messageCount,
    'activeMessageCount': activeMessageCount,
    'failedMessageCount': failedMessageCount,
    'toolCallCount': toolCallCount,
    'activeToolCallCount': activeToolCallCount,
    'failedToolCallCount': failedToolCallCount,
    'approvalCount': approvalCount,
    'taskCount': taskCount,
    'activeTaskCount': activeTaskCount,
    'failedTaskCount': failedTaskCount,
    'modelBusy': modelBusy,
    if (modelStatus != null) 'modelStatus': modelStatus!.name,
    'contextItemCount': contextItemCount,
    'contextTokenCount': contextTokenCount,
    'fileMentionCount': fileMentionCount,
    'conversationCount': conversationCount,
    'unreadConversationCount': unreadConversationCount,
    'traceEventCount': traceEventCount,
    'activeTraceEventCount': activeTraceEventCount,
    'failedTraceEventCount': failedTraceEventCount,
    'warningTraceEventCount': warningTraceEventCount,
    'patchFileCount': patchFileCount,
    'reviewIssueCount': reviewIssueCount,
    'logEntryCount': logEntryCount,
    'warningLogEntryCount': warningLogEntryCount,
    'errorLogEntryCount': errorLogEntryCount,
  };

  SemanticState toSemanticState() {
    return SemanticState(<String, Object?>{
      'workflowHealth': health.name,
      ...toJson(),
    });
  }
}

bool _messageActive(MessageStatus status) {
  return status == MessageStatus.queued || status == MessageStatus.streaming;
}

bool _taskActive(TaskGraphStatus status) {
  return status == TaskGraphStatus.pending || status == TaskGraphStatus.running;
}

bool _patchNeedsAttention(PatchReviewStatus status) {
  return status == PatchReviewStatus.reviewing ||
      status == PatchReviewStatus.changesRequested ||
      status == PatchReviewStatus.rejected ||
      status == PatchReviewStatus.failed;
}

T? _firstOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
