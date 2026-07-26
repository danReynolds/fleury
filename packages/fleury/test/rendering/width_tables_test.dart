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

import 'package:fleury/fleury.dart';
import 'package:fleury/src/rendering/width_tables.dart';
import 'package:test/test.dart';

void main() {
  test('committed width tables are in sync with the generator', () async {
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
  }, timeout: const Timeout(Duration(seconds: 60)));

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
          reason: '$name: range at $i touches or overlaps the previous one — '
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

  test('curated deviations from the raw UCD survive regeneration', () {
    // These three are deliberate and load-bearing; a regeneration that dropped
    // them would silently change rendering. Each is documented in the
    // generator's `_curate`.
    const resolver = DefaultWidthResolver();
    const standard = TerminalProfile.standard;
    const cjk = TerminalProfile.cjk;

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
