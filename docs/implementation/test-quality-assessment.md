# Test Quality Assessment & Plan

**Date:** 2026-06-12
**Method:** Measured line coverage (per-suite VM collection, see recipe
below), full methodology inventory across all packages, scored against
TUI testing best practice.

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
| `terminal/windows_driver.dart` | 12.7% | Windows APIs can't run on the dev host; Windows validation is deferred post-MVP by decision |
| `runtime/run_tui.dart` | 59.1% | Real-terminal entry: signal handlers, suspend/resume, crash-restore paths — unreachable headless |
| `terminal/posix_driver.dart` | ~0 (no unit suite) | Real-TTY code (termios, SIGWINCH/SIGTSTP); exercised daily by the benchmark harness but not by a test |
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
| Untrusted-input fuzzing | rare but correct practice | only 2 seeded-RNG suites (ticker, renderer oracle); **input parser has 50 deterministic tests, zero fuzz** | **GAP** |
| Real-PTY integration tests | teatest does this | **none as tests** — the benchmark harness exercises PTY daily, but boot/resize/suspend/crash-restore have no test | **GAP** |
| Capability-matrix testing | none in field | capabilities detection tested; widgets not systematically tested under degraded profiles | **GAP** (pairs with GlyphTier) |
| Coverage measurement + gate | standard | first measured today; no gate, no CI | **GAP** |

Verdict: **the suite is genuinely strong — top of the field on
methodology, with real coverage to back it** — and the gaps are
specific, not systemic: the real-terminal seam (exactly the files
headless tests can't reach), fuzzing, capability matrices, and the
absence of a coverage gate.

## The plan

**T1 — PTY integration suite (the one real hole).** We already own the
machinery (`profiling/capture_pty.dart`, dart:ffi openpty). Add
`test/integration/pty_test.dart` (tagged, on-demand + pre-release):
spawn a small fixture on a real PTY and assert (a) boots and emits a
first frame; (b) SIGWINCH resize repaints at the new size; (c) SIGTSTP
suspend emits restore sequences and `fg` re-enters; (d) clean exit
restores the terminal (mouse-mode resets present); (e) kill mid-frame
still restores. This is what takes `run_tui`/`posix_driver` from
"exercised by benchmarks" to "asserted by tests."

**T2 — input-parser fuzz suite.** The parser is the untrusted-input
surface. Seeded-RNG suite (the renderer-oracle pattern): random byte
soup, truncated/malformed CSI/OSC/DCS, broken UTF-8, paste bombs —
asserting no-throw, bounded event output, and parser-state recovery.
Cheap; high assurance per line.

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

Explicitly accepted, not planned: windows_driver stays at ~13% until
the post-MVP Windows validation pass (testing it properly requires
Windows CI); browser line-coverage for fleury_web (dart2js coverage
tooling is not worth the complexity — the Chrome suite + parity oracle
+ readiness gate carry that surface).
