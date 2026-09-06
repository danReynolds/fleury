# Changelog

## 0.1.0

- Add a shared `FleuryTarget` for exact type/key scopes and role/label queries,
  with `button`, `field`, and `checkbox` selector aliases. Targets resolve live
  controls, reject missing or ambiguous matches, and share capability-checked
  operations including `press`, `fill`, `check`, and `setValue`.
- Add target count, value, enabled, checked, and focus matchers. Value assertions
  respect all shared redaction flags; snapshots remain immutable observations.

- `invokeSemanticAction` now fails the test when an action cannot complete,
  reporting the action, target, outcome, and semantic tree. Pass
  `allowFailure: true` when asserting an expected rejection or callback failure.
  The lower-level `fleury_test_support` harness continues returning results.
- `pumpWidget` and `pump` now complete a frame, including layout, paint, and
  post-frame callbacks. `render(size: ...)` also updates the ambient viewport.
  Use `mountWidget` for tests that deliberately defer layout or paint.

- Initial release of `FleuryTester`, `testWidgets`, finders, semantic testing
  helpers, deterministic clocks, and file-backed golden matching.
- Missing golden files now fail instead of being created implicitly. Set
  `FLEURY_UPDATE_GOLDENS=1` to create or update baselines deliberately.
- Golden mismatches now preserve distinct expected, actual, and file-path
  state so failure output reports the real diff.
