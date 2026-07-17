import '../foundation/geometry.dart';
import '../rendering/border.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/edge_insets.dart';
import '../rendering/layout.dart';
import '../rendering/render_flex.dart';
import '../rendering/render_object.dart';
import '../rendering/render_objects.dart';
import '../rendering/render_stack.dart';
import '../rendering/render_wrap.dart';
import '../rendering/width_resolver.dart';
import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import 'align.dart';
import 'framework.dart';
import 'media_query.dart';
import 'selection/selectable.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// EmptyBox
// ---------------------------------------------------------------------------

/// A widget that mounts as a leaf and produces no visible output.
///
/// Useful as a placeholder where a `Widget?` is required and the
/// intentional answer is "nothing." Not a render-bearing widget — it
/// doesn't produce a render object, so it doesn't claim cells. (For an
/// empty rectangle that claims space, use `SizedBox`.)
final class EmptyBox extends Widget {
  const EmptyBox({super.key});

  @override
  Element createElement() => _EmptyBoxElement(this);
}

final class _EmptyBoxElement extends Element {
  _EmptyBoxElement(super.widget);

  @override
  void performRebuild() {
    // Leaf: nothing to build.
  }

  @override
  void visitChildren(void Function(Element child) visitor) {
    // Leaf.
  }
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/// Displays a string of text in the terminal.
///
/// The text is sanitized (control codes replaced with U+FFFD) before
/// reaching the cell buffer, so widget code can safely pass arbitrary
/// or untrusted strings. Grapheme widths are resolved against the
/// configured [TerminalProfile].
///
/// With [softWrap] true (default), text exceeding the available width
/// wraps onto additional rows at word boundaries (or hard-breaks
/// inside words longer than the width). With [softWrap] false, automatic
/// reflow is disabled; explicit newlines still create rows, and each long row
/// is clipped at the right edge. This is useful for status bars, key hints, or
/// anywhere overflow is preferable to reflow.
/// Its own [style] is merged on top of the ambient [DefaultTextStyle], so
/// a parent can set a base color/dim for a whole subtree once and each
/// `Text` overrides only what it sets.
final class Text extends StatelessWidget implements WidgetUpdatePruner {
  const Text(
    this.data, {
    super.key,
    this.style = CellStyle.empty,
    this.softWrap = true,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.left,
    this.profile = TerminalProfile.standard,
    this.allowSelect = true,
  });

  /// The text to display. Terminal control codes are sanitized before paint.
  final String data;

  /// Style merged over the nearest [DefaultTextStyle].
  final CellStyle style;

  /// Whether text automatically wraps to additional rows.
  ///
  /// When false, explicit newlines still create rows and each long row clips
  /// horizontally.
  final bool softWrap;

  /// Cap the number of lines; extra content is cut off (and ellipsized
  /// when [overflow] is [TextOverflow.ellipsis]).
  final int? maxLines;

  /// How content that exceeds the width/line budget is shown.
  final TextOverflow overflow;

  /// Horizontal alignment of each line within the available width.
  /// Defaults to [TextAlign.left]. Use [TextAlign.center] for
  /// centred headings, [TextAlign.right] for status numbers or
  /// right-anchored key hints.
  final TextAlign textAlign;

  /// Terminal width profile used to measure grapheme clusters.
  final TerminalProfile profile;

  /// Whether this Text participates in any ancestor `SelectionArea`'s
  /// selection. Defaults to `true`. Set to `false` for cosmetic
  /// labels that shouldn't be user-selectable (status indicators,
  /// tooltips, hint-bar fragments, etc.) — they'll still render but
  /// the mouse-drag highlight skips over them and Ctrl+A doesn't
  /// pull them into the selection.
  final bool allowSelect;

  @override
  bool hasEquivalentWidgetConfiguration(Widget other) {
    return other is Text &&
        key == other.key &&
        data == other.data &&
        style == other.style &&
        softWrap == other.softWrap &&
        maxLines == other.maxLines &&
        overflow == other.overflow &&
        textAlign == other.textAlign &&
        profile == other.profile &&
        allowSelect == other.allowSelect;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticRole.text,
      label: data,
      value: data,
      includeChildren: false,
      child: _RawText(
        data: data,
        style: DefaultTextStyle.of(context).merge(style),
        softWrap: softWrap,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        profile: profile,
        allowSelect: allowSelect,
      ),
    );
  }
}

