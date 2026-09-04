import 'package:fleury/fleury_core.dart';

/// Semantic roles contributed by the `fleury_widgets` catalog.
///
/// Core Fleury owns the generic vocabulary every surface understands — the
/// constants on [SemanticRole]. The roles below describe this catalog's domain
/// widgets (agent consoles, code review, tracing, workflow plans), and each
/// names the core role it projects through, so a surface that only knows the
/// core set — the served browser client, an older agent bridge, the coverage
/// policy — still treats a patch review as a region and a message as a list
/// item.
///
/// Match them exactly like core roles:
///
/// ```dart
/// find.byRole(WidgetRoles.toolCall)
/// tree.byRole(WidgetRoles.message)
/// if (node.role == WidgetRoles.approval) ...
/// ```
///
/// Declare your own the same way in your own package; see [SemanticRole].
abstract final class WidgetRoles {
  /// `ConversationNavigator`: the searchable list of conversations.
  static const conversationNavigator = SemanticRole(
    'conversationNavigator',
    base: SemanticRole.navigation,
  );

  /// One conversation row inside a `ConversationNavigator`.
  static const conversation = SemanticRole(
    'conversation',
    base: SemanticRole.listItem,
  );

  /// `ContextPanel`: the attached-context region of an agent console.
  static const contextPanel = SemanticRole(
    'contextPanel',
    base: SemanticRole.region,
  );

  /// One attached item inside a `ContextPanel`.
  static const contextItem = SemanticRole(
    'contextItem',
    base: SemanticRole.listItem,
  );

  /// `TraceTimeline`: an ordered list of trace events.
  static const traceTimeline = SemanticRole(
    'traceTimeline',
    base: SemanticRole.list,
  );

  /// One event inside a `TraceTimeline`.
  static const traceEvent = SemanticRole(
    'traceEvent',
    base: SemanticRole.listItem,
  );

  /// `PatchReview`: the review surface for a set of file patches.
  static const patchReview = SemanticRole(
    'patchReview',
    base: SemanticRole.region,
  );

  /// One file inside a `PatchReview`.
  static const patchFile = SemanticRole(
    'patchFile',
    base: SemanticRole.listItem,
  );

  /// `MessageList`: a transcript of conversation messages.
  static const messageList = SemanticRole(
    'messageList',
    base: SemanticRole.list,
  );

  /// One message inside a `MessageList`.
  static const message = SemanticRole('message', base: SemanticRole.listItem);

  /// `FileMentionPicker`: the file search popup behind an `@` mention.
  static const fileMentionPicker = SemanticRole(
    'fileMentionPicker',
    base: SemanticRole.list,
  );

  /// One candidate file inside a `FileMentionPicker`.
  static const fileMention = SemanticRole(
    'fileMention',
    base: SemanticRole.listItem,
  );

  /// `CommandPalette`: the searchable command menu. Its rows are core
  /// [SemanticRole.command] nodes, shared with the app kernel.
  static const commandPalette = SemanticRole(
    'commandPalette',
    base: SemanticRole.menu,
  );

  /// `ModelStatusBar`: the live status of the active model.
  static const modelStatus = SemanticRole(
    'modelStatus',
    base: SemanticRole.status,
  );

  /// The token-usage meter inside a `ModelStatusBar`.
  static const tokenMeter = SemanticRole(
    'tokenMeter',
    base: SemanticRole.status,
  );

  /// `TaskGraph`: a workflow plan. Its nodes are core [SemanticRole.task]s.
  static const taskGraph = SemanticRole('taskGraph', base: SemanticRole.tree);

  /// `ToolCallCard`: one tool invocation and its live status.
  static const toolCall = SemanticRole('toolCall', base: SemanticRole.status);

  /// `ApprovalPrompt`: a request the user must approve or reject.
  static const approval = SemanticRole('approval', base: SemanticRole.button);

  /// Every role this catalog declares, for tooling that enumerates
  /// vocabularies.
  static const List<SemanticRole> values = <SemanticRole>[
    conversationNavigator,
    conversation,
    contextPanel,
    contextItem,
    traceTimeline,
    traceEvent,
    patchReview,
    patchFile,
    messageList,
    message,
    fileMentionPicker,
    fileMention,
    commandPalette,
    modelStatus,
    tokenMeter,
    taskGraph,
    toolCall,
    approval,
  ];
}
