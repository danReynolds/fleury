# RFC 0019: Width Policy and Display Lowering

**Status:** Implemented — P1 (measured width policy, PR #175) and P2
(source-preserving display lowering, PR #176) shipped 2026-07-27. P3 (declare
tier) remains future work.
**Date:** 2026-07-27
**Decision point for:** what Fleury does when its width model and the
terminal's rendering disagree — the failure class behind the storybook
scroll-garble, and the open question left by the 2026-07 width work
(UCD-generated tables, the VS16 cluster rule, the containment pin, the startup
glyph probe).

Cross-references: **RFC 0013** (capability contract — the probe rides the same
startup handshake), the width table generator
([`tool/ucd_width_tables.dart`](../../tool/ucd_width_tables.dart)), and the
peer/terminal research summarized in §3 and §14.

---

## 1. Summary

Terminals disagree about how many cells a glyph occupies, and no protocol
reliably reports which behaviour a given terminal has. Fleury already measures
the truth directly at startup — draw a glyph, read the cursor — but the
measurements are consumed by nothing except the renderer's defensive pin.

This RFC organizes width handling into three layers with one invariant and one
boundary rule:

> **The invariant:** every display atom occupies at most two cells. The cell
> buffer, diff renderer, wire plan and web client never represent a single
> atom wider than two.
>
> **The boundary rule:** any disagreement expressible within 0/1/2 cells is a
> **width policy** matter — the resolver's classification adapts to the
> measured surface, bytes unchanged. Only a sequence the terminal expands
> *beyond* two cells is **lowered**: projected into several ≤2-cell display
> atoms. Lowering is a display projection; the **source text is preserved
> above it** and remains canonical for copy, semantics, and selection.

The pipeline, end to end:

```
measure surface behaviour            (probe, §6.1)
    → derive one bounded policy      (policy object, §6.2)
    → resolve representable
      disagreements                  (P1, §6.3)
    → lower only beyond-algebra
      sequences                      (P2, §6.4)
    → preserve logical source        (projection contract, §6.4)
    → pin the unresolved tail        (containment, §6.5)
```

**Lowering's contract is geometric, not pictorial:** splitting confidently
restores *cell geometry* and is expected to preserve the common visual
behaviour of summing terminals; CPR measures cursor advance, not which glyphs
were painted, so pixel equivalence is not claimed. The per-axis operator
overrides are the escape hatch for the unusual surface.

Unprobed terminals get today's behaviour, byte for byte. The web surface is
untouched: the serve client renders the model directly, so it agrees with the
model by construction.

## 2. The problem and its mechanics

Fleury keeps a cell-grid model of the screen. Layout reserves cells per glyph
via the width resolver; the diff renderer tracks the cursor position implied
by those widths and positions subsequent writes relative to it. When the model
says 2 and the terminal draws 1 (or vice versa), the tracked cursor diverges
from the real one and every later relative write lands shifted — the frame
garbles.

The 2026-07 width work eliminated the *self-inflicted* portion of this and
bounded the rest:

- **Tables are generated from the UCD** (Unicode 17.0.0) with an offline
  freshness gate; 13,005 code points the hand-written excerpts measured wrong
  were corrected
  ([`width_tables.dart`](../../packages/fleury/lib/src/rendering/width_tables.dart)).
- **Presentation selectors are a cluster rule**, not table rows: VS16 promotes
  its base to emoji presentation (2 cells), VS15 forces text (1).
- **Uncertainty is contained**: `hasUncertainWidth` classifies the
  emoji-capable clusters, and the renderer re-anchors the cursor absolutely
  after each one
  ([`ansi_renderer.dart`](../../packages/fleury/lib/src/rendering/ansi_renderer.dart)
  `needsWidthPin`), so a disagreement is a local artifact, never a cascade.
- **The startup probe measures the terminal**
  ([`terminal_probe.dart`](../../packages/fleury/lib/src/terminal/terminal_probe.dart)
  `probeGlyphWidths`): one batched round trip writes representative glyphs and
  reads a cursor position report after each. `fleury diagnose --probe` prints
  the results.

What remains is the *external* disagreement: the model is right per Unicode,
and a large share of deployed terminals render differently. Today the only
mitigation is the pin — which keeps a wrong-width glyph from destroying the
frame but leaves it visibly wrong: on a summing terminal, a family emoji
occupies 2 model cells while the terminal draws 6–8 columns, so the pin
truncates it and the row shows a mutilated glyph.

This matters disproportionately for Fleury because of the agent-console use
case: transcript panes render **LLM output verbatim**, and model output is
emoji-dense. "Restrict your glyphs" is workable guidance for chrome an app
author draws; it is unusable for arbitrary text a model streams.

## 3. Evidence

Two probe runs from real terminals (2026-07-27), plus the field survey.

| measurement | terminal A¹ | Warp | Fleury models |
|---|---|---|---|
| ambiguous `─` | 1 | 1 | 1 (probed) |
| VS16 `❤️` | **1** | **2** | 2 |
| text dingbat `✓` | 1 | 1 | 1 |
| ZWJ `👨‍👩‍👦` | **3** | **8** | 2 |

¹ `TERM_PROGRAM` unset; a minimal embedded emulator.

The ZWJ numbers decompose. `👨‍👩‍👦` is three emoji joined by two ZWJs:

| family | emoji width | joiner cost | clusters? | 👨‍👩‍👦 | representatives |
|---|---|---|---|---|---|
| joined | 2 | — | yes | **2** | kitty, Ghostty, foot, Windows Terminal, iTerm2 |
| sum, free joiners | 2 | 0 | no | **6** | VTE/GNOME, Alacritty, xterm, **xterm.js → VS Code** |
| sum, paid joiners | 2 | 1 | no | **8** | **Warp**, Apple Terminal, mintty, mlterm |
| sum, narrow emoji | 1 | 0 | no | **3** | terminal A |

Four families, three near-binary parameters. The survey data (ucs-detect
corpus, ~30 terminals, June 2026) confirms the same structure at scale and
puts the biggest single cluster in perspective: **19 of ~30 terminals render
`❤️` at 1 cell** — including the default terminals of macOS, GNOME, and
VS Code. There is no single right answer to publish; the only correct width
for `❤️` is *this terminal's* width.

A caveat the design must respect (§6.1): a single glyph per class is a
*signal*, not proof. `─` is the character most likely to be special-cased
narrow by an otherwise ambiguous-wide terminal (grids must work); a font
missing `🙂` measures its replacement glyph; a terminal may join some ZWJ
sequences and not others. Adaptation requires agreement across
representatives; disagreement stays conservative.

## 4. Rejected designs

Recorded so later work doesn't relitigate them.

**Per-terminal correction tables** (wcwidth 0.8's approach: offline-measured
overrides keyed on `TERM_PROGRAM`). Rejected: a large, rotting data surface;
misses unknown terminals entirely; and Fleury can measure the live terminal
directly, which is strictly better evidence than a lookup keyed on an env var
that terminal A doesn't even set.

**Mode 2027 negotiation** (Charm/ultraviolet, 2026-07-02). The right instinct
— make both sides commit to one algorithm — but DECRQM 2027 lies in both
directions: kitty answers "unsupported" and clusters correctly; WezTerm
answers "permanently set" while not honoring VS16; foot answers "permanently
reset" unless configured a particular way; tmux answers 0 and swallows the
DECSET. A capability bit that misreports the best terminals is not a
contract. CPR measurement observes the behaviour itself.

**OSC 66 as the primary mechanism** (kitty's text-sizing protocol: the app
declares the width). Correct long-term direction, adopted by 2 of ~30
terminals, and a multiplexer that doesn't understand it drops the text *with*
the envelope. Slotted as a future enhancement tier (§11), not a foundation.

**Unbounded adaptive geometry** (probe feeds the resolver, one grapheme
reserves 6–8 buffer cells for a summed family). Rejected on cost: the cell
buffer, diff renderer, wire plan and web client all assume a glyph occupies
≤2 cells (leading + continuation); >2-cell atoms are surgery through every
layer. Lowering achieves the same alignment by projecting the *sequence* into
several bounded atoms instead of widening one atom.

**Destructive shaping as the default** (v1 of this RFC: strip `FE0F`, treat
the shaped string as canonical — shaped clipboard, shaped semantics).
Rejected in review, and rightly: a 1-vs-2-cell disagreement is fully
expressible inside the algebra, so it is a resolver-policy matter with bytes
unchanged; and transcript text is user data — a projection may change what is
*painted*, never what is *copied or announced*. Stripping selectors remains
available as a targeted emission workaround for a demonstrated rendering
defect, not as the mechanism.

**Restrict-and-contain only** (Rich/Textual's historical answer: follow the
spec, tell users to avoid modern emoji). Insufficient for the transcript case
(§2); the guidance survives for app chrome, but the framework must handle
arbitrary text.

## 5. Design principle

Fleury already adapts per surface on every other axis — color depth
downsampling, `GlyphTier.ascii` border substitution
([`basic.dart:917`](../../packages/fleury/lib/src/widgets/basic.dart)), image
protocol selection. Width joins them, structured by the boundary rule:

- **Within the algebra → policy.** If the terminal's behaviour for a glyph
  class is 0, 1, or 2 cells, the resolver's classification for that class
  adapts. Geometry follows the measured surface; bytes never change. This
  deliberately makes width classification surface-dependent — within the
  bounded 0/1/2 algebra, which is the actual invariant. (The rejected design
  was not adaptive classification; it was *unbounded* atoms.)
- **Beyond the algebra → lowering.** If the terminal expands one logical
  cluster past two cells, no classification fixes it. The cluster is lowered
  to display atoms the terminal renders at model width. The observation
  making this safe: **the lowered form is what summing terminals render
  anyway** — a terminal that sums `👨‍👩‍👦` is drawing `👨👩👦` regardless of what
  we send; the joined form just adds mispredicted joiner columns. Lowering
  also normalizes away the joiner-cost axis (the 6-vs-8 split in §3): once
  joiners are no longer emitted to summing terminals, their joiner pricing
  never applies. When lowering is authorized (§6.4), the geometry is exactly
  predictable: predicted width after lowering = Σ predicted component widths
  = Σ measured component widths = terminal advance.
- **Source above both.** The application's text is canonical. Lowering
  produces a *display projection* with a mapping back to source; copy,
  semantics, and selection answer from source.

## 6. Mechanism

### 6.1 Probe: representatives, agreement, and `unknown`

`probeGlyphWidths` extends to a small battery — still one `\r`-anchored
batched write, one round trip, one DA sentinel; each measurement starts at
column 1 so nothing accumulates or wraps. Classes and representatives
(~14 writes; final list is an implementation detail with fixed criteria:
old, widely-deployed code points from distinct blocks):

| class | representatives | derives |
|---|---|---|
| ambiguous | `─` (box drawing), `α` (Greek), `°` (Latin-1 punct) | `ambiguous: one\|two\|unknown` |
| emoji presentation | `🙂`, `😀`, and the bare ZWJ components `👨 👩 👦` | `emojiPresentation: one\|two\|unknown` |
| emoji variation sequence | `❤️` (U+2764 FE0F), `⚠️` (U+26A0 FE0F), `⚕️` | `emojiVariationSequence: one\|two\|unknown` |
| ZWJ sequences | `👨‍👩‍👦` (family), `👩‍⚕️` (profession) | `clusters: joined\|summed\|unknown` |
| text presentation | `✓` | diagnostic only |

Rules:

- **Representative independence.** A glyph reinforces agreement only for the
  class it belongs to: `⚕️` (a variation sequence) never participates in the
  bare emoji-presentation vote, and vice versa — otherwise the *common*
  combination "bare emoji wide, variation sequence narrow" would wrongly
  force `emojiPresentation` to `unknown`. The ZWJ components are probed bare
  and double as emoji-presentation representatives *and* as the measured
  inputs to the summing equation.
- **Agreement or `unknown`.** A class adapts only when its representatives
  agree; any disagreement or anomalous value yields `unknown` for that axis.
  `unknown` keeps the spec default *and the pin* — never adaptation. This is
  what defuses tofu: a font missing one emoji cannot reclassify the class.
- **Summing is an inequality, not an estimate.** With per-component
  measurements in hand, a sequence is *summed* when
  `componentSum ≤ sequenceAdvance ≤ componentSum + zwjCount`
  (accepting free, paid, and mixed-cost joiners without measuring a bare
  ZWJ), and *joined* when `sequenceAdvance ≤ 2` — each required to hold for
  **every** probed sequence; anything else, including a terminal that joins
  professions but sums families, is `unknown`.
- **The batch is atomic.** CPR replies are ordered but unlabeled: if the
  reply count is wrong, ordering is anomalous, or the DA sentinel arrives
  early, the entire battery is discarded and every axis derives its default.
  Per-axis salvage of a partial batch is unsafe without indexed replies and
  is not attempted.
- Raw measurements stay nullable and diagnostic (`WidthMeasurements`),
  separate from derived policy; both appear in `fleury diagnose`.

### 6.2 One policy object, provenance beside it

Raw measurements and environment overrides are folded **once**, at capability
construction, into a single derived object — layout never combines width
guesses and lowering decisions independently, so incoherent mixes are
unrepresentable:

```dart
enum CellWidth { one, two }

final class CellWidthPolicy {
  final CellWidth ambiguous;               // spec default: one
  final CellWidth emojiPresentation;       // spec default: two
  final CellWidth emojiVariationSequence;  // spec default: two
}

enum ClusterLowering { preserve, split }   // `unknown` derives to preserve

final class TextPresentationPolicy {
  final CellWidthPolicy widths;
  final ClusterLowering lowering;
}
```

- **Value equality is operational only.** Provenance lives beside the policy,
  not on it — `ResolvedTextPresentationPolicy(policy, decisions)` where
  `decisions` maps each axis to `default | probe | environment` — so two
  policies with identical geometry never differ for equality, layout
  invalidation, or `PreparedText` caching. The widget layer reports its own
  explicit override as `application` provenance without threading metadata
  through width lookups. `fleury diagnose` prints the decisions map.
- `SurfaceCapabilities` carries the policy. The backend-neutral layer does
  **not** expose a terminal-named type: `TerminalProfile` is replaced by
  `CellWidthPolicy` in the resolver signature (pre-launch clean break;
  `standard`/`cjk` survive as named presets at the terminal boundary).
- Widgets accept an optional explicit `TextPresentationPolicy`; null means
  ambient. An explicit policy overrides *the whole object*, keeping widths
  and lowering coherent by construction.
- **A policy change dirties layout, not merely paint.** Policy is fixed at
  startup in production; this rule exists so tests and future hot paths
  cannot observe a stale-geometry frame.

### 6.3 P1 — ambient width policy in the resolver

Text widgets (`Text`, `RichText`, `TextInput`, `TextArea`) resolve the
ambient policy from `MediaQuery` at build and pass it explicitly into their
render objects (render objects never read ambient context themselves).

**Resolver precedence is defined by cluster kind** — the width axes apply
only to the classes they were measured on, so a selector *inside* a
composite can never leak the simple-sequence answer onto the whole:

```
1. recognized emoji ZWJ sequence      → P2 lowering when policy says split;
                                        otherwise composite rule (base-keyed,
                                        capped at 2) + pin
2. modifier / flag / keycap / tag seq → existing specialized rules + pin
3. simple emoji variation sequence
   (one base + one FE0F/FE0E, nothing
   else)                              → FE0E: 1;
                                        FE0F: policy.emojiVariationSequence
4. single Emoji_Presentation scalar   → policy.emojiPresentation
5. East Asian Wide / Fullwidth        → 2
6. East Asian Ambiguous               → policy.ambiguous
7. otherwise                          → 1  (zero-width handled before all)
```

`👩‍⚕️` therefore takes branch 1 (its FE0F belongs to a component, not to the
cluster), and `1️⃣` takes branch 2 — `emojiVariationSequence: one` narrows
`❤️` and nothing else.

Two semantics change:

- **`emojiPresentation: one` gains veto power.** Today the flag cannot narrow
  `🙂`, because UAX #11 ED4 folds `Emoji_Presentation=Yes` into East Asian
  Wide and the wide table wins. Under this RFC the emoji-presentation class
  resolves 1 when the policy says so. CJK ideographs and other Wide classes
  are never affected (the classes are distinct generated tables).
- **`emojiVariationSequence: one` resolves the simple sequence at 1** —
  bytes unchanged, `❤️` emitted as-is, modelled at what this terminal draws.
  This single change corrects the largest disagreement cluster in the field
  (19 of ~30 terminals) with no lowering at all.

**One policy reaches every geometry consumer.** The P1 invariant: a
paragraph has exactly one effective `CellWidthPolicy`, used by wrapping,
cell placement, hit testing, caret movement, selection painting, clipping,
and the renderer's uncertainty decisions. P1 includes an audit for width
resolution constructed *beside* the render-object path (caret helpers,
editing offset↔cell mapping, selection measurement, buffer-write defaults);
any found are converted to take the policy as a required argument. Without
this, P1's "editable text stays internally consistent" claim would be false
— a caret helper defaulting to spec policy would disagree with painting,
turning a terminal-only mismatch into an internal one.

**Per-surface layout ownership is explicit.** A laid-out tree is bound to
one policy; surfaces with different policies (a terminal session and a serve
session) own separate layout passes via their own `MediaQuery` — which is
the existing per-surface model, now stated as a rule.

**The pin covers `unknown` ambiguous — verified, not assumed.** The
renderer's ambiguous pin arm keys off the *resolved* axis: it disengages
only when the axis measured `one`; both `two` and `unknown` keep it engaged
(today's conservative default when the probe fails). This closes a real
gap: `hasUncertainWidth` classifies emoji-capable clusters, so an
ambiguous-class glyph like `α` on an axis-unknown terminal would otherwise
be unpinned and able to cascade. An end-to-end gate test encodes exactly
the §6.1 disagreement fixture (`─`=1, `α`=2, `°`=2 → axis `unknown`) and
asserts that a wide-drawn `α` cannot shift the text written after it.

P1 applies to editable text too: with no lowering, display equals value, so
caret and selection math stay internally consistent while agreeing with the
terminal *better* than today.

Unprobed, every axis keeps its spec default — nothing changes for pipes, CI,
tests, or serve.

### 6.4 P2 — source-preserving display lowering

A general **logical-cluster → display-atoms lowerer** (not a ZWJ string
helper), applied only when the derived lowering action is `split`, for
read-only text.

**Authorization: summed observation is not sufficient.** Splitting is exact
only when the policy predicts what the terminal will do with the emitted
components. The derivation:

```
cluster observation = summed
    when every probed sequence satisfies the summing inequality (§6.1)

lowering action = split
    when observation == summed
    AND every measured component width equals the width the effective
        policy predicts for it
otherwise → preserve  (+ pin)
```

The second conjunct matters: if the terminal sums `👨=1, 👩=2, 👦=2 → 5` but
the emoji-presentation axis derived `unknown` (defaulting components to 2),
splitting would model 6 against a drawn 5 — better than the 8-column joiner
error, but not the exact alignment this design promises, so it is not
authorized automatically. `FLEURY_CLUSTER_MODE=split` may force it.

**Parsing, not string surgery.** Lowering operates on a parsed
representation of each grapheme cluster: identify *emoji ZWJ sequences*
using the emoji properties/sequence data (grapheme segmentation alone
cannot do this — an extended grapheme cluster deliberately contains the
whole sequence, so a second, intra-cluster parse is required). Non-emoji
ZWJ usage — Arabic, Indic, any script where the joiner affects shaping —
is untouched, byte-identical. Components keep their attachments: `👩🏽‍⚕️`
lowers to `👩🏽` + `⚕️`, never to `👩 🏽 ⚕ FE0F`. Modifier sequences
(`👍🏽`), flags, keycaps and tag sequences are not ZWJ sequences and are
never split; they remain the pin's responsibility (the lowerer's shape
gives them a natural home if measurement ever motivates more).

**Two-stage projection, one choke point.**

```
logical text + policy            → TextProjection        (cached: text, policy)
TextProjection + source style runs → PreparedParagraph   (cached: projection, runs)
```

Sequence detection runs across the flattened logical text, so splitting
source across compatible rich-text spans changes nothing; coalescing equal
style runs is a no-op; a lowered component inherits the effective source
style covering its base. The paragraph/text-layout API itself accepts
logical text plus policy and prepares display atoms internally — a shared
helper that render objects *may* call is explicitly not enough, because a
bypass reintroduces divergence.

**The projection retains cluster structure**, not just a flat mapping:

```dart
final class PreparedText {
  final String logicalText;     // canonical, post-sanitization
  final String displayText;
  final List<PreparedCluster> changedClusters;  // sparse; identity elsewhere
}

final class PreparedCluster {
  final TextRange sourceRange;              // one logical grapheme cluster
  final TextRange displayRange;             // its contiguous display image
  final List<TextRange> displayAtomRanges;  // ≥1 atoms, each ≤ 2 cells
}
```

Mapping properties (the §10 gates): every display atom maps to exactly one
source grapheme range; atom→source mappings are monotone non-decreasing;
every source grapheme maps to one contiguous, non-empty display range;
unchanged regions are identity; mapping a source range to display and back
preserves its grapheme boundaries.

**Source is defined post-sanitization.** The pipeline is explicit:
application text → existing control-character sanitization → canonical
logical text → projection → display atoms. `logicalText` is the
post-sanitization form; lowering does not pretend to map back to raw
application input (the sanitizer already transforms).

**Selection lives in source coordinates.** The selection model stores
source offsets only; display offsets exist for hit testing and painting.
Copy is `logicalText.substring(selection)` — a lowered family is copied
once, as `👨‍👩‍👦`. A display hit inside a lowered group resolves to the source
cluster's start or end boundary by affinity (upstream → before, downstream
→ after); **no selection endpoint can rest inside a source cluster**. Once
a drag crosses any atom of the group, the whole source cluster is included;
multi-cluster drags fall out of the existing anchor/focus normalization
with no emoji-specific state. Semantics announce source text with bounds
from the cluster's display range.

