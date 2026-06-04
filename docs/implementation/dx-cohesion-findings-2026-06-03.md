# Fleury DX + Cohesion Findings

**Reviewer role:** Independent DX + architecture-cohesion audit
**Date:** 2026-06-03
**Priority frame:** Arch + feature set + DX first; perf second/ballpark (per maintainers).
**Method:** (1) Built a representative ~250-line multi-screen dev-tool app
(`dx-probe/`) from a newcomer's footing, logging every friction point and every
analyzer round-trip; (2) wrote headless tests including a semantic-tree query;
(3) ran two parallel systematic audits across the core + ~57-widget catalog for
contract consistency and API ergonomics. Findings below are triangulated across
all three.

> Headline: **The designs are right; the propagation is uneven.** Almost every
> issue is a *scale/consistency* problem (an exemplar exists, but it hasn't been
> applied uniformly), not a *design* problem. That's the encouraging read — the
> fixes are mechanical rollouts against known-good patterns, not redesigns.

---

## 0. The single best result: the semantic differentiator is real and free

The ~250-line probe app, with **zero `Semantics(...)` annotations written by
me**, produced this (trimmed):

```
nodeCount: 13, roleCounts: {app:2, command:4, region:1, screen:3, text:2, textField:1}
app "Service Monitor" {screenCount:3, activeScreenId:services, commandCount:4}
  command "Go to Services" actions:[activate] {shortcut: Ctrl+1}
  command "Clear filter" value:"Reset the service filter" actions:[activate]
  screen "Services" selected:true actions:[navigate]
    region "Services commands"
      textField "type to filter services…" actions:[clear, focus]
        {selectionBase:0, clipboardPolicy:allowed, redactedValue:false, ...}
      text "[Ctrl+1] Go to Services · [Ctrl+2] Go to Logs · ..."
```

An agent, test, or accessibility layer can read this and operate the app by
role/label/action. **This is the frontier bet from the assessment, working
end-to-end, contributed automatically by the app kernel + widgets.** It is also
the most adoption-invisible differentiator — so the priority is to make it
*feel*-able (see §4).

Testing DX is genuinely strong: headless `pumpWidget` → `renderToString()` →
`semantics()` / `semanticInspectionSnapshot()`, no terminal required. The probe's
3 tests passed first try.

---

## 1. The friction my newcomer build actually hit (empirical)

In ~250 lines I hit **three "Flutter muscle-memory is wrong here" divergences**,
each caught only at compile time:

| # | I wrote (Flutter instinct) | Reality | Why it stings |
| --- | --- | --- | --- |
| 1 | `ListenableBuilder(listenable: x)` | param is `animation:` | The class is *named* after `Listenable`, but the param is `animation` — and a `Listenable` isn't an animation. Diverges from Flutter's exact same class. |
| 2 | `ScreenController.of(context)` | `ScreenControllerScope.of(context)` | Flutter is `Foo.of(context)`; Fleury splits into `FooScope.of(context)` for app-kernel scopes. |
| 3 | `itemBuilder: (ctx, i) =>` | `(ctx, i, bool selected)` | Selection-aware (and documented), but breaks Flutter's `ListView.builder` arity. |

These are the central DX theme: **Fleury is ~95% Flutter, so adopters bring full
Flutter muscle memory — and the 5% divergences surprise them with nothing but a
compile error to catch it.** Being 95% Flutter is in some ways harder than being
70% Flutter; the closer the mirror, the more costly each divergence. This is the
*single most important DX lever* because "Flutter devs feel at home" is the whole
adoption thesis.

Other friction logged while building:
- **No app-kernel example to crib from.** None of the 8 core examples or 3 widget
  demos use `FleuryApp`/screens/commands — the headline differentiator vs Nocterm.
  I assembled it by reading `app.dart`/`commands.dart`/`status.dart`.
- **Switching screens from a command is non-obvious.** `CommandContext` exposes
  only `commands` + `buildContext`; reaching the `ScreenController` requires
  `ScreenControllerScope.of(ctx.buildContext!)` — discovered by source-reading.
- **`snapshot.toString()` returns `Instance of 'SemanticInspectionSnapshot'`** —
  to see the differentiator you must call `toInspectionJson()`. Small, but it's
  the first thing a curious dev tries.

---

## 2. Contract-cohesion matrix (systematic audit)

Across the ~57-widget catalog:

| Contract dimension | Coverage | Verdict | Worst drift |
| --- | --- | --- | --- |
| **Semantics** | ~86% | **Strong, consistent** | Charts intentionally shallow (fine, but undocumented as such) |
| **Disposal lifecycle** | ~35% but exemplary where present | Strong pattern, partial rollout | Missing on Autocomplete, CompletionTextInput, CommandPalette, SearchPanel |
| **Redaction / untrusted-output** | ~46% | Partial | Autocomplete doesn't sanitize `displayStringForOption` (injection risk if options are untrusted) |
| **Selection / copy / export** | ~50%, 3 incompatible patterns | Fragmented | `controller.copy()` (DataTable, good) vs `onCopy` callback (ToolCallCard) vs none (MarkdownText) |
| **Theming** | ~35% standard / ~19% component | Drifted + dead code | Chart theme defaults (`barChartPalette`, `lineChartPalette`, …) defined in `component_theme.dart` but **never consumed** |
| **Capability fallback** | **~6% (3/52)** | **Critical drift** | Canvas, LineChart, BarChart, ColorPicker, JsonView assume glyphs/colors with no fallback |

