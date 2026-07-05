import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

/// Protocol-neutral role for one message in a [MessageList].
enum MessageRole { user, assistant, system, tool, log, event }

/// Lifecycle/status attached to one message in a [MessageList].
enum MessageStatus { queued, streaming, complete, failed, cancelled }

/// One logical message in a [MessageList].
final class MessageEntry {
  const MessageEntry({
    required this.text,
    this.id,
    this.role = MessageRole.log,
    this.status = MessageStatus.complete,
    this.author,
    this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  /// Stable identity used by semantics and copy callbacks.
  final Object? id;

  /// Protocol-neutral role for the message.
  final MessageRole role;

  /// Status for streamed or workflow-owned messages.
  final MessageStatus status;

  /// Optional display author/source.
  final String? author;

  /// Optional message timestamp.
  final DateTime? timestamp;

  /// Message body text.
  final String text;

  /// App-specific semantic state carried by the message.
  final Map<String, Object?> metadata;
}

/// Options for exporting [MessageEntry] rows.
final class MessageListExportOptions {
  const MessageListExportOptions({
    this.includePrefix = true,
    this.startIndex = 0,
    this.maxMessages,
    this.maxLineLength = 1000,
  }) : assert(startIndex >= 0),
       assert(maxMessages == null || maxMessages >= 0),
       assert(maxLineLength == null || maxLineLength >= 0);

  /// Whether exported rows include role/status/author prefixes.
  final bool includePrefix;

  /// First message index to export.
  final int startIndex;

  /// Maximum number of messages to export.
  final int? maxMessages;

  /// Maximum copied/displayed message length per row.
  final int? maxLineLength;
}

/// Result of exporting [MessageEntry] rows.
final class MessageListExportResult {
  const MessageListExportResult({
    required this.text,
    required this.messageCount,
    required this.startIndex,
    required this.truncated,
  });

  final String text;
  final int messageCount;
  final int startIndex;
  final bool truncated;
}

/// Clipboard behavior for [MessageList] selected-message copy.
final class MessageListCopyOptions {
  const MessageListCopyOptions({
    this.includePrefix = true,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  });

  /// Whether copied rows include role/status/author prefixes.
  final bool includePrefix;

  /// Clipboard write behavior for copied message text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [MessageList] copies the selected message.
final class MessageListCopyResult {
  const MessageListCopyResult({
    required this.messageIndex,
    required this.message,
    required this.text,
    required this.report,
  });

  final int messageIndex;
  final MessageEntry message;
  final String text;
  final ClipboardWriteReport report;
}

/// Controller for [MessageList] selection and tail-follow behavior.
class MessageListController extends ChangeNotifier {
  MessageListController({int? selectedIndex, bool followTail = true})
    : _list = ListController(
        selectedIndex:
            selectedIndex ?? (followTail ? _tailSelectionSentinel : 0),
        pinToBottom: followTail,
      ) {
    _list.addListener(notifyListeners);
  }

  final ListController _list;
  bool _disposed = false;

  ListController get _listController => _list;

  int? get selectedIndex => _list.selectedIndex;
  set selectedIndex(int? value) {
    _checkNotDisposed();
    _list.selectedIndex = value;
  }

  bool get followTail => _list.pinToBottom;
  set followTail(bool value) {
    _checkNotDisposed();
    if (_list.pinToBottom == value) return;
    _list.pinToBottom = value;
    if (value && _list.itemCount > 0) {
      _list.selectedIndex = _list.itemCount - 1;
    }
    notifyListeners();
  }

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    followTail = false;
    _list.jumpToIndex(index);
  }

  void scrollToBottom() {
    _checkNotDisposed();
    followTail = true;
    if (_list.itemCount > 0) _list.selectedIndex = _list.itemCount - 1;
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('MessageListController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _list.removeListener(notifyListeners);
    _list.dispose();
    super.dispose();
  }
}

const _tailSelectionSentinel = 1 << 30;

/// Exports messages as sanitized newline-delimited text.
MessageListExportResult exportMessages(
  List<MessageEntry> messages, {
  MessageListExportOptions options = const MessageListExportOptions(),
}) {
  final start = options.startIndex > messages.length
      ? messages.length
      : options.startIndex;
  final available = messages.length - start;
  final limit = options.maxMessages == null || options.maxMessages! > available
      ? available
      : options.maxMessages!;
  final rows = <String>[];
  for (var offset = 0; offset < limit; offset++) {
    rows.add(
      _formatMessageLine(
        messages[start + offset],
        includePrefix: options.includePrefix,
        maxLineLength: options.maxLineLength,
      ).text,
    );
  }
  return MessageListExportResult(
    text: rows.join('\n'),
    messageCount: rows.length,
    startIndex: start,
    truncated: start + limit < messages.length,
  );
}

/// Keyboard-navigable transcript/message region for developer workflows.
class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.messages,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel = 'Messages',
    this.showPrefix = true,
    this.showTimestamp = false,
    this.maxLineLength = 1000,
    this.copySelection = true,
    this.copyOptions = const MessageListCopyOptions(),
    this.onCopy,
  }) : assert(maxLineLength == null || maxLineLength >= 0);

