import 'package:fleury/fleury.dart';

/// Shows a hint anchored below [child] while focus is anywhere inside it.
///
/// A TUI has no hover, so focus is the trigger: Tab onto the wrapped
/// widget (or a focusable within it) and the [message] floats beneath it
/// via the [Anchor]/[Follower] primitive; move focus away and it
/// disappears. Built on [FocusWithin], so it tracks descendant focus —
/// wrap a button or field and it just works.
class Tooltip extends StatefulWidget {
  const Tooltip({
    super.key,
    required this.message,
    this.semanticLabel = 'Tooltip',
    required this.child,
  });

  final String message;

  /// Label exposed through the semantic app graph.
  final String semanticLabel;

  final Widget child;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  final AnchorLink _link = AnchorLink();
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
      builder: (_) => Follower(
        link: _link,
        child: Container(
          border: const BoxBorder(style: BorderStyle.rounded),
          child: Semantics(
            role: SemanticRole.text,
            label: widget.semanticLabel,
            value: _safeMessage,
            state: const SemanticState({'tooltipVisible': true}),
            child: Text(widget.message),
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
      child: FocusWithin(
        onFocusChange: _onFocusChange,
        child: KeyBindings(
          bindings: <KeyBinding>[
            KeyBinding(
              KeyChord.escape,
              onEvent: (event) {
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
          child: Anchor(link: _link, child: widget.child),
        ),
      ),
    );
  }

  String get _safeMessage {
    return sanitizeForDisplay(
      widget.message.replaceAll(_tooltipLineBreakPattern, ' '),
    );
  }
}

final _tooltipLineBreakPattern = RegExp(r'[\r\n\t]');
