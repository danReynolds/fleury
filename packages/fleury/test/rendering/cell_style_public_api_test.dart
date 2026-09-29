import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'pressed paint composes after focus, before invalid, and survives copying',
    () {
      const style = CellStyle.interactive(
        focused: CellStyle(inverse: false, underline: true),
        pressed: CellStyle(inverse: true, foreground: AnsiColor(2)),
        invalid: CellStyle(foreground: AnsiColor(1)),
        disabled: CellStyle(dim: true),
      );
      final copied = style
          .copyWith(bold: true)
          .merge(const CellStyle(background: AnsiColor(4)));
      final pressed = CellStyle.resolve(
        cascade: [copied],
        focused: true,
        pressed: true,
      );
      expect(pressed.inverse, isTrue);
      expect(pressed.underline, isTrue);
      expect(pressed.bold, isTrue);
      expect(pressed.background, const AnsiColor(4));
      expect(pressed.foreground, const AnsiColor(2));
      expect(
        CellStyle.resolve(
          cascade: [copied],
          pressed: true,
          invalid: true,
        ).foreground,
        const AnsiColor(1),
      );
      final disabled = CellStyle.resolve(
        cascade: [style],
        pressed: true,
        focused: true,
        disabled: true,
      );
      expect(disabled.dim, isTrue);
      expect(disabled.inverse, isFalse);
      expect(disabled.underline, isFalse);
      final overridden = style.merge(
        const CellStyle.interactive(pressed: CellStyle.none),
      );
      expect(
        CellStyle.resolve(cascade: [overridden], pressed: true).inverse,
        isFalse,
      );
      expect(style, isNot(overridden));
      const same = CellStyle.interactive(
        focused: CellStyle(inverse: false, underline: true),
        pressed: CellStyle(inverse: true, foreground: AnsiColor(2)),
        invalid: CellStyle(foreground: AnsiColor(1)),
        disabled: CellStyle(dim: true),
      );
      expect(
        copied,
        same
            .copyWith(bold: true)
            .merge(const CellStyle(background: AnsiColor(4))),
      );
      expect(style.hashCode, same.hashCode);
    },
  );

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