**Wrapping treats a lowered cluster as a no-break group.** The atoms of one
source cluster stay on one line when the group fits; a component break
inside the group is forced only when the group alone exceeds the line
width. The same rule governs truncation/ellipsis, clipping, hit testing,
and highlight painting — one grapheme never silently spans lines merely
because it was lowered.

**Caching is a per-render-object memo**, not a global keyed cache: last
logical text identity, last operational policy, last projection — with two
fast paths that matter more than any cache: `lowering == preserve` bypasses
the parser entirely, and text containing no U+200D returns an identity
projection with zero per-cluster allocation. Provenance is never part of a
cache key.

**Editable text is excluded**, and the limitation is stated honestly: the
pin *bounds* the damage of an unlowered wide sequence in a `TextInput` to
the affected region, but does not make editing it correct — the caret can
sit atop mis-rendered components and selection highlights can miss visible
glyphs. ZWJ-heavy editable text remains locally mis-rendered until
value↔display offset mapping is designed (follow-up, out of scope).

### 6.5 Containment (role unchanged, gate verified)

`needsWidthPin` remains permanent infrastructure. Post-adaptation it covers
exactly the tail it should: per-codepoint quirks (tmux's hardcoded `✍`=2,
kitty's nine wcwidth-disagreeing code points, Fitzpatrick and
regional-indicator edge cases), Unicode version skew, fonts, every
`unknown` axis (including ambiguous — §6.3), sequences whose lowering was
not authorized, and every unprobed session.