final class _RawText extends LeafRenderObjectWidget {
  const _RawText({
    required this.data,
    required this.style,
    required this.softWrap,
    required this.maxLines,
    required this.overflow,
    required this.textAlign,
    required this.profile,
    required this.allowSelect,
  });

  final String data;
  final CellStyle style;
  final bool softWrap;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final TerminalProfile profile;
  final bool allowSelect;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final r = RenderText(
      text: data,
      style: style,
      softWrap: softWrap,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      profile: profile,
    );
    // Wire the Selectable to the ambient registrar so app-wide
    // selection systems see this text widget. allowSelect == false
    // masks us off — register against null, which is a no-op.
    r.attachToSelection(allowSelect ? SelectionScope.maybeOf(context) : null);
    return r;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderText renderObject,
  ) {
    renderObject
      ..text = data
      ..style = style
      ..softWrap = softWrap
      ..maxLines = maxLines
      ..overflow = overflow
      ..textAlign = textAlign
      ..profile = profile;
    // If the ambient SelectionScope changed (e.g. a SelectionArea
    // mounted above us) OR allowSelect flipped, re-attach.
    renderObject.attachToSelection(
      allowSelect ? SelectionScope.maybeOf(context) : null,
    );
  }

  @override
  LeafRenderObjectElement createElement() => _RawTextElement(this);
}

/// Custom element that detaches the [RenderText]'s Selectable from
/// the ambient registrar on permanent unmount. The base class would
/// just drop the render object on the floor; we need to tell the
/// area to forget it.
class _RawTextElement extends LeafRenderObjectElement {
  _RawTextElement(_RawText super.widget);

  @override
  void unmount() {
    (renderObject as RenderText).detachFromSelection();
    super.unmount();
  }
}

// ---------------------------------------------------------------------------
// ErrorWidget
// ---------------------------------------------------------------------------

/// The fallback shown in place of a subtree whose `build` threw — a red,
/// bordered panel with the error message, so one broken widget doesn't
/// take down the whole UI (and the dev sees what failed).
///
/// Customize globally via [ErrorWidget.builder]. The runtime wires this
/// in as the build-error boundary; see `BuildOwner.errorBuilder`.
final class ErrorWidget extends StatelessWidget {
  const ErrorWidget(this.error, {this.stackTrace, super.key});

  final Object error;
  final StackTrace? stackTrace;

  /// Builds the widget for a caught build error. Replace to customize the
  /// look (or to surface more detail). Must not itself throw.
  static Widget Function(Object error, StackTrace stack) builder =
      (error, stack) => ErrorWidget(error, stackTrace: stack);

