# Fleury External Assessment

**Reviewer role:** Independent framework/architecture assessment
**Date:** 2026-06-03
**Scope:** Quality today, foundations, architecture, ecosystem position, top-tier-2026
competitiveness, and where to take it next.
**Method:** Read the strategy corpus (roadmap, why-fleury, cut-list, scorecards,
launch-hardening), execution journal + decision log; verified code directly
(`framework.dart`, `render_object.dart`, editing, semantics, rendering); ran
`dart analyze` (clean) and the core suite (1466 tests passing); spot-checked the
dirty-propagation pipeline and developer-facing API; mapped the mid-2026
cross-language TUI landscape.

> One-line verdict: **The engineering is top-decile and the foundations are
> sound enough that the framework question is essentially answered. The open
> questions are now strategic — which "top-tier" you mean — and evidentiary:
> several stated differentiators are architecturally complete but validated
> against a sample of roughly two.**

---

## 1. Quality today

What I verified rather than took on faith:

- **~72K LOC source / ~59.5K LOC tests; 1466 core tests passing; clean
  `dart analyze`; ~2 TODO/FIXME markers in the whole tree.** That test-to-source
  ratio and near-total absence of scaffolding markers is the strongest single
  signal here. Most "v1" frameworks are nowhere near this disciplined.
- **The decision log is ~190 rationale-backed durable decisions**, including a
  consistently applied "mutation-after-dispose is a lifecycle error" contract
  across ~25 controllers, and a deliberate paint-only vs. layout-dirty
  invalidation split. This is unusually rigorous record-keeping.
- **The benchmark lab is a genuine differentiator of *process*:** real peer
  fixtures in Go (Bubble Tea), Rust (Ratatui), Python (Textual), JS
  (Ink/OpenTUI), and Dart (Nocterm), with repeated-variance runs, and explicit
  annotation of which behavior is peer-owned vs. fixture-owned. That honesty is
  rare.

**Quality grade: A-.** The minus is not about the code — it's that the
*validation surface* is narrower than the green gates imply (see §5).

Context that shapes everything below: **this codebase is being built by a
long-running autonomous agent** ("Codex Self-Brief," journal lines 50–60). That
explains the meticulous docs/tests, and it means the benchmarks and the
"MVP complete" self-grade are produced and graded by the same system. The
methodology is sound but has not been adversarially checked by a different party
or run on different hardware.

## 2. Foundations

Strong and correctly chosen. The framework is built on real primitives, not
mimicry:

- **Genuine three-tree model** — real Element reconciliation with keys and
  GlobalKey reparenting, push-based `InheritedWidget` dependency tracking,
  depth-sorted `BuildOwner.flushBuild`. (`framework.dart`)
- **Real dirty propagation** — `markNeedsLayout` walks up, layout is
  constraint-cached and short-circuits on `!_needsLayout && same constraints`.
  Not a per-frame full-tree rebuild. (`render_object.dart:84–229`)
- **Grapheme-indexed text model** — real `TextEditingValue`/selection/undo/paste,
  not a string with a cursor int.
- **Parallel semantic tree** — ~60 roles, typed actions/state, wired into tester
  and inspector. This is the architectural bet, and it exists in code.
- **Clean terminal driver abstraction** — native/posix/windows/fake drivers,
  typed event stream, capability model, ANSI diff renderer with wide-char safety
  and synchronized output (DEC 2026).

The API surface is genuinely Flutter-shaped and pleasant (the counter
quickstart uses modern Dart dot-shorthands and reads like idiomatic Flutter).

**Foundations grade: A.** Nothing here needs to be torn up. The growth is
additive.

## 3. Architecture review

Four observations at the architecture altitude:

**(a) The retained-vs-immediate bet is the most interesting — and most
under-sold — result.** Conventional wisdom says immediate-mode (Ratatui) wins
TUI performance. The SB.3 numbers suggest a retained, diffing framework can be
*competitive with immediate-mode Rust* on app-shaped data workloads (DataTable
100k rows: Fleury page-move p95 ~772µs vs. Ratatui ~908µs median; OpenTUI ~9ms;
Textual ~97ms). If it survives real-terminal/SSH conditions, this is the single
most marketable, counterintuitive claim Fleury has — and it's currently buried
in a scorecard cell. **Caveat:** the real-terminal bottleneck is usually byte
emission and SSH latency, not CPU layout — which is either where retained
cell-diffing shines hardest, or where the abstraction tax surfaces. Unknown
until measured.

