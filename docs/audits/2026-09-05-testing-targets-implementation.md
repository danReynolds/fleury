# Shared testing targets: implementation receipt

> Historical receipt from the original implementation checkout. The PR was
> subsequently ported to current main; see the [PR review receipt](2026-09-05-testing-pr-review.md)
> for current validation and additional review fixes. Failures below describe
> that earlier checkout only.

Date: 2026-09-05. Working tree on `danreynolds/launch-audit-fixes`, based on
`a9eb740aacc60c8fd8483abaa1aa8ce49f78c3c0`. This is local implementation and
validation evidence, not a clean-commit, CI, deployment, or release receipt.

## Delivered

- One `FleuryTarget` for exact type/key widget scopes and role/label/ID semantic
  queries. `button`, `field`, and `checkbox` return that same type. Structural
  targets count and scope widgets; actions and state require a semantic target.
- Shared operations (`press`, `focus`, `fill`, `check`, `uncheck`, `setValue`,
  `open`, `close`, `select`, `submit`, `copy`, `perform`) and seven target matchers.
  Queries resolve live, enforce cardinality, preserve modal/hidden-route
  semantics, and use existing contributor ownership for synthetic nodes.
- `textEditable` semantic state supports fields independently of their role.
  Read-only and disabled controls remain discoverable. Filling validates before
  focusing and refuses a remounted replacement before delivering text.
- MultiSelect options support boolean desired-state updates without changing
  their option keys. Tree branches expose the shared `expanded` property.
- The testing guide pairs counter, editor, and custom async-control source with
  executable tests and live examples. It introduces selection, logical/input
  coverage, matchers, and frame/waiting terms before relying on them. Its editor
  uses the real Dialog widget and explicit FleuryApp setup.
- CodeDemoSplit renders all supplied file/test tabs, including the fifth dialog
  tab, with bounded source scrolling and usable inline/expanded preview panes.
  Package README and changelogs describe the supported interface.

No per-widget driver hierarchy, role-enum migration, automatic retries,
automatic scrolling, implicit primary-child selection, or hidden settle was
introduced. The existing low-level result API remains available. Domain role
classification and improved collection-reveal APIs remain separate work.

## Review corrections

React and Flutter persona follow-up reviews found two issues and verified their
fixes independently:

1. Value assertions now recognize `redactedValue`, `obscureText`, and
   `clipboardRedacted`, including positive/negated matcher failure formatting.
2. Composite operations track semantic identity and the contributing element,
   allowing legitimate capability changes. A field may remove its focus action
   after focus; a checkbox may disable itself after reaching checked state.
   Real remounts are still rejected.

New target tests cover identity, ambiguity, scopes, disabled/unsupported actions,
controlled state, filters, callbacks, async pending work, remounts, and redaction.
Real-widget coverage includes Checkbox, Toggle, Switch, PasswordInput,
MultiSelect, Select, NumberInput, Autocomplete, forms, tabs, trees, and a
10,000-row virtualized DataTable with synthetic semantic rows/cells.

## Validation

The final contributor run analyzed all 11 configured packages successfully.
`dart tool/fleury_dev.dart check` then reached the browser suite, whose four
failures were reproduced against unchanged HEAD (details below). Remaining
suites were run explicitly because that command stops at the first red suite.

| Check | Result |
| --- | --- |
| Core non-integration suite | 2,962 passed; 1 skipped |
| fleury_test | 44 passed, including 28 target tests |
| fleury_widgets, final run with DST-observing TZ | 1,100 passed; 1 skipped, including 9 target integration tests |
| Themes / Git / example console / storybook | 7 / 4 / 25 / 43 passed |
| Samples | 92 passed |
| Core integration, serial | 45 passed |
| Documentation | 65 Dart tests and 2 Node export checks passed |
| Website production build | dart2js examples compiled; 144 pages built |
| Shared remote client | Regenerated successfully; source fingerprint `e83b4453144c5be8` |
| Browser package, VM + Chrome | 512 passed; 4 failures reproduced at HEAD |
| MCP | 147 passed and one app-attachment timeout during concurrent validation; all 5 showcase cases passed on serial rerun |

Primary commands were `dart tool/fleury_dev.dart check`, `dart test` in each
affected package, `TZ=America/New_York dart test` for the final widget suite,
`dart test -t integration --concurrency=1` in core,
`dart test test/mcp_showcase_e2e_test.dart --concurrency=1`, and `npm run build`
in website. Formatting, final targeted analysis, and `git diff --check` passed.

Four stale paste tests were aligned with existing HEAD behavior: scheduled paste
work processes multiple chunks within a time budget, and segmented paste is
chunked below the one-shot threshold. They retain initial pending-state,
lossless-content, and undo assertions. A themes documentation example now uses
the web-safe import, matching its existing package guard. No paste runtime or
browser-host implementation was changed for those checks.

## Existing browser failures

The following also fail with original core and web sources extracted using
`git archive HEAD` into a temporary directory and the same resolved external
dependencies:

- `run_tui_surface_test.dart`: IME composition input is queued and dispatched
  during a frame — no pending frame flush.
- `run_tui_surface_test.dart`: semantic action request before first semantic
  tree records notFound — expected a further pending frame.
- `mount_app_test.dart`: mountApp assembles retained DOM rendering and browser
  input — expected two instrumentation frames, observed three.
- `dom_demo_test.dart`: retained DOM demo renders and handles browser input —
  a pending-frame expectation failed.

These remain unresolved; the repository-wide check is not green. Baseline
outputs and final result summaries are retained in
[testing-targets evidence](./2026-09-05-testing-targets-evidence/validation.json).

## Browser review

At the local guide preview, verified source/test tab switching, the fifth dialog
tab, bounded code scrolling, and expanded source/demo browsing. Exercised the
counter through Enter; edited the draft, saved with Ctrl+S, opened/cancelled the
discard dialog, and observed an offline save preserving the draft. The custom
control showed Publishing and then Published. The final guide was left open at
its first test. This is browser preview evidence, not a native terminal matrix.