  @override
  Widget build(BuildContext context) {
    return Container(
      border: const BoxBorder(
        style: BorderStyle.rounded,
        cellStyle: CellStyle(foreground: AnsiColor(1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        '⚠ $error',
        style: const CellStyle(foreground: AnsiColor(1)),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SizedBox
// ---------------------------------------------------------------------------

/// A widget that imposes specific dimensions on its child.
///
/// A null width or height adds no constraint on that axis beyond the bounds
/// supplied by the parent, so the child chooses its size there. With no child,
/// a null axis resolves to the parent's minimum (often zero).
final class SizedBox extends SingleChildRenderObjectWidget {
  const SizedBox({
    super.key,
    this.width,
    this.height,

    /// Content constrained to the requested size, or null for an empty box.
    super.child,
  });

  /// Convenience for a fixed `width x height` box with no child.
  const SizedBox.fromSize({
    super.key,

    /// Fixed width in terminal cells.
    required int cols,

    /// Fixed height in terminal rows.
    required int rows,
  }) : width = cols,
       height = rows,
       super(child: null);

  /// Convenience for a zero-sized leaf.
  const SizedBox.shrink({super.key})
    : width = 0,
      height = 0,
      super(child: null);

  /// Forces the box to fill the parent's bounded space on both axes.
  /// An unbounded axis remains unconstrained, and the child chooses its size.
  /// In a [Row] or [Column], use [Expanded] or [Flexible] to claim remaining
  /// main-axis space; inflexible children are unbounded on that axis.
  const SizedBox.expand({
    super.key,

    /// Content forced to fill all bounded space supplied by the parent.
    super.child,
  }) : width = expandSize,
       height = expandSize;

  /// Forces the box to be `dimension x dimension`. Equivalent to
  /// `SizedBox(width: dimension, height: dimension, child: child)`.
  const SizedBox.square({
    super.key,

    /// Width and height in cells, or null to defer both axes to the parent.
    int? dimension,

    /// Content constrained to the square.
    super.child,
  }) : width = dimension,
       height = dimension;

  /// Sentinel value carried as a `width`/`height` to mean "take all
  /// the parent-imposed space on this axis." Exposed for advanced
  /// callers; most code should reach for [SizedBox.expand] instead.
  static const int expandSize = 0x7fffffff;

  /// Requested width in cells, or null to add no width constraint.
  final int? width;

  /// Requested height in rows, or null to add no height constraint.
  final int? height;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSizedBox(width: width, height: height);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSizedBox renderObject,
  ) {
    renderObject
      ..width = width
      ..height = height;
  }
}

// ---------------------------------------------------------------------------
// Padding
// ---------------------------------------------------------------------------

/// Wraps [child] in an [EdgeInsets] of empty cells on each side.
final class Padding extends SingleChildRenderObjectWidget {
  const Padding({
    super.key,
    required this.padding,

    /// Content inset by [padding], or null to reserve padding alone.
    super.child,
  });

  /// Empty cells to insert around the child.
  final EdgeInsets padding;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPadding(padding: padding);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPadding renderObject,
  ) {
    renderObject.padding = padding;
  }
}

// ---------------------------------------------------------------------------
// Flex / Row / Column / Expanded / Flexible
// ---------------------------------------------------------------------------

/// Lays children along a main axis using the flex protocol from
/// [RenderFlex]. [Row] and [Column] are convenience subclasses that fix
/// the direction.
class Flex extends MultiChildRenderObjectWidget {
  const Flex({
    super.key,
    required this.direction,
    this.mainAxisSize = MainAxisSize.max,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    super.children,
  });

  final Axis direction;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFlex(
      direction: direction,
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFlex renderObject,
  ) {
    renderObject
      ..direction = direction
      ..mainAxisSize = mainAxisSize
      ..mainAxisAlignment = mainAxisAlignment
      ..crossAxisAlignment = crossAxisAlignment;
  }
}

/// Horizontal [Flex].
class Row extends Flex {
  const Row({
    super.key,
    super.mainAxisSize,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.children,
  }) : super(direction: Axis.horizontal);
}

/// Vertical [Flex].
class Column extends Flex {
  const Column({
    super.key,
    super.mainAxisSize,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.children,
  }) : super(direction: Axis.vertical);
}

/// A widget that takes a `flex` share of the available main-axis space
/// in a [Flex]. Always uses [FlexFit.tight] — the child is forced to
/// take exactly its allocation.
class Expanded extends Flexible {
  const Expanded({super.key, super.flex, required super.child})
    : super(fit: FlexFit.tight);
}

/// A flexible empty gap along the main axis of a [Row] or [Column].
///
/// A `Spacer()` between two children pushes them to opposite ends;
/// `Spacer(flex: 2)` takes twice the share of another `Spacer`. It is
/// shorthand for `Expanded(flex: flex, child: const SizedBox.shrink())`.
class Spacer extends StatelessWidget {
  const Spacer({super.key, this.flex = 1})
    : assert(flex > 0, 'Spacer flex must be greater than zero.');

  /// This spacer's share of the remaining main-axis space, relative to
  /// other flex children.
  final int flex;

  @override
  Widget build(BuildContext context) =>
      Expanded(flex: flex, child: const SizedBox.shrink());
}

/// A widget that takes up to a `flex` share of the available main-axis
/// space in a [Flex]. With [FlexFit.loose] the child can take less than
/// its allocation; with [FlexFit.tight] it must take exactly that much.
class Flexible extends SingleChildRenderObjectWidget {
  const Flexible({
    super.key,
    this.flex = 1,
    this.fit = FlexFit.loose,

    /// Content laid out within this widget's flex allocation.
    required Widget super.child,
  });

  /// Share of remaining main-axis space relative to sibling flex children.
  final int flex;

  /// Whether the child must fill its allocation or may use less of it.
  final FlexFit fit;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFlexible(flex: flex, fit: fit);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFlexible renderObject,
  ) {
    renderObject
      ..flex = flex
      ..fit = fit;
  }
}

// ---------------------------------------------------------------------------
// Stack / Positioned
// ---------------------------------------------------------------------------

/// Overlays children at the same origin and lets later siblings
/// overwrite earlier ones.
///
/// Non-positioned children determine the stack's size (intrinsic of the
/// largest non-positioned child). Positioned children float on top with
/// explicit offsets and (optional) sizes. Children paint in declaration
/// order; the cell buffer's eviction rules handle wide-grapheme
/// overlap correctly.
final class Stack extends MultiChildRenderObjectWidget {
  const Stack({super.key, super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderStack();

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderStack renderObject,
  ) {
    // RenderStack has no per-frame configuration today.
  }
}

/// Shows the child at [index] and keeps the rest mounted but unpainted,
/// so their state survives switching between them — the basis for tabbed
/// or paged surfaces that must remember each page. Sized to the largest
/// child; an out-of-range [index] shows nothing.
final class IndexedStack extends MultiChildRenderObjectWidget {
  const IndexedStack({super.key, this.index = 0, super.children});

  /// Which child to paint. Out-of-range paints nothing.
  final int index;

  @override
  MultiChildRenderObjectElement createElement() => _IndexedStackElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderIndexedStack(index: index);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderIndexedStack renderObject,
  ) {
    renderObject.index = index;
  }
}

final class _IndexedStackElement extends MultiChildRenderObjectElement
    implements SemanticChildrenProvider {
  _IndexedStackElement(IndexedStack super.widget);

  @override
  IndexedStack get widget => super.widget as IndexedStack;

  @override
  void visitSemanticChildren(void Function(Element child) visitor) {
    final children = childElements;
    final active = widget.index;
    if (active < 0 || active >= children.length) return;
    visitor(children[active]);
  }
}

// ---------------------------------------------------------------------------
// Wrap
// ---------------------------------------------------------------------------

/// Flows [children] left-to-right, wrapping to a new row when the next
/// one won't fit the available width. The layout behind chips, tags,
/// token lists, and reflowing toolbars.
///
/// [spacing] separates children within a row; [runSpacing] separates the
/// rows. A child too wide for the line gets a row of its own.
final class Wrap extends MultiChildRenderObjectWidget {
  const Wrap({
    super.key,
    this.spacing = 0,
    this.runSpacing = 0,

    /// Widgets flowed into successive runs in declaration order.
    super.children = const <Widget>[],
  });

  /// Gap between children within a row.
  final int spacing;

  /// Gap between rows.
  final int runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderWrap(spacing: spacing, runSpacing: runSpacing);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderWrap renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

/// Places its [child] at the given offset (and optional size) inside a
/// [Stack].
///
/// `width` / `height` of `null` mean "use the child's intrinsic size on
/// that axis." Using this widget outside a [Stack] is supported but the
/// position is ignored — the child paints at the parent's normal layout
/// position.
final class Positioned extends SingleChildRenderObjectWidget {
  const Positioned({
    super.key,
    this.left = 0,
    this.top = 0,
    this.width,
    this.height,

    /// Content positioned relative to the surrounding [Stack].
    required Widget super.child,
  });

  /// Horizontal offset from the stack's left edge, in cells.
  final int left;

  /// Vertical offset from the stack's top edge, in rows.
  final int top;

  /// Child width in cells, or null to use its intrinsic width.
  final int? width;

  /// Child height in rows, or null to use its intrinsic height.
  final int? height;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPositioned(left: left, top: top, width: width, height: height);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPositioned renderObject,
  ) {
    renderObject
      ..left = left
      ..top = top
      ..width = width
      ..height = height;
  }
}

// ---------------------------------------------------------------------------
// Container
// ---------------------------------------------------------------------------

/// A convenience widget composing [Padding] + [SizedBox] + an
/// optional [BoxBorder] frame.
///
/// Composition order, from outermost to innermost: `SizedBox` →
/// `Border` → `Padding` → child. That means `width` / `height`
/// describe the *outer* dimensions including the border, and
/// `padding` insets the child away from the border on the inside.
final class Container extends StatelessWidget {
  const Container({
    super.key,
    this.alignment,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.border,
    this.color,
    this.child,
  });

  /// How the [child] is positioned inside the container's content
  /// area (after padding, inside the border). null means "stretch the
  /// child to fill the available space" — the same behaviour you get
  /// when [Container] has no alignment today. Use [Alignment.center]
  /// to centre a fixed-size child inside a larger container, etc.
  final Alignment? alignment;

  /// Outer width in cells, including border and padding; null leaves it flexible.
  final int? width;

  /// Outer height in rows, including border and padding; null leaves it flexible.
  final int? height;

  /// Empty cells inserted between the border and the child.
  final EdgeInsets? padding;

  /// Empty cells inserted outside the border, between this container
  /// and its parent. Implemented as a wrapping [Padding] — equivalent
  /// to wrapping the whole Container in `Padding(padding: margin, ...)`.
  final EdgeInsets? margin;

  /// Draws a four-sided border around [child]. Adds one cell on each
  /// side to the container's total extent.
  final BoxBorder? border;

  /// Background color painted into every cell the container occupies
  /// (after padding, inside the border). null leaves the underlying
  /// surface visible — appropriate for laying a Container over an
  /// already-styled background.
  final Color? color;

  /// Content inside the optional padding, fill, and border.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    Widget? result = child;
    final align = alignment;
    if (align != null && result != null) {
      result = Align(alignment: align, child: result);
    }
    final p = padding;
    if (p != null) {
      result = Padding(padding: p, child: result);
    }
    final fill = color;
    if (fill != null) {
      result = _FilledBox(color: fill, child: result);
    }
    final b = border;
    if (b != null) {
      result = _Border(border: b, child: result);
    }
    if (width != null || height != null) {
      result = SizedBox(width: width, height: height, child: result);
    }
    final m = margin;
    if (m != null) {
      result = Padding(padding: m, child: result ?? const EmptyBox());
    }
    return result ?? const EmptyBox();
  }
}

/// An opaque, theme-aware background that fills its slot — the terminal analog
/// of a card or sheet. Put screen or dialog content on a [Surface] and nothing
/// painted beneath shows through; [NavigatorState.present] wraps presented
/// content in one by default, so a modal is never see-through.
///
/// The fill resolves to [color], else [ColorScheme.surface], else a concrete
/// brightness-appropriate default — always opaque, unlike
/// [ColorScheme.background] (nullable = the terminal default, i.e. transparent).
class Surface extends StatelessWidget {
  const Surface({super.key, this.color, this.child});

  /// Explicit fill. When null, resolves from the theme (see the class doc).
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final fill =
        color ??
        theme.colorScheme.surface ??
        (theme.brightness == Brightness.dark
            ? const RgbColor(0x12, 0x12, 0x14)
            : const RgbColor(0xF2, 0xF2, 0xF4));
    return _FilledBox(color: fill, child: child);
  }
}

class _FilledBox extends SingleChildRenderObjectWidget {
  const _FilledBox({required this.color, super.child});
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFilledBox(color);

