import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('RenderText intrinsics', () {
    test('max width is the unwrapped text width', () {
      final r = RenderText(text: 'hello, world');
      expect(r.computeMaxIntrinsicWidth(null), 'hello, world'.length);
      expect(r.computeMinIntrinsicWidth(null), 'hello, world'.length);
    });

    test('max height is one row when nothing forces a wrap', () {
      final r = RenderText(text: 'abc');
      expect(r.computeMaxIntrinsicHeight(null), 1);
      expect(r.computeMaxIntrinsicHeight(100), 1);
    });

    test('newlines produce more rows', () {
      final r = RenderText(text: 'a\nb\nc');
      expect(r.computeMaxIntrinsicHeight(null), 3);
    });

    test('a narrow width forces additional rows under softWrap', () {
      final r = RenderText(text: 'one two three four five');
      // No wrap at the natural width.
      expect(r.computeMaxIntrinsicHeight(null), 1);
      // A narrow width has to wrap onto multiple rows.
      expect(r.computeMaxIntrinsicHeight(6), greaterThan(1));
    });

    test('maxLines caps the height', () {
      final r = RenderText(
        text: 'one two three four five six seven',
        maxLines: 2,
      );
      expect(r.computeMaxIntrinsicHeight(6), 2);
    });

    test('empty text has no intrinsic size', () {
      final r = RenderText(text: '');
      expect(r.computeMaxIntrinsicWidth(null), 0);
      expect(r.computeMaxIntrinsicHeight(null), 0);
    });
  });

  group('Default render object intrinsics', () {
    test('zero for ROs that do not override (default)', () {
      // RenderSizedBox with no explicit size and no child returns 0 from the
      // SizedBox override (delegates to a null child).
      final r = RenderSizedBox();
      expect(r.computeMaxIntrinsicWidth(null), 0);
      expect(r.computeMaxIntrinsicHeight(null), 0);
    });
  });
}
