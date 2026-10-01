import '../input/events.dart';
import '../rendering/cell.dart';
import '../semantics/semantics.dart';
import 'focus.dart';
import 'form_control.dart';
import 'framework.dart';
import 'keyboard.dart';
import 'pointer.dart';
import 'selection/selection_area.dart';
import 'theme.dart';

/// Shared focus, hover, validation, and activation behavior for controls.
/// Enter or Space activates ([onActivate]) when enabled. The [builder] gets
/// the fully resolved style and active style states for the control.
///
/// Enter arrives as a `KeyEvent`; Space arrives as inserted text, so the
/// control claims text input and consumes a single space (declining all
/// other text so it still bubbles).
class FocusableControl extends StatefulWidget {
  const FocusableControl({
    required this.onActivate,
    this.onSecondaryActivate,
    required this.builder,
    required this.semanticRole,
    required this.defaultStyle,
    this.semanticLabel,
    this.semanticValue,
    this.semanticChecked,
    this.semanticSelected = false,
    this.styleSelected = false,
    this.onSetValue,
    this.focusNode,
    this.autofocus = false,
    this.participatesInForm = false,
    this.validationError,
    this.style,
  });

  /// Activation — Enter, Space, a click, or a semantic `activate`. Nothing
  /// waits on work it starts, a semantic activation included: an error from
  /// that work reaches the zone (runApp's error overlay), as a key's does.
  /// Throwing [SemanticActionDeclined] declines the activation: a key or a
  /// click then does nothing, and a semantic activation reports it
  /// `unsupported`. Anything else it throws reports that activation `failed`.
  final void Function()? onActivate;
  final void Function()? onSecondaryActivate;
  final Widget Function(
    CellStyle style,
    bool enabled,
    Set<CellStyleState> states,
  )
  builder;
  final CellStyle defaultStyle;
  final SemanticRole semanticRole;
  final String? semanticLabel;
  final Object? semanticValue;
  final bool? semanticChecked;
  final bool semanticSelected;
  final bool styleSelected;

  /// When non-null, the control advertises [SemanticAction.setValue] and routes
  /// the payload here — letting an agent set the value directly (idempotent),
  /// instead of toggling via [onActivate] and hoping it lands.
  final SemanticSetValueCallback? onSetValue;

  final FocusNode? focusNode;
  final bool autofocus;
  final bool participatesInForm;
  final String? validationError;
  final CellStyle? style;

  bool get enabled => onActivate != null;

  @override
  State<FocusableControl> createState() => _FocusableControlState();
}

