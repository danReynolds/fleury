# DX + Cohesion Re-audit

**Date:** 2026-06-11 (baseline: dx-cohesion-findings-2026-06-03)
**Method:** Four parallel contract audits across the catalog (capability +
sanitization; copy/export + disposal; theming + semantics; prior-fix
verification + catalog delta), with agent-reported claims spot-verified
against source before recording. Catalog: 57 fleury_widgets modules + 39
core widget modules; zero widgets added since June 3 (growth was
storybook infrastructure).

> Headline: **three of the eight June-3 open items closed quietly, one
> resolved itself, and the two that remain open are exactly the two
> biggest — capability fallback (untouched) and sanitization (wider than
> recorded).** Every Tier-1 fix holds.

## The matrix, June 3 vs today

| Contract | June 3 | Today | Verdict |
| --- | --- | --- | --- |
| Copy/selection/export | ~50%, **3 incompatible patterns** | **1 unified pattern** (`onCopy` callback + per-widget typed `*CopyResult`), 19 widgets | **CLOSED** — converged (see note) |
| Disposal lifecycle | ~35%, 4 named gaps | **34/34 resource-owning stateful widgets correct**, incl. all four named (Autocomplete, CompletionTextInput, CommandPalette, SearchPanel) | **CLOSED** |
| Snapshot `toString()` | `Instance of …` | Readable (`inspection.dart:236` delegates to `toDebugString()`) | **CLOSED** |
| Doc-comment inversion | core ~20% vs widgets ~80% | core ~67% vs widgets ~82% | **Mostly closed**; stragglers: text_area, animation_builder, presence, ticker_mode |
| Dead chart theme tokens | `barChartPalette` etc. defined, unconsumed | **Deleted** — tokens no longer exist | **RESOLVED** (by deletion; charts now have no theme tokens at all — see open items) |
| Semantics | ~86% | 51/53 fleury_widgets (96%); charts still shallow | Strong; shallowness **still undocumented** |
| Sanitization | ~46%; Autocomplete gap | 23/57; **the gap is a class, not a widget**: autocomplete, completion_text_input, menu, select all render option labels unsanitized | **OPEN — WIDER than recorded** |
| Capability fallback | ~6% (3/52) | **3/57 — same three widgets** (data_table, image, markdown_text); 15 glyph-rendering widgets with none | **OPEN — UNCHANGED, still the critical drift** |

Prior-fix verification: ListenableBuilder `listenable:` ✓, no
ScreenController ✓, nullable-`onChanged` disable convention ✓, ListView
`itemBuilder` arity documented as intentional ✓.

Still missing from June 3 Tier 1: **no FleuryApp multi-screen example in
`packages/fleury/example/`** (reference implementation lives in
`fleury_example_console`; the dx-probe seed was never promoted).

## Corrections to agent-reported numbers (recorded for honesty)

- An auditor reported all 31 `*Style` fields in `component_theme.dart`
  as dead. **False positive**: the fields feed the `resolve*` methods
  (`controlFocusStyle ?? theme.focusedStyle`), which are consumed by the
  10 themed widgets. Encapsulation, not dead code.
- Coverage percentages that pool core infrastructure widgets (align,
  repaint_boundary, theme, …) understate real coverage — semantics and
  theming are not applicable contracts for most of those. The honest
  denominators are the per-contract applicable sets used above.
- "Copy coverage 33% (down from 50%)" compares different denominators;
  the real change is pattern unification. Remaining copy-less widgets
  are mostly ones where copy is arguable (charts, pickers, progress) —
  the deliberate-decision list below covers the few real candidates.

## A decision worth recording

June 3 recommended converging copy on `controller.copy() -> Result`
(DataTable's then-pattern). The catalog instead converged on the
**`onCopy` callback + typed result** shape — uniformly, including
DataTable and MarkdownText. Consistency was the goal and consistency
exists; the June 3 recommendation is moot. Record in the decision log:
the copy contract is `onCopy: void Function(XCopyResult)` with a typed
per-widget result.

## Prioritized plan

**P0a — sanitize the option-label class (small, security-adjacent).**
Four widgets render provider/app-supplied option labels raw:
`autocomplete.dart` (~238), `completion_text_input.dart` (~343),
`menu.dart` (~408/423), `select.dart` (~501/709). Same fix shape in
each: sanitize the label on the render path, plus a regression test per
widget asserting escape-sequence stripping. This closes the June 3 gap
and its three newly-found siblings in one pass.

**P0b — capability fallback: DESIGN FIRST (see
[capability-fallback-design](capability-fallback-design.md), 2026-06-11).**
The 3/57 number conflates three problems: color fallback is already
centralized in the renderer (100%, zero widget code), behavioral
capabilities are 3/3 covered, and the real gap is glyph-repertoire
fallback — generalized via a GlyphTier in MediaQuery + ascii tiers in
the shared painting primitives, NOT per-widget requirement plumbing.
Original framing kept below for the record:** 15 glyph-rendering widgets (canvas, line_chart, bar_chart,
sparkline, gauge, heatmap, calendar_heatmap, histogram, braille,
half_block_buffer, digits, color_picker, json_view, diff_view,
code_view) assume glyph/color support with no
`resolveCapabilityRequirement` handling. Roll out from the `Image`
exemplar. This is the least-realized differentiator pillar and pairs
with the post-MVP terminal-matrix work; it is the largest single item
between here and the API freeze.

**P1 — promote the app-kernel example.** Distill the
`fleury_example_console` multi-screen + commands structure into a small
`packages/fleury/example/` app plus a "build a multi-screen app"
walkthrough. The headline differentiator still has no crib-able example
in the package a newcomer opens first. (June 3 Tier 1 item, last one
standing.)

**P1 — charts theming decision.** The dead tokens were deleted rather
than consumed, leaving charts with hardcoded palettes and no theme
surface. Decide once: either re-introduce chart palette tokens that the
chart widgets actually consume, or record that charts are
constructor-prop-styled by design. Either is defensible; the current
state (neither) is the only wrong answer.

**P2 — small closeouts.**
- Document chart semantic shallowness as intentional (one doc-comment
  pass over the chart widgets).
- Finish core doc stragglers (text_area, animation_builder, presence,
  ticker_mode).
- Decide the copy-stragglers list: `tree` (tree_table has copy, tree
  does not) and `text_area` are the only real candidates.

## Relation to the core audit

This re-audit completes step 1 (re-verification) of
[core-api-dx-audit-readiness](core-api-dx-audit-readiness.md). The
remaining audit scope is unchanged: the design rulings (virtualization
API defaults, state-story guide) and the never-audited areas (focus
accessibility, error semantics, navigator metadata, action-invocation
UX, const discipline, semver policy). With disposal and copy closed,
the mechanical-rollout surface is down to capability fallback +
sanitization + the theming decision.
