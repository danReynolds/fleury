# RFC: Terminal Accessibility — Opportunity Assessment & Recommendation

**Status:** Assessment (pre-launch). **Recommendation: defer the build, bank the option.**
**Date:** 2026-06-30. **Author:** advisory pass, backed by a deep-research sweep
(102 agents · 20 sources · 25 claims adversarially verified, 21 confirmed / 4 killed).

---

## TL;DR

- **The opportunity is real and well-documented.** "Genuinely accessible terminal
  apps" is an unmet need confirmed by peer review (CHI 2021), W3C, and GitHub's
  own engineering team. There is **no "terminal ARIA"** and **no shipped
  structured-tree-native solution** at the framework level.
- **Fleury's architecture is the production-proven foundation — and it's already
  built.** The model that ships today (AccessKit, Chromium) is structurally
  identical to ours: an app-maintained tree of roles/labels/values/actions/focus,
  fed by incremental deltas, translated into each OS's native a11y API for the
  user's *existing* screen reader. We already produce that tree (for tests, MCP,
  and the browser ARIA surface).
- **But native, in-terminal accessibility is genuine R&D, not an easy win** — two
  unsolved pieces (below), plus real assistive-technology user testing — and the
  competitive urgency is **low** (competitors are shipping point-fixes, not racing
  a structured framework).
- **Recommendation: do not build native terminal a11y now. Bank the option
  instead** — it costs almost nothing because the expensive part (the
  architecture) is already done and doesn't rot. Concretely: (1) validate the
  browser-companion path so the one claim we *can* make is true, not hopeful;
  (2) keep the architecture a11y-ready (mostly already true); (3) this doc.

---

## Verification status — the structural layer is now tested (2026-06-30)

Path A's first "do-now" item is **done**: there is now an invariant-based
accessibility suite — [`packages/fleury_web/test/accessibility_test.dart`][suite]
(12 tests, runs in CI via `dart test -p chrome`). It asserts the things that make
the ARIA projection *accessible*, not just present:

- every interactive node gets an **accessible name** (the #1 a11y failure mode);
- every emitted `role` is a **valid ARIA role**;
- **states** (checked/expanded/selected/disabled) and **live regions**
  (status/progress/log → `aria-live`) map correctly;
- the **focused** node is exposed as a focusable element;
- **no duplicate ids** and **required structural children** (a list contains its
  list items) hold;
- the visual cell grid stays **`aria-hidden`** (no double-exposure);
- and a **future-guard**: *every* `SemanticRole` resolves to valid-ARIA-or-a-plain
  container, so a role added later can't ship without an accessibility decision.

**All pass** — fleury_web's accessible DOM is structurally sound. This converts the
"you already largely support this" claim from inference into a tested, CI-protected
fact at the projection layer.

Remaining verification layers (not yet built): **(a)** an axe-core / Playwright
WCAG-engine pass for generic rule coverage (a separate Node toolchain), and
**(b)** AT-user testing — the efficacy gate before any loud claim.

[suite]: ../../packages/fleury_web/test/accessibility_test.dart

---

## Why this is even a question: the moat is already dug

The reason deferral is low-regret is that the **hard, expensive, hard-to-retrofit
part is already done.** Fleury maintains a first-class semantic/accessibility tree
(roles, labels, values, actions, focus) and fine-grained change tracking — not for
accessibility, but as a byproduct of being agent-drivable, testable, and
browser-served. The research confirms that *this exact tree-plus-deltas model is
what the production a11y stacks use.* So we are not deciding "build the foundation
now or lose it." The foundation is permanent and free. We are only deciding *when*
to add the additive layer on top — and that can wait with no penalty.

## The opportunity (validated)

| Finding | Confidence | Source |
| --- | --- | --- |
| The #1 terminal-a11y problem is **missing semantic structure** (no roles/headings/landmarks; users parse linearly — "extremely inefficient") | High (3-0) | CHI 2021 (Google Research), W3C WCAG2ICT, GitHub Eng |
| Spinners / progress bars / decorative Unicode are read as gibberish; redraw-spam **freezes/skips** NVDA·JAWS·Narrator | High (3-0) | CHI 2021, GitHub Eng, real NVDA-user reports |
| **No "terminal ARIA."** OSC 133/FinalTerm marks only 4 coarse *shell* boundaries; zero app-level role/value/focus. No comprehensive standard. | High (3-0) | iTerm2 spec, Contour docs, W3C |
| Everyone's shipping **point-fixes**: GitHub CLI, OpenAI Codex (fix filed by an NVDA user, Feb 2026), Gemini CLI all added "screen-reader modes" — none structured-tree-native | High (3-0) | project issue trackers |

**Read:** the pain is acute and validated by real users; the structured-tree
opportunity is open; the window is narrowing toward *point-fixes*, not toward a
framework that does it properly — which is the lane only we are positioned for.

## Fleury is uniquely positioned

The cross-platform model that ships in production — **AccessKit** (egui, Bevy,
Servo, Slint, Godot) and **Chromium** — represents accessible UI as a tree of
nodes with integer ids, roles, labels/values, AT-requestable actions, and a focus
node, fed by **incremental `TreeUpdate` deltas**, translated into each OS's native
API (UIA / NSAccessibility / AT-SPI). It delivers to the user's *own* screen
reader — **not** custom TTS/braille. **That is Fleury's accessibility tree,
verbatim.** No terminal-only framework (Ink, Bubble Tea, ratatui, tcell) has a
semantic model to project from; we do.

## What it would actually take (the two hard parts)

This is where "not an easy win" lives. Both surfaced from adversarial verification:

1. **An announcement-policy layer — change-tracking is necessary but NOT proven
   sufficient on its own.** The strongest form of our hypothesis ("change-tracking
   eliminates redraw-spam re-announcements") was **refuted (0-3, 1-2)**: the
   sources describe deltas for *performance and event generation*, not for
   *suppressing screen-reader re-announcements*. The production systems pair deltas
   **with** a deliberate policy layer (Chromium fires exactly one
   `AXLiveRegionChanged` per change, scoped focus/value events, skips unchanged
   nodes). So we'd need to build that targeted-event / live-region layer on top of
   our change tracker — and *prove* it produces clean output, empirically.

2. **The terminal delivery channel — genuinely unsolved.** AccessKit/Chromium push
   into OS a11y APIs that **GUI windows own**; a TUI process inside a terminal
   emulator owns no accessible window. Options:
   - **(a) Our existing browser/ARIA surface as a companion accessible view** — and
     a Google technical disclosure proposes exactly this pattern. *Lowest risk;
     mostly already built.*
   - (b) register a native a11y provider/window ourselves (hard, per-platform);
   - (c) ride an emerging emulator bridge (Ghostty already exposes terminal
     contents through native platform a11y APIs — partner or competitor).
   - Plus a macOS wrinkle: alt-screen fullscreen breaks VoiceOver/Speak Selection;
     a non-fullscreen default preserves them.

3. **And:** decorative-glyph suppression, and **real AT-user testing** before any
   claim is made loudly.

## The two paths

| | Path A — Browser-companion | Path B — Native in-terminal |
| --- | --- | --- |
| Effort | **Low** — ARIA surface + coverage oracle already exist; needs a real screen-reader validation pass | **High / R&D** — announcement layer + delivery channel + per-platform + AT testing |
| Risk | Low | Real (sufficiency + delivery both unproven) |
| Claim it unlocks | "Accessible by serving to a browser" — true today, unique among TUI frameworks | "The first genuinely accessible TUI" — the moonshot |
| Timing fit | Now (cheap) | Post-launch |

## Recommendation & rationale

**Defer Path B. Do the cheap, option-preserving work now:**

1. **Validate Path A** — one real screen-reader session against a served Fleury app
   (the `aria-hidden` grid + semantic DOM + coverage oracle are already in
   `fleury_web`). If it holds up, "accessible via the browser surface" becomes a
   *tested* claim, not a hopeful one — a line no other TUI framework can make, for
   near-zero cost. If we won't test it, we don't claim it loudly.
2. **Keep the architecture a11y-ready** — mostly already true; just don't make
   decisions that demote the semantic tree or change tracking from first-class.
3. **Bank this doc** — it stakes the position and de-risks the future "go" decision.

**Why defer the build, specifically:**
- **Pre-launch focus.** A11y is not one of the headline pillars (framework / agents
  / two-surfaces / performance). Sinking weeks of R&D here now trades against the
  launch.
- **Low urgency.** No one is building structured-tree TUI a11y; point-fixes don't
  preempt it; and because our foundation is done, we can move *fast* if someone
  does. Waiting is low-regret.
- **Credibility needs the build.** A11y-as-differentiator only works if it's real
  and AT-tested — which *is* the expensive part. Claiming it before that is worse
  than silence.

**Net:** the moat is already dug, so we get to pick the timing. The disciplined
pre-launch move is to bank the option, make only the one claim we can back cheaply,
and spend the R&D when there's post-launch bandwidth and an AT-user partnership.

## When to revisit (triggers)

- A competitor ships **structured-tree** (not point-fix) TUI accessibility.
- An **assistive-technology user / org partnership** materializes (the only way to
  validate efficacy honestly).
- Post-launch bandwidth frees up.
- A **customer or regulatory** requirement (EAA, Section 508, EN 301 549) makes it
  a gating need.
- A terminal-emulator **a11y bridge** (e.g. Ghostty) matures into a real delivery
  channel, collapsing Path B's hardest piece.

## Evidence quality / honest caveats

- The flagship empirical study is **small** (12 developers); peer-reviewed and
  corroborated, but not large-scale demand data.
- The AccessKit/Chromium precedent is **GUI/desktop**, so "it transfers to
  terminals" is a sound **inference**, not a cited fact for the terminal case.
- Two of the four killed claims were the *exact* "change-tracking alone solves
  redraw-spam" hypothesis — captured above as the thing to prototype, not assume.
- Linux console readers (Orca, Speakup, BRLTTY) were **not** individually validated
  here; the verified behavior centers on macOS VoiceOver and NVDA/JAWS/Narrator.

### Sources
CHI 2021 — Accessibility of Command Line Interfaces ·
github.blog — building a more accessible CLI ·
accesskit.dev + docs.rs/accesskit (TreeUpdate) ·
Chromium accessibility overview ·
iTerm2 escape-code spec / Contour OSC 133 docs ·
openai/codex#11823, anthropics/claude-code#11002, google-gemini/gemini-cli#5148 ·
ghostty-org/ghostty#2351.
