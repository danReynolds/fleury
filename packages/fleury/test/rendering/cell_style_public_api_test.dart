import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

void main() {
  test('public CellStyle.resolve supports custom interactive controls', () {
    const defaults = CellStyle.interactive(
      focused: CellStyle(bold: true),
      invalid: CellStyle(underline: true),
    );
    const local = CellStyle(foreground: AnsiColor(6));

    final resolved = CellStyle.resolve(
      cascade: const [defaults, local],
      focused: true,
      invalid: true,
    );

    expect(resolved.foreground, const AnsiColor(6));
    expect(resolved.bold, isTrue);
    expect(resolved.underline, isTrue);
  });

  test('public CellStyle.resolve keeps disabled state exclusive', () {
    const style = CellStyle.interactive(
      selected: CellStyle(inverse: true),
      disabled: CellStyle(dim: true),
    );

    final resolved = CellStyle.resolve(
      cascade: const [style],
      selected: true,
      disabled: true,
    );

    expect(resolved.dim, isTrue);
    expect(resolved.inverseOrNull, isNull);
  });
}
