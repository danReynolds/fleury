import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

import 'model_status_bar.dart';

/// Protocol-neutral kind for one context-pack item.
enum ContextItemKind {
  file,
  symbol,
  message,
  diff,
  log,
  command,
  instruction,
  note,
  url,
  tool,
  other,
}

/// Priority hint for context-pack display and future pruning policies.
enum ContextItemPriority { low, normal, high, critical }

/// One app-owned context item displayed by [ContextPanel].
final class ContextItem {
  const ContextItem({
    required this.id,
    required this.label,
    this.detail,
    this.kind = ContextItemKind.other,
    this.priority = ContextItemPriority.normal,
    this.tokenCount = 0,
    this.source,
    this.pinned = false,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
  }) : assert(tokenCount >= 0);

  /// Stable identity used by semantics, selection, and callbacks.
  final Object id;

  /// Primary display label for the context item.
  final String label;

  /// Optional longer detail text.
  final String? detail;

  /// Kind of context represented by this item.
  final ContextItemKind kind;

  /// Priority hint for display and pruning.
  final ContextItemPriority priority;

  /// Token count attributed to this item.
  final int tokenCount;

  /// Optional source/origin label.
  final String? source;

  /// Whether this item is pinned in the context set.
  final bool pinned;

  /// Whether this item can be selected and activated.
  final bool enabled;

  /// App-specific semantic state carried by the item.
  final Map<String, Object?> metadata;

  String get displayId => id.toString();
}