### 6.6 Environment overrides

Per-axis, matching the existing convention (`FLEURY_AMBIGUOUS_WIDTH`,
`FLEURY_GLYPH_TIER`, `FLEURY_COLOR_DEPTH`):

- `FLEURY_AMBIGUOUS_WIDTH=narrow|wide` — exists today, unchanged.
- `FLEURY_EMOJI_WIDTH=narrow|wide` — the emoji-presentation axis.
- `FLEURY_VS16_WIDTH=narrow|wide` — the emoji-variation-sequence axis
  (independent: "bare emoji wide, sequence narrow" is the *common*
  combination and must be expressible; the operator-facing name keeps the
  term of art).
- `FLEURY_CLUSTER_MODE=joined|split` — the lowering axis; `split` may force
  lowering past incomplete confidence (§6.4).

Overrides win over probe results; probe results win over defaults; the
decisions map records which applied.

## 7. What it fixes

A transcript pane renders `❤️ deploy approved 👨‍👩‍👦` on each family:

| terminal | today | P1 (policy) | P2 (+lowering) |
|---|---|---|---|
| kitty / Ghostty (joins, sequence = 2) | correct | correct, byte-identical | correct, byte-identical |
| VS Code / GNOME (sums, sequence = 1) | ❤️ off by one; family truncated | ❤️ modelled 1 → **aligned**, same bytes | family lowered → **aligned**, renders what it drew anyway, minus the corruption |
| Warp / Apple Terminal (sums, sequence = 2) | family truncated; 6-column error per glyph | ❤️ correct at 2 | family lowered → **aligned** |
| terminal A (narrow emoji) | every emoji off by one | emoji modelled 1 → **aligned** | family lowered, components at 1 → 3 = 3 ✓ |
| unprobed pipe / CI / serve | spec model + pin | identical, byte for byte | identical, byte for byte |

