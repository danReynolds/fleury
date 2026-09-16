# Cache recovery, geometry and keyed-list rebuilds

Follow-up to the September 15 architecture audit, updated against main
`f00a5b3182933501e1195ae47d2e245510b66919`.

## Changes

- A repaint exception leaves that cache and enclosing caches invalid. Partially
  written cells are never reused as a completed cache. Recovery stays with the
  host/error boundary; a persistent exception does not create a retry loop.
  Invalidations raised during a successful paint survive for the next frame.
- Repaint boundaries declare the clip already imposed by their finite cache.
  Fully clipped content no longer advertises visible focus/semantic bounds;
  partially clipped semantic bounds match displayed cells. Switching caching
  in either direction invalidates geometry and enclosing caches. Overflowing
  content still needs layout space or an external overlay.
- Keyed lazy lists automatically reuse their validated reverse lookup when the
  ordered keys are unchanged. Every key is still read on each parent update;
  visible rows still rebuild. Changed keys rebuild the lookup, validating
  duplicates including those outside the viewport. There is no new public API.

## Identity ownership and complexity

The key callback may close over mutable data. Neither unchanged callback
identity nor unchanged item count establishes that keys stayed the same.
A parent update therefore compares every key against the prior snapshot. This
is O(itemCount), but avoids a new key array and reverse map when keys match.

At the first changed key, capture reuses the already checked prefix and builds
a fresh map. Remaining keys are read once, and duplicates checked against the
entire captured prefix. The previous snapshot is never mutated: callbacks and
validation must succeed before publishing the replacement. Count changes use
a full capture. Navigation without a parent update already reuses the snapshot.

Keys require stable equality and hash codes. Equal fresh key objects can reuse
the snapshot; as with any map cache, the old equal key instances can remain
retained until keys change or the list unmounts. Row state, current-item identity,
viewport anchoring and pointer selection keep their existing behavior.

## Correctness evidence

Regressions cover paint exceptions before and after partial writes in single
and nested boundaries; frame-driver recovery after an unrelated repaint;
clipping and cache-mode changes under an outer cache; visible labels updating
with stable keys; same-closure mutable data; offscreen mutations and duplicates;
failed-capture retry; and a 200-update identity oracle exercising insertion,
removal, replacement, swapping, reversal and navigation.

The focused suite also covers eager/lazy controllers, horizontal scrolling,
follow-tail behavior, cursor/viewport preservation and pointer selection. The
profiling lab checks every measured update's 20 visible labels and exact key
read counts. Validation receipts and final measurements are recorded below.

## Reproduction

From a bootstrapped checkout, after committing the candidate:

```sh
cd packages/fleury
FLEURY_VERIFY_REPAINT_CACHE=1 dart test -x 'integration || pty'
```

From the repository root:

```sh
dart tool/fleury_dev.dart benchmark gates
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=f00a5b31 --candidate=HEAD \
  --scenario=keyed-list-1k,keyed-list,keyed-list-strings,keyed-list-reorder,keyed-list-replace,unkeyed-list-rebuild \
  --runs=5 --samples=150 --warmup=30 --out=/tmp/keyed-list-comparison
dart tool/fleury_dev.dart benchmark lab compare \
  --baseline=f00a5b31 --candidate=HEAD \
  --scenario=panes-40,dashboard-leaf,typing,list \
  --runs=5 --samples=500 --warmup=60 --out=/tmp/cache-list-comparison
```

Use new output directories and run on a quiet machine without concurrent
builds/tests. The lab retains frozen harnesses, source/binary/dependency hashes,
raw samples, correctness counters and per-process confidence intervals. Raw
machine/build/test receipts remain local; only the summary ships with the PR.
