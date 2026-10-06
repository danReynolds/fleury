# Changelog

## 0.1.1

- Adds a runnable example test.

## 0.1.0

Initial public release, October 5, 2026. Requires Dart 3.10.4 or later and
`fleury ^0.1.0`. Keep this package in development dependencies.

- `FleuryTester`, `testWidgets`, widget finders, semantic testing helpers,
  deterministic clocks, and file-backed golden matching.
- Shared `FleuryTarget` queries combine exact type/key scopes with role/label
  queries and `button`, `field`, and `checkbox` shortcuts. Targets resolve live
  controls, reject missing or ambiguous matches, and check capabilities before
  `press`, `fill`, `check`, and `setValue` operations.
- Count, value, enabled, checked, and focus matchers. Value assertions respect
  shared redaction flags; snapshots remain immutable observations.
- `pumpWidget` and `pump` complete layout, paint, and post-frame callbacks.
  `render(size: ...)` also updates the ambient viewport; `mountWidget` supports
  tests that deliberately defer a frame.
- `invokeSemanticAction` fails with target, outcome, and semantic-tree context
  when an action cannot complete. Use `allowFailure: true` when asserting an
  expected rejection or callback failure.
- `sendTerminalBytes` exercises fragmented terminal-parser input, with an
  optional injected parser.
- Missing goldens fail by default. Set `FLEURY_UPDATE_GOLDENS=1` to deliberately
  create or update them; mismatch output preserves expected, actual, and path
  details.
