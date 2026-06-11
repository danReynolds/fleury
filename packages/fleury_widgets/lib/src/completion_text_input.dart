import 'package:fleury/fleury.dart';

import 'option_label.dart';

/// Request passed to a [TextCompletionProvider].
final class TextCompletionRequest {
  const TextCompletionRequest({
    required this.value,
    required this.range,
    required this.query,
  });

  final TextEditingValue value;
  final TextRange range;
  final String query;
}

typedef TextCompletionProvider =
    Iterable<TextCompletionOption> Function(TextCompletionRequest request);

typedef TextCompletionRequestBuilder =
    TextCompletionRequest Function(TextEditingValue value);

/// Builds a completion request for the selected range or current word.
TextCompletionRequest defaultTextCompletionRequest(TextEditingValue value) {
  if (!value.selection.isCollapsed) {
    final range = value.selection.range;
    return TextCompletionRequest(
      value: value,
      range: range,
      query: value.text.substring(range.normalizedStart, range.normalizedEnd),
    );
  }

  final end = value.selection.extentOffset;
  var start = end;
  while (start > 0) {
    final previous = TextEditingModel.previousGraphemeBoundary(
      value.text,
      start,
    );
    final grapheme = value.text.substring(previous, start);
    if (grapheme.trim().isEmpty) break;
    start = previous;
  }
  return TextCompletionRequest(
    value: value,
    range: TextRange(start: start, end: end),
    query: value.text.substring(start, end),
  );
}

/// A [TextInput] with an anchored completion menu.
///
/// The field uses core [TextCompletionController] semantics for option state
/// and acceptance. This widget supplies provider-driven options plus the
/// floating menu UI; [TextInput] still owns editing, Tab acceptance, Escape
/// dismissal, and Up/Down completion navigation.
class CompletionTextInput extends StatefulWidget {
  const CompletionTextInput({
    super.key,
    required this.provider,
    this.requestBuilder = defaultTextCompletionRequest,
    this.controller,
    this.completionController,
    this.historyController,
    this.focusNode,
    this.autofocus = false,
    this.onSubmit,
    this.onEscape,
    this.onCompletionAccepted,
    this.placeholder = '',
    this.placeholderStyle = const CellStyle(dim: true),
    this.style = CellStyle.empty,
    this.cursorStyle = const CellStyle(inverse: true),
    this.blinkInterval = const Duration(milliseconds: 500),
    this.enableBlink = true,
    this.enabled = true,
    this.readOnly = false,
    this.validationError,
    this.clipboardPolicy,
    this.pastePolicy = const TextPastePolicy(),
    this.commitHistoryOnSubmit = true,
    this.showOnEmptyQuery = false,
    this.maxVisible = 6,
  });

  final TextCompletionProvider provider;
  final TextCompletionRequestBuilder requestBuilder;
  final TextEditingController? controller;
  final TextCompletionController? completionController;
  final TextHistoryController? historyController;
  final FocusNode? focusNode;
  final bool autofocus;
  final void Function(String text)? onSubmit;
  final void Function()? onEscape;
  final void Function(TextCompletionOption option)? onCompletionAccepted;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final Duration blinkInterval;
  final bool enableBlink;
  final bool enabled;
  final bool readOnly;
  final String? validationError;
  final TextClipboardPolicy? clipboardPolicy;
  final TextPastePolicy pastePolicy;
  final bool commitHistoryOnSubmit;
  final bool showOnEmptyQuery;
  final int maxVisible;

  @override
  State<CompletionTextInput> createState() => _CompletionTextInputState();
}

class _CompletionTextInputState extends State<CompletionTextInput> {
  late TextEditingController _controller;
  late TextCompletionController _completion;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsCompletion = false;
  bool _ownsFocusNode = false;

