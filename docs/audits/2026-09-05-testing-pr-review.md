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

These are local checks on macOS with Dart 3.12.2. GitHub CI and the cross-platform
create matrix have not run: automatic approval review blocked the push and PR
creation, requiring explicit permission for publication to the public
`danReynolds/fleury` repository. No PR has been created. The branch and review
are complete locally. No actionable review findings remain after the fixes.


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
