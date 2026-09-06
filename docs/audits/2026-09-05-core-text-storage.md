# Core text storage and lifecycle performance

The preceding viewport/selection pass, PR #217, was reviewed, its findings
resolved, and its final CI passed before merging as
`85ea87fec94ccbfaa4097703384bd1c8b96fe649`. This pass starts from that main.

## Retained changes and review

Each production change was reviewed and measured before starting the next.
The incremental CSV preserves both retained and rejected trials, including
median/p95 timings, output fingerprints, changed-frame counts and copy lengths.
These are informational measurements; no gate or tolerance was weakened.

1. `eb485676`: ordinary glyphs retain only grapheme, width and immutable style.
   Lowered emoji atoms alone carry group metadata; newline identity comes from
   the grapheme. Reviewed newline creation, lowering boundaries and selection
   source recovery. 119 targeted regressions and all eight fast gates passed.
   The 67,000 ordinary glyphs in the selected rich-document heap probe shrink
   from 4,288,000 to 2,144,000 shallow live bytes.
2. `a1613467`: resolve styled source runs once per update and compare their
   values before remeasuring/wrapping. Preserve each source span boundary;
   preserve the cross-span paragraph walk on lowering surfaces. The snapshot
   observes mutation of reused child lists instead of trusting span identity.
   Tests cover equal distinct trees, mutable children, ambient styles,
   changed grapheme boundaries and policy changes. 122 regressions and all
   eight fast gates passed. At 1,000 lines, unchanged rich-document rebuilds
   fall from about 11–12 ms to 0.10–0.15 ms, including 1,000 styled spans.
3. `fd82aca4`: share immutable printable-ASCII glyphs inside each resolved
   source run with a temporary 95-slot index. It is discarded after flattening;
   there is no retained/global pool or invalidation scheme. Styles and policy
   remain local to the run; non-ASCII clusters and lowered groups retain their
   resolver paths. 123 regressions, eight fast gates and the 7,680-case
   differential contract passed. The selected rich-document probe uses
   315,600 total Fleury-class shallow live bytes versus 4,474,560 on main.
4. `9092ad7b`: wrap over ranges in the existing glyph list, removing transient
   paragraph, word and separator lists. Reviewed empty/trailing/consecutive
   spaces, link whitespace, zero-width glyphs, forced word breaks, explicit
   newlines, truncation and unbounded widths. All 123 regressions, eight gates
   and the differential contract passed. Resizing a 1,000-line rich document
   drops from about 5.7 ms to 3.9 ms in the incremental comparison.
5. `87f42288`: copy only intersecting lines for ordinary selections, avoiding
   a temporary joined string for the whole document. Lowered groups retain
   their existing canonical-source splice. Regressions cover every forward
   and reverse pair of boundaries across blank lines, CJK and a ZWJ cluster.
   125 regressions, eight gates and the differential contract passed. A short
   selection in a 10,000-line document takes roughly half or less the former
   copy-plus-frame time in the measured plain/rich workloads.
6. `88c54c46`: use the character buffer when constructing selection text from
   single-code-unit glyphs, keeping multi-code-unit clusters intact. Reviewed
   UTF-16 preservation, empty clusters and source offsets. 125 regressions,
   eight gates and the differential contract passed. This reduces the
   incremental 1,000-line resize measurement by about 15%.

7. `cd24fe69`: retain the scalar document length with the existing layout-line
   identity. Repeated range queries now reuse it; replacement recomputes it, and
   every paint (including an empty paint) releases obsolete line snapshots.
   No per-line offset index was added. The full-copy control exposed a slowdown
   in the initial slice-based copy implementation: complete selections now use
   the SDK bulk join. With length reuse, 10,000-line drag frames fall from about
   0.35–0.37 ms to 0.10–0.12 ms, and partial/full copy both improve. 128 targeted
   regressions and all eight fast gates passed. The initial copy-control CSV
   is retained as evidence of the qualification finding, not the final result.

## Workloads and proof boundaries

`document_work_probe.dart` measures initial mount/first frame, equal rebuilds,
edits, resizing between 60 and 80 columns, pointer-driven selection and copy.
Fixtures are log-shaped with distinct numbers, ASCII, CJK and ZWJ emoji. They
use plain text, one styled source run, or one differently styled span per line.
Fixture generation is outside timing. Opening includes mount and first frame;
other operations include mutation, frame construction, diff and commit.
Process startup, terminal encoding/transport and terminal display are excluded.
The final probe also includes full-document copy as a regression control.

`rich_text_contract_probe.dart` produces a deterministic fingerprint over 7,680
cases spanning widths 0/1/5/12/unbounded, wrap on/off, preserve/CJK/lowering,
truncation/overflow, blank lines, control sanitization, zero-width glyphs,
styles/links, viewport clipping and selected copy. Main and every retained
candidate measured so far produce `4267333977`.

The JIT CPU attribution probe is separate from AOT timing claims. After range
wrapping, 3,635 CPU samples from repeated 10,000-line resizes attributed about
51.5% inclusively to constructing selection lines; this motivated change 6.

Heap probes use deterministic Dart VM-service snapshots with explicit GC.
Fleury-class totals count shallow object storage and exclude SDK strings,
lists, VM/tool overhead and external allocations. They are not total RAM or
an allocation rate. Lifecycle snapshots exercise mount, replacement, resize,
selection and unmount, with ten warmup cycles and fifty additional cycles.
The first rich-document run returns to exactly the same empty-state class
totals after release and after all fifty cycles. No document render objects
or non-constant glyphs remain. This is bounded lifecycle evidence, not proof
that every application or callback lifetime is leak-free.

## Trials not retained

- A bounded per-run hash map shared non-ASCII glyphs as well, but opening and
  editing 1,000 short styled spans regressed about 10%. The fixed ASCII index
  retains most of the memory benefit and improves those operations.
- Checking glyph width before comparing for a newline improved only about
  2–4% in three alternating resize comparisons. It was discarded as a marginal
  result rather than expanded into another optimization.
- The earlier shared-frame pass already tested scratch-cell replay sharing
  and bounded Flex scratch allocation; ordinary sample-frame gains were only
  a few percent, with no demonstrated broad retained-memory reduction.
- Reconciliation rewrites, persistent layout caches and document virtualization
  remain unproven proposals. Caching the benchmark's two alternating widths
  would reward this script without establishing a real resize improvement.

Final main-versus-candidate receipts, sample controls, complete contributor
checks and PR review are still being collected.
