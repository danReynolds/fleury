import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

class _Caret implements CaretHost {
  @override
  CellRect? localCaretRect = CellRect.fromLTWH(2, 1, 1, 1);
  RenderGeometry? geometry = RenderGeometry(
    bounds: CellRect.fromLTWH(10, 20, 8, 4),
  );
  @override
  RenderGeometry? screenGeometry() => geometry;
}

void main() {
  test(
    'public custom caret host derives placement, clipping and ownership',
    () {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final first = _Caret(), second = _Caret();
      focus.attachCaretHost(first);
      expect(focus.caretRect, CellRect.fromLTWH(12, 21, 1, 1));
      first.geometry = RenderGeometry(bounds: CellRect.fromLTWH(30, 40, 8, 4));
      expect(focus.caretRect, CellRect.fromLTWH(32, 41, 1, 1));
      first.geometry = RenderGeometry(
        bounds: CellRect.fromLTWH(30, 40, 8, 4),
        clip: CellRect.fromLTWH(30, 42, 8, 2),
      );
      expect(focus.caretRect, isNull);
      focus.attachCaretHost(second);
      focus.detachCaretHost(first);
      expect(focus.caretRect, CellRect.fromLTWH(12, 21, 1, 1));
      second.localCaretRect = null;
      expect(focus.caretRect, isNull);
      second.localCaretRect = CellRect.fromLTWH(2, 1, 1, 1);
      focus.detachCaretHost(second);
      expect(focus.caretRect, isNull);
    },
  );
}
