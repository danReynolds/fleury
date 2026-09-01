// RFC 0019 §6.2 — the width policy layer.
//
// Raw probe observations (WidthMeasurements) and environment overrides are
// folded ONCE, at capability construction, into a single derived policy that
// every geometry consumer shares. Layout never combines width guesses and
// lowering decisions independently, so incoherent mixes — an explicit
// wide-emoji width with an ambient split-lowering, say — are unrepresentable.
//
// Provenance lives BESIDE the policy, never on it: two policies with
// identical geometry compare equal regardless of whether an axis came from a
// probe, an environment override, or the spec default, so caches and layout
// invalidation never see diagnostic metadata.

import 'package:meta/meta.dart';

/// A width class's answer: one cell or two. The whole policy layer stays
/// inside the bounded cell algebra — no axis can express a width above two
/// (RFC 0019 invariant: display atoms never exceed two cells).
enum CellWidth { one, two }

/// How many cells each measured width class occupies on this surface.
///
/// These are the axes every disagreement expressible in 0/1/2 cells reduces
/// to. Each applies ONLY to its own cluster kind (the resolver precedence
/// ladder, RFC 0019 §6.3): [emojiVariationSequence] answers a simple
/// base+VS16 pair and can never leak onto a ZWJ sequence or keycap that
/// merely contains a selector; [emojiPresentation] answers bare
/// `Emoji_Presentation` scalars and never affects CJK.
@immutable
final class CellWidthPolicy {
  const CellWidthPolicy({
    this.ambiguous = CellWidth.one,
    this.emojiPresentation = CellWidth.two,
    this.emojiVariationSequence = CellWidth.two,
  });

  /// UAX #11 East Asian Ambiguous. Spec default: narrow.
  final CellWidth ambiguous;

  /// Bare `Emoji_Presentation` scalars. Spec default: wide (UAX #11 ED4).
  final CellWidth emojiPresentation;

  /// Simple emoji variation sequences (one base + VS16). Spec default: wide
  /// (UTS #51); measured 1 on roughly 19 of ~30 surveyed terminals.
  final CellWidth emojiVariationSequence;

  /// The spec-following policy — what every terminal gets until measured
  /// evidence or an explicit override says otherwise, and what tests and
  /// unprobed pipes always get.
  static const CellWidthPolicy spec = CellWidthPolicy();

  /// Legacy/CJK terminals: ambiguous renders two cells.
  static const CellWidthPolicy cjk = CellWidthPolicy(ambiguous: CellWidth.two);

  @override
  bool operator ==(Object other) =>
      other is CellWidthPolicy &&
      other.ambiguous == ambiguous &&
      other.emojiPresentation == emojiPresentation &&
      other.emojiVariationSequence == emojiVariationSequence;

  @override
  int get hashCode =>
      Object.hash(ambiguous, emojiPresentation, emojiVariationSequence);

  @override
  String toString() =>
      'CellWidthPolicy(ambiguous: ${ambiguous.name}, '
      'emojiPresentation: ${emojiPresentation.name}, '
      'emojiVariationSequence: ${emojiVariationSequence.name})';
}

/// What happens to emoji ZWJ sequences on this surface.
///
/// [split] is authorized only when summing was confidently measured AND the
/// width policy predicts every measured component (RFC 0019 §6.4) — an
/// `unknown` observation always derives [preserve], never adaptation.
/// Consumed by the P2 display-lowering layer; carried in the policy now so
/// width and lowering can never be combined incoherently.
enum ClusterLowering { preserve, split }

/// The one effective text-presentation policy for a surface: widths plus
/// lowering, as a single value so no consumer can mix them from different
/// sources.
@immutable
final class TextPresentationPolicy {
  const TextPresentationPolicy({
    this.widths = CellWidthPolicy.spec,
    this.lowering = ClusterLowering.preserve,
  });

  final CellWidthPolicy widths;
  final ClusterLowering lowering;

  /// Spec widths, no lowering — the unprobed/test/serve default.
  static const TextPresentationPolicy spec = TextPresentationPolicy();

  @override
  bool operator ==(Object other) =>
      other is TextPresentationPolicy &&
      other.widths == widths &&
      other.lowering == lowering;

  @override
  int get hashCode => Object.hash(widths, lowering);

  @override
  String toString() =>
      'TextPresentationPolicy(widths: $widths, lowering: ${lowering.name})';
}

/// One decided axis of the policy, for provenance.
enum WidthAxis {
  ambiguous,
  emojiPresentation,
  emojiVariationSequence,
  lowering,
}

/// Where an axis's value came from. Diagnostic only — never part of policy
/// equality or cache keys.
enum WidthDecisionSource {
  /// The spec default: no probe evidence and no override. For adaptation
  /// purposes this is the `unknown` state — conservative consumers (the
  /// renderer's ambiguous pin) stay engaged on it.
  spec,

  /// Derived from agreeing probe measurements.
  probe,

  /// Forced by a `FLEURY_*` environment override.
  environment,
}

/// A [TextPresentationPolicy] plus the per-axis record of where each value
/// came from. The policy is the operational value; [decisions] exists for
/// `fleury diagnose` and conservative gating, and deliberately does not
/// participate in equality.
@immutable
final class ResolvedTextPresentationPolicy {
  const ResolvedTextPresentationPolicy({
    this.policy = TextPresentationPolicy.spec,
    this.decisions = const <WidthAxis, WidthDecisionSource>{},
  });

  final TextPresentationPolicy policy;

  /// Per-axis provenance. Axes absent from the map are [WidthDecisionSource.spec].
  final Map<WidthAxis, WidthDecisionSource> decisions;

  WidthDecisionSource sourceOf(WidthAxis axis) =>
      decisions[axis] ?? WidthDecisionSource.spec;

  /// Whether [axis] rests on evidence (probe or override) rather than the
  /// spec default. The renderer's conservative gates key off this: an axis
  /// that is merely defaulted is `unknown`, and unknown never disengages a
  /// safety net (RFC 0019 §6.3).
  bool isEvidenced(WidthAxis axis) =>
      sourceOf(axis) != WidthDecisionSource.spec;

  /// Whether the ANSI renderer must keep its defensive per-cell reposition
  /// engaged for ambiguous-width glyphs (RFC 0019 decision 9).
  ///
  /// The pin comes off only for an ambiguous axis that is BOTH resolved narrow
  /// and evidenced. A spec default is not evidence: `unknown` keeps the safety
  /// net on, because a terminal nobody measured may still draw box drawing two
  /// cells wide, and then every cell after it on the row is displaced.
  ///
  /// This is the whole of the renderer's ambiguous-width decision, in one
  /// place, derived from the same policy layout measures with — so the two
  /// cannot answer differently for one session.
  bool get pinsAmbiguousWidth =>
      !(isEvidenced(WidthAxis.ambiguous) &&
          policy.widths.ambiguous == CellWidth.one);

  Map<String, Object?> toJson() => <String, Object?>{
    'policy': <String, Object?>{
      'ambiguous': policy.widths.ambiguous.name,
      'emojiPresentation': policy.widths.emojiPresentation.name,
      'emojiVariationSequence': policy.widths.emojiVariationSequence.name,
      'lowering': policy.lowering.name,
    },
    'decisions': <String, Object?>{
      for (final axis in WidthAxis.values) axis.name: sourceOf(axis).name,
    },
  };

  @override
  String toString() =>
      'ResolvedTextPresentationPolicy($policy, decisions: '
      '{${WidthAxis.values.map((a) => '${a.name}: ${sourceOf(a).name}').join(', ')}})';
}
