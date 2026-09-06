# Testing DX and guide: PR review

Date: 2026-09-05. Branch `codex/testing-guide-dx`, based on main commit
`e5217c0f456febaa0aebb033d0485cfb78487309`.

The implementation was ported from the earlier launch-audit checkout into an
isolated worktree. It preserves main's open `SemanticRole` vocabulary,
`WidgetRoles`, text-policy helpers, production-surface wrapping, and input
latching. Original launch-audit work is excluded from the PR.

## Review findings and corrections

React and Flutter developer-persona reviewers inspected the implementation and
its integration with current main. Two additional defects were fixed:

- **Private diagnostic content:** strict low-level action failures included raw
  selector values or arbitrary callback messages. Selector values are now
  redacted; callback diagnostics report the error type. `allowFailure: true`
  still returns the original error for explicit assertions. Regression tests
  include missing and ambiguous selectors and callback-thrown query errors.
- **Ambiguous widget-scope ownership:** colliding semantic IDs could make scoped
  queries report zero matches. Matching published nodes now require unique,
  known contributor ownership before subtree filtering. Tests cover two- and
  three-way collisions, positive/zero/negated assertions, actions, snapshots,
  and legitimate exclusion markers.

Current-main integration also restores the existing synchronous segmented-paste
expectations and fixes a WhichKey fixture to set its viewport before the first
complete frame. The original popup layout assertions remain intact. Declared
custom roles are tested and exact role matching is explained in the guide. The earlier implementation receipt and feasibility probes are
explicitly historical evidence.

## Validation

- All 11 package analyses passed in the contributor check.
- Focused review checks passed: 31 target tests, 9 widget integration tests,
  10 guide tests, and 47 core semantics/frame-contract tests.
- Website production build passed: 66 Dart documentation tests, 2 Node checks,
  dart2js examples, and 144 generated pages.
- The shared remote client asset was regenerated with Dart 3.12.2.
- Core non-integration: 3,209 passed, 1 skipped. Testing facade: 49 passed.
- Widgets with a DST-observing timezone: 1,197 passed, 1 skipped.
- Themes / Git / example console / storybook: 7 / 4 / 25 / 43 passed.
- Browser package (VM + Chrome): 523 passed. Samples: 92 passed.
- MCP: 151 passed, including the real showcase end-to-end cases.
- Core integration, serial: 63 passed.
- All local test suites passed: 5,431 tests in total, with 2 declared skips.
  Formatting of changed library, test, and example files and `git diff --check`
  passed. The launcher retains its pre-existing formatting; its only code
  change is the guide test registration.

The contributor launcher stopped at the WhichKey fixture. After correcting it,
the full widget suite and every remaining suite were run explicitly; the earlier
core and facade passes remained valid. The website build also exercised the
documentation gate and compiled the complete browser example surface.

These initial checks ran locally on macOS with Dart 3.12.2, before publication.
The later review and validation below supersede this initial receipt.


## Guide simplification, 2026-09-06

Browser feedback showed that the guide was teaching too many contracts before
readers had a reason to use them. The main path now has four small live examples:
a counter, two independently scoped preferences forms, a save with controlled
completion, and an animated progress bar. Source and test tabs accompany each.
The operation tables and long role/action explanations were removed; detailed
contracts are linked from the end. Setup is expandable. The larger editor and
custom async-control fixtures remain in the executable suite.

Prose fell from roughly 1,790 words to 430. Code wraps and the guide's panels give
more room to source, including in the expanded playground. The Work field starts
focused; the keyboard regression mounts FleuryApp to exercise its Tab bindings.

Validation for this follow-up: 71 Dart documentation tests (including 15 guide
cases), 2 Node export checks, scoped Dart analysis, dart2js compilation, and the
144-page website build passed. The final panel layout also passed an Astro
production build. Browser checks verified independent Work edits, the completed
save, the animated meter, source tabs, and the expanded playground. Framework
runtime code was unchanged, so the previous full-suite receipt above remains
separate from this documentation-focused validation.

### Separate DX finding: TextInput pointer focus

In the inline preferences demo, clicking an unfocused Name field and typing did
not focus or edit it. Tab focused the field and typing then worked. Checkbox
clicks both focused and toggled their controls. TextInput's current implementation
contributes hover handling but no tap handler that requests its FocusNode;
that input-handling code is unchanged from the main branch used for this PR.

Follow-up: define click-to-focus/caret behavior for editable controls and add
native and browser pointer regressions. The guide now makes its keyboard route
clear, but semantic fill tests alone do not qualify this pointer behavior.

## Executable Preferences walkthrough, 2026-09-06

The Preferences demo now has Run test, Stop, Run again, and Try it yourself
controls. A fresh FleuryTester executes the same scenario as the command-line
test; the browser displays its rendered cell frames with short pauses and
highlights the matching source line. Four assertions visibly confirm Work's
changes and Personal's unchanged values. The test tab is extracted from that
scenario, omitting only the pause markers. No recorded frames or predetermined
pass results are used.

