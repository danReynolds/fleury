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
expectations, tests declared custom roles, and explains exact role matching in
the guide. The earlier implementation receipt and feasibility probes are
explicitly historical evidence.

## Validation

- All 11 package analyses passed in the contributor check.
- Focused review checks passed: 31 target tests, 9 widget integration tests,
  10 guide tests, and 47 core semantics/frame-contract tests.
- Website production build passed: 66 Dart documentation tests, 2 Node checks,
  dart2js examples, and 144 generated pages.
- The shared remote client asset was regenerated with Dart 3.12.2.
- Full contributor validation is running; final results will be recorded here.

These are local checks. CI and platform-specific evidence are tracked on the PR.