**Exemplars to roll out *from*:** semantics — `LogRegion`, `DataTable`, `Form`;
disposal — `TextInput` (28 checks), `Form`; capability — `Image.dart` (the *only*
good example); copy — `DataTable` (`DataTableCopyResult`); theming — `DataTable`,
`ProgressBar`.

---

## 3. The pattern that unifies §1, §2, and the prior assessment

Three independent angles — the terminal-matrix evidence (assessment §5), the
widget capability audit (~6%), and my hands-on build — **converge on one
conclusion: the capability / terminal-correctness pillar is the least-realized
differentiator.** It exists as architecture (`capability_requirements.dart`) and
one exemplar (`Image`), but it has not propagated to the catalog or been
validated against real terminals. Semantics is the opposite: designed *and*
propagated *and* proven end-to-end.

So the differentiators sort into two buckets:
- **Realized & provable:** semantics, testing, app kernel, retained-perf-on-data.
- **Architected but unpropagated/unvalidated:** capability fallback, unified
  copy/selection, consistent theming, terminal compatibility.

The work is to move bucket two into bucket one — propagation, not invention.

---

## 4. Prioritized recommendations (DX/arch first, per your priorities)

**Tier 1 — highest leverage, mostly low effort:**

1. **Kill the Flutter uncanny-valley divergences.** Rename/alias to match Flutter
   exactly where the class *is* Flutter's: `ListenableBuilder` should accept
   `listenable:` (keep `animation` as a deprecated alias). Add `FleuryApp.of` /
   `ScreenController.of` aliases alongside the `…Scope.of` forms. Where a
   divergence is intentional (selection-aware `itemBuilder`), surface it in the
   error path or a lint, not just a doc comment. **This protects the entire
   adoption thesis and is a day of work.**
2. **Ship the missing app-kernel example + a getting-started guide.** The headline
   differentiator has no demo. The probe app I built (`dx-probe/bin/main.dart`) is
   a ready-made seed — promote a cleaned version into `packages/fleury/example/`
   and write a "build a multi-screen app" walkthrough. Highest onboarding ROI.
3. **Fix the doc-comment inversion.** Core widgets (~20% `///`) are *less*
   documented than `fleury_widgets` (~80%) — backwards, since core is harder to
   learn. Prioritize `TextInput`, `TextArea`, `ListView`, `FleuryApp`,
   `AppCommand`, and the controller-ownership pattern ("if `controller` is null,
   the widget creates and owns one").

**Tier 2 — cohesion rollouts against existing exemplars:**

4. **Capability-fallback rollout.** Make `resolveCapabilityRequirement()` (per the
   `Image` exemplar) a required part of the widget contract for any widget that
   assumes glyphs/colors: Canvas, charts, ColorPicker, JsonView. This is the
   pillar that most needs realization, and it pairs with the real-terminal-matrix
   validation from the main assessment.
5. **Unify the copy/selection API.** Pick the `controller.copy() → Result` pattern
   (DataTable) and converge ToolCallCard/MessageList/MarkdownText onto it.
6. **Finish the disposal-lifecycle rollout** to Autocomplete, CompletionTextInput,
   CommandPalette, SearchPanel.
7. **Theming: consume the dead chart palettes** (or delete them), and define a
   theming-coverage bar so widgets stop hardcoding styles.
8. **Sanitize `Autocomplete` options** (untrusted-completion injection gap).

**Tier 3 — make the differentiator feel-able:**

9. Give `SemanticInspectionSnapshot` a readable `toString()`, and ship a
   copy-pasteable "drive your app from a test / from an agent via the semantic
   tree" demo. This converts the strongest-but-invisible differentiator into
   something an evaluator sees in five minutes.

**Explicitly deferred (your call): perf.** The one perf-adjacent item worth
folding into arch is finishing the paint-only/layout invalidation audit — it's an
invalidation-contract consistency issue, the same species as everything above.

---

## 5. Bottom line

DX is **good and, in the testing + semantics paths, genuinely excellent** — but
it has a sharp, fixable edge: the closer-than-anyone Flutter mirror means small
divergences hurt more than they would in a less-faithful framework, and the
flagship features (app kernel, semantics) are under-exampled. The architecture's
cohesion is strong where it's been propagated (semantics, disposal) and drifted
where it hasn't (capability 6%, theming, copy). None of this is a design flaw —
it's the predictable unevenness of a large surface built fast, and the exemplars
to fix against already exist in the tree. Close the Flutter-divergence gap, ship
the app-kernel example, and roll the capability/copy/theming contracts out to
parity, and the "strong arch + features + DX" bar is met with room to spare.
