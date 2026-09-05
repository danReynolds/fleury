// Freshness gate for the generated character-width tables.
//
// width_tables.dart is derived from the Unicode Character Database by
// tool/ucd_width_tables.dart. This test fails if the committed file was
// hand-edited, or if the generator changed without a regeneration:
//
//     dart run tool/fleury_dev.dart build-width-tables
//
// It delegates to that tool's `--check` mode, which recomputes the fingerprint
// from the committed tables plus the generator's own source. That is
// deliberately OFFLINE — regenerating needs the network, verifying must not,
// so this runs in CI like any other test.
//
// What it cannot catch: a new Unicode release upstream. Nothing local can, and
// bumping the pinned version is a judgement call rather than a chore — every
// release since 8.0 widened codepoints, and deployed terminals span roughly
// Unicode 12.1 to 17.0 at once, so "newest" is not automatically "most
// compatible". See tool/ucd_width_tables.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/width_tables.dart';
import 'package:test/test.dart';

void main() {
  test(
    'committed width tables are in sync with the generator',
    () async {
      // test/rendering/ -> packages/fleury -> packages -> repo root
      final repoRoot = Directory.current.parent.parent.path;
      final result = await Process.run('dart', [
        'run',
        'tool/fleury_dev.dart',
        'build-width-tables',
        '--check',
      ], workingDirectory: repoRoot);
      expect(
        result.exitCode,
        0,
        reason:
            'width tables are stale or hand-edited — run '
            '`dart run tool/fleury_dev.dart build-width-tables`.\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('tables are well-formed: sorted, coalesced, non-overlapping', () {
    // Guards the binary search's precondition. A generator bug that emitted
    // unsorted or touching ranges would silently make lookups miss.
    const tables = <String, List<int>>{
      'zeroWidthRanges': zeroWidthRanges,
      'wideRanges': wideRanges,
      'ambiguousRanges': ambiguousRanges,
      'emojiPresentationRanges': emojiPresentationRanges,
    };
    tables.forEach((name, ranges) {
      expect(ranges.length.isEven, isTrue, reason: '$name: unpaired bound');
      expect(ranges, isNotEmpty, reason: '$name: empty');
      var previousEnd = -2;
      for (var i = 0; i < ranges.length; i += 2) {
        final start = ranges[i];
        final end = ranges[i + 1];
        expect(start, lessThanOrEqualTo(end), reason: '$name: inverted at $i');
        expect(
          start,
          greaterThan(previousEnd + 1),
          reason:
              '$name: range at $i touches or overlaps the previous one — '
              'it should have been coalesced',
        );
        expect(end, lessThan(0x110000), reason: '$name: out of range at $i');
        previousEnd = end;
      }
    });
  });

  test('the pinned Unicode version is recorded', () {
    expect(widthTablesUnicodeVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(widthTablesFingerprint, isNotEmpty);
  });

  test(
    'combined lookup preserves every scalar under every width-axis pairing',
    () {
      // Derive the old resolver's answer directly from its original property
      // tables, independently of the generator's combined partition.
      final expected = Uint8List(0x110000);
      void assign(List<int> ranges, int cls) {
        for (var i = 0; i < ranges.length; i += 2) {
          for (var code = ranges[i]; code <= ranges[i + 1]; code++) {
            expected[code] = cls;
          }
        }
      }

      assign(ambiguousRanges, 3);
      assign(wideRanges, 2);
      assign(emojiPresentationRanges, 4);
      assign(zeroWidthRanges, 1);

      final actual = Uint8List(expected.length);
      expect(scalarWidthRanges.length % 3, 0);
      var previousEnd = -1;
      var previousClass = -1;
      for (var i = 0; i < scalarWidthRanges.length; i += 3) {
        final start = scalarWidthRanges[i];
        final end = scalarWidthRanges[i + 1];
        final cls = scalarWidthRanges[i + 2];
        expect(start, greaterThan(previousEnd));
        expect(end, greaterThanOrEqualTo(start));
        expect(end, lessThan(expected.length));
        expect(cls, inInclusiveRange(1, 4));
        expect(start == previousEnd + 1 && cls == previousClass, isFalse);
        actual.fillRange(start, end + 1, cls);
        previousEnd = end;
        previousClass = cls;
      }
      const resolver = DefaultWidthResolver();
      final policies = [
        for (final ambiguous in CellWidth.values)
          for (final emoji in CellWidth.values)
            CellWidthPolicy(ambiguous: ambiguous, emojiPresentation: emoji),
      ];
      for (var code = 0; code < expected.length; code++) {
        final cls = expected[code];
        if (actual[code] != cls) {
          fail('classification mismatch at U+${code.toRadixString(16)}');
        }
        final grapheme = String.fromCharCode(code);
        for (final policy in policies) {
          final width = switch (cls) {
            1 => 0,
            2 => 2,
            3 => policy.ambiguous == CellWidth.two ? 2 : 1,
            4 => policy.emojiPresentation == CellWidth.two ? 2 : 1,
            _ => 1,
          };
          final measured = resolver.widthOfGrapheme(grapheme, policy);
          if (measured != width) {
            fail(
              'width mismatch at U+${code.toRadixString(16)} under $policy: '
              '$measured instead of $width',
            );
          }
        }
      }
    },
  );

  test('curated deviations from the raw UCD survive regeneration', () {
    // These three are deliberate and load-bearing; a regeneration that dropped
    // them would silently change rendering. Each is documented in the
    // generator's `_curate`.
    const resolver = DefaultWidthResolver();
    const standard = CellWidthPolicy.spec;
    const cjk = CellWidthPolicy.cjk;

    // Soft hyphen prints as a visible hyphen, despite being category Cf.
    expect(resolver.widthOfGrapheme('\u{00AD}', standard), 1);

    // Private Use Area must not be Ambiguous: Nerd Fonts and Powerline depend
    // on a one-cell advance, so a CJK profile must not double them.
    expect(resolver.widthOfGrapheme('\u{E000}', cjk), 1);
    expect(resolver.widthOfGrapheme('\u{F8FF}', cjk), 1);

    // Width is capped at 2 — the ecosystem's convergent behaviour.
    for (final g in ['\u{17D8}', '\u{1F468}\u{200D}\u{1F469}', '中', '🙂']) {
      expect(
        resolver.widthOfGrapheme(g, standard),
        lessThanOrEqualTo(2),
        reason: 'g=$g',
      );
    }
  });
}
