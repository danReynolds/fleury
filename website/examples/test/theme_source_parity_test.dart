// The theming guide shows a hand-written theme's source beside its live
// render. Those are two artifacts — a `const ThemeData` and a string — so
// nothing stops them drifting apart, and the failure is silent and dishonest:
// the page keeps rendering a picture while displaying code that no longer
// produced it.
//
// This asserts every colour in the displayed source is a colour the real theme
// actually has, and vice versa.

import 'package:fleury/fleury_core.dart';
import 'package:fleury_doc_examples/registry.dart';
import 'package:test/test.dart';

/// Every `RgbColor(0xNN, 0xNN, 0xNN)` in [source], as comparable colours.
Set<int> _colorsInSource(String source) {
  final re = RegExp(
    r'RgbColor\(\s*0x([0-9A-Fa-f]{2})\s*,\s*0x([0-9A-Fa-f]{2})\s*,\s*0x([0-9A-Fa-f]{2})\s*\)',
  );
  return {
    for (final m in re.allMatches(source))
      (int.parse(m.group(1)!, radix: 16) << 16) |
          (int.parse(m.group(2)!, radix: 16) << 8) |
          int.parse(m.group(3)!, radix: 16),
  };
}

int _packed(Color? c) {
  final rgb = c!.toRgb();
  return (rgb.r << 16) | (rgb.g << 8) | rgb.b;
}

void main() {
  group('the guide shows the theme it renders', () {
    test('every colour in the source is in the theme, and vice versa', () {
      final scheme = customThemeForTest.colorScheme;
      final inTheme = <int>{
        _packed(scheme.background),
        _packed(scheme.foreground),
        _packed(scheme.surface),
        _packed(scheme.primary),
        _packed(scheme.focus),
        _packed(scheme.success),
        _packed(scheme.warning),
        _packed(scheme.error),
        _packed(scheme.info),
      };
      final inSource = _colorsInSource(customThemeSourceForTest);

      String hex(int v) => '#${v.toRadixString(16).padLeft(6, '0')}';
      expect(
        inSource.difference(inTheme).map(hex),
        isEmpty,
        reason: 'the displayed source has colours the theme does not',
      );
      expect(
        inTheme.difference(inSource).map(hex),
        isEmpty,
        reason: 'the theme has colours the displayed source does not',
      );
    });

    test('the source names the styles the theme actually sets', () {
      final src = customThemeSourceForTest;
      expect(src, contains('brightness: Brightness.dark'));
      expect(customThemeForTest.brightness, Brightness.dark);

      // Each style field the theme customises must be visible in the source —
      // they are the point of the section that shows it.
      expect(src, contains('mutedStyle'));
      expect(src, contains('selectionStyle'));
      expect(src, contains('focusedStyle'));
      expect(src, contains('controlStyle'));
      expect(src, contains('borderStyle'));
      expect(customThemeForTest.borderStyle, BorderStyle.rounded);
      expect(customThemeForTest.mutedStyle.dim, isTrue);
      expect(customThemeForTest.selectionStyle.inverse, isTrue);
      expect(customThemeForTest.focusedStyle.bold, isTrue);
      expect(
        customThemeForTest.controlStyle?.styleFor(ControlState.focused)?.bold,
        isTrue,
      );
      expect(
        customThemeForTest.controlStyle
            ?.styleFor(ControlState.invalid)
            ?.underline,
        isTrue,
      );
    });

    test('the theme sets every opaque role a preview needs', () {
      // background/foreground/surface nullable-by-default: a demo theme that
      // left them unset would render against the page, not itself.
      final scheme = customThemeForTest.colorScheme;
      expect(scheme.background, isNotNull);
      expect(scheme.foreground, isNotNull);
      expect(scheme.surface, isNotNull);
    });
  });
}
