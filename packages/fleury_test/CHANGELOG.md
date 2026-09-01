# Changelog

## 0.1.0

- Initial release of `FleuryTester`, `testWidgets`, finders, semantic testing
  helpers, deterministic clocks, and file-backed golden matching.
- Missing golden files now fail instead of being created implicitly. Set
  `FLEURY_UPDATE_GOLDENS=1` to create or update baselines deliberately.
- Golden mismatches now preserve distinct expected, actual, and file-path
  state so failure output reports the real diff.
