// The theming guide shows a hand-written theme's source beside its live
// render. Those are two artifacts — a `const ThemeData` and a string — so
// nothing stops them drifting apart, and the failure is silent and dishonest:
// the page keeps rendering a picture while displaying code that no longer
// produced it.
//
// This asserts every named role in the displayed source and guide matches the
// live theme, so swapping two colors cannot pass by preserving the same set.

import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_internal.dart';
import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

int _packed(Color? c) {
  final rgb = c!.toRgb();
  return (rgb.r << 16) | (rgb.g << 8) | rgb.b;
}

String get _guide =>
    File('../src/content/docs/guides/theming.mdx').readAsStringSync();

void main() {
  group('the guide shows the theme it renders', () {
    test('every named color role matches the rendered theme', () {
      final scheme = customThemeForTest.colorScheme;
      final roles = <String, (Color?, String)>{
        'background': (scheme.background, '0x1C, 0x18, 0x14'),
        'foreground': (scheme.foreground, '0xEB, 0xDB, 0xB2'),
        'surface': (scheme.surface, '0x2A, 0x24, 0x1E'),
        'primary': (scheme.primary, '0xE8, 0xA3, 0x3D'),
        'focus': (scheme.focus, '0xF2, 0xC5, 0x5C'),
        'success': (scheme.success, '0x8E, 0xC0, 0x7C'),
        'warning': (scheme.warning, '0xE8, 0xA3, 0x3D'),
        'error': (scheme.error, '0xE5, 0x6B, 0x5B'),
        'info': (scheme.info, '0x83, 0xA5, 0x98'),
      };
      for (final MapEntry(key: role, value: (color, literal))
          in roles.entries) {
        expect(
          customThemeSourceForTest,
          contains('$role: RgbColor($literal)'),
          reason: 'displayed source must name the $role value',
        );
        expect(
          _guide,
          contains('$role: RgbColor($literal)'),
          reason: 'guide source must name the live $role value',
        );
        final bytes = literal
            .split(', ')
            .map((part) => int.parse(part.substring(2), radix: 16))
            .toList();
        final expected = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
        expect(
          _packed(color),
          expected,
          reason: 'live $role must match source',
        );
      }
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
      expect(src, contains('borderStyle'));
      expect(customThemeForTest.borderStyle, BorderStyle.rounded);
      expect(customThemeForTest.mutedStyle.dim, isTrue);
      expect(customThemeForTest.selectionStyle.inverse, isTrue);
      expect(customThemeForTest.focusedStyle.bold, isTrue);
      expect(customThemeForTest.interactiveStyle, isNull);
      expect(
        _guide,
        contains('FleuryApp(theme: amber, home: const Dashboard());'),
      );
      expect(
        customThemeSourceForTest,
        contains('FleuryApp(theme: amber, home: const Dashboard());'),
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

  testWidgets('interaction-state source and live demo cover the same setup', (
    tester,
  ) {
    final example = exampleList.singleWhere(
      (example) => example.id == 'themes.interactive_styles',
    );
    final source = example.code!;
    const stateLines = [
      'focused: CellStyle(inverse: true, bold: true)',
      'hovered: CellStyle(underline: true)',
      'selected: CellStyle(foreground: Colors.green, bold: true)',
      'invalid: CellStyle(foreground: Colors.red, underline: true)',
      'disabled: CellStyle(dim: true)',
    ];
    for (final line in stateLines) {
      expect(source, contains(line), reason: 'registry source omitted $line');
      expect(_guide, contains(line), reason: 'guide source omitted $line');
    }
    expect(source, interactiveStyleSourceForTest);
    expect(
      source,
      contains('FleuryApp(theme: theme, home: const DeploymentForm());'),
    );
    expect(
      _guide,
      contains('FleuryApp(theme: theme, home: const DeploymentForm());'),
    );

    final focused = resolveCellStyle(
      cascade: [interactiveStyleForTest],
      states: const {CellStyleState.focused},
    );
    final hovered = resolveCellStyle(
      cascade: [interactiveStyleForTest],
      states: const {CellStyleState.hovered},
    );
    final selected = resolveCellStyle(
      cascade: [interactiveStyleForTest],
      states: const {CellStyleState.selected},
    );
    final invalid = resolveCellStyle(
      cascade: [interactiveStyleForTest],
      states: const {CellStyleState.invalid},
    );
    final disabled = resolveCellStyle(
      cascade: [interactiveStyleForTest],
      states: const {CellStyleState.disabled},
    );
    expect(focused.inverse, isTrue);
    expect(focused.bold, isTrue);
    expect(hovered.underline, isTrue);
    expect(selected.foreground, Colors.green);
    expect(selected.bold, isTrue);
    expect(invalid.foreground, Colors.red);
    expect(invalid.underline, isTrue);
    expect(disabled.dim, isTrue);

    tester.pumpWidget(example.builder());
    final output = tester.renderToString(
      size: CellSize(example.cols, example.rows),
      emptyMark: ' ',
    );
    expect(output, contains('INTERACTION STYLES'));
    expect(output, contains('base'));
    expect(output, contains('focused'));
    expect(output, contains('hovered'));
    expect(output, contains('selected'));
    expect(output, contains('invalid'));
    expect(output, contains('disabled'));
  });

  testWidgets('visual style examples render the code paths the guide shows', (
    tester,
  ) async {
    for (final (id, expected) in <(String, List<String>)>[
      ('themes.local_style', ['api-gateway']),
      ('themes.cell_style', ['Default text', 'Styled text']),
      (
        'themes.local_interactive',
        ['LOCAL INTERACTION STYLE', 'Theme focus', 'Local focus'],
      ),
      ('themes.invalid_none', ['NEUTRAL INVALID CHROME', 'Submit']),
    ]) {
      final example = exampleList.singleWhere((example) => example.id == id);
      expect(example.code, isNotNull, reason: '$id must show its source');
      tester.pumpWidget(example.builder());
      final output = tester.renderToString(
        size: CellSize(example.cols, example.rows),
        emptyMark: ' ',
      );
      for (final text in expected) {
        expect(output, contains(text), reason: '$id omitted $text');
      }
    }

    final invalid = exampleList.singleWhere(
      (example) => example.id == 'themes.invalid_none',
    );
    tester.pumpWidget(invalid.builder());
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Submit',
    );
    tester.pump();
    final output = tester.renderToString(
      size: CellSize(invalid.cols, invalid.rows),
      emptyMark: ' ',
    );
    expect(output, contains('Enter a query.'));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Query')
          .validationError,
      'Enter a query.',
    );
  });
}
