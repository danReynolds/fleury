import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

// Shared dark theme for the Fleury sample apps, modeled on the storybook
// "cyber" palette so the showcases match the docs site.
const Color _fg = RgbColor(0xC8, 0xD3, 0xE0);
const Color _bg = RgbColor(0x0B, 0x0F, 0x14);
const Color _muted = RgbColor(0x6B, 0x7A, 0x8C);
const Color _accent = RgbColor(0x3D, 0xDC, 0x97);

/// The theme every sample app renders with.
const ThemeData fleurySampleTheme = ThemeData(
  brightness: Brightness.dark,
  textStyle: CellStyle(foreground: _fg),
  mutedStyle: CellStyle(foreground: _muted),
  selectionStyle: CellStyle(foreground: _bg, background: _accent, bold: true),
  focusedStyle: CellStyle(bold: true, foreground: _accent),
  borderStyle: BorderStyle.rounded,
  colorScheme: ColorScheme(
    foreground: _fg,
    background: _bg,
    primary: _accent,
    success: RgbColor(0x3D, 0xDC, 0x97),
    warning: RgbColor(0xF5, 0xC2, 0x11),
    error: RgbColor(0xFF, 0x5C, 0x57),
    info: RgbColor(0x56, 0xC2, 0xFF),
  ),
);

/// Wraps a sample app's content in the shared theme, a [Toaster] host, and a
/// full-surface background fill — so each sample is a self-contained root that
/// runs identically in a terminal or over `fleury serve` in the browser.
class SampleScaffold extends StatelessWidget {
  const SampleScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: fleurySampleTheme,
      child: Toaster(
        child: Container(
          color: fleurySampleTheme.colorScheme.background,
          child: child,
        ),
      ),
    );
  }
}

/// A bordered panel with a colored title row — the common framing for the
/// dashboard meters, the file-manager panes, and the agent surfaces.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.focused = false,
    this.expandChild = true,
  });

  final String title;
  final Widget child;

  /// Optional right-aligned widget on the title row (e.g. a status string).
  final Widget? trailing;

  /// When true the border + title glow with the accent color (active pane).
  final bool focused;

  /// When true the child is wrapped in [Expanded] so it fills the panel; set
  /// false for intrinsically-sized content laid out by the parent.
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final titleStyle = CellStyle(
      bold: true,
      foreground: focused ? accent : theme.colorScheme.foreground,
    );
    return Container(
      border: BoxBorder(
        style: theme.borderStyle,
        cellStyle: focused
            ? CellStyle(foreground: accent)
            : theme.mutedStyle,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(title, style: titleStyle),
              const Expanded(child: SizedBox.shrink()),
              if (trailing != null) trailing!,
            ],
          ),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}
