// Popup: the floating-chrome composite.
//
// Floating content composites over whatever is already painted — cells are
// not auto-cleared — so a float must own every cell it covers, or the app
// bleeds through its frame. Every stock overlay used to hand-assemble that
// contract (position + frame + Surface + selection opt-out), and every one
// forgot an ingredient at some point. Popup bundles the non-varying parts so
// a float can't be assembled wrong; the parts that genuinely vary stay with
// the caller.
//
// The same two-level split exists in the peer frameworks: ratatui's `Clear`
// vs `tui-popup`, Flutter's `Material` vs `Dialog`. `Surface` is Fleury's
// mechanism level; Popup is the composite level.

import 'package:fleury/fleury_core.dart';

/// An opaque, framed, chrome layer for floating content.
///
/// A floating widget composites over the app — cells are not auto-cleared —
/// so it must paint its own background or the content underneath shows
/// through its frame. [Popup] owns that contract:
///
///   * an **opaque fill** (a [Surface], themed like the Navigator gives a
///     presented route),
///   * a **frame** (the theme border, or [border]; [Popup.bare] for content
///     that draws its own),
///   * **chrome semantics** — the ambient text selection skips it, the way a
///     browser makes control chrome unselectable. Set [selectableContent]
///     for a popup whose text the user should be able to copy.
///
/// It deliberately does NOT position itself and does NOT manage focus:
/// anchor it with [Follower], pin it with [Align], mount it in an
/// [OverlayEntry], and wrap it in a modal [FocusScope] when it should trap
/// focus — exactly as the stock overlays do.
///
/// **When to reach for it.** Work down this ladder and stop at the first
/// rung that fits:
///
///  1. A stock overlay fits (`Tooltip`, `Menu`, `Select`, `Toaster`,
///     `WhichKey`, `CommandPalette`)? Use it — they build on Popup
///     internally, and you never touch this widget.
///  2. Modal content the user acts on? `context.present(...)` — the
///     Navigator supplies the surface, barrier, and focus trap, and
///     `Dialog` is the frame for that. Don't hand-build modality from
///     Popup.
///  3. A custom **non-modal** float you place yourself (a hover card, a
///     status flyout, a HUD)? This widget, positioned with [Follower],
///     [Align], or an [OverlayEntry].
///  4. Just layering your own content (a label over a chart)? A plain
///     [Stack] — that's layout, not floating. The moment a layer covers
///     content that keeps painting underneath it, it needs this widget's
///     fill, or the content bleeds through.
///
/// ```dart
/// // An anchored hint (how Tooltip is built):
/// Follower(link: link, child: Popup(child: Text('Saved 2 minutes ago')))
///
/// // A pinned toast-style layer:
/// Align(
///   alignment: Alignment.bottomRight,
///   child: Popup(
///     border: const BoxBorder(style: BorderStyle.rounded),
///     padding: const EdgeInsets.symmetric(horizontal: 1),
///     child: Text('Build finished'),
///   ),
/// )
/// ```
class Popup extends StatelessWidget {
  /// A framed popup. [border] overrides the theme frame.
  const Popup({
    super.key,
    this.border,
    this.padding,
    this.color,
    this.selectableContent = false,
    required this.child,
  }) : _framed = true;

  /// A popup with the opaque fill and chrome semantics but no frame — for
  /// content that draws its own (a titled `Panel`, custom chrome).
  const Popup.bare({
    super.key,
    this.padding,
    this.color,
    this.selectableContent = false,
    required this.child,
  }) : border = null,
       _framed = false;

  /// The frame. Null on the default constructor means the theme's border
  /// style;
  /// [Popup.bare] draws none.
  final BoxBorder? border;

  /// Inner padding between the frame and the content.
  final EdgeInsets? padding;

  /// Fill override. Null resolves the theme surface color (see [Surface]).
  final Color? color;

  /// Whether the popup's text participates in the ambient selection.
  ///
  /// Defaults to false: a popup is chrome, and dragging across the app
  /// should not pick up hint text. Enable it for a popup whose content the
  /// user may want to copy (an error detail, a code snippet).
  final bool selectableContent;

  /// The popup content.
  final Widget child;

  final bool _framed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content = Container(
      border: _framed ? (border ?? BoxBorder(style: theme.borderStyle)) : null,
      padding: padding,
      child: child,
    );
    content = Surface(color: color, child: content);
    if (!selectableContent) {
      content = SelectionArea.disabled(child: content);
    }
    return content;
  }
}
