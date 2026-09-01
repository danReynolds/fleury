// A render-object widget re-reads its inherited dependencies on a
// dependency-only rebuild.
//
// `update()` calls `updateRenderObject`, but a rebuild triggered purely by a
// dependency change (Theme swapped above a hoisted `const` render-object
// widget — the widget instance never changes, so `update()` never runs)
// only reconciled children. The render object kept the configuration it
// read at creation: a themed box kept painting the OLD colour.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Paints one cell in the theme's primary colour, read through the
/// element's own BuildContext — a dependency of the render-object element.
class _ThemedCell extends LeafRenderObjectWidget {
  const _ThemedCell();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderThemedCell(Theme.of(context).colorScheme.primary);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderThemedCell renderObject,
  ) {
    renderObject.color = Theme.of(context).colorScheme.primary;
  }
}

class _RenderThemedCell extends RenderObject {
  _RenderThemedCell(this._color);

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaintOnly();
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(1, 1));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    buffer.writeGrapheme(offset, 'x', style: CellStyle(foreground: _color));
  }
}

void main() {
  testWidgets('a hoisted const render-object widget repaints with the new '
      'theme', (tester) {
    // The SAME widget instance both times: only the dependency changes.
    const cell = _ThemedCell();
    Widget themed(Color primary) => Theme(
      data: ThemeData(colorScheme: ColorScheme(primary: primary)),
      child: cell,
    );

    tester.pumpWidget(themed(const AnsiColor(1)));
    expect(
      tester.render(size: const CellSize(1, 1)).atColRow(0, 0).style.foreground,
      const AnsiColor(1),
    );

    tester.pumpWidget(themed(const AnsiColor(4)));
    expect(
      tester.render(size: const CellSize(1, 1)).atColRow(0, 0).style.foreground,
      const AnsiColor(4),
      reason:
          'the theme changed under an unchanged widget; the render '
          'object must re-read it',
    );
  });
}
