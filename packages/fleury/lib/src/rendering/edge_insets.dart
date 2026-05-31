import 'package:meta/meta.dart';

/// Insets in terminal cells on each side of a rectangle.
///
/// Used by `Padding` to inset its child within the available space. All
/// fields are integers because terminal layout is integer-cell based.
@immutable
final class EdgeInsets {
  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  }) : assert(left >= 0, 'left must be non-negative'),
       assert(top >= 0, 'top must be non-negative'),
       assert(right >= 0, 'right must be non-negative'),
       assert(bottom >= 0, 'bottom must be non-negative');

  const EdgeInsets.all(int value)
    : left = value,
      top = value,
      right = value,
      bottom = value,
      assert(value >= 0, 'value must be non-negative');

  const EdgeInsets.symmetric({int horizontal = 0, int vertical = 0})
    : left = horizontal,
      right = horizontal,
      top = vertical,
      bottom = vertical,
      assert(horizontal >= 0, 'horizontal must be non-negative'),
      assert(vertical >= 0, 'vertical must be non-negative');

  static const EdgeInsets zero = EdgeInsets.only();

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get horizontal => left + right;
  int get vertical => top + bottom;

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'EdgeInsets(l=$left, t=$top, r=$right, b=$bottom)';
}
