import 'package:fleury/fleury.dart';
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
    test('empty is the no-op style', () {
      const empty = CellStyle.empty;
      expect(empty.foreground, isNull);
      expect(empty.background, isNull);
      expect(empty.bold, isFalse);
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