  @override
  void updateRenderObject(BuildContext context, _RenderFilledBox r) {
    r.color = color;
  }
}

class _RenderFilledBox extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderFilledBox(this._color);

  Color _color;
  set color(Color v) {
    if (_color == v) return;
    _color = v;
    markNeedsPaintOnly();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final c = _child;
    if (c == null) {
      return constraints.constrain(
        CellSize(constraints.maxCols ?? 0, constraints.maxRows ?? 0),
      );
    }
    return c.layout(constraints);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    final s = size;
    final fillStyle = CellStyle(background: _color);
    // Pre-fill every covered cell with our background — gives empty
    // cells a colored square (otherwise they'd render as terminal-
    // default).
    for (var r = 0; r < s.rows; r++) {
      for (var col = 0; col < s.cols; col++) {
        final c = offset.col + col;
        final ro = offset.row + r;
        if (c < 0 || c >= buffer.size.cols) continue;
        if (ro < 0 || ro >= buffer.size.rows) continue;
        buffer.writeGrapheme(CellOffset(c, ro), ' ', style: fillStyle);
      }
    }
    // Now paint the child. writeGrapheme replaces the cell wholesale,
    // so cells the child touches lose our bg. Walk back through and
    // merge our bg into any cell the child painted that didn't set
    // its own background.
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
    for (var r = 0; r < s.rows; r++) {
      for (var col = 0; col < s.cols; col++) {
        final c = offset.col + col;
        final ro = offset.row + r;
        if (c < 0 || c >= buffer.size.cols) continue;
        if (ro < 0 || ro >= buffer.size.rows) continue;
        final cell = buffer.atColRow(c, ro);
        if (cell.style.background != null) continue; // child set its own
        if (cell.role == CellRole.empty) continue; // already our fill
        if (cell.role == CellRole.continuation ||
            cell.role == CellRole.overlay) {
          continue;
        }
        buffer.writeGrapheme(
          CellOffset(c, ro),
          cell.grapheme!,
          style: cell.style.merge(fillStyle),
        );
      }
    }
  }
}