The VS16 question this session kept relitigating dissolves: probed terminals
get their measured truth per terminal; the spec answer (2) survives only as
the default for unprobed sessions — and the bytes are identical either way.

## 8. Costs and risks

- **CJK terminals get different geometry** — correctly different (a `─` the
  terminal draws at 2 cells now occupies 2 model cells), but borders and
  layouts change on ambiguous-wide terminals the first time the CJK path
  goes live. Pre-launch is the window for this.
- **Editable text keeps a known local defect** on summing terminals (§6.4) —
  bounded by the pin, honestly documented, fixed by follow-up mapping work.
- **Probe misclassification** is defused by agreement-or-`unknown` and batch
  atomicity, but a systematically consistent-and-wrong font (all
  representatives tofu at the same width) would still adapt to what it
  measures — which *is* the behaviour apps get on that surface, and
  per-axis overrides remain.
- **Mid-session change**: policy is fixed at startup, like color/glyph/image
  capabilities. A font swap that changes emoji availability mid-session is
  out of scope for the same reason it is for those axes.
- **Perf surface**: one extra table membership check on the resolver's
  non-ASCII path (emoji-presentation veto), sequence classification on the
  composite-cluster path, policy plumb-through, and — in P2 — per-set-text
  parse/lowering proportional to text length behind the two fast paths.
  Wire/alloc/paint gates must stay flat.

