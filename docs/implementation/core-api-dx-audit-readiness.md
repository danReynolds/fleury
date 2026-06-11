# Core API/DX Audit — Readiness Assessment

Date: 2026-06-11. Written at the close of the perf/arch line (web
industry-leading plan, wire-efficiency plan, and perf closeout all
COMPLETE) as the consolidating entry point for the deferred core
API/DX audit. The audit itself has NOT run; this records what exists,
what it already knows, and what it must still decide.

## Status: deferred by design, inputs actively harvested

The general core audit (widget API surface, effects system, app
kernel, text editing, DX cohesion) was explicitly deferred in
`web-industry-leading-plan.md` until the frame-path work landed — that
condition is now met. Findings are scattered across four source docs;
no formal audit milestone exists in `milestones.md` yet.

## Source documents (read in this order)

1. `dx-cohesion-findings-2026-06-03.md` — the contract inventory.
   Coverage percentages per cross-cutting contract and Tier 1/2/3
   recommendations.
2. `widget-api-ergonomics-audit-2026-06-08.md` — constructor-level
   ergonomics; highest-impact sign-offs already landed (nullable
   `onChanged` disables across form controls, semantic labels on
   display widgets). Verdict: no broad DX emergency; remaining work is
   evidence-driven polish.
3. `dx-peer-assessment-2026-06-08.md` — competitive DX positioning
   (P0: newcomer path; P1: devtools workflow, user-facing CLI verbs,
   catalog contracts, state-story guide; P2: lints, web onboarding).
4. `decision-log.md` — API stability principles already decided
   (private renderers, lifecycle rules, screen-registry removal).

## What is already fixed (do not re-audit)

- ListenableBuilder naming/param parity with Flutter.
- Framework screen controller removed; app sections are ordinary
  widgets (app-kernel DX review, 2026-06-08).
- Nullable-`onChanged` disable convention across form controls;
  `MultiSelect<T>` controlled-set contract; semantic `label` on
  Table/DataTable/ProgressBar.
- Keyed-row recycling anti-pattern documented on `RepaintBoundary`
  (2026-06-11).

## Open inputs the audit must rule on (inventory)

Contract-propagation rollouts (from the June 3 findings — the
percentages are that audit's measurements and need re-verification):

- Capability fallback: ~6% of widgets (3/52); Canvas, charts,
  ColorPicker, JsonView lack it. The single most critical drift.
- Copy/selection API: three incompatible patterns
  (`controller.copy()` vs `onCopy` callback vs absent). Pick one
  (June 3 recommendation: `controller.copy() -> Result`).
- Disposal lifecycle: strong pattern, ~35% rollout; missing on
  Autocomplete, CompletionTextInput, CommandPalette, SearchPanel.
- Theming: dead chart-palette tokens defined but never consumed;
  uneven coverage.
- Sanitization: Autocomplete `displayStringForOption` injection gap.
- Semantic differentiator visibility:
  `SemanticInspectionSnapshot.toString()` unreadable; no
  copy-paste-able semantic-drive demo.
- `itemBuilder` arity divergence from Flutter (documented, accepted —
  re-confirm at audit time).

Design questions recorded as core-audit inputs by the perf line:

- Data virtualization as the default API path (2026-06-11, SB.11):
  lazy row/column providers; `TreeTableSearchIndex` should derive
  text on demand or store offsets (partially landed 2026-06-11 — the
  index now retains a shared blob + spans instead of per-row
  rows/text; the windowed/provider row-building API question remains);
  whether TreeTable needs a render island.
- State-management story needs a concise authored guide (setState
  local / ChangeNotifier shared / TaskController async / commands for
  app actions) — the pieces exist, the narrative doesn't.

## Areas with NO recorded audit input (must be scoped in or out)

- Render-object public surface (currently private by decision; the
  audit should confirm or define extension points).
- Focus traversal/accessibility alt-input paths.
- Error semantics: validation errors, error UI, boundaries.
- Navigator/route metadata, deep-linking, state restoration.
- Unified action-invocation UX across palette/menus/buttons.
- Constructor-signature review for accidental per-frame allocation
  (const discipline).
- Breaking-change/semver policy pre-freeze.

## Perf interface to the audit (the perf line is CLOSED)

Perf work is complete and protected (web readiness gate + wire gate +
byte-equivalence oracle). The audit should NOT reopen frame-path
performance. The only perf-shaped items it owns are API-design items:
the data-virtualization defaults above, and the const/allocation
discipline review. Anything else perf-related needs a real-app signal
first, not more synthetic rows.

## Suggested shape (for the maintainer to ratify, not a plan yet)

1. Consolidation pass: re-verify the June 3 coverage numbers against
   today's catalog (three months of drift).
2. Rule on the recorded design questions (one decision doc each).
3. Contract-propagation rollouts as mechanical workstreams
   (capability fallback first).
4. The no-input areas triaged into audit-now vs post-launch.
5. Exit: an API-freeze readiness statement feeding
   `adoption-distribution-ecosystem.md` (public docs are blocked on
   freeze).
