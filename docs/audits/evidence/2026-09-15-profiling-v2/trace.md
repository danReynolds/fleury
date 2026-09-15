# Fleury workload diagnosis

Scenario: `typing`. JIT diagnostic; timings are not AOT comparison results.

643 CPU samples over 0.86 seconds; 0 unknown leaf samples.

Profiles collected by an external supervisor.

Heap before: 32027584 bytes; after: 43698544; after forced GC: 32967936. These include workload bookkeeping and JIT runtime state.

| Exclusive samples | Function |
|---:|---|
| 22 | `_concatAll` |
| 11 | `_findValueOrInsertPoint` |
| 10 | `_snapshotAnchorOf` |
| 8 | `_insert` |
| 8 | `_copyRect` |
| 7 | `copy` |
| 7 | `_interpolate` |
| 7 | `<anonymous closure>` |
| 7 | `_instanceOf` |
| 7 | `_set` |
| 7 | `_hashPattern` |
| 7 | `_resolveScreenGeometry` |
| 7 | `diffAgainst` |
| 6 | `<anonymous closure>` |
| 6 | `_getValueOrData` |
| 6 | `_getValueOrData` |
| 5 | `_collectInto` |
| 5 | `_hasUnsafeCodeUnit` |
| 5 | `_childIndexOf` |
| 4 | `makeFixedListUnmodifiable` |

Inspect trace.json for inclusive stacks, source locations, GC events, and complete class inventories, including SDK allocations. Repeat a targeted run before attributing a regression to a small sample count.