class _Border extends SingleChildRenderObjectWidget {
  const _Border({required this.border, super.child});

  final BoxBorder border;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderBorder(border: _effectiveBorder(context));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBorder renderObject,
  ) {
    renderObject.border = _effectiveBorder(context);
  }

  /// On an ASCII glyph tier, box-drawing borders degrade to the ASCII style
  /// (`+`, `-`, `|`) so they stay legible on legacy terminals/fonts.
  BoxBorder _effectiveBorder(BuildContext context) {
    if (MediaQuery.glyphTierOf(context) != GlyphTier.ascii ||
        border.style == BorderStyle.ascii) {
      return border;
    }
    return BoxBorder(style: BorderStyle.ascii, cellStyle: border.cellStyle);
  }
}

// ---------------------------------------------------------------------------
// ConstrainedBox
// ---------------------------------------------------------------------------

/// Forces its child to satisfy additional layout constraints. Sits
/// between [SizedBox] (which sets *one* fixed size) and a bare child
/// (which uses whatever the parent gave it) — useful when you want
/// "at least 20 cells wide, no more than 40" or similar bounds.
///
/// The child is laid out within the intersection of the parent's
/// constraints and these additional ones. If the intersection is
/// empty (e.g. you asked for `minWidth: 50` inside a parent that
/// offered at most 20), the parent's bounds win.
final class ConstrainedBox extends SingleChildRenderObjectWidget {
  const ConstrainedBox({
    super.key,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,

    /// Content laid out within the intersection of these and parent constraints.
    required Widget super.child,
  });

