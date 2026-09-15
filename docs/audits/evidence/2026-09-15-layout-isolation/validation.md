# Validation receipt

Date: 2026-09-15. Dart SDK: 3.12.2, macOS arm64.
Baseline: f52b000762f58eca3b030a468fd162c94b769cce.
Implementation: 2506da65 (subsequent documentation/evidence cleanup does not change runtime behavior).

- `dart tool/fleury_dev.dart check`: exit 0. Includes analysis, all package and browser tests, dart2js smoke, and 64 terminal/remote integration cases.
- `FLEURY_VERIFY_REPAINT_CACHE=1 dart test -x integration` in packages/fleury: exit 0, 3,536 tests passed, one existing skip.
- `dart test` in packages/fleury_widgets: exit 0, 1,293 tests passed.
- `dart test test/rendering/layout_isolation_test.dart -r expanded`: exit 0, 16 tests passed; includes 160 mutations comparing independent incremental/full-layout trees.
- Analysis of changed render files, new regression test, and new benchmark: no issues.
- `dart run tool/hot_reload_probe/driver.dart` in packages/fleury: exit 0, all checks pass.
- `dart tool/fleury_dev.dart benchmark gates`: exit 0, all required fast gates pass.
- Regenerated embedded client: compiled JavaScript unchanged (401,644 bytes); source fingerprint refreshed. The freshness integration test passes.
- AOT pane-update benchmark: identical source on baseline and candidate, two alternating-order runs, 5,000 frames per configuration. Raw JSON is stored here. This is a rendering workload, not an application-wide speed claim.
- Falsification: the parent-reuse test fails on unchanged main (two parent layouts instead of one). The first-error recovery test failed on the initial candidate and passes after the child-size fallback.

GitHub CI is a separate post-push check; this receipt records local results and does not claim independent review or manual terminal/browser dogfooding.
