import 'package:fleury/fleury_core.dart';

/// A bordered pane with a title row — the standard framing for dashboard
/// meters, file-manager panes, log surfaces, and any multi-pane screen.
///
/// ```dart
/// Panel(
///   title: 'CPU',
///   trailing: Text('42%'),
///   child: Sparkline(data: samples),
/// )
/// ```
///
/// The border and title resolve from the ambient [Theme]: muted at rest, the
/// [ColorScheme.primary] accent when the pane is active, so the user can see
/// where input goes. **Active-ness is detected, not declared** — the panel
/// watches the focus tree ([FocusWithin]) and accents itself whenever focus is
/// anywhere inside it. Nesting resolves innermost-first, so an inner pane
/// lights up without also lighting its ancestors.
///
/// Set [focused] only to override that: `true`/`false` pins the chrome
/// regardless of where focus is, which is what a static showcase or a pane
/// whose "active" notion isn't focus wants.
///
/// The panel is a semantic **region** named by [title] (override with
/// [semanticLabel]), so tests and agents can address each pane directly.
///
/// By default the [child] expands to fill the remaining panel height
/// ([expandChild] true) — right for panes sized by the surrounding layout
/// (e.g. inside [Expanded]). Set [expandChild] false for intrinsically-sized
/// content, letting the panel hug its child.
class Panel extends StatefulWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.focused,
    this.expandChild = true,
    this.semanticLabel,
  });

  /// Title shown on the panel's first row, styled by the theme.
  final String title;

  /// The panel body.
  final Widget child;

  /// Optional right-aligned widget on the title row (e.g. a status string).
  final Widget? trailing;

  /// Overrides the detected active state. Null (default) means "follow focus":
  /// the panel accents itself while focus is inside it.
  final bool? focused;

  /// When true (default) the child is wrapped in [Expanded] so it fills the
  /// panel; set false for intrinsically-sized content.
  final bool expandChild;

  /// Semantic label (the accessibility name; not rendered). Defaults to
  /// [title].
  final String? semanticLabel;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  /// Whether focus is inside this panel, tracked by [FocusWithin]. Only
  /// consulted when the caller left [Panel.focused] null.
  bool _focusWithin = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final focused = widget.focused ?? _focusWithin;
    final titleStyle = CellStyle(
      bold: true,
      foreground: focused ? accent : theme.colorScheme.foreground,
    );
    return Semantics(
      role: SemanticRole.region,
      label: widget.semanticLabel ?? widget.title,
      focused: focused,
      // Always mounted so the subtree shape doesn't change when a caller
      // toggles `focused` between null and a pinned value; the listener is
      // idle when the panel isn't following focus.
      child: FocusWithin(
        onFocusChange: (within) {
          if (widget.focused != null || within == _focusWithin) return;
          setState(() => _focusWithin = within);
        },
        child: Container(
          border: BoxBorder(
            style: theme.borderStyle,
            cellStyle: focused
                ? CellStyle(foreground: accent)
                : theme.mutedStyle,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: widget.expandChild
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(widget.title, style: titleStyle),
                  const Expanded(child: SizedBox.shrink()),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
              if (widget.expandChild)
                Expanded(child: widget.child)
              else
                widget.child,
            ],
          ),
        ),
      ),
    );
  }
}