  /// Additional minimum width in cells, bounded by the parent's constraints.
  final int? minWidth;

  /// Additional maximum width in cells, bounded by the parent's constraints.
  final int? maxWidth;

  /// Additional minimum height in rows, bounded by the parent's constraints.
  final int? minHeight;

  /// Additional maximum height in rows, bounded by the parent's constraints.
  final int? maxHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderConstrainedBox(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    covariant _RenderConstrainedBox renderObject,
  ) {
    renderObject
      ..minWidth = minWidth
      ..maxWidth = maxWidth
      ..minHeight = minHeight
      ..maxHeight = maxHeight;
  }
}

class _RenderConstrainedBox extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderConstrainedBox({
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
  });

  int? minWidth;
  int? maxWidth;
  int? minHeight;
  int? maxHeight;

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Intersect this widget's requested bounds with the parent's.
    // Parent bounds always win on conflict (Flutter semantics).
    final parentMaxCols = constraints.maxCols;
    final parentMaxRows = constraints.maxRows;
    int minC = (minWidth ?? constraints.minCols);
    int? maxC = maxWidth ?? parentMaxCols;
    if (parentMaxCols != null && (maxC == null || maxC > parentMaxCols)) {
      maxC = parentMaxCols;
    }
    if (maxC != null && minC > maxC) minC = maxC;
    if (minC < constraints.minCols) minC = constraints.minCols;
    // The parent-min re-clamp above can raise minC back above a smaller
    // widget maxC (e.g. an Expanded parent's tight minCols vs a narrow
    // maxWidth). Re-raise maxC so the parent's tight bound wins rather than
    // building an impossible min > max — Flutter's enforce semantics.
    if (maxC != null && maxC < minC) maxC = minC;

    int minR = (minHeight ?? constraints.minRows);
    int? maxR = maxHeight ?? parentMaxRows;
    if (parentMaxRows != null && (maxR == null || maxR > parentMaxRows)) {
      maxR = parentMaxRows;
    }
    if (maxR != null && minR > maxR) minR = maxR;
    if (minR < constraints.minRows) minR = constraints.minRows;
    if (maxR != null && maxR < minR) maxR = minR;

    final childConstraints = CellConstraints(
      minCols: minC,
      maxCols: maxC,
      minRows: minR,
      maxRows: maxR,
    );
    return _child?.layout(childConstraints) ?? CellSize(minC, minR);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}