The browser entry point evaluates the same synchronous Matcher contract outside
package:test's test zone. Its small bundle is loaded only on demand. Inline and
expanded runners have independent state and dispose on stop, completion, close,
and page navigation. The ordinary interactive widget is available via Try it
yourself. A native-terminal import in the tester facade was narrowed to the core
API so the real tester can compile for the browser; no tester operation changed.

Validation: 73 Dart documentation tests (17 guide cases), 49 tester-package
tests, 2 Chrome runner tests, and 2 Node export checks passed. Regression cases
cover intermediate states, a deliberately invalidated assertion, cancellation,
and a fresh replay. Scoped analysis and the tester package analysis passed.
Both Dart browser bundles compiled and the production site built 144 pages;
the subsequent source-extraction component also passed the production build.
In-app browser checks confirmed source highlighting, all four passing checks,
stop/replay, the expanded run, and return to the interactive widget.


## Suite migration and final review, 2026-09-06

The final audit examined 447 owned `*_test.dart` files in package and website
`test/` trees, with no Dart AST parser diagnostics. It migrated 211 existing
`invokeSemanticAction` call sites to shared targets and actions: 110 in widgets,
35 in the console, 29 in samples, 9 in storybook, and 28 in documentation tests.
Those last four suites now contain no raw semantic invocations. Ordinary state
assertions use target matchers or snapshots. Fixed-size fixtures set their
viewport before mounting; obsolete preparatory renders and app-wrapper helpers
were removed without replacing keyboard or pointer input coverage.

The retained low-level calls exercise the layer they are testing:

- 42 widget calls: 12 rejection/stale/unsupported cases, 22 value coercion,
  clamp, round-trip or ownership cases, 7 advertised numeric/chart actions,
  and 1 paired sortable-header action contract.
- 32 core calls stay on the package-neutral harness. Core deliberately does not
  depend on its testing companion, avoiding a circular hosted dev-dependency.
- 11 facade calls verify strict failures, privacy, and explicit result access.
  Three are new validation-error privacy call sites.
- Three `pumpFleuryHome` calls specifically test that compatibility helper.

Independent React, Flutter, and Textual reviewers found no remaining actionable
API blocker after correction. One further privacy defect was fixed: selector
diagnostics could include input embedded in a validation-error message. Both
semantic-query and strict-action diagnostics now redact that criterion while
matching the original value; explicit failure results still expose the original
node to the test. Regression tests cover all three protected-value flags.

The review also fixed tester disposal in a loading-error fixture, corrected the
README's extended-example link, and made guide runner attachment consistent
with Astro page lifecycle events. The contributor check now includes the two
Chrome runner tests. Those tests cover real shared Dart execution, assertion
failure, disposal, and fresh replay; TypeScript bundle-load failure and
stop-during-load remain manually reviewed paths rather than automated DOM tests.

### Final local validation

`dart tool/fleury_dev.dart check` completed successfully with all 11 package
analyses and 5,441 passing Dart tests, plus 2 declared skips. That includes
3,209 core unit tests, 52 facade tests, 1,197 widget tests, 7 theme tests, 4 Git
tests, 25 console tests, 43 storybook tests, 523 browser-package VM/Chrome tests,
92 sample tests, 151 MCP tests, 73 docs tests, 2 Preferences runner Chrome tests,
and 63 serial terminal integration tests. The dart2js smoke also passed.
The production website build passed its 2 Node checks and generated 144 pages.

Main advanced to `cc3569d34f150f81b5768180251a6691fa117fdf` during validation.
That commit was merged into this branch. Semantic source merged cleanly; the
browser asset was regenerated from the combined sources (fingerprint
`fbba5c9c9e390316`). An independent reviewer verified that snapshot-local sibling
indices preserve contributor ownership and fail-closed scoped queries. After
integration, core analysis and all 3,212 core unit tests passed (1 skip), as did
all 52 facade tests, the 73-test docs/2-test Node/144-page site build, both browser
bundles, and every fast performance gate. The upstream commit adds one test
file with three snapshot regressions; the final owned suite has 448 test files.
Formatting and source diff whitespace checks passed (captured logs and golden
terminal cells retain their literal whitespace). GitHub CI supplies the full
integrated Linux run and cross-platform create matrix before merge.


### PR browser review follow-up

The final Playwright-persona review of PR #221 found a minor presentation bug:
expanding a completed inline Preferences run copied its execution highlight into
a fresh runner. Attachment now clears only the new runner's code scope. A live
browser check confirmed the expanded demo starts with zero highlighted lines,
keeps the inline highlight, passes all four assertions with its own highlight,
and disposes on close while preserving the inline result.
