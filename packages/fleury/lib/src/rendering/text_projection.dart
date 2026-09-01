// RFC 0019 §6.4 — the source-preserving display projection.
//
// Lowering never rewrites the application's text: it produces a *projection*
// — a display string plus sparse, monotone mappings back to the canonical
// logical text. Painting and width layout consume the display side; copy,
// semantics and selection answer from the source side. A projection may
// change what is painted, never what is copied or announced (RFC 0019
// decision 3).
//
// Two fast paths matter more than any cache (review round 2): a `preserve`
// policy bypasses the parser entirely, and text with no U+200D returns the
// identity projection with zero per-cluster allocation — both hand back the
// input string itself.

import 'package:characters/characters.dart';

import '../editing/text_editing.dart' show TextRange;
import 'emoji_sequence.dart';
import 'width_policy.dart';

/// One logical grapheme cluster whose display image differs from its source:
/// a lowered emoji ZWJ sequence, projected into per-component display atoms.
///
/// Ranges are half-open UTF-16 code-unit ranges — [sourceRange] into
/// [TextProjection.logicalText], [displayRange] and every [displayAtomRanges]
/// entry into [TextProjection.displayText]. The atoms tile [displayRange]
/// exactly, in order; each atom is one ≤2-cell cluster by construction
/// (the parser only emits base+attachment components).
final class PreparedCluster {
  const PreparedCluster({
    required this.sourceRange,
    required this.displayRange,
    required this.displayAtomRanges,
  });

  final TextRange sourceRange;
  final TextRange displayRange;
  final List<TextRange> displayAtomRanges;

  @override
  String toString() =>
      'PreparedCluster(source: $sourceRange, display: $displayRange, '
      'atoms: $displayAtomRanges)';
}

/// A logical string and its display projection under one
/// [TextPresentationPolicy].
///
/// [changedClusters] is the whole of the source↔display correspondence:
/// outside those ranges display IS source, and inside one the cluster is
/// atomic — no position may rest between its atoms (RFC 0019 decision 14).
/// Consumers derive what they need from the ranges. Selection, the only
/// consumer that needs source coordinates, works in the FLAT space of the
/// wrapped lines rather than this unwrapped display space, so it projects the
/// ranges into that space once (`RenderText.loweredGroups`) instead of
/// converting offsets one at a time.
final class TextProjection {
  const TextProjection._(
    this.logicalText,
    this.displayText,
    this.changedClusters,
  );

  /// The unchanged projection: display IS the logical string (same object —
  /// gate 15, identity allocation).
  const TextProjection.identity(String text)
    : this._(text, text, const <PreparedCluster>[]);

  /// Canonical (post-sanitization) text — what copy and semantics answer with.
  final String logicalText;

  /// What layout measures and paint draws.
  final String displayText;

  /// The lowered clusters, in ascending source order. Empty means identity.
  final List<PreparedCluster> changedClusters;

  bool get isIdentity => changedClusters.isEmpty;

  /// The lowered cluster whose display image contains [displayOffset], if any.
  PreparedCluster? clusterAtDisplay(int displayOffset) {
    for (final cluster in changedClusters) {
      if (displayOffset >= cluster.displayRange.start &&
          displayOffset < cluster.displayRange.end) {
        return cluster;
      }
      if (cluster.displayRange.start > displayOffset) break;
    }
    return null;
  }
}

const int _zwjCodeUnit = 0x200D;

/// Projects [logicalText] for display under [policy].
///
/// Identity unless the policy authorizes lowering AND the text contains a
/// joiner AND a cluster parses as an emoji ZWJ sequence — everything else,
/// including shaping-significant non-emoji ZWJ text, passes through
/// byte-identical (property gate 10 rides on the parser's strictness).
TextProjection projectText(
  String logicalText, {
  required TextPresentationPolicy policy,
}) {
  if (policy.lowering != ClusterLowering.split) {
    return TextProjection.identity(logicalText);
  }
  // Zero-allocation reject for the overwhelmingly common case: U+200D is a
  // BMP code unit, so a plain code-unit scan is exact.
  var hasZwj = false;
  for (var i = 0; i < logicalText.length; i++) {
    if (logicalText.codeUnitAt(i) == _zwjCodeUnit) {
      hasZwj = true;
      break;
    }
  }
  if (!hasZwj) return TextProjection.identity(logicalText);

  final display = StringBuffer();
  final changed = <PreparedCluster>[];
  var sourceOffset = 0;
  for (final cluster in logicalText.characters) {
    final components = splitEmojiZwjSequence(cluster);
    if (components == null) {
      display.write(cluster);
    } else {
      final displayStart = display.length;
      final atoms = <TextRange>[];
      for (final component in components) {
        atoms.add(
          TextRange(
            start: display.length,
            end: display.length + component.length,
          ),
        );
        display.write(component);
      }
      changed.add(
        PreparedCluster(
          sourceRange: TextRange(
            start: sourceOffset,
            end: sourceOffset + cluster.length,
          ),
          displayRange: TextRange(start: displayStart, end: display.length),
          displayAtomRanges: List.unmodifiable(atoms),
        ),
      );
    }
    sourceOffset += cluster.length;
  }
  if (changed.isEmpty) {
    // Joiners were present but nothing parsed as an emoji sequence (Arabic,
    // Indic, malformed) — identity, same object, no mappings.
    return TextProjection.identity(logicalText);
  }
  return TextProjection._(
    logicalText,
    display.toString(),
    List.unmodifiable(changed),
  );
}
