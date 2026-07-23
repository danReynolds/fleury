import 'package:fleury/fleury_core.dart';

/// A bordered pane with a title row — the standard framing for dashboard
/// meters, file-manager panes, log surfaces, and any multi-pane screen.
///
/// ```dart
/// Panel(
///   title: 'CPU',
///   trailing: Text('42%'),
///   focused: _cpuFocus.hasFocus,
///   child: Sparkline(data: samples),
/// )
/// ```
///
/// The border and title resolve from the ambient [Theme]: muted at rest, the
/// [ColorScheme.primary] accent when [focused] is true — pass the active
/// pane's focus state so the user can see where input goes. `focused` is
/// plain controlled state (rebuild with the new value; e.g. from a
/// [FocusNode] listener or `focusNode.hasFocus` in build).
///
/// The panel is a semantic **region** named by [title] (override with
/// [semanticLabel]), so tests and agents can address each pane directly.
///
/// By default the [child] expands to fill the remaining panel height
/// ([expandChild] true) — right for panes sized by the surrounding layout
/// (e.g. inside [Expanded]). Set [expandChild] false for intrinsically-sized
/// content, letting the panel hug its child.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.focused = false,
    this.expandChild = true,
    this.semanticLabel,
  });

  /// Title shown on the panel's first row, styled by the theme.
  final String title;

  /// The panel body.
  final Widget child;

  /// Optional right-aligned widget on the title row (e.g. a status string).
  final Widget? trailing;

  /// Whether this panel is the active pane. When true the border and title
  /// use the theme's accent so focus is visible at a glance.
  final bool focused;

  /// When true (default) the child is wrapped in [Expanded] so it fills the
  /// panel; set false for intrinsically-sized content.
  final bool expandChild;

  /// Semantic label (the accessibility name; not rendered). Defaults to
  /// [title].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final titleStyle = CellStyle(
      bold: true,
      foreground: focused ? accent : theme.colorScheme.foreground,
    );
    return Semantics(
      role: SemanticRole.region,
      label: semanticLabel ?? title,
      focused: focused,
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
          mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                // Panel title is chrome, not selectable text; the child stays
                // selectable.
                Text(title, allowSelect: false, style: titleStyle),
                const Expanded(child: SizedBox.shrink()),
                if (trailing != null) trailing!,
              ],
            ),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