## 9. Property gates

Beyond example fixtures (terminal A and Warp's measurements as
policy-derivation tests), these hold as invariant tests:

1. **Bounded atoms**: every emitted display atom resolves to ≤ 2 cells.
2. **Unprobed compatibility**: with no probe evidence, emitted bytes are
   byte-identical to today's.
3. **Unknown is conservative**: inconsistent or absent probes never trigger
   lowering or policy adaptation; removing any single CPR reply from a
   probe fixture makes the batch unusable (atomicity), never
   mis-attributed.
4. **Resolver class precedence**: a FE0F inside a ZWJ, keycap, or other
   composite sequence never causes the whole sequence to take the
   simple-variation-sequence width.
5. **Composite-width containment**: an unknown-axis ambiguous glyph (`α` on
   the §6.1 disagreement fixture) and an unknown composite emoji can each
   be followed by ordinary text without shifting it — end to end, through
   the renderer.
6. **Split soundness**: whenever the automatic policy derives `split`,
   every probed emitted component resolves to its measured width.
7. **Projection coverage**: every source grapheme maps to one non-empty,
   contiguous display range; every display atom belongs to exactly one
   source grapheme; unchanged regions are identity.
8. **Boundary round-trip**: every valid source grapheme boundary survives
   source → display → source with the specified affinity.