/// Controller for [ContextPanel] selection and viewport state.
class ContextPanelController extends ChangeNotifier {
  ContextPanelController({int selectedIndex = 0})
    : _list = ListController(selectedIndex: selectedIndex) {
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

  ({int first, int last})? get visibleRange => _list.visibleRange;

  void jumpToIndex(int index) {
    _checkNotDisposed();
    _list.jumpToIndex(index);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('ContextPanelController has been disposed.');
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

/// Clipboard/export behavior for [ContextPanel] selected-item copy.
final class ContextPanelCopyOptions {
  const ContextPanelCopyOptions({
    this.includeDetail = true,
    this.includeSource = true,
    this.includeTokenCount = true,
    this.maxDetailLength = 1000,
    this.clipboardPolicy = ClipboardWritePolicy.standard,
  }) : assert(maxDetailLength == null || maxDetailLength >= 0);

  /// Whether copied item text includes [ContextItem.detail].
  final bool includeDetail;

  /// Whether copied item text includes [ContextItem.source].
  final bool includeSource;

  /// Whether copied item text includes [ContextItem.tokenCount].
  final bool includeTokenCount;

  /// Maximum copied detail length.
  final int? maxDetailLength;

  /// Clipboard write behavior for copied context text.
  final ClipboardWritePolicy clipboardPolicy;
}

/// Result delivered after [ContextPanel] copies the selected item.
final class ContextPanelCopyResult {
  const ContextPanelCopyResult({
    required this.itemIndex,
    required this.item,
    required this.text,
    required this.report,
  });

  final int itemIndex;
  final ContextItem item;
  final String text;
  final ClipboardWriteReport report;
}

/// Result delivered after [ContextPanel] activates a context item.
final class ContextPanelSelectResult {
  const ContextPanelSelectResult({required this.itemIndex, required this.item});

  final int itemIndex;
  final ContextItem item;
}

/// Exports one [ContextItem] as sanitized clipboard/debug text.
String exportContextItem(
  ContextItem item, {
  ContextPanelCopyOptions options = const ContextPanelCopyOptions(),
}) {
  final parts = <String>[
    _sanitizeContextText(item.label),
    item.kind.name,
    item.priority.name,
    if (item.pinned) 'pinned',
    if (options.includeTokenCount && item.tokenCount > 0)
      '${item.tokenCount} tokens',
    if (options.includeSource && item.source != null)
      _sanitizeContextText(item.source!),
    if (options.includeDetail && item.detail != null)
      _truncateGraphemes(
        _sanitizeContextText(item.detail!),
        options.maxDetailLength,
      ),
  ];
  return parts.where((part) => part.trim().isNotEmpty).join(' | ');
}

/// Compact context-pack inspector for model-backed developer workflows.
class ContextPanel extends StatefulWidget {
  const ContextPanel({
    super.key,
    required this.items,
    this.usage,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.label = 'Context',
    this.maxVisible = 6,
    this.showTokenShare = false,
    this.copySelection = true,
    this.copyOptions = const ContextPanelCopyOptions(),
    this.onSelect,
    this.onCopy,
  }) : assert(maxVisible > 0);

  /// Context items to display, select, activate, and copy.
  final List<ContextItem> items;

  /// Optional overall token-usage totals used for share display.
  final TokenUsage? usage;

  /// External selection and visible-range controller.
  final ContextPanelController? controller;

  /// Focus node used for keyboard navigation.
  final FocusNode? focusNode;

  /// Whether the panel should request focus when mounted.
  final bool autofocus;

  /// Semantic and visual label for the panel.
  final String label;

  /// Maximum visible rows before the list scrolls.
  final int maxVisible;

  /// Append each item's share of the panel's total token budget — e.g.
  /// `1,024 tokens (12%)` — next to its count. Off by default. Makes it
  /// obvious at a glance which items dominate the context window. Items
  /// with no tokens, or when the total is zero, get no share suffix.
  final bool showTokenShare;

  /// Whether Ctrl+C and semantic copy export the selected item.
  final bool copySelection;

  /// Clipboard/export options for selected-item copy.
  final ContextPanelCopyOptions copyOptions;

  /// Called when a context item is activated.
  final void Function(ContextPanelSelectResult result)? onSelect;

  /// Called after a copy attempt completes.
  final void Function(ContextPanelCopyResult result)? onCopy;

  @override
  State<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends State<ContextPanel> {
  late ContextPanelController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focusedWithin = false;
  Object? _pendingSelectedContextItemId;
  int _selectionSyncGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ContextPanelController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ContextPanel');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(covariant ContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? ContextPanelController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'ContextPanel');
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.items != oldWidget.items) {
      _syncSelectionAfterItemUpdate(oldWidget.items);
    }
  }

  void _onControllerChange() => setState(() {});

  void _syncSelectionAfterItemUpdate(List<ContextItem> oldItems) {
    _selectionSyncGeneration++;
    _pendingSelectedContextItemId = null;
    if (widget.items.isEmpty) {
      _controller.selectedIndex = null;
      return;
    }
    final selectedIndex = _controller.selectedIndex;
    if (selectedIndex == null) {
      _controller.selectedIndex = 0;
      return;
    }
    if (selectedIndex >= 0 && selectedIndex < oldItems.length) {
      final selectedId = oldItems[selectedIndex].id;
      final nextIndex = widget.items.indexWhere(
        (item) => item.id == selectedId,
      );
      if (nextIndex != -1) {
        _selectIndexAfterListCountRefresh(selectedId, nextIndex);
        return;
      }
    }
    _controller.selectedIndex = selectedIndex.clamp(0, widget.items.length - 1);
  }

  void _selectIndexAfterListCountRefresh(Object selectedId, int nextIndex) {
    final knownItemCount = _controller._listController.itemCount;
    if (knownItemCount == 0 || nextIndex < knownItemCount) {
      _controller.selectedIndex = nextIndex;
      return;
    }

    _pendingSelectedContextItemId = selectedId;
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
    if (_pendingSelectedContextItemId != selectedId) return;
    final nextIndex = widget.items.indexWhere((item) => item.id == selectedId);
    if (nextIndex == -1) {
      _pendingSelectedContextItemId = null;
      return;
    }
    _pendingSelectedContextItemId = null;
    _controller.selectedIndex = nextIndex;
  }

  void _onFocusWithinChange(bool focused) {
    if (_focusedWithin == focused) return;
    setState(() {
      _focusedWithin = focused;
    });
  }

  Future<void> _copySelection() async {
    if (!widget.copySelection || widget.items.isEmpty) return;
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.items.length - 1,
    );
    final item = widget.items[selected];
    final text = exportContextItem(item, options: widget.copyOptions);
    final report = await ClipboardScope.of(
      context,
    ).writeWithReport(text, policy: widget.copyOptions.clipboardPolicy);
    if (!mounted) return;
    widget.onCopy?.call(
      ContextPanelCopyResult(
        itemIndex: selected,
        item: item,
        text: text,
        report: report,
      ),
    );
  }

  void _selectCurrent() {
    if (widget.items.isEmpty) return;
    _focusNode.requestFocus();
    final selected = (_controller.selectedIndex ?? 0).clamp(
      0,
      widget.items.length - 1,
    );
    final item = widget.items[selected];
    if (!item.enabled) return;
    widget.onSelect?.call(
      ContextPanelSelectResult(itemIndex: selected, item: item),
    );
  }

  Future<void> _selectAt(int index) async {
    if (index < 0 || index >= widget.items.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    _selectCurrent();
  }

  Future<void> _copyAt(int index) async {
    if (index < 0 || index >= widget.items.length) return;
    _focusNode.requestFocus();
    _controller.selectedIndex = index;
    await _copySelection();
  }

  Future<void> _handlePanelAction(SemanticAction action) async {
    switch (action) {
      case SemanticAction.focus:
      case SemanticAction.navigate:
        _focusNode.requestFocus();
        setState(() {});
        return;
      case SemanticAction.submit:
        _selectCurrent();
        return;
      case SemanticAction.copy:
        await _copySelection();
        return;
      case _:
        return;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _controller.selectedIndex;
    final visibleRange = _controller.visibleRange;
    final copyEnabled = widget.copySelection && widget.items.isNotEmpty;
    final canSelect = widget.onSelect != null;
    final selectedItem =
        selectedIndex == null ||
            selectedIndex < 0 ||
            selectedIndex >= widget.items.length
        ? null
        : widget.items[selectedIndex];
    final visible = widget.items.isEmpty
        ? 1
        : (widget.items.length > widget.maxVisible
              ? widget.maxVisible
              : widget.items.length);

    Widget list = widget.items.isEmpty
        ? Text('No context items')
        : ListView.builder(
            controller: _controller._listController,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            itemCount: widget.items.length,
            onSelect: (_) => _selectCurrent(),
            itemBuilder: (context, index, activeSelected) {
              final selected = index == _controller.selectedIndex;
              return _ContextItemRow(
                item: widget.items[index],
                index: index,
                selected: selected,
                activeSelection: activeSelected,
                canSelect: canSelect,
                copyEnabled: copyEnabled,
                tokenShareTotal: widget.showTokenShare
                    ? _totalTokens(widget.items)
                    : null,
                onSelect: () => _selectAt(index),
                onCopy: () => _copyAt(index),
              );
            },
          );

    if (copyEnabled) {
      list = KeyBindings(
        bindings: [
          KeyBinding(
            KeyChord.ctrl.c,
            label: 'Copy context item',
            onEvent: (_) => unawaited(_copySelection()),
          ),
        ],
        child: list,
      );
    }

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_summaryText(widget.label, widget.items, widget.usage)),
        SizedBox(height: visible, child: list),
      ],
    );

    return FocusWithin(
      onFocusChange: _onFocusWithinChange,
      child: Semantics(
        role: SemanticRole.contextPanel,
        label: _sanitizeContextText(widget.label),
        value: _contextValue(widget.usage),
        focused: _focusedWithin || _focusNode.hasFocus,
        actions: {
          SemanticAction.focus,
          SemanticAction.navigate,
          if (canSelect) SemanticAction.submit,
          if (copyEnabled) SemanticAction.copy,
        },
        onAction: _handlePanelAction,
        state: SemanticState({
          'collectionRowCount': widget.items.length,
          'contextItemCount': widget.items.length,
          'contextTokenCount': _totalTokens(widget.items),
          'pinnedContextItemCount': widget.items.fold<int>(
            0,
            (total, item) => total + (item.pinned ? 1 : 0),
          ),
          'copyEnabled': copyEnabled,
          'clipboardPolicy': widget.copyOptions.clipboardPolicy.name,
          ..._tokenState(widget.usage),
          if (visibleRange != null && widget.items.isNotEmpty) ...{
            'visibleRangeStart': visibleRange.first,
            'visibleRangeEnd': visibleRange.last,
          },
          'selectedIndex': ?selectedIndex,
          if (selectedItem != null) ..._selectedItemState(selectedItem),
        }),
        child: child,
      ),
    );
  }
}

