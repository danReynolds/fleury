import 'package:fleury/fleury.dart';
// GraphemeScanDebugStats is debug instrumentation on the editing model,
// deliberately not exported by the production barrels; reached here like other
// internals.
import 'package:fleury/src/editing/text_editing.dart'
    show GraphemeScanDebugStats, GraphemeScanStats;
import 'package:test/test.dart';

/// A document shaped like the ones this defect actually hurts: an agent
/// transcript or a code buffer, plain text, 64-code-unit lines.
String document({required int lines}) => '${'x' * 63}\n' * lines;

/// 1 MiB.
final largeDocument = document(lines: 16384);

GraphemeScanStats measure(void Function() body) {
  GraphemeScanDebugStats.begin();
  body();
  return GraphemeScanDebugStats.take();
}

void main() {
  group('grapheme boundary scan width', () {
    test('a mid-document snap reads a bounded window, not the prefix', () {
      final offset = largeDocument.length ~/ 2;
      expect(offset, 524288, reason: 'the insert lands ~512 KiB in');

      final stats = measure(
        () =>
            TextEditingModel.snapOffsetToGraphemeBoundary(
              largeDocument,
              offset,
            ),
      );

      expect(stats.scanCount, 1);
      expect(
        stats.widestScan,
        lessThanOrEqualTo(64),
        reason:
            'snapping must read the text around the offset — the containing '
            'grapheme cluster, at worst the containing 64-code-unit line. A '
            'scan that starts at 0 reads the whole 512 KiB prefix, so every '
            'mid-document keystroke re-walks the document above the caret.',
      );
    });

    test('the snap window does not grow with the document', () {
      int widestAtMidpoint(int lines) {
        final text = document(lines: lines);
        return measure(
          () => TextEditingModel.snapOffsetToGraphemeBoundary(
            text,
            text.length ~/ 2,
          ),
        ).widestScan;
      }

      // 4 KiB against 1 MiB — a 256x document is the same amount of scanning.
      expect(widestAtMidpoint(16384), widestAtMidpoint(64));
    });

    test('a mid-document insert costs a bounded number of scanned units', () {
      final offset = largeDocument.length ~/ 2;
      final value = TextEditingValue(
        text: largeDocument,
        selection: TextSelection.collapsed(offset: offset),
      );

      final stats = measure(() => TextEditingModel.insert(value, 'z'));

      // insert -> replaceSelection -> replaceRange snaps both range edges, then
      // the resulting TextEditingValue snaps both selection edges.
      expect(stats.scanCount, greaterThanOrEqualTo(1));
      expect(
        stats.codeUnitsScanned,
        lessThanOrEqualTo(64 * stats.scanCount),
        reason:
            'one keystroke in the middle of a 1 MiB TextArea used to scan '
            '~512 KiB per snap, several times over, for a single character',
      );
    });

    test('caret movement and deletion read a bounded window too', () {
      final offset = largeDocument.length ~/ 2;
      final value = TextEditingValue(
        text: largeDocument,
        selection: TextSelection.collapsed(offset: offset),
      );

      for (final (name, op) in <(String, TextEditingValue Function())>[
        ('moveLeft', () => TextEditingModel.moveLeft(value)),
        ('moveRight', () => TextEditingModel.moveRight(value)),
        ('backspace', () => TextEditingModel.backspace(value)),
        ('delete', () => TextEditingModel.delete(value)),
      ]) {
        final stats = measure(op);
        expect(
          stats.widestScan,
          lessThanOrEqualTo(64),
          reason: '$name walked ${stats.widestScan} code units',
        );
      }
    });

    test('the collector is closed by default and records nothing', () {
      TextEditingModel.snapOffsetToGraphemeBoundary(largeDocument, 100);
      final stats = GraphemeScanDebugStats.take();
      expect(stats.scanCount, GraphemeScanStats.empty.scanCount);
      expect(stats.codeUnitsScanned, GraphemeScanStats.empty.codeUnitsScanned);
    });
  });

  group('grapheme boundary correctness around the scan anchor', () {
    // A line start is the anchor a line-scoped scan would begin from, and the
    // document end is the append short-circuit that hid this defect. Both must
    // land exactly where a from-zero walk did.
    test('an offset at a line start is already a boundary', () {
      const text = 'alpha\nbravo\ncharlie';
      for (final offset in [0, 6, 12]) {
        expect(
          TextEditingModel.snapOffsetToGraphemeBoundary(text, offset),
          offset,
        );
      }
      // The newline itself is a boundary on both sides.
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, 5), 5);
      expect(TextEditingModel.previousGraphemeBoundary(text, 6), 5);
      expect(TextEditingModel.nextGraphemeBoundary(text, 5), 6);
    });

    test('an offset inside an emoji ZWJ sequence snaps out of it', () {
      // A 3-person family: 8 code units, one grapheme cluster, on line 2.
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      final text = 'one\ntwo${family}tail\nthree';
      final start = text.indexOf(family);
      final end = start + family.length;
      expect(end - start, 8);

      // Every interior offset resolves to one of the cluster's two edges.
      for (var offset = start + 1; offset < end; offset++) {
        final snapped = TextEditingModel.snapOffsetToGraphemeBoundary(
          text,
          offset,
        );
        expect(
          snapped,
          anyOf(start, end),
          reason: 'offset $offset landed inside the cluster',
        );
        expect(TextEditingModel.previousGraphemeBoundary(text, offset), start);
        expect(TextEditingModel.nextGraphemeBoundary(text, offset), end);
      }
      // Nearest edge wins; a tie rounds forward.
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, start + 1),
          start);
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, start + 4), end);
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, end - 1), end);
    });

    test('an offset inside a combining sequence snaps out of it', () {
      // Base + two combining marks: three code units, one cluster.
      const text = 'first\ná̂z\nlast';
      final start = text.indexOf('á̂');
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, start), start);
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, start + 1),
        start,
      );
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, start + 2),
        start + 3,
      );
      expect(
        TextEditingModel.previousGraphemeBoundary(text, start + 2),
        start,
      );
      expect(TextEditingModel.nextGraphemeBoundary(text, start + 1), start + 3);
    });

    test('offsets at and past the document end clamp to the end', () {
      const text = 'tail\u{1F642}';
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, text.length),
          text.length);
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, text.length + 9),
        text.length,
      );
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(text, -3), 0);
      expect(
        TextEditingModel.nextGraphemeBoundary(text, text.length),
        text.length,
      );
      expect(TextEditingModel.previousGraphemeBoundary(text, text.length), 4);
      // The last cluster is a surrogate pair: its interior offset still snaps.
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, text.length - 1),
        text.length,
      );
    });

    test('an empty document has one boundary', () {
      expect(TextEditingModel.snapOffsetToGraphemeBoundary('', 0), 0);
      expect(TextEditingModel.snapOffsetToGraphemeBoundary('', 5), 0);
      expect(TextEditingModel.previousGraphemeBoundary('', 0), 0);
      expect(TextEditingModel.nextGraphemeBoundary('', 0), 0);
    });
  });
}
