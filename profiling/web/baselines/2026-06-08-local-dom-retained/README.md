# 2026-06-08 local retained DOM baseline

Status: local candidate evidence, not a release gate.

This directory contains a retained DOM web benchmark suite collected on the
local development machine. It is useful for architectural review because it
uses the product benchmark tooling, records comparable run-environment
metadata, and preserves the generated readiness artifacts. It should not be
treated as an approved Phase 5/6 baseline until the product/browser conditions
and threshold policy are reviewed.

## Commands

```sh
fleury benchmark web-suite --runs=3 --output-dir=profiling/web/baselines/2026-06-08-local-dom-retained --scoreboard=profiling/web/baselines/2026-06-08-local-dom-retained/scoreboard.md --write-thresholds=profiling/web/baselines/2026-06-08-local-dom-retained/thresholds.candidate.json --timeout=60
fleury benchmark web-semantic-audit --input=profiling/web/baselines/2026-06-08-local-dom-retained --output=profiling/web/baselines/2026-06-08-local-dom-retained/semantic-coverage.md --max-fallback-cells=0 --strict
fleury benchmark web-readiness-bundle --captures=profiling/web/baselines/2026-06-08-local-dom-retained --manual=profiling/web/manual --output-dir=profiling/web/baselines/2026-06-08-local-dom-retained/readiness-candidate --thresholds=profiling/web/baselines/2026-06-08-local-dom-retained/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json
```

## Artifacts

- `*-run-*.json`: 33 Chrome captures, three per scenario.
- `scoreboard.md`: human-readable frame scoreboard.
- `thresholds.candidate.json`: generated candidate threshold policy.
- `semantic-coverage.md`: human-readable semantic fallback audit.
- `readiness-candidate/scoreboard.json`: machine-readable scoreboard with the
  candidate threshold policy applied.
- `readiness-candidate/semantic-coverage.json`: machine-readable semantic
  fallback audit.
- `readiness-candidate/manual-validation-audit.json`: manual evidence audit.
- `readiness-candidate/web-readiness.json` and `web-readiness.md`: combined
  readiness result.

## Summary

- Frame scoreboard: pass for run-count, comparable-environment, and candidate
  threshold policy checks.
- Semantic coverage: pass with 33 captures, 912 frames, and zero fallback
  cells or fallback nodes.
- Readiness: fail, because manual validation evidence is missing for
  `chrome-ime-macos` and `chrome-voiceover-macos`.
- Performance signal: the local over-budget behavior is dominated by
  `runtimeRenderMs` and `semanticApplyMs`, not by DOM apply. The worst local
  median total-frame p95 in this run is `single-dirty-cell-160x50` at
  2718.4 ms; `stress-300x100` is fully over budget.

## Caveats

`thresholds.candidate.json` was generated from this same local run with default
headroom. It is a review starting point, not an approved release threshold
policy. Rename or copy reviewed values to `thresholds.json` before using them
as the Phase 5 gate.

## Follow-up Smoke

A later focused smoke after the sparse row-diff and RepaintBoundary semantic
replay fixes was collected under
`/tmp/fleury_web_damage_smoke_after_semantics_zUt1WY`. It did not replace this
promoted baseline, but it confirmed the targeted behavior:

- `noop-160x50`: 0 dirty rows, 0 replaced rows, 0 fallback cells.
- `single-dirty-cell-160x50`: 1 dirty row, 1 replaced row, 0 fallback cells.
- Both focused captures remained runtime-render dominated rather than
  DOM-apply dominated.
