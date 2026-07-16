# Test Quality Assessment & Plan

**Date:** 2026-06-12
**Method:** Measured line coverage (per-suite VM collection, see recipe
below), full methodology inventory across all packages, scored against
TUI testing best practice.

> Historical measurement snapshot. As of 2026-07-15, the previously missing
> terminal tier exists: deterministic POSIX lifecycle and Windows handoff tests
> cover mode ownership, startup signals, EOF, suspend, and handoff concurrency;
> the PTY integration suite covers boot, resize, startup termination,
> Ctrl+Z/`fg`, handoff, crash containment, and restoration. The counts and
> coverage percentages below remain the original 2026-06-12 measurements.

## The numbers (measured, not estimated)

| Package | Line coverage | Tests |
| --- | --- | --- |
| fleury (core) | **84.4%** own tests / **86.3%** incl. widgets-suite hits | 1,622 |
| fleury_widgets | **90.3%** (worst file 77.5%) | 833 |
| fleury_web | not line-measured (browser); 195 VM + 149 Chrome tests + DOM parity oracle | 344 |
| fleury_example_console | semantic app-journey tests | 26 |

Combined core areas: semantics 94.8%, remote 94.4%, app kernel 92.5%,
debug 89.5%, effects 89.0%, rendering 87.8%, editing 87.5%,
widgets 87.5%. The honest low spots:

| Area / file | Coverage | Why |
| --- | --- | --- |
| `terminal/windows_driver.dart` | 12.7% (historical) | Deterministic mode-planning, EOF, and handoff lifecycle paths are now covered off-host; real console behavior remains a Windows release-device check |
| `runtime/run_tui.dart` | 59.1% | Real-terminal entry: signal handlers, suspend/resume, crash-restore paths — unreachable headless |
| `terminal/posix_driver.dart` | ~0 (historical) | Now covered by deterministic lifecycle/signal suites and real-PTY integration; this row preserves the original coverage snapshot |
| `widgets/key_bindings.dart` | 54.8% | Chord-sequence machinery partially covered |
| `runtime` area overall | 67.9% | Dominated by run_tui + hot-reload paths |

**Operational footgun, recorded:** a naive `dart test --coverage=DIR`
run silently produced JSON for only 10 of 142 suites (reporting 30%
coverage — wildly wrong), and `coverage:test_with_coverage` crashed
outright. The working recipe is per-directory collection:
`for d in test/*/; do dart test --coverage=COV "$d"; done` then
`format_coverage --lcov --report-on=lib`. Any future coverage gate must
encode this, and must sanity-check the JSON count against the suite
count before trusting the percentage.

## Methodology scorecard vs TUI best practice

What a strong TUI suite needs, and where fleury stands:

| Practice | Field reference | Fleury | Verdict |
| --- | --- | --- | --- |
| Headless determinism (fake driver/clock/tickers) | Textual pilot, ink-testing-library | `FleuryTester` + `FakeClock`/`FakeTickerScheduler`/`FakeDriver`/`TestClipboard` | **Strong** |
| Assertion ladder: semantic > structural > visual | Nobody has the semantic rung | `semantics()`/`accessibilitySnapshot()` (role/state/action/announcement asserts), `render().atColRow`, `matchesGolden` | **Beyond field** — semantic-first testing is unique |
| Golden/snapshot fence with review workflow | Textual SVG snapshots, teatest goldens | `test/goldens/` per widget × config, `FLEURY_UPDATE_GOLDENS=1`, review-every-diff doctrine | **Strong** |
| Input simulation (keys, typing, paste, mouse, resize) | varies | `sendKey/type/paste/sendMouse`, mutable `viewportSize`; 13 mouse suites, 7 resize suites | **Strong** |
| Incremental-engine oracles | none in field | 300-frame seeded byte-equivalence oracle; retained-vs-rebuilt semantics divergence oracle; web DOM parity oracle | **Beyond field** |
| Lifecycle/leak discipline | rare | 34/34 disposal correctness; post-dispose mutation is a tested lifecycle error | **Strong** |
| Perf regression gates | rare | web readiness gate + wire byte gate + oracle | **Beyond field** |
| Multi-surface testing | textual-web (untested parity) | same scenarios on VM + real Chrome + parity oracle | **Strong** |
| Untrusted-input fuzzing | rare but correct practice | Seeded byte-soup coverage drives malformed/truncated CSI, OSC, paste, UTF-8, mouse, and ordinary text across randomized chunk boundaries, asserting no throw, bounded output, and recovery | **Strong** |
| Real-PTY integration tests | teatest does this | Deterministic lifecycle seams plus a real-PTY suite cover boot, resize, startup termination, Ctrl+Z/`fg`, handoff, crash containment, and restoration | **Strong** |
| Capability-matrix testing | none in field | capabilities detection tested; widgets not systematically tested under degraded profiles | **GAP** (pairs with GlyphTier) |
| Coverage measurement + gate | standard | first measured today; no gate, no CI | **GAP** |

Verdict: **the suite is genuinely strong — top of the field on
methodology, with real coverage to back it** — and the remaining gaps are
specific, not systemic: capability matrices, platform-device checks, and the
absence of a coverage gate.

## The plan

**T1 — PTY integration suite — completed 2026-07-15.**
`test/integration/pty_run_app_test.dart` uses the existing openpty harness to
assert boot, resize, startup termination, Ctrl+Z/`fg`, child-process handoff,
crash containment, and restoration. Deterministic POSIX and Windows lifecycle
suites cover failure paths that are unsafe or platform-specific in the PTY
harness. Real Windows console behavior and native IME/accessibility behavior
remain release-device checks.

**T2 — input-parser fuzz suite — completed 2026-07-15.** The parser's
seeded-RNG suite mixes random bytes with truncated and malformed CSI/OSC,
broken UTF-8, bracketed paste, SGR mouse, SS3, and ordinary text across random
feed boundaries and idle flushes. It asserts no throw and bounded event output;
focused deterministic cases assert parser-state recovery and paste bounds.

**T3 — coverage made repeatable and floored.** A `fleury_dev coverage`
verb encoding the per-directory recipe + JSON-count sanity check +
per-package floors (core ≥ 80%, widgets ≥ 85%, windows_driver
excluded until the Windows pass). Manual gate alongside `check` and
`benchmark wire-gate` until CI exists.

**T4 — key_bindings headless coverage.** Chord sequences, timeouts
under FakeClock, conflict/precedence paths — pure unit work, no PTY
needed. Takes the worst non-platform file from 55% to normal.

**T5 — capability-matrix tests (rides with GlyphTier).** Parametrize a
spot-check suite across ColorMode (and GlyphTier when it lands) via
MediaQuery override, using storybook stories as fixtures — making
degraded-terminal rendering an asserted contract, not a hope.

Explicitly accepted: native Windows console and IME/accessibility checks remain
release-device work rather than pretending an off-host test proves them;
browser line coverage for fleury_web is still not worth the dart2js tooling
complexity because the Chrome suite, parity oracle, and readiness gate carry
that surface.