// ---------------------------------------------------------------------------
// AspectRatio
// ---------------------------------------------------------------------------

/// Sizes its child to a target width:height ratio while staying within the
/// parent's constraints. When bounded constraints admit the ratio, the largest
/// matching box wins. An unbounded axis falls back to its minimum, and
/// incompatible minimums can force the result away from the target ratio.
///
/// ⚠ Terminal cells are typically *taller than wide* (often roughly
/// 2:1 height:width). A literal 1:1 [aspectRatio] produces a visually
/// rectangular box. For visually square content (e.g. heatmap cells)
/// multiply by the cell height-to-width ratio:
/// `AspectRatio(aspectRatio: 2.0, ...)` for a typical 2:1 cell, or use your
/// terminal's measured cell aspect.
final class AspectRatio extends SingleChildRenderObjectWidget {
  const AspectRatio({
    super.key,
    required this.aspectRatio,

    /// Content laid out within the resolved box.
    required Widget super.child,
  }) : assert(aspectRatio > 0, 'aspectRatio must be > 0');

  /// Target ratio expressed as `width / height` in cells. A ratio of
  /// `2.0` means the box is twice as wide as it is tall.
  final double aspectRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAspectRatio(aspectRatio: aspectRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    covariant _RenderAspectRatio renderObject,
  ) {
    renderObject.aspectRatio = aspectRatio;
  }
}

class _RenderAspectRatio extends RenderObject
    implements RenderObjectWithSingleChild {
  _RenderAspectRatio({required double aspectRatio})
    : _aspectRatio = aspectRatio;

  double _aspectRatio;
  double get aspectRatio => _aspectRatio;
  set aspectRatio(double value) {
    if (_aspectRatio == value) return;
    _aspectRatio = value;
    markNeedsLayout();
  }

  RenderObject? _child;
  @override
  RenderObject? get child => _child;
  @override
  set child(RenderObject? value) {
    if (identical(_child, value)) return;
    if (_child != null) dropChild(_child!);
    _child = value;
    if (value != null) adoptChild(value);
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    // Pick the largest box that fits both axes at the target ratio.
    // Unbounded axes (null maxCols/maxRows) fall back to the lower
    // bound — we can't enlarge into infinity sensibly.
    final maxC = constraints.maxCols ?? constraints.minCols;
    final maxR = constraints.maxRows ?? constraints.minRows;
    var w = maxC;
    var h = (w / _aspectRatio).floor();
    if (h > maxR) {
      h = maxR;
      w = (h * _aspectRatio).floor();
      if (w > maxC) w = maxC;
    }
    if (w < constraints.minCols) w = constraints.minCols;
    if (h < constraints.minRows) h = constraints.minRows;
    final tight = CellConstraints(
      minCols: w,
      maxCols: w,
      minRows: h,
      maxRows: h,
    );
    _child?.layout(tight);
    return CellSize(w, h);
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    _child?.paint(
      buffer,
      offset,
      screenOffset: screenOffset ?? offset,
      clipRect: clipRect,
    );
  }
}
