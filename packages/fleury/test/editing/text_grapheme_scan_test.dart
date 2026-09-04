import 'dart:math';

import 'package:characters/characters.dart';
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A document shaped like the ones this defect actually hurts: an agent
/// transcript or a code buffer, plain text, 64-code-unit lines.
String document({required int lines}) => '${'x' * 63}\n' * lines;

/// 1 MiB.
final largeDocument = document(lines: 16384);

/// Wall-clock for [rounds] snaps at the midpoint of a [lines]-line document.
Duration snapCost({required int lines, int rounds = 300}) {
  final text = document(lines: lines);
  final offset = text.length ~/ 2 + 7; // mid-line, off any boundary tie
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    TextEditingModel.snapOffsetToGraphemeBoundary(text, offset);
  }
  return sw.elapsed;
}

void main() {
  group('grapheme boundary scan is local to the caret', () {
    test('the cost of a mid-document snap does not grow with the document', () {
      // The old implementation walked `text.characters` from offset 0, so a
      // snap 512 KiB into a document cost 16x one 32 KiB in. Local
      // resolution makes the two the same work; the ratio is asserted with a
      // wide margin so machine load cannot fail it (the old code's ratio is
      // ~16, the new one's ~1). Both loops are warmed by the first call.
      snapCost(lines: 64);
      final small = snapCost(lines: 512).inMicroseconds; // 32 KiB
      final large = snapCost(lines: 16384).inMicroseconds; // 1 MiB
      expect(
        large,
        lessThan(small * 6),
        reason: '1 MiB snap $large µs vs 32 KiB snap $small µs (x300)',
      );
    });

    test('a text starting with an unpaired low surrogate still resolves', () {
      // Fixed-width truncation through an emoji leaves a lone low surrogate
      // at index 0; the sanitizer keeps it. package:characters walks off the
      // front of such a string, so these used to throw a RangeError from
      // Home+Right, Backspace and insert.
      final cut = '\u{1F44D} nice work'.substring(1);
      expect((cut.codeUnitAt(0) & 0xFC00) == 0xDC00, isTrue);
      expect(TextEditingModel.nextGraphemeBoundary(cut, 0), 1);
      expect(TextEditingModel.previousGraphemeBoundary(cut, 1), 0);
      expect(TextEditingModel.previousGraphemeBoundary(cut, 2), 1);
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(cut, 1), 1);
      expect(TextEditingModel.snapOffsetToGraphemeBoundary(cut, 3), 3);
      expect(
        TextEditingModel.nextGraphemeBoundary(cut, cut.length),
        cut.length,
      );
      // The from-start fallback keeps CharacterRange.at's shape mid-cluster.
      final family = '${cut.substring(0, 1)}\u{1F468}\u200D\u{1F469}x';
      final start = 1;
      final end = family.length - 1;
      expect(
        TextEditingModel.previousGraphemeBoundary(family, start + 2),
        start,
      );
      expect(TextEditingModel.nextGraphemeBoundary(family, start + 2), end);
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(family, start + 1),
        start,
      );
    });
  });

  group('grapheme boundary correctness around the scan anchor', () {
    test('selecting a flag does not consume the following Indic letter', () {
      final controller = TextEditingController(text: '🇨🇦ष');
      addTearDown(controller.dispose);
      controller.caretOffset = 0;
      controller.moveCursorRight(extend: true);
      expect(controller.selectedText, '🇨🇦');
      controller.delete();
      expect(controller.text, 'ष');
    });

    test('local lookups agree with forward segmentation at every offset', () {
      final random = Random(40904);
      const units = [
        'a',
        'b',
        '\n',
        '\r',
        '\u0301',
        '\u200d',
        '\u0600',
        '🇨',
        '🇦',
        '🙂',
        'ष',
        'क्ष',
        '👩‍👩‍👧‍👦',
        '\uD800',
        '\uDC00',
      ];
      for (var sample = 0; sample < 2000; sample++) {
        final text = List.generate(
          1 + random.nextInt(12),
          (_) => units[random.nextInt(units.length)],
        ).join();
        final boundaries = <int>[0];
        for (final cluster in text.characters) {
          boundaries.add(boundaries.last + cluster.length);
        }
        for (var offset = 0; offset <= text.length; offset++) {
          final before = boundaries.where((b) => b < offset).lastOrNull ?? 0;
          final after =
              boundaries.where((b) => b > offset).firstOrNull ?? text.length;
          final lo = boundaries.lastWhere((b) => b <= offset);
          final hi = boundaries.firstWhere((b) => b >= offset);
          expect(
            [
              TextEditingModel.previousGraphemeBoundary(text, offset),
              TextEditingModel.nextGraphemeBoundary(text, offset),
              TextEditingModel.snapOffsetToGraphemeBoundary(text, offset),
            ],
            [before, after, offset - lo < hi - offset ? lo : hi],
            reason:
                'sample $sample, code units ${text.codeUnits}, offset $offset',
          );
        }
      }
    });

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
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, start + 1),
        start,
      );
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, start + 4),
        end,
      );
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
      expect(TextEditingModel.previousGraphemeBoundary(text, start + 2), start);
      expect(TextEditingModel.nextGraphemeBoundary(text, start + 1), start + 3);
    });

    test('offsets at and past the document end clamp to the end', () {
      const text = 'tail\u{1F642}';
      expect(
        TextEditingModel.snapOffsetToGraphemeBoundary(text, text.length),
        text.length,
      );
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