class _ContextItemRow extends StatelessWidget {
  const _ContextItemRow({
    required this.item,
    required this.index,
    required this.selected,
    required this.activeSelection,
    required this.canSelect,
    required this.copyEnabled,
    required this.tokenShareTotal,
    required this.onSelect,
    required this.onCopy,
  });

  final ContextItem item;
  final int index;
  final bool selected;
  final bool activeSelection;
  final bool canSelect;
  final bool copyEnabled;

  /// Panel-wide token total for the per-item share suffix, or null to omit it.
  final int? tokenShareTotal;
  final Future<void> Function() onSelect;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final label = _sanitizeContextText(item.label);
    final detail = item.detail == null
        ? null
        : _sanitizeContextText(item.detail!);
    final source = item.source == null
        ? null
        : _sanitizeContextText(item.source!);
    final id = _sanitizeContextText(item.displayId);
    return Semantics(
      role: SemanticRole.contextItem,
      label: label,
      value: detail,
      selected: selected,
      enabled: item.enabled,
      actions: {
        if (item.enabled && canSelect) SemanticAction.activate,
        if (selected && copyEnabled) SemanticAction.copy,
      },
      onAction: (action) async {
        switch (action) {
          case SemanticAction.activate:
            if (item.enabled && canSelect) await onSelect();
            return;
          case SemanticAction.copy:
            if (selected && copyEnabled) await onCopy();
            return;
          case _:
            return;
        }
      },
      state: SemanticState({
        ...item.metadata,
        'rowIndex': index,
        'viewIndex': index,
        'rowKey': id,
        'contextItemId': id,
        'contextItemKind': item.kind.name,
        'contextItemTokenCount': item.tokenCount,
        'contextItemPriority': item.priority.name,
        'pinned': item.pinned,
        'source': ?source,
        'outputSanitized': _itemWasSanitized(item),
      }),
      child: Text(
        _rowText(
          label: label,
          item: item,
          activeSelection: activeSelection,
          tokenShareTotal: tokenShareTotal,
        ),
        style: _rowStyle(
          Theme.of(context),
          selected: selected,
          activeSelection: activeSelection,
          item: item,
        ),
      ),
    );
  }
}