9. **Idempotence**: lowering an already-lowered display is identity.
10. **Non-emoji safety**: Arabic/Indic/arbitrary non-emoji ZWJ text is
    byte-identical under every policy.
11. **Modifier integrity**: modifiers and selectors never detach from their
    base during lowering.
12. **Span invariance**: splitting source across compatible rich-text spans
    changes neither sequence detection nor lowering.
13. **Policy coherence**: no combination of explicit and ambient settings
    can mix incompatible width and lowering decisions.
14. **Policy invalidation**: changing the effective policy marks layout
    dirty, not merely paint dirty.
15. **Identity allocation**: with `preserve` lowering or no recognized
    sequence, preparation reuses the input and allocates no per-cluster
    mappings.

## 10. Staging

**P1 — capability-derived width policy.** Probe battery with agreement
rules and batch atomicity; `WidthMeasurements` (raw) separated from
`TextPresentationPolicy` (derived) with the provenance map beside it;
`CellWidthPolicy` replaces `TerminalProfile` in the resolver; resolver
precedence by cluster kind; ambient plumbing through
`SurfaceCapabilities`/`MediaQuery`; the one-policy-per-paragraph audit
(caret/hit-test/selection helpers take the policy as a required argument);
the unknown-ambiguous pin gate and its end-to-end test; env overrides;
diagnose provenance. **No text mutation of any kind.** Includes the pending
diagnose fix (measured ambiguous folded into the report). Gates: alloc,
paint, wire, bundle-size, plus property gates 2–5, 13–14.

