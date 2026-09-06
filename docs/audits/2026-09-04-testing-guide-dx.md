# Testing guide DX review

Implemented the approved frame and semantic-action changes after rewriting the
Testing guide. The guide uses a small counter first, then a draft editor with
controlled save completion, failure/retry, discard confirmation, keyboard
input, an animation, and a reviewed cell golden. Its live demos and executable
tests share the same widgets.

The browser-review follow-up pairs widget source and executable tests in file
tabs beside both live examples. It introduces roles, labels, activation, and
Dart matchers before the first test, and explains frame and waiting operations
before the editor. Editor tests now show `pumpWidget(FleuryApp(home: ...))`
explicitly: `pumpFleuryHome` hides ordinary app composition behind an unclear
name. The helper remains available; this follow-up changes the teaching path.
Long source panes scroll within the expanded playground, and switching files
returns the code pane to its beginning. The seven guide tests, documentation
checks, and 144-page website build pass after this follow-up. Browser checks
cover both file tabs, expanded source scrolling, and live editor input/save.

Work is based on `danreynolds/launch-audit-fixes` at
`a9eb740aacc60c8fd8483abaa1aa8ce49f78c3c0`. The local `origin/main` contains later
text-policy, keyboard-latching, and repaint-boundary work. Those changes were
not folded into this patch. The pump, semantic targeting, and render-size
implementations inspected for this audit were unchanged in that comparison.

## 1. Complete frames — implemented

Before this change, mounting a `LayoutBuilder` did not mount its child until a
separate render. Even `pump()` left it absent. Post-frame callbacks could run
before any layout or paint. A render-size override also disagreed with
`MediaQuery`: layout reported 40 columns while the ambient size remained 80.

`pumpWidget` and `pump` now complete one synchronous frame: build, layout,
paint, then post-frame callbacks. Geometry and pointer targets are immediately
available. A timed pump keeps the existing ticker cadence and paints the final
frame; it does not wait for Dart futures or implicitly settle. Callbacks that
schedule more work leave it for the next frame.

`render(size: ...)` and `renderToString(size: ...)` now perform a real viewport
resize, including `MediaQuery` and subsequent frames. They do not advance time
or drain post-frame callbacks. Framework tests can use `mountWidget` to defer
layout/paint, `owner.flushBuild()` for build-only updates, and `render` to
inspect the next paint separately.

Caller migrations preserve the test's purpose:

- Render-error and first-paint accounting tests explicitly defer rendering.
- Virtualization and scroll tests set their intended viewport before mounting.
- Expected-disabled semantic actions explicitly opt in to receiving a result.
- The console command helper no longer silently resizes the viewport. Its
  transcript tests and the agent sample use a consistent size from the start.

The source change also invalidated the embedded remote client's source
fingerprint. The asset was regenerated with the repository build command and
its freshness test passes.

## 2. Semantic diagnostics — implemented

Previously a missing button, duplicate label, and disabled button all returned
`notFound`. Action availability was part of target selection, so disabled
controls disappeared from the candidate set; zero and multiple matches then
collapsed into the same result.

Identity is now resolved first. The result distinguishes `notFound`,
`ambiguous`, `disabled`, `unsupported`, callback `failed`, and `completed`.
`SemanticTree.single` throws `SemanticQueryError`, a `StateError` subtype with
a match count. Its message includes the requested selectors, a sample of
matching nodes, and a redacted tree summary capped at 60 lines.

The application-facing `fleury_test` tester fails the test when an action
cannot complete. Expected rejections use `allowFailure: true` and assert on
the returned status. The package-neutral `fleury_test_support` tester keeps
returning results for tooling and lower-level tests. Diagnostics omit action
payloads and reuse the existing tree-value redaction rules.

## 3. Async completion — documented; behavior unchanged

`settle()` observes UI quiescence, not application request completion. It can
return while a future remains pending. The editor's injected save callback and
controlled `Completer` make pending, failed, retained-draft, duplicate-submit,
and retry assertions deterministic. The guide completes that work before
settling and asserting the result.

No fake async clock, new waiting helper, or application task framework was
introduced. Such a change would need a separate timing contract.

## Before and after evidence

The [probe source](2026-09-04-testing-guide-evidence/harness_probe.dart),
[original output](2026-09-04-testing-guide-evidence/harness_probe.json), and
[current output](2026-09-04-testing-guide-evidence/harness_probe.after.json)
record the observable differences:

| Observation | Before | After |
| --- | --- | --- |
| Layout-time child after mount / pump | absent / absent | present / present |
| Render override: layout / MediaQuery columns | 40 / 80 | 40 / 40 |
| Missing action target | `notFound` | `notFound`, with query details |
| Duplicate action target | `notFound` | `ambiguous` |
| Disabled action target | `notFound` | `disabled` |
| Settle with unfinished future | returns while pending | unchanged |

Run the current probe from the repository root:

```sh
dart --packages=website/examples/.dart_tool/package_config.json \
  docs/audits/2026-09-04-testing-guide-evidence/harness_probe.dart
```

## Validation

[Validation receipts](2026-09-04-testing-guide-evidence/validation.json) retain
the suite summaries and exact baseline failure names.

- Focused core harness and semantics: **155 passed**. New frame regressions cover
  layout-time children, callback geometry/order, pointer routing, viewport/state
  consistency, partial phases, layout failures, and a timed animation's bounds.
- `fleury_test`: **16 passed**, including strict and result-returning paths for
  all five failure outcomes, successful dispatch, query context/redaction, and
  omission of action payloads.
- Widget package: **1,091 passed, one skipped**. Console: **25 passed**.
- Full core non-integration run: **2,958 passed, four existing failures**.
  All four reproduce in an isolated copy of the unchanged commit: the
  TextInput/TextArea large-paste per-frame expectations and parser-segmented
  paste expectations. The approved changes do not modify paste behavior.
- Core integration: **44 passed** in the broad run; its one failing embedded
  client freshness check **passed on rerun after asset regeneration**.
- Themes: **six passed, one existing failure**. The web-safety guard matches a
  native import inside a documentation example. Reproduced on the baseline.
- Web VM/Chrome: **512 passed, four existing failures**. Baseline reproduction
  confirms the IME frame-flush, pre-first-tree action timing, mount frame-count,
  and DOM demo input failures.
- Git: **four passed**. Storybook: **43 passed**. Samples: **92 passed**.
  MCP: **148 passed**.
- Analysis across all eleven packages: no errors or warnings; existing
  informational lints remain. Final analysis of the changed harness, semantic
  code, and console tests is clean.
- The website build passes: two API-export checks, **62 Dart documentation
  tests**, example generation/JavaScript compilation, and **144 pages**. The
  existing unresolved `fleury-mono.woff2` warning remains.
- Both focused Chrome guide tests pass: painted counter activation and offline
  editor failure/retry. Visual review of the built page confirms the demos fit
  their frames. The shared guide suite has **seven passing tests**.

The aggregate `fleury_dev check` remains red on the four baseline core paste
failures; the later suites were run separately so that early stop could not
hide regressions. This is local validation, not CI, a release, or broad
physical-terminal qualification.
