import 'package:fleury/fleury.dart';

/// Shows a hint anchored below [child] while focus is anywhere inside it.
///
/// A TUI has no hover, so focus is the trigger: Tab onto the wrapped
/// widget (or a focusable within it) and the [message] floats beneath it
/// via the [Anchor]/[Follower] primitive; move focus away and it
/// disappears. Built on [FocusWithin], so it tracks descendant focus —
/// wrap a button or field and it just works.
class Tooltip extends StatefulWidget {
  const Tooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  final AnchorLink _link = AnchorLink();
  OverlayEntry? _entry;

  void _onFocusChange(bool within) => within ? _show() : _hide();

  void _show() {
    if (_entry != null) return;
    final entry = OverlayEntry(
      builder: (_) => Follower(
        link: _link,
        child: Container(
          border: const BoxBorder(style: BorderStyle.rounded),
          child: Text(widget.message),
        ),
      ),
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusWithin(
      onFocusChange: _onFocusChange,
      child: Anchor(link: _link, child: widget.child),
    );
  }
}
