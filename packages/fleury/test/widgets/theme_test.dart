import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('x');
  }
}

void main() {
  group('Theme.of', () {
    testWidgets('falls back to ThemeData.fallback with no ancestor', (tester) {
      late ThemeData seen;
      tester.pumpWidget(_Capture((c) => seen = Theme.of(c)));
      expect(seen, ThemeData.fallback);
    });

    testWidgets('returns the nearest provided ThemeData', (tester) {
      late ThemeData seen;
      const data = ThemeData(selectionStyle: CellStyle(bold: true));
      tester.pumpWidget(
        Theme(data: data, child: _Capture((c) => seen = Theme.of(c))),
      );
      expect(seen.selectionStyle, const CellStyle(bold: true));
    });

    testWidgets('maybeOf is null without an ancestor', (tester) {
      ThemeData? seen = ThemeData.fallback;
      tester.pumpWidget(_Capture((c) => seen = Theme.maybeOf(c)));
      expect(seen, isNull);
    });
  });

  group('DefaultTextStyle cascade', () {
    testWidgets('a Text inherits the ambient default style', (tester) {
      tester.pumpWidget(
        const DefaultTextStyle(
          style: CellStyle(foreground: AnsiColor(1)),
          child: Text('hi'),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 1));
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(1));
    });

    testWidgets("the Text's own style overrides, attributes merge", (tester) {
      tester.pumpWidget(
        const DefaultTextStyle(
          style: CellStyle(foreground: AnsiColor(1), bold: true),
          child: Text('hi', style: CellStyle(foreground: AnsiColor(2))),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 1));
      final s = buf.atColRow(0, 0).style;
      expect(s.foreground, const AnsiColor(2), reason: 'color overridden');
      expect(s.bold, isTrue, reason: 'bold inherited via merge');
    });

    testWidgets('no DefaultTextStyle leaves Text unstyled', (tester) {
      tester.pumpWidget(const Text('hi'));
      final buf = tester.render(size: const CellSize(4, 1));
      expect(buf.atColRow(0, 0).style, CellStyle.empty);
    });

    testWidgets('Theme cascades its textStyle to descendant Text', (tester) {
      tester.pumpWidget(
        const Theme(
          data: ThemeData(textStyle: CellStyle(foreground: AnsiColor(5))),
          child: Text('hi'),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 1));
      expect(buf.atColRow(0, 0).style.foreground, const AnsiColor(5));
    });

    testWidgets('DefaultTextStyle.merge layers without dropping the outer', (
      tester,
    ) {
      tester.pumpWidget(
        DefaultTextStyle(
          style: const CellStyle(bold: true),
          child: DefaultTextStyle.merge(
            style: const CellStyle(foreground: AnsiColor(2)),
            child: const Text('hi'),
          ),
        ),
      );
      final buf = tester.render(size: const CellSize(4, 1));
      final s = buf.atColRow(0, 0).style;
      expect(s.bold, isTrue, reason: 'outer bold survives the inner merge');
      expect(s.foreground, const AnsiColor(2), reason: 'inner color applied');
    });
  });

  group('color derivation', () {
    test('lighten/darken move predictably and preserve the type', () {
      const c = RgbColor(100, 100, 100);
      expect(c.lighten(0.5), const RgbColor(178, 178, 178));
      expect(c.darken(0.5), const RgbColor(50, 50, 50));
    });

    test('toRgb resolves palette colors', () {
      expect(const AnsiColor(9).toRgb(), const RgbColor(255, 0, 0));
      expect(const IndexedColor(231).toRgb(), const RgbColor(255, 255, 255));
      expect(const IndexedColor(16).toRgb(), const RgbColor(0, 0, 0));
    });
  });

  group('extensions', () {
    test('an extension is retrieved by type; first assignable wins', () {
      const ext = _Brand(RgbColor(1, 2, 3));
      final theme = ThemeData(extensions: const [ext]);
      expect(theme.extension<_Brand>(), same(ext));
      expect(theme.extension<_Other>(), isNull);
    });

    testWidgets('extensions reach widgets via Theme.of', (tester) {
      late _Brand? brand;
      tester.pumpWidget(
        Theme(
          data: ThemeData(extensions: const [_Brand(RgbColor(9, 9, 9))]),
          child: _Capture((c) => brand = Theme.of(c).extension<_Brand>()),
        ),
      );
      expect(brand?.accent, const RgbColor(9, 9, 9));
    });

    test('extensions participate in equality (drive rebuilds)', () {
      expect(
        ThemeData(extensions: const [_Brand(RgbColor(1, 1, 1))]),
        ThemeData(extensions: const [_Brand(RgbColor(1, 1, 1))]),
      );
      expect(
        ThemeData(extensions: const [_Brand(RgbColor(1, 1, 1))]),
        isNot(ThemeData(extensions: const [_Brand(RgbColor(2, 2, 2))])),
      );
    });
  });

  group('presets', () {
    test('dark/light carry the matching brightness and a seeded primary', () {
      expect(ThemeData.dark().brightness, Brightness.dark);
      expect(ThemeData.light().brightness, Brightness.light);
      // fromSeed preserves the seed verbatim as primary (no remap).
      expect(
        ColorScheme.fromSeed(const RgbColor(10, 20, 30)).primary,
        const RgbColor(10, 20, 30),
      );
    });
  });

  group('F9: focus role + degradation convention', () {
    test('scheme exposes a themeable focus role, distinct and copyable', () {
      expect(ColorScheme.standard.focus, Colors.brightCyan);
      final custom = ColorScheme.standard.copyWith(focus: Colors.azure);
      expect(custom.focus, Colors.azure);
      expect(custom == ColorScheme.standard, isFalse);
      // Only focus changed — the rest of the role set is untouched.
      expect(custom.primary, ColorScheme.standard.primary);
    });

    test('the focus color drops under NO_COLOR but downsamples on 16-color, so '
        'the paved path pairs it with the bold focusedStyle attribute', () {
      final focus = ColorScheme.standard.focus;
      // A color role alone is gone under NO_COLOR...
      expect(quantizeColor(focus, ColorMode.none), isNull);
      // ...but present (quantized) on a 16-color terminal.
      expect(quantizeColor(focus, ColorMode.ansi16), isNotNull);
      // The attribute half (bold) is what remains when color is stripped, so a
      // `colors.focus` + `focusedStyle` cue never fully vanishes under NO_COLOR.
      expect(ThemeData.fallback.focusedStyle.bold, isTrue);
      expect(ThemeData.fallback.mutedStyle.dim, isTrue);
    });
  });
}

class _Brand {
  const _Brand(this.accent);
  final RgbColor accent;
  @override
  bool operator ==(Object other) => other is _Brand && other.accent == accent;
  @override
  int get hashCode => accent.hashCode;
}

class _Other {
  const _Other();
}