Map<String, Object?> _tokenState(TokenUsage? usage) {
  if (usage == null) return const <String, Object?>{};
  final used = usage.effectiveContextUsed;
  final limit = usage.contextLimit;
  final ratio = usage.contextRatio;
  return <String, Object?>{
    'tokenInput': usage.input,
    'tokenOutput': usage.output,
    'tokenCached': usage.cached,
    'tokenTotal': usage.total,
    'contextUsed': ?used,
    'contextLimit': ?limit,
    'contextRemaining': ?usage.contextRemaining,
    'contextRatioPercent': ?(ratio == null ? null : (ratio * 100).round()),
  };
}

Map<String, Object?> _selectedItemState(ContextItem item) {
  final id = _sanitizeContextText(item.displayId);
  return <String, Object?>{
    'selectedKey': id,
    'selectedContextItemId': id,
    'selectedContextItemKind': item.kind.name,
    'selectedContextItemTokenCount': item.tokenCount,
    'selectedContextItemPriority': item.priority.name,
  };
}

String? _contextValue(TokenUsage? usage) {
  if (usage == null) return null;
  final used = usage.effectiveContextUsed;
  final limit = usage.contextLimit;
  if (used == null) return usage.total.toString();
  return limit == null ? used.toString() : '$used/$limit';
}