**P2 — source-preserving display lowering.** Emoji-sequence parsing inside
grapheme clusters; `joined|summed|unknown` observation and the
split-authorization conjunct; `TextProjection`/`PreparedParagraph`
two-stage preparation as the paragraph API's own choke point;
`PreparedCluster` structure with the mapping properties;
source-coordinate selection with boundary affinity; the no-break-group
wrapping rule; per-object memo caching with the two fast paths; editable
widgets excluded. Property gates 1, 6–12, 15.

**P3 (future, separate RFC if pursued) — declare tier.** OSC 66 `w=` on
terminals that support it (kitty, foot), sitting above policy: declare the
model's width instead of adapting to the terminal's. Also the natural home
for revisiting mode 2027 emission (not detection).

## 11. Decisions recorded

1. The invariant is the **bounded cell algebra** (≤ 2 cells per display
   atom), not universal geometry. Width *classification* may follow the
   measured surface; atom *width* never exceeds two.
2. **Boundary rule**: 0/1/2-expressible disagreement → resolver policy,
   bytes unchanged. Beyond-algebra expansion → lowering. Nothing else ever
   rewrites text.
3. **Source is canonical.** Lowering is a display projection with a mapping;
   copy, semantics, and selection answer from source. A projection may
   change what is painted, never what is copied or announced.
