import 'package:fleury/fleury_core.dart';

/// Shows a hint below [child] while keyboard focus is anywhere inside it.
///
/// Focus is the trigger, not the mouse: Tab onto the wrapped widget (or any
/// focusable widget inside it) and [message] appears in a framed box just
/// below it, or above it when there isn't room; move focus away and it
/// disappears. Escape hides it until focus leaves and returns. Wrap a button
/// or a field and it works without setup. Clicks elsewhere in the app still
/// work while the hint is showing.
class Tooltip extends StatefulWidget {
  const Tooltip({
    super.key,
    required this.message,
    this.semanticLabel = 'Tooltip',
    required this.child,
  });

  /// Hint text shown while focus is within [child], unless the user dismisses
  /// it with Escape. Leaving and re-entering the child restores the hint.
  final String message;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  /// Widget whose descendant focus controls tooltip visibility.
  final Widget child;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  final BoundsNotifier _bounds = BoundsNotifier();
  OverlayEntry? _entry;

  // Set when Esc dismisses the tip while the trigger keeps focus; cleared when
  // focus leaves, so re-focusing the trigger shows the tip again.
  bool _dismissed = false;

  void _onFocusChange(bool within) {
    if (within) {
      if (!_dismissed) _show();
    } else {
      _dismissed = false;
      _hide();
    }
  }

  void _show() {
    if (_entry != null) return;
    final entry = OverlayEntry(
      owner: context,
      // BoundsAnchor, not AnchoredFloat: a tooltip is decorative chrome that
      // shows on focus and is never dismissed by a click, so it must not
      // stack AnchoredFloat's full-screen AbsorbPointer. That barrier ate every
      // click, scroll and click-to-focus in the app for as long as a tooltip
      // was visible. The dismissable floats (Autocomplete, ColorPicker,
      // CompletionTextInput) keep AnchoredFloat — they each pass onTapOutside
      // and need the outside click.
      builder: (context) => BoundsAnchor(
        notifier: _bounds,
        // Container.framed supplies the float's skin: an opaque fill so the
        // app beneath doesn't bleed through, plus the frame. The tooltip's
        // text is chrome, not content, so it opts out of the app's ambient
        // selection — stated here rather than inherited from the fact that an
        // overlay entry happens to mount outside DefaultRootSelection.
        child: SelectionArea.disabled(
          child: Container.framed(
            border: const BoxBorder(style: BorderStyle.rounded),
            child: Semantics(
              role: SemanticRole.text,
              label: widget.semanticLabel,
              value: _safeMessage,
              state: const SemanticState({'tooltipVisible': true}),
              child: Text(widget.message, allowSelect: false),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
    setState(() {});
  }

  void _hide({bool notify = true}) {
    _entry?.remove();
    _entry = null;
    if (notify && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant Tooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message ||
        widget.semanticLabel != oldWidget.semanticLabel) {
      _entry?.markNeedsBuild();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _hide(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.region,
      label: widget.semanticLabel,
      value: _safeMessage,
      hint: _safeMessage,
      state: SemanticState({'tooltipVisible': _entry != null}),
      child: FocusDetector(
        onFocusChange: _onFocusChange,
        child: KeyBindings(
          bindings: <KeyBinding>[
            KeyBinding(
              KeySequence.escape,
              onTrigger: (event) {
                if (_entry == null) {
                  event.bubble();
                  return;
                }
                // WCAG 1.4.13: a persistent tip must be dismissible without
                // moving focus, in case it overlays content the user wants.
                _dismissed = true;
                _hide();
              },
              hideFromHintBar: true,
            ),
          ],
          child: BoundsObserver(notifier: _bounds, child: widget.child),
        ),
      ),
    );
  }

  String get _safeMessage {
    return sanitizeSingleLine(widget.message);
  }
}
