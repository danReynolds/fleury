import 'package:fleury/fleury_host.dart';

/// Modal chrome — a bordered, padded panel with an optional [title] —
/// ready to hand to `present`:
///
/// ```dart
/// context.present<bool>(Dialog(
///   title: 'Delete file?',
///   child: Column(
///     mainAxisSize: MainAxisSize.min,
///     children: [Text('This cannot be undone.'), /* buttons… */],
///   ),
/// ));
/// ```
///
/// Dialog supplies only the frame; positioning is `present`'s job (it
/// centers by default). Give it a [width] for a stable panel size, or
/// leave it null to size to the content.
class Dialog extends StatelessWidget {
  const Dialog({
    super.key,
    this.title,
    this.titleStyle,
    this.border,
    this.padding = const EdgeInsets.symmetric(horizontal: 1),
    this.width,
    required this.child,
  });

  /// Optional heading drawn at the top of the panel, inside the border.
  final String? title;

  /// Style for the [title]. Defaults to the theme's focused/emphasis style
  /// (bold).
  final CellStyle? titleStyle;

  /// The panel's border. Defaults to a box in the theme's border style.
  final BoxBorder? border;

  /// Inner padding between the border and the content.
  final EdgeInsets padding;

  /// Total panel width (including the border). Null sizes to content.
  final int? width;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = title;
    final body = t == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t, style: titleStyle ?? theme.focusedStyle),
              const SizedBox(height: 1),
              child,
            ],
          );
    return Semantics(
      role: SemanticRole.dialog,
      label: t,
      actions: const <SemanticAction>{SemanticAction.dismiss},
      onAction: (action) {
        if (action == SemanticAction.dismiss) {
          Navigator.maybeOf(context)?.pop();
        }
      },
      state: SemanticState({'hasTitle': t != null}),
      child: Container(
        width: width,
        border: border ?? BoxBorder(style: theme.borderStyle),
        padding: padding,
        child: body,
      ),
    );
  }
}