  /// Source messages to render and copy.
  final List<MessageEntry> messages;

  /// External selection and tail-follow controller.
  final MessageListController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the list should request focus when mounted.
  final bool autofocus;

  /// Semantic label (the accessibility name; not rendered) for the message list.
  final String semanticLabel;

  /// Whether rows render role/status/author prefixes.
  final bool showPrefix;

  /// Prefix each row with the message's [MessageEntry.timestamp] as a
  /// local `HH:mm:ss` clock, when one is set. Off by default — a chat
  /// transcript usually doesn't want it, but agent/log views do. Rows
  /// without a timestamp are left unprefixed (no spacer), so a mixed list
  /// stays aligned only where times exist.
  final bool showTimestamp;

  /// Maximum displayed message length per row.
  final int? maxLineLength;

  /// Whether Ctrl+C and semantic copy export the selected message.
  final bool copySelection;

  /// Clipboard/export options for selected-message copy.
  final MessageListCopyOptions copyOptions;

  /// Called after a copy attempt completes.
  final void Function(MessageListCopyResult result)? onCopy;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  late MessageListController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;
  Object? _pendingSelectedMessageId;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? MessageListController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'MessageList');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? MessageListController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'MessageList');
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.messages != oldWidget.messages) {
      _syncSelectionAfterMessageUpdate(oldWidget.messages);
    }
  }

  void _onControllerChange() => setState(() {});

  void _syncSelectionAfterMessageUpdate(List<MessageEntry> oldMessages) {
    _selectionSyncGeneration++;
    _pendingSelectedMessageId = null;
    if (_controller.followTail) return;
    if (widget.messages.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) {
      _controller.selectedIndex = 0;
      return;
    }
    if (selectedIndex >= 0 && selectedIndex < oldMessages.length) {
      final selectedId = oldMessages[selectedIndex].id;
      if (selectedId != null) {
        final nextIndex = widget.messages.indexWhere(
          (message) => message.id == selectedId,
        );
        if (nextIndex != -1) {
          _selectIndexAfterListCountRefresh(selectedId, nextIndex);
          return;
        }
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(
      0,
      widget.messages.length - 1,
    );
  }

  void _selectIndexAfterListCountRefresh(Object selectedId, int nextIndex) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedMessageId = selectedId;
    final generation = _selectionSyncGeneration;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      scheduleMicrotask(() {
        _applyPendingSelection(generation, selectedId);
      });
      return;
    }
    binding.addPostFrameCallback((_) {
      _applyPendingSelection(generation, selectedId);
    });
  }

  void _applyPendingSelection(int generation, Object selectedId) {
    if (!mounted || generation != _selectionSyncGeneration) return;
    if (_pendingSelectedMessageId != selectedId) return;
    final nextIndex = widget.messages.indexWhere(
      (message) => message.id == selectedId,
    );
    if (nextIndex == -1) {
      _pendingSelectedMessageId = null;
      return;
    }
    _pendingSelectedMessageId = null;
    _controller.selectedIndex = nextIndex;
  }

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  void _focusList() {
    _focusNode.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _copySelection({bool focusList = false}) async {
    if (!widget.copySelection || widget.messages.isEmpty) return;
    if (focusList) _focusList();
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.messages.length - 1,
    );
    final message = widget.messages[selected];
    final line = _formatMessageLine(
      message,
      includePrefix: widget.copyOptions.includePrefix,
      maxLineLength: widget.maxLineLength,
    );
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(line.text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      MessageListCopyResult(
        messageIndex: selected,
        message: message,
        text: line.text,
        report: report,
      ),
    );
  }

  void _activateAt(int index) {
    if (index < 0 || index >= widget.messages.length) return;
    _focusList();
    _controller.followTail = false;
    _controller.selectedIndex = index;
  }

  Future<void> _copyAt(int index) async {
    if (index < 0 || index >= widget.messages.length) return;
    _focusList();
    _controller.followTail = false;
    _controller.selectedIndex = index;
    await _copySelection();
  }

  Future<void> _handleListAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusList();
        return;
      case SemanticAction.copy:
        await _copySelection(focusList: true);
        return;
      case _:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRange = _controller.visibleRange;
    final selectedIndex = _controller.selectedIndex;
    final copyEnabled = widget.copySelection && widget.messages.isNotEmpty;
    final selectedMessage =
        selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.messages.length
        ? null
        : widget.messages[selectedIndex];

    Widget list = ListView.builder(
      controller: _controller._listController,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      itemCount: widget.messages.length,
      onSelect: _activateAt,
      itemBuilder: (context, index, activeSelected) {
        final selected = index == _controller.selectedIndex;
        return _MessageRow(
          message: widget.messages[index],
          index: index,
          selected: selected,
          activeSelection: activeSelected,
          showPrefix: widget.showPrefix,
          showTimestamp: widget.showTimestamp,
          maxLineLength: widget.maxLineLength,
          copyEnabled: copyEnabled,
          onActivate: () => _activateAt(index),
          onCopy: () => _copyAt(index),
        );
      },
    );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy message',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.messageList,
        label: widget.semanticLabel,
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handleListAction,
        state: SemanticState({
          'collectionRowCount': widget.messages.length,
          'totalMessageCount': widget.messages.length,
          'followTail': _controller.followTail,
          'copyEnabled': copyEnabled,
          'copyIncludesPrefix': widget.copyOptions.includePrefix,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          if (visibleRange != null) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?selectedIndex,
          ..._selectedMessageState(selectedMessage),
        }),
        child: list,
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.index,
    required this.selected,
    required this.activeSelection,
    required this.showPrefix,
    required this.showTimestamp,
    required this.maxLineLength,
    required this.copyEnabled,
    required this.onActivate,
    required this.onCopy,
  });

  final MessageEntry message;
  final int index;
  final bool selected;
  final bool activeSelection;
  final bool showPrefix;
  final bool showTimestamp;
  final int? maxLineLength;
  final bool copyEnabled;
  final VoidCallback onActivate;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = _formatMessageLine(
      message,
      includePrefix: showPrefix,
      includeTimestamp: showTimestamp,
      maxLineLength: maxLineLength,
    );
    final style = _styleForMessage(message).merge(
      activeSelection
          ? theme.selectionStyle
          : selected
          ? theme.mutedStyle
          : CellStyle.empty,
    );
    return Semantics(
      role: SemanticRole.message,
      label: line.message,
      value: line.text,
      selected: selected,
      actions: {
        SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            onActivate();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        'rowIndex': index,
        'viewIndex': index,
        if (message.id != null) ...{
          'rowKey': message.id,
          'messageId': message.id,
        },
        'messageRole': message.role.name,
        'messageStatus': message.status.name,
        if (message.author != null) 'author': message.author,
        if (message.timestamp != null)
          'timestamp': message.timestamp!.toIso8601String(),
        'outputSanitized': line.sanitized,
        'outputTruncated': line.truncated,
        'outputOriginalLength': line.originalLength,
        ...message.metadata,
      }),
      child: Text(line.text, style: style),
    );
  }
}

