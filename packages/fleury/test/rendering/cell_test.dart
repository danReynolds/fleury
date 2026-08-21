import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_internal.dart';
import 'package:test/test.dart';

void main() {
  group('Color', () {
    test('AnsiColor equality', () {
      expect(const AnsiColor(3), equals(const AnsiColor(3)));
      expect(const AnsiColor(3), isNot(equals(const AnsiColor(4))));
    });

    test('IndexedColor equality and rejection of out-of-range indices', () {
      expect(const IndexedColor(255), equals(const IndexedColor(255)));
      expect(() => IndexedColor(256), throwsA(isA<AssertionError>()));
    });

    test('RgbColor equality and component access', () {
      const c = RgbColor(255, 128, 64);
      expect(c, equals(const RgbColor(255, 128, 64)));
      expect(c.r, 255);
      expect(c.g, 128);
      expect(c.b, 64);
    });

    test('Color cross-type comparisons are unequal', () {
      expect(const AnsiColor(0), isNot(equals(const IndexedColor(0))));
    });
  });

  group('CellStyle', () {
    test('none is the no-op style', () {
      const none = CellStyle.none;
      expect(none.foreground, isNull);
      expect(none.background, isNull);
      expect(none.bold, isFalse);
    });

    test('copyWith overrides only the specified fields', () {
      const base = CellStyle(foreground: AnsiColor(1), bold: true);
      final updated = base.copyWith(bold: false);
      expect(updated.foreground, const AnsiColor(1));
      expect(updated.bold, isFalse);
    });

    test('merge: other set fields override; unset ones are inherited', () {
      const a = CellStyle(foreground: AnsiColor(1), bold: true);
      const b = CellStyle(foreground: AnsiColor(2), italic: true);
      final merged = a.merge(b);
      expect(merged.foreground, const AnsiColor(2));
      expect(merged.bold, isTrue, reason: 'inherited (b leaves bold unset)');
      expect(merged.italic, isTrue);
    });

    test('merge: an explicit false turns off an inherited attribute', () {
      const base = CellStyle(bold: true, underline: true);
      const override = CellStyle(bold: false); // explicitly off
      final merged = base.merge(override);
      expect(merged.bold, isFalse, reason: 'override cancels inherited bold');
      expect(merged.underline, isTrue, reason: 'untouched attr inherited');
    });

    test('unset and explicit-false are distinct values but read the same', () {
      const unset = CellStyle();
      const off = CellStyle(bold: false);
      expect(unset.bold, isFalse);
      expect(off.bold, isFalse);
      expect(unset == off, isFalse, reason: 'tri-state distinguishes them');
    });

    test('value equality', () {
      const a = CellStyle(bold: true, foreground: AnsiColor(1));
      const b = CellStyle(bold: true, foreground: AnsiColor(1));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('CellStyle.state', () {
    test('is const and behaves like its base outside state resolution', () {
      const style = CellStyle.state(
        base: CellStyle(foreground: AnsiColor(6), bold: true),
        focused: CellStyle(underline: true),
      );

      expect(style.foreground, const AnsiColor(6));
      expect(style.bold, isTrue);
      expect(style.underline, isFalse);
    });

    test('plain local styles change the base without erasing state cues', () {
      const defaults = CellStyle.state(
        focused: CellStyle(bold: true),
        invalid: CellStyle(underline: true),
      );

      final resolved = resolveCellStyle(
        cascade: const [
          defaults,
          CellStyle(foreground: AnsiColor(5)),
        ],
        states: const {CellStyleState.focused, CellStyleState.invalid},
      );

      expect(resolved.foreground, const AnsiColor(5));
      expect(resolved.bold, isTrue);
      expect(resolved.underline, isTrue);
    });

    test('the highest non-null patch wins for each state as one unit', () {
      const theme = CellStyle.state(
        focused: CellStyle(foreground: AnsiColor(4), bold: true),
      );
      const local = CellStyle.state(focused: CellStyle(underline: true));

      final resolved = resolveCellStyle(
        cascade: const [theme, local],
        states: const {CellStyleState.focused},
      );

      expect(resolved.foreground, isNull);
      expect(resolved.boldOrNull, isNull);
      expect(resolved.underline, isTrue);
    });

    test('null inherits while CellStyle.none suppresses a state cue', () {
      const theme = CellStyle.state(
        base: CellStyle(foreground: AnsiColor(2)),
        focused: CellStyle(inverse: true),
      );
      const inherit = CellStyle.state();
      const suppress = CellStyle.state(focused: CellStyle.none);

      final inherited = resolveCellStyle(
        cascade: const [theme, inherit],
        states: const {CellStyleState.focused},
      );
      final suppressed = resolveCellStyle(
        cascade: const [theme, suppress],
        states: const {CellStyleState.focused},
      );

      expect(inherited.foreground, const AnsiColor(2));
      expect(inherited.inverse, isTrue);
      expect(suppressed.foreground, const AnsiColor(2));
      expect(suppressed.inverseOrNull, isNull);
    });

    test('active states compose in deterministic paint order', () {
      const style = CellStyle.state(
        selected: CellStyle(background: AnsiColor(4)),
        hovered: CellStyle(dim: false),
        focused: CellStyle(bold: true),
        invalid: CellStyle(foreground: AnsiColor(1), underline: true),
      );

      final resolved = resolveCellStyle(
        cascade: const [style],
        states: const {
          CellStyleState.selected,
          CellStyleState.hovered,
          CellStyleState.focused,
          CellStyleState.invalid,
        },
      );

      expect(resolved.background, const AnsiColor(4));
      expect(resolved.dimOrNull, isFalse);
      expect(resolved.bold, isTrue);
      expect(resolved.foreground, const AnsiColor(1));
      expect(resolved.underline, isTrue);
    });

    test('disabled is exclusive of transient and value states', () {
      const style = CellStyle.state(
        selected: CellStyle(inverse: true),
        focused: CellStyle(bold: true),
        disabled: CellStyle(dim: true),
        invalid: CellStyle(underline: true),
      );

      final resolved = resolveCellStyle(
        cascade: const [style],
        states: const {
          CellStyleState.selected,
          CellStyleState.focused,
          CellStyleState.disabled,
          CellStyleState.invalid,
        },
      );

      expect(resolved.dim, isTrue);
      expect(resolved.inverseOrNull, isNull);
      expect(resolved.boldOrNull, isNull);
      expect(resolved.underlineOrNull, isNull);
    });

    test(
      'stateful styles have value equality and preserve states on merge',
      () {
        const a = CellStyle.state(
          base: CellStyle(foreground: AnsiColor(2)),
          focused: CellStyle(bold: true),
        );
        const b = CellStyle.state(
          base: CellStyle(foreground: AnsiColor(2)),
          focused: CellStyle(bold: true),
        );

        expect(a, b);
        expect(a.hashCode, b.hashCode);
        expect(
          a.merge(const CellStyle(background: AnsiColor(0))),
          const CellStyle.state(
            base: CellStyle(foreground: AnsiColor(2), background: AnsiColor(0)),
            focused: CellStyle(bold: true),
          ),
        );
      },
    );
  });

  group('CellStyle.linkUri (OSC 8 carrier)', () {
    test('defaults to null; empty and const singletons carry no link', () {
      expect(const CellStyle().linkUri, isNull);
      expect(CellStyle.none.linkUri, isNull);
    });

    test('== distinguishes styles that differ only by link', () {
      const a = CellStyle(foreground: AnsiColor(1), linkUri: 'https://a');
      const b = CellStyle(foreground: AnsiColor(1), linkUri: 'https://b');
      const c = CellStyle(foreground: AnsiColor(1));
      expect(a == b, isFalse, reason: 'different link targets are not equal');
      expect(a == c, isFalse, reason: 'link vs no-link are not equal');
      expect(
        a,
        equals(const CellStyle(foreground: AnsiColor(1), linkUri: 'https://a')),
        reason: 'same visual style + same link are equal',
      );
    });

    test('hashCode differs for link-differing styles', () {
      const a = CellStyle(linkUri: 'https://a');
      const b = CellStyle(linkUri: 'https://b');
      const none = CellStyle();
      expect(a.hashCode, isNot(b.hashCode));
      expect(a.hashCode, isNot(none.hashCode));
    });

    test('identical-instance fast-path short-circuits ==', () {
      // A run of linked cells shares one CellStyle instance; identical
      // instances must compare equal without reading fields.
      const shared = CellStyle(bold: true, linkUri: 'https://x');
      expect(identical(shared, shared), isTrue);
      // ignore: prefer_const_declarations
      final same = shared;
      expect(shared == same, isTrue);
    });

    test('merge takes the other link when set, else keeps this one', () {
      const base = CellStyle(linkUri: 'https://base');
      const overrideSet = CellStyle(bold: true, linkUri: 'https://override');
      const overrideUnset = CellStyle(bold: true);
      expect(base.merge(overrideSet).linkUri, 'https://override');
      expect(
        base.merge(overrideUnset).linkUri,
        'https://base',
        reason: 'other leaves link unset -> inherit this',
      );
      expect(const CellStyle().merge(overrideSet).linkUri, 'https://override');
    });

    test('copyWith preserves link when not overridden', () {
      const base = CellStyle(bold: true, linkUri: 'https://keep');
      expect(base.copyWith(bold: false).linkUri, 'https://keep');
      expect(base.copyWith(linkUri: 'https://new').linkUri, 'https://new');
    });

    test('link is non-visual: sameVisualStyleAs ignores it', () {
      const a = CellStyle(foreground: AnsiColor(2), linkUri: 'https://a');
      const b = CellStyle(foreground: AnsiColor(2), linkUri: 'https://b');
      const c = CellStyle(foreground: AnsiColor(2));
      const d = CellStyle(foreground: AnsiColor(3));
      expect(a.sameVisualStyleAs(b), isTrue, reason: 'only link differs');
      expect(a.sameVisualStyleAs(c), isTrue, reason: 'link vs none, same fg');
      expect(a.sameVisualStyleAs(d), isFalse, reason: 'foreground differs');
    });

    test('a link-only style is visually empty', () {
      expect(const CellStyle(linkUri: 'https://x').isVisuallyEmpty, isTrue);
      expect(CellStyle.none.isVisuallyEmpty, isTrue);
      expect(const CellStyle(bold: true).isVisuallyEmpty, isFalse);
      // isVisuallyEmpty matches `== empty` for link-free styles.
      expect(const CellStyle(bold: false).isVisuallyEmpty, isFalse);
    });

    test('toString surfaces the link', () {
      expect(
        const CellStyle(linkUri: 'https://x').toString(),
        contains('link=https://x'),
      );
      expect(CellStyle.none.toString(), isNot(contains('link=')));
    });
  });

  group('Cell', () {
    test('Cell.empty is a const singleton-shaped value', () {
      expect(const Cell.empty(), equals(const Cell.empty()));
      expect(const Cell.empty().role, CellRole.empty);
      expect(const Cell.empty().grapheme, isNull);
    });

    test('Cell.leading carries a grapheme', () {
      const c = Cell.leading(grapheme: 'A');
      expect(c.role, CellRole.leading);
      expect(c.grapheme, 'A');
    });

    test('Cell.continuation has null grapheme', () {
      const c = Cell.continuation();
      expect(c.role, CellRole.continuation);
      expect(c.grapheme, isNull);
    });

    test('Equal cells have equal hash codes', () {
      const a = Cell.leading(grapheme: 'X', style: CellStyle(bold: true));
      const b = Cell.leading(grapheme: 'X', style: CellStyle(bold: true));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