4. **Width axes bind to cluster kinds** via the resolver precedence ladder;
   a selector inside a composite never takes the simple-sequence width, and
   probe representatives vote only within their own class.
5. Measurement (CPR) outranks negotiation (DECRQM) and identification
   (`TERM_PROGRAM`); adaptation keys off measured behaviour only.
6. **Agreement or `unknown`**, per axis, with an **atomic batch**: anomalous
   replies discard the battery. Summing is established by the
   component-sum inequality, per sequence.
7. **Summed authorizes nothing by itself**: `split` additionally requires
   the policy to predict every measured component; otherwise `preserve`.
   Lowering's contract is cell geometry, not pixel equivalence.
8. Unprobed = today's bytes. No adaptation without evidence.
9. The pin is permanent infrastructure — engaged for `two` *and* `unknown`
   ambiguous, every unauthorized sequence, and the unparameterizable tail;
   its coverage of the unknown-ambiguous case is test-verified, not
   assumed.
10. `emojiPresentation: one` vetoes the emoji-presentation class only; CJK
    width is never affected by emoji axes.
11. The variation-sequence axis is named for the **sequence**
    (`emojiVariationSequence`), not the selector; stripping selectors is
    reserved for demonstrated rendering defects.
12. Lowering is structural (parse → identify → lower → resolve), never
    string replacement on U+200D; non-emoji ZWJ is untouchable; components
    keep their attachments.
13. **One effective policy per paragraph**, passed explicitly to every
    geometry consumer; per-surface layout passes own their policies.
14. **Selection state lives in source coordinates**; display coordinates
    exist for hit testing and painting; endpoints never rest inside a
    source cluster.
15. **A lowered cluster is a no-break group** for wrapping, truncation,
    clipping, hit testing, and painting; component breaks only when the
    group alone exceeds the line.
16. `PreparedText.logicalText` is the post-sanitization canonical text.
17. Policy equality is operational; provenance is diagnostic metadata
    beside the value, never in cache keys or equality.
18. Editable-text lowering is deferred until value↔display offset mapping
    exists; its local mis-rendering on summing terminals is a documented
    known limitation, bounded by the pin.

## 12. Open questions for review

1. **Final representative list** — classes and criteria are fixed (§6.1);
   the concrete code points are an implementation choice to be recorded in
   the probe's doc comment with per-glyph rationale.
2. **P1 audit scope** — the sweep for width resolution constructed outside
   the render-object path (§6.3) may surface helpers whose conversion is
   mechanical or may reveal a deeper editing-path dependency; if the
   latter, the P1 PR reports it rather than absorbing it silently.

## 13. Acknowledgements

Two rounds of peer review (2026-07-27) shaped this RFC materially: the
bounded-algebra framing, the boundary rule, VS16-as-policy,
source-preserving lowering, probe confidence and batch atomicity, the
resolver precedence ladder, the split-authorization conjunct, the
source-coordinate selection model, the no-break-group rule, and most of §9.

## 14. References

- Probe data: `fleury diagnose --probe`, terminal A + Warp, 2026-07-27 (§3).
- ucs-detect corpus and per-terminal survey (jquast, 2025-11 / 2026-06):
  <https://ucs-detect.readthedocs.io/results.html>,
  "Perfecting Terminal Character Width Using Correction Tables" (2026-06-07).
- Hashimoto, "Grapheme Clusters and Terminal Emulators" (2023-10-02):
  <https://mitchellh.com/writing/grapheme-clusters-in-terminals>.
- kitty text-sizing protocol (OSC 66):
  <https://sw.kovidgoyal.net/kitty/text-sizing-protocol/>.
- Charm ultraviolet `3a9b1e43` (2026-07-02): mode-2027-gated width method —
  the negotiation-shaped peer solution this RFC's measurement approach
  supersedes.
- UAX #11 East Asian Width (17.0.0), UTS #51 (emoji, incl. ZWJ/modifier
  sequence data), UAX #29 (segmentation).
- In-tree: `width_resolver.dart`, `width_tables.dart` + generator +
  freshness gate, `terminal_probe.dart`, `ansi_renderer.dart`
  (`needsWidthPin`), `capabilities.dart`, `diagnostics.dart`,
  `media_query.dart`.