Map<String, Object?> _selectedMessageState(MessageEntry? message) {
  if (message == null) return const <String, Object?>{};
  return <String, Object?>{
    if (message.id != null) ...{
      'selectedKey': message.id,
      'selectedMessageId': message.id,
    },
    'messageRole': message.role.name,
    'messageStatus': message.status.name,
    if (message.author != null) 'author': message.author,
  };
}

final class _FormattedMessageLine {
  const _FormattedMessageLine({
    required this.text,
    required this.message,
    required this.sanitized,
    required this.truncated,
    required this.originalLength,
  });

  final String text;
  final String message;
  final bool sanitized;
  final bool truncated;
  final int originalLength;
}

_FormattedMessageLine _formatMessageLine(
  MessageEntry message, {
  required bool includePrefix,
  required int? maxLineLength,
  bool includeTimestamp = false,
}) {
  final original = message.text;
  final sanitized = _sanitizeMessageText(original);
  final truncatedMessage = _truncateGraphemes(sanitized, maxLineLength);
  final clock = includeTimestamp && message.timestamp != null
      ? '${_formatClock(message.timestamp!)} '
      : '';
  final prefix = includePrefix ? _prefixFor(message) : '';
  return _FormattedMessageLine(
    text: '$clock$prefix$truncatedMessage',
    message: truncatedMessage,
    sanitized: sanitized != original,
    truncated: truncatedMessage != sanitized,
    originalLength: original.length,
  );
}