String _summaryText(String label, List<ContextItem> items, TokenUsage? usage) {
  final safeLabel = _sanitizeContextText(label);
  final itemCount = items.length;
  final itemTokens = _totalTokens(items);
  final usageText = usage == null
      ? '${_formatTokenCount(itemTokens)} item tokens'
      : _usageSummary(usage);
  return '$safeLabel: $itemCount items  $usageText';
}

String _usageSummary(TokenUsage usage) {
  final used = usage.effectiveContextUsed;
  final limit = usage.contextLimit;
  if (used == null) return '${_formatTokenCount(usage.total)} tokens';
  if (limit == null) return '${_formatTokenCount(used)} context';
  final percent = usage.contextRatio == null
      ? null
      : (usage.contextRatio! * 100).round();
  return '${_formatTokenCount(used)}/${_formatTokenCount(limit)}'
      '${percent == null ? '' : ' $percent%'}';
}

String _rowText({
  required String label,
  required ContextItem item,
  required bool activeSelection,
  int? tokenShareTotal,
}) {
  final prefix = activeSelection ? '> ' : '  ';
  final tokens = item.tokenCount > 0
      ? _formatTokenCount(item.tokenCount)
      : null;
  final share = tokens != null && tokenShareTotal != null && tokenShareTotal > 0
      ? ' (${(item.tokenCount / tokenShareTotal * 100).round()}%)'
      : '';
  final meta = <String>[
    item.kind.name,
    item.priority.name,
    if (tokens != null) '$tokens$share',
    if (item.pinned) 'pinned',
  ];
  return '$prefix$label  ${meta.join('  ')}';
}

int _totalTokens(List<ContextItem> items) =>
    items.fold<int>(0, (total, item) => total + item.tokenCount);

String _formatTokenCount(int count) {
  if (count >= 1000000) {
    final value = count / 1000000;
    return '${_trimFixed(value)}m';
  }
  if (count >= 1000) {
    final value = count / 1000;
    return '${_trimFixed(value)}k';
  }
  return count.toString();
}

String _trimFixed(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

String _truncateGraphemes(String text, int? maxLength) {
  if (maxLength == null) return text;
  if (maxLength == 0) return '';
  final characters = text.characters;
  if (characters.length <= maxLength) return text;
  return characters.take(maxLength).toString();
}

bool _itemWasSanitized(ContextItem item) {
  return _sanitizeContextText(item.displayId) != item.displayId ||
      _sanitizeContextText(item.label) != item.label ||
      (item.detail != null &&
          _sanitizeContextText(item.detail!) != item.detail) ||
      (item.source != null &&
          _sanitizeContextText(item.source!) != item.source);
}

String _sanitizeContextText(String text) {
  return sanitizeSingleLine(text).replaceAll(RegExp(' +'), ' ').trim();
}

CellStyle _rowStyle(
  ThemeData theme, {
  required bool selected,
  required bool activeSelection,
  required ContextItem item,
}) {
  if (!item.enabled) return theme.mutedStyle;
  if (activeSelection) return theme.selectionStyle;
  if (selected) return theme.mutedStyle;
  return switch (item.priority) {
    ContextItemPriority.low => theme.mutedStyle,
    ContextItemPriority.normal => CellStyle.empty,
    ContextItemPriority.high => const CellStyle(foreground: AnsiColor(11)),
    ContextItemPriority.critical => const CellStyle(
      bold: true,
      foreground: AnsiColor(9),
    ),
  };
}