  final AnchorLink _link = AnchorLink();
  final ListController _list = ListController(selectedIndex: 0);
  FocusManager? _manager;
  OverlayEntry? _entry;
  CellStyle _selectionStyle = const CellStyle(inverse: true);
  BorderStyle _borderStyle = BorderStyle.rounded;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onTextChange);
    _completion = widget.completionController ?? TextCompletionController();
    _ownsCompletion = widget.completionController == null;
    _completion.addListener(_onCompletionChange);
    _focusNode =
        widget.focusNode ?? FocusNode(debugLabel: 'CompletionTextInput');
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(CompletionTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onTextChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onTextChange);
    }
    if (widget.completionController != oldWidget.completionController) {
      _completion.removeListener(_onCompletionChange);
      if (_ownsCompletion) _completion.dispose();
      _completion = widget.completionController ?? TextCompletionController();
      _ownsCompletion = widget.completionController == null;
      _completion.addListener(_onCompletionChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode =
          widget.focusNode ?? FocusNode(debugLabel: 'CompletionTextInput');
      _ownsFocusNode = widget.focusNode == null;
    }
    _syncCompletion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context);
    if (!identical(manager, _manager)) {
      _manager?.removeListener(_syncCompletion);
      _manager = manager;
      _manager?.addListener(_syncCompletion);
    }
  }

  void _onTextChange() {
    _syncCompletion();
  }

  void _onCompletionChange() {
    _list.selectedIndex = _completion.state.selectedIndex;
    _syncOverlay();
  }

  void _syncCompletion() {
    if (!mounted) return;
    if (!widget.enabled || widget.readOnly || !_focusNode.hasFocus) {
      _completion.close();
      _syncOverlay();
      return;
    }

    final request = widget.requestBuilder(_controller.value);
    if (!widget.showOnEmptyQuery && request.query.isEmpty) {
      _completion.close();
      _syncOverlay();
      return;
    }

    final options = widget.provider(request).toList(growable: false);
    if (options.isEmpty) {
      _completion.close();
      _syncOverlay();
      return;
    }

    _completion.open(
      range: request.range,
      query: request.query,
      options: options,
      selectedIndex: _completion.state.selectedIndex,
    );
  }

  void _syncOverlay() {
    final shouldOpen =
        _focusNode.hasFocus &&
        _completion.isOpen &&
        _completion.state.hasOptions;
    if (!shouldOpen) {
      _close();
      return;
    }
    if (_entry == null) {
      final entry = OverlayEntry(
        builder: (_) => Follower(link: _link, child: _suggestions()),
      );
      _entry = entry;
      Overlay.of(context).insert(entry);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _acceptCompletionAt(int index) {
    if (!widget.enabled || widget.readOnly) return;
    final state = _completion.state;
    if (!state.active || index < 0 || index >= state.options.length) return;
    final option = state.options[index];
    _controller.replaceRange(state.range, option.replacement, singleLine: true);
    _completion.close();
    widget.onCompletionAccepted?.call(option);
  }

  Widget _suggestions() {
    final state = _completion.state;
    final options = state.options;
    final visible = options.length > widget.maxVisible
        ? widget.maxVisible
        : options.length;
    var width = 0;
    for (final option in options) {
      final detail = option.detail;
      final label = sanitizeOptionLabel(
        detail == null ? option.label : '${option.label}  $detail',
      );
      if (label.length > width) width = label.length;
    }
    _list.selectedIndex = state.selectedIndex;
    return Semantics(
      role: SemanticRole.menu,
      label: 'Completions',
      focused: _focusNode.hasFocus,
      selected: true,
      expanded: true,
      actions: const <SemanticAction>{
        SemanticAction.focus,
        SemanticAction.close,
      },
      state: SemanticState({
        'filterText': state.query,
        'collectionRowCount': options.length,
        if (state.selectedIndex != null) 'selectedKey': state.selectedIndex,
        'visibleRangeStart': 0,
        'visibleRangeEnd': visible - 1,
      }),
      onAction: (action) {
        switch (action) {
          case SemanticAction.focus:
            _focusNode.requestFocus();
            return;
          case SemanticAction.close:
            _completion.close();
            _syncOverlay();
            return;
          case _:
            return;
        }
      },
      child: Container(
        border: BoxBorder(style: _borderStyle),
        child: SizedBox(
          width: width + 2,
          height: visible,
          child: ListView.builder(
            controller: _list,
            selectionActive: true,
            itemCount: options.length,
            itemBuilder: (_, i, selected) {
              final option = options[i];
              final rawDetail = option.detail;
              final detail = rawDetail == null
                  ? null
                  : sanitizeOptionLabel(rawDetail);
              final optionLabel = sanitizeOptionLabel(option.label);
              final label = detail == null
                  ? optionLabel
                  : '$optionLabel  $detail';
              return Semantics(
                role: SemanticRole.menuItem,
                label: optionLabel,
                value: option.replacement,
                hint: detail,
                focused: _focusNode.hasFocus && selected,
                selected: selected,
                actions: const <SemanticAction>{
                  SemanticAction.select,
                  SemanticAction.activate,
                },
                state: SemanticState({
                  'rowIndex': i,
                  'menuItemPosition': i + 1,
                  'menuItemCount': options.length,
                  'entryKind': 'completion',
                  'completionQuery': state.query,
                  if (option.id != null) 'completionId': option.id,
                }),
                onAction: (action) {
                  switch (action) {
                    case SemanticAction.select:
                    case SemanticAction.activate:
                      _list.selectedIndex = i;
                      _acceptCompletionAt(i);
                      return;
                    case _:
                      return;
                  }
                },
                child: Text(
                  '${selected ? '› ' : '  '}$label',
                  style: selected ? _selectionStyle : CellStyle.empty,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _close();
    _manager?.removeListener(_syncCompletion);
    _controller.removeListener(_onTextChange);
    _completion.removeListener(_onCompletionChange);
    if (_ownsController) _controller.dispose();
    if (_ownsCompletion) _completion.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _selectionStyle = theme.selectionStyle;
    _borderStyle = theme.borderStyle;
    return Anchor(
      link: _link,
      child: TextInput(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onSubmit: widget.onSubmit,
        onEscape: widget.onEscape,
        placeholder: widget.placeholder,
        placeholderStyle: widget.placeholderStyle,
        style: widget.style,
        cursorStyle: widget.cursorStyle,
        blinkInterval: widget.blinkInterval,
        enableBlink: widget.enableBlink,
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        validationError: widget.validationError,
        clipboardPolicy: widget.clipboardPolicy,
        historyController: widget.historyController,
        commitHistoryOnSubmit: widget.commitHistoryOnSubmit,
        completionController: _completion,
        onCompletionAccepted: widget.onCompletionAccepted,
        pastePolicy: widget.pastePolicy,
      ),
    );
  }
}