final _messageLineBreakPattern = RegExp(r'[\r\n\t]');

String _sanitizeMessageText(String original) {
  if (!_needsMessageSanitization(original)) return original;
  return sanitizeForDisplay(original).replaceAll(_messageLineBreakPattern, ' ');
}

bool _needsMessageSanitization(String text) {
  for (final codeUnit in text.codeUnits) {
    if (codeUnit == 0x1b ||
        codeUnit == 0x9b ||
        codeUnit == 0x9d ||
        codeUnit == 0x90 ||
        codeUnit == 0x98 ||
        codeUnit == 0x9e ||
        codeUnit == 0x9f ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d ||
        codeUnit == 0x09) {
      return true;
    }
  }
  return false;
}

String _truncateGraphemes(String text, int? maxLineLength) {
  if (maxLineLength == null) return text;
  if (maxLineLength == 0) return '';
  final characters = text.characters;
  if (characters.length <= maxLineLength) return text;
  return characters.take(maxLineLength).toString();
}

String _prefixFor(MessageEntry message) {
  final parts = <String>[
    message.role.name,
    if (message.author != null && message.author!.isNotEmpty) message.author!,
  ];
  return '[${parts.join(' ')}] ';
}

/// Local `HH:mm:ss` clock for the optional per-row timestamp.
String _formatClock(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

CellStyle _styleForMessage(MessageEntry message) {
  if (message.status == MessageStatus.failed) {
    return const CellStyle(foreground: AnsiColor(9));
  }
  if (message.status == MessageStatus.streaming ||
      message.status == MessageStatus.queued) {
    return const CellStyle(dim: true);
  }
  return switch (message.role) {
    MessageRole.user => const CellStyle(foreground: AnsiColor(14)),
    MessageRole.assistant => const CellStyle(foreground: AnsiColor(10)),
    MessageRole.system => const CellStyle(foreground: AnsiColor(12)),
    MessageRole.tool => const CellStyle(foreground: AnsiColor(11)),
    MessageRole.log || MessageRole.event => CellStyle.empty,
  };
}
