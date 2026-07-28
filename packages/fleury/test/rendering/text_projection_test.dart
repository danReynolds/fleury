// RFC 0019 §6.4 / §9 — the source-preserving projection's property gates.
//
// Gates pinned here: 1 (bounded atoms), 7 (projection coverage), 8 (boundary
// round-trip), 9 (idempotence), 10 (non-emoji safety), 15 (identity
// allocation). Gate 6 (split soundness) lives with the policy derivation.

import 'package:characters/characters.dart';
import 'package:fleury/src/rendering/text_projection.dart';
import 'package:fleury/src/rendering/width_policy.dart';
import 'package:fleury/src/rendering/width_resolver.dart';
import 'package:test/test.dart';

const _split = TextPresentationPolicy(lowering: ClusterLowering.split);
const _family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}'; // 👨‍👩‍👦

void main() {
  group('fast paths (gate 15: identity allocation)', () {
    test('preserve policy returns the same string object, no mappings', () {
      const text = 'hello $_family world';
      final projection = projectText(text, policy: TextPresentationPolicy.spec);
      expect(projection.isIdentity, isTrue);
      expect(identical(projection.displayText, text), isTrue);
      expect(projection.changedClusters, isEmpty);
    });

    test('no joiner in the text bypasses the parser entirely', () {
      const text = 'plain ascii and 🙂 emoji';
      final projection = projectText(text, policy: _split);
      expect(projection.isIdentity, isTrue);
      expect(identical(projection.displayText, text), isTrue);
    });

    test('joiners that parse as nothing still yield identity (gate 10)', () {
      // Arabic shaping joiner: byte-identical under every policy.
      const text = 'x \u{0644}\u{200D}\u{0627} y';
      final projection = projectText(text, policy: _split);
      expect(projection.isIdentity, isTrue);
      expect(identical(projection.displayText, text), isTrue);
    });
  });

  group('lowering', () {
    test('a family lowers to three atoms; neighbours are untouched', () {
      const text = 'a $_family b';
      final projection = projectText(text, policy: _split);
      expect(projection.isIdentity, isFalse);
      expect(
        projection.displayText,
        'a \u{1F468}\u{1F469}\u{1F466} b',
        reason: 'joiners dropped, components verbatim',
      );
      expect(projection.logicalText, text, reason: 'source is canonical');
      final cluster = projection.changedClusters.single;
      expect(cluster.displayAtomRanges, hasLength(3));
    });

    test('atoms tile the display range exactly, in order (gate 7)', () {
      final projection = projectText(
        'x$_family${'\u{1F469}\u{200D}\u{2695}\u{FE0F}'}y',
        policy: _split,
      );
      for (final cluster in projection.changedClusters) {
        var cursor = cluster.displayRange.start;
        for (final atom in cluster.displayAtomRanges) {
          expect(atom.start, cursor, reason: 'atoms must tile contiguously');
          expect(atom.end, greaterThan(atom.start), reason: 'non-empty atom');
          cursor = atom.end;
        }
        expect(cursor, cluster.displayRange.end);
      }
    });

    test('every atom is one cluster of ≤ 2 cells (gate 1)', () {
      final projection = projectText(
        '$_family \u{1F469}\u{1F3FD}\u{200D}\u{2695}\u{FE0F}',
        policy: _split,
      );
      const resolver = DefaultWidthResolver();
      for (final cluster in projection.changedClusters) {
        for (final atom in cluster.displayAtomRanges) {
          final text = projection.displayText.substring(atom.start, atom.end);
          expect(text.characters.length, 1, reason: 'one cluster per atom');
          expect(
            resolver.widthOfGrapheme(text, CellWidthPolicy.spec),
            lessThanOrEqualTo(2),
            reason: 'atom=$text',
          );
        }
      }
    });

    test('multiple sequences project independently and in order', () {
      final projection = projectText(
        '$_family and $_family',
        policy: _split,
      );
      expect(projection.changedClusters, hasLength(2));
      expect(
        projection.changedClusters[0].displayRange.end,
        lessThanOrEqualTo(projection.changedClusters[1].displayRange.start),
      );
    });
  });

  group('mapping properties', () {
    test('unchanged regions map by identity shift (gate 7)', () {
      const text = 'ab $_family cd';
      final projection = projectText(text, policy: _split);
      // 'a' 'b' ' ' before the cluster: identity.
      expect(projection.sourceToDisplay(0), 0);
      expect(projection.sourceToDisplay(3), 3);
      // After the cluster: shifted by the two dropped joiners.
      final delta = projection.displayText.length - text.length;
      expect(
        projection.sourceToDisplay(text.length),
        text.length + delta,
      );
      expect(
        projection.displayToSource(projection.displayText.length),
        text.length,
      );
    });

    test('boundary round-trip preserves grapheme boundaries (gate 8)', () {
      const text = 'ab $_family cd 🙂';
      final projection = projectText(text, policy: _split);
      var offset = 0;
      for (final cluster in text.characters) {
        final display = projection.sourceToDisplay(offset);
        expect(
          projection.displayToSource(display),
          offset,
          reason: 'boundary at $offset must survive the round trip',
        );
        offset += cluster.length;
      }
      expect(projection.sourceToDisplay(text.length), isNotNull);
    });

    test('inside a lowered cluster, affinity snaps to the boundaries', () {
      const text = _family;
      final projection = projectText(text, policy: _split);
      final cluster = projection.changedClusters.single;
      final inside = cluster.displayRange.start +
          (cluster.displayAtomRanges.first.end -
              cluster.displayAtomRanges.first.start);
      expect(
        projection.displayToSource(inside),
        cluster.sourceRange.start,
        reason: 'upstream affinity → before the logical cluster',
      );
      expect(
        projection.displayToSource(inside, downstream: true),
        cluster.sourceRange.end,
        reason: 'downstream affinity → after the logical cluster',
      );
      // No endpoint can rest inside the source cluster (decision 14).
      expect(
        projection.sourceToDisplay(cluster.sourceRange.start + 2),
        cluster.displayRange.start,
      );
    });

    test('clusterAtDisplay finds the group; misses return null', () {
      const text = 'a $_family';
      final projection = projectText(text, policy: _split);
      final cluster = projection.changedClusters.single;
      expect(
        projection.clusterAtDisplay(cluster.displayRange.start),
        same(cluster),
      );
      expect(projection.clusterAtDisplay(0), isNull);
      expect(projection.clusterAtDisplay(cluster.displayRange.end), isNull);
    });
  });

  group('idempotence (gate 9)', () {
    test('projecting an already-lowered display is identity', () {
      final first = projectText('x $_family y', policy: _split);
      final second = projectText(first.displayText, policy: _split);
      expect(second.isIdentity, isTrue);
      expect(identical(second.displayText, first.displayText), isTrue);
    });
  });
}