**(b) The paint-only / layout-dirty split is incomplete, and it's the perf
ceiling.** `markNeedsPaint()` still walks layout up via `_markNeedsLayoutUp()`;
only `markNeedsPaintOnly()` avoids it, and the team is auditing setters under
scenario pressure rather than all at once (decision-log rows 152–153). This is
the right method and it's tracked — but it's the thing that most threatens the
benchmark wins once apps get dense. Finishing it should outrank new widgets.

**(c) No native-core escape hatch.** OpenTUI's defining 2026 move is a Zig core
over C ABI — native perf with reactive ergonomics. Fleury is pure Dart. Fine
for app-shaped workloads (the numbers prove it), but it caps any literal
"fastest" claim. The "Hybrid Performance Islands" bet anticipates this; decide
explicitly whether render islands are real launch surface or a someday-bet.

**(d) Scope surface is enormous for the team size.** 57 widgets already, plus
seven "engines," plus agent widgets, plus capability contracts, plus replay
hooks. The non-goals warn against breadth-before-depth, and the widget count
suggests the temptation partly won. Breadth is cheap to claim and expensive to
keep correct (Textual's own DataTable/Unicode issues are the cautionary tale).
I'd rather see ~15 widgets bulletproof against the full contract
(semantics + selection + copy + capability fallback + tests) than 57 that are
mostly there.

**Architecture grade: A- / B+.** Excellent bones; the risks are concentration
(too broad) and an unfinished perf optimization that underpins the flagship
claim.

## 4. Ecosystem position (mid-2026)

Verified landscape: Bubble Tea v2 stable (June 2026, Charm-backed, MVU leader);
Textual 8.x (deepest app platform, but Textualize the company wound down in
2025); Ratatui 0.30 (Dec 2025, immediate-mode/perf standard, now `no_std`);
OpenTUI 0.3.x (pre-1.0 but ~11.6k stars, Zig core, powers OpenCode); Ink
(dominant in AI CLIs — Claude Code, Gemini CLI, Copilot CLI); Nocterm 0.6.0
(~338 stars, the only direct Dart peer).

| Axis | Fleury's standing |
| --- | --- |
| Dart TUI | Clear path to #1. Nocterm is pre-1.0, thin on app-kernel/data/diagnostics. **Winnable decisively.** |
| App-kernel maturity | Behind Textual (the bar); ahead of most. Real but young. |
| Data-widget perf | Surprisingly strong; a real differentiator *if* independently validated. |
| Semantic / agent-legible state | **Ahead of the entire field.** Nobody owns this frontier. |
| Capability / security contracts | Ahead of most; rare. **But reality-validated against ~2 terminals.** |
| Raw render throughput | Behind native-core (OpenTUI/Ratatui) by architecture; fine for app workloads. |
| Ecosystem / adoption / production users | Effectively zero, like Nocterm. Not an engineering gap. |

The frontier the whole field is moving toward — capability negotiation (now
table stakes), streaming, and especially **semantic / agent-legible UI state and
accessibility** — is exactly where Fleury has aimed. That read of where 2026 is
going is correct, and the semantic/accessibility frontier is genuinely unowned.

## 5. The evidence gap (the thing the journal exposed)

**"MVP complete / strict gate green" is achieved by shrinking the launch
terminal matrix to two environments — Apple Terminal and tmux — both on one
macOS machine** (tmux running inside Terminal.app). iTerm2, Kitty, Ghostty,
Alacritty, WezTerm, SSH, and all of Windows were explicitly deferred out of MVP
(journal ~20303–20577; decision-log rows 52–53).

This is a reasonable scoping call for a single-machine MVP gate. The problem is
that **terminal correctness/compatibility is one of the four pillars Fleury
wants to differentiate on**, and it now rests on two captures, neither
exercising the hard cases the pillar exists for (Kitty keyboard/graphics, Sixel,
SSH latency, multiplexer passthrough, Windows conhost). The green checkmark
reads as more validation than exists.

Generalized: **several stated differentiators are architecturally complete but
validated against a sample of roughly two.** Closing that gap is now
higher-leverage than any new feature.

## 6. Is Fleury competitive for "top-tier 2026"?

Two honest answers, because the north star holds two ambitions at once:

- **"Top-tier for Dart"** — yes, clearly, and close. Nocterm is the only peer
  and Fleury already exceeds it on app-kernel, data widgets, diagnostics, and
  test surface. This is winnable now.
- **"Top-tier cross-language"** — not yet, and the bar is structural, not
  technical. The biggest demand driver in TUI — AI agent CLIs — is consolidating
  entirely outside Dart (Ink/Node, Bubble Tea/Go, Ratatui/Rust, OpenTUI/TS).
  Fleury is building arguably the best agent-CLI primitives in the one language
  the agent-CLI builders aren't using. A Go/Rust/Python/TS developer has no
  reason to adopt Dart for a TUI unless Fleury offers a *frontier capability the
  incumbents lack*, productized so it's worth switching languages for.

The only realistic cross-language wedge is the one Fleury is already closest to:
**semantic / agent-legible / accessible UI state** — a structured representation
an agent or screen reader can read and drive, instead of scraping cells. Nobody
owns it. But today it's architecturally true and adoption-invisible: you can't
*feel* it in a five-minute trial. That's the gap between "real differentiator"
and "differentiator that wins users."

## 7. Where to take it — prioritized

Ordered by leverage, not effort.

1. **Pick the posture explicitly and write it down.** Recommended: *"Best-in-class
   for Dart, credibly excellent overall"* as the launch position, with the
   semantic/agent-legible frontier as the deliberately-resourced differentiation
   bet. Apply the same discipline already shown around "best TUI overall" to the
   word "top-tier" in the north star.
2. **Close the evidence gap on the differentiator pillars.** Real-terminal matrix
   (Kitty, Ghostty, WezTerm, Alacritty, iTerm2, SSH, tmux, Windows) becomes a
   *blocker* for any public terminal-robustness claim — not post-MVP. Treat
   "capability model: implemented, validation pending" as the honest status.
3. **Independently re-run the flagship benchmark.** The retained-vs-Ratatui
   result is the most marketable and most counterintuitive claim, and it's
   self-graded by the build agent. Re-run on different hardware, under real
   terminals and simulated SSH latency. If it holds, *lead* with it.
4. **Finish the paint-only / layout-dirty audit across the widget catalog.** It's
   the perf ceiling under density and it protects #3.
5. **Trade widget breadth for contract depth.** Define the Fleury widget contract
   and make a small set bulletproof against it; let the rest be post-launch /
   community.
6. **Make the semantic/agent-legible frontier *feel*-able.** Ship a demo where an
   agent or test drives a Fleury app through structured actions, and a stable
   inspection protocol. This is the difference between an architecture slide and
   a reason to switch.
7. **Get a hard Dart-AOT cold-start number.** The prompt↔fullscreen continuum and
   the agent-CLI use case both live or die on startup latency; it's
   under-validated and it's exactly what that audience optimizes for.
8. **Publish the benchmark harness and capability-contract design as standalone
   community artifacts.** Cheapest path to category leadership independent of
   adoption — the ideas travel even if the package stays Dart-niche.

Minor hardening: full-suite parallel test runs hit temp-space exhaustion and
process-test timeouts (journal ~20588–20611), forcing `--concurrency=1` for
integration tests. Worth fixing before external contributors hit it.

## 8. Bottom line

Fleury is a genuinely impressive piece of work — the execution discipline is the
rarest ingredient and it's clearly present. The engineering question is
essentially answered, so the leverage now is almost entirely (a) strategic —
choosing which "top-tier" you mean and concentrating the frontier bet instead of
spreading across the catalog — and (b) evidentiary — making the validation
surface as real as the architecture. Do those two things and "best Dart TUI
framework" is yours to lose, with a credible, non-hand-wavy path toward
cross-language relevance through the one frontier nobody else owns.