class _FocusableControlState extends State<FocusableControl>
    implements TextInputClaimant {
  late FocusNode _node;
  bool _owns = false;
  bool _hovered = false;
  bool _pressed = false;
  FormControlRegistration? _formRegistration;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'control');
    _node.textInputClaimant = this;
    _owns = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(FocusableControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pressed = false;
    if (widget.focusNode != oldWidget.focusNode) {
      _node.textInputClaimant = null;
      if (_owns) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'control');
      _node.textInputClaimant = this;
      _owns = widget.focusNode == null;
    }
    _syncFormClaim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registration = FormControlScope.maybeOf(context);
    if (!identical(registration, _formRegistration)) {
      _formRegistration?.release(this);
      _formRegistration = widget.participatesInForm ? registration : null;
      _formRegistration?.claim(this, focusNode: _node, enabled: widget.enabled);
    } else {
      _syncFormClaim();
    }
  }

  void _syncFormClaim() => _formRegistration?.updateClaim(
    this,
    focusNode: _node,
    enabled: widget.enabled,
  );

  // A key or a click. One that declined (a command that turned out
  // disabled) does nothing.
  void _activate() {
    try {
      _run();
    } on SemanticActionDeclined {
      return;
    }
  }

  void _run() {
    widget.onActivate!();
    _formRegistration?.controlValueChanged(this);
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _setValue(Object? payload) {
    widget.onSetValue?.call(payload);
    _formRegistration?.controlValueChanged(this);
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event.code == KeyCode.enter) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onTextInput(String text) {
    // Claim Space as activation; decline everything else so it bubbles.
    if (text == ' ') {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  @override
  void deactivate() {
    // Capture is dropped when this subtree leaves the active tree, including
    // a GlobalKey move. A preserved State must not carry its held visual along.
    // The same goes for hover: the router drops a deactivated region without
    // `onExit`, and re-enters it after reactivation if the pointer is over it.
    _pressed = false;
    _hovered = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _node.textInputClaimant = null;
    _formRegistration?.release(this);
    if (_owns) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validationError = _formRegistration?.error ?? widget.validationError;
    // Rebuilds when this control's own focus flips (the focus cue).
    final focused = context.listen(_node).hasFocus;
    final states = <CellStyleState>{
      if (_hovered) CellStyleState.hovered,
      if (focused) CellStyleState.focused,
      if (_pressed) CellStyleState.pressed,
      if (widget.styleSelected) CellStyleState.selected,
      if (!widget.enabled) CellStyleState.disabled,
      if (validationError != null) CellStyleState.invalid,
    };
    final resolvedStyle = resolveCellStyle(
      cascade: [
        widget.defaultStyle,
        Theme.of(context).interactiveStyle,
        widget.style,
      ],
      states: states,
    );
    final Widget content = !widget.enabled
        ? Semantics(
            role: widget.semanticRole,
            label: widget.semanticLabel,
            value: widget.semanticValue,
            selected: widget.semanticSelected,
            checked: widget.semanticChecked,
            enabled: false,
            validationError: validationError,
            child: widget.builder(resolvedStyle, false, states),
          )
        : Semantics(
            role: widget.semanticRole,
            label: widget.semanticLabel,
            value: widget.semanticValue,
            focused: focused,
            selected: widget.semanticSelected,
            checked: widget.semanticChecked,
            enabled: true,
            validationError: validationError,
            actions: {
              SemanticAction.focus,
              SemanticAction.activate,
              if (widget.onSetValue != null) SemanticAction.setValue,
            },
            onAction: (action) {
              switch (action) {
                case SemanticAction.focus:
                  _node.requestFocus();
                  return;
                case SemanticAction.activate:
                  _node.requestFocus();
                  // A decline or a throw reaches the action's result.
                  _run();
                  return;
                case _:
                  return;
              }
            },
            onSetValue: widget.onSetValue == null ? null : _setValue,
            child: GestureDetector(
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              // A click focuses the control and activates it, so pointer users
              // get the same affordance as keyboard users.
              onTap: () {
                _node.requestFocus(reveal: false);
                _activate();
              },
              onSecondaryTap: widget.onSecondaryActivate == null
                  ? null
                  : () {
                      _node.requestFocus(reveal: false);
                      try {
                        widget.onSecondaryActivate!();
                      } on SemanticActionDeclined {
                        // A declined right-click is a no-op, like a primary click.
                        return;
                      }
                    },
              child: KeyDetector(
                onKey: (event) {
                  if ((_onKey)(event) == KeyEventResult.handled) {
                    event.consume();
                  }
                },
                child: Focus(
                  focusNode: _node,
                  autofocus: widget.autofocus,
                  child: widget.builder(resolvedStyle, true, states),
                ),
              ),
            ),
          );
    // A form control is a styled, interactive component — not selectable text.
    // Opt its label out of the ambient text selection, the way a browser makes
    // `<button>` text non-selectable. Standalone Text stays selectable.
    return MouseRegion(
      cursor: widget.enabled ? MouseCursor.pointer : MouseCursor.basic,
      onEnter: () {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: () {
        if (_hovered) setState(() => _hovered = false);
      },
      child: SelectionArea.disabled(child: content),
    );
  }
}
