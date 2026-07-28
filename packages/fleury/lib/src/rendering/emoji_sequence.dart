// RFC 0019 §6.4 — intra-cluster emoji ZWJ sequence recognition.
//
// An extended grapheme cluster deliberately contains an entire ZWJ sequence
// (UAX #29 GB11), so grapheme segmentation cannot yield the component
// boundaries display lowering needs — that takes a second parse INSIDE the
// cluster, keyed on the emoji properties, which is exactly what this file is.
//
// Parsing, not string surgery: splitting happens at ZWJ boundaries only,
// components keep their attachments (a base's skin-tone modifier and
// variation selector travel with it), and anything unrecognized returns null
// so the caller preserves the source bytes. Non-emoji ZWJ — Arabic, Indic,
// any script where the joiner affects shaping — never parses as a sequence,
// because its segment bases are not Extended_Pictographic.

import 'width_resolver.dart';
import 'width_tables.dart';

const int _zwj = 0x200D;
const int _vs15 = 0xFE0E;
const int _vs16 = 0xFE0F;

/// Splits one extended grapheme [cluster] into its emoji ZWJ sequence
/// components — `👨‍👩‍👦` → `[👨, 👩, 👦]`, `👩🏽‍⚕️` → `[👩🏽, ⚕️]` — or returns
/// null when the cluster is not a recognized emoji ZWJ sequence.
///
/// Recognition is deliberately strict (RFC 0019 decision 10): a cluster
/// qualifies only when it contains at least one ZWJ, every ZWJ-delimited
/// segment is non-empty, every segment's base is `Extended_Pictographic`, and
/// every non-base code point in a segment is an attachment (an
/// `Emoji_Modifier` or a variation selector). Anything else — no joiner,
/// shaping-significant joiners between letters, tag sequences, malformed
/// segments — is null, and null means "preserve the source bytes": the
/// conservative answer costs a pin, a wrong split costs correctness.
///
/// The returned components are plain ≤2-cell clusters by construction; the
/// joiners are not included.
List<String>? splitEmojiZwjSequence(String cluster) {
  // Cheap reject: the common case has no joiner at all. Code-unit scan —
  // U+200D is BMP, so this needs no rune iteration.
  var hasZwj = false;
  for (var i = 0; i < cluster.length; i++) {
    if (cluster.codeUnitAt(i) == _zwj) {
      hasZwj = true;
      break;
    }
  }
  if (!hasZwj) return null;

  final components = <String>[];
  final segment = StringBuffer();
  var segmentLength = 0; // code points in the current segment

  for (final rune in cluster.runes) {
    if (rune == _zwj) {
      if (segmentLength == 0) return null; // leading or doubled ZWJ
      components.add(segment.toString());
      segment.clear();
      segmentLength = 0;
      continue;
    }
    if (segmentLength == 0) {
      // Segment base: must be pictographic, or this is not an emoji sequence
      // (an Arabic letter next to a shaping ZWJ lands here and bails).
      if (!widthRangesContain(extendedPictographicRanges, rune)) return null;
    } else {
      // Attachments only: a skin-tone modifier or a variation selector rides
      // with its base. Anything else (a second pictographic without a joiner,
      // a keycap, a tag character) makes the cluster unrecognized.
      final isAttachment =
          rune == _vs15 ||
          rune == _vs16 ||
          widthRangesContain(emojiModifierRanges, rune);
      if (!isAttachment) return null;
    }
    segment.writeCharCode(rune);
    segmentLength++;
  }
  if (segmentLength == 0) return null; // trailing ZWJ
  components.add(segment.toString());

  // One segment means every ZWJ was malformed-adjacent; not a sequence.
  return components.length >= 2 ? components : null;
}
