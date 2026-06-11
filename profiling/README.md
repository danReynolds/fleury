# fleury TUI profiling harness (all-Dart)

Compare fleury vs peer TUIs on language-agnostic output axes (bytes on the wire,
frames, control overhead, ttfb) plus field-standard runtime axes (RSS, CPU load,
sustained FPS) and band each: way-off / ballpark / competitive / leading. Spec:
`docs/implementation/profiling-harness.md`.

```sh
dart pub get
# 1. capture a framework's scenario app under a real pty (dart:ffi; POSIX)
dart run capture_pty.dart --out /tmp/fleury-scroll --timeout 5 --ui-mode strict-ui -- <run command>
# 2. analyze one, or compare several captures of the same scenario
dart run analyze.dart fleury=/tmp/fleury-scroll nocterm=/tmp/nocterm-scroll
```

Preferred full-ui first-reading commands:

```sh
fleury benchmark wire sb1 --runs=3
fleury benchmark wire sb2 --runs=3
fleury benchmark wire sb3 --runs=3
fleury benchmark wire sb4 --runs=3
fleury benchmark wire sb5 --runs=3
fleury benchmark wire sb6 --runs=3
fleury benchmark wire sb7 --runs=3
fleury benchmark wire sb8 --runs=3
fleury benchmark wire sb9 --runs=3
fleury benchmark wire sb10 --runs=3
fleury benchmark wire sb11 --runs=3
fleury benchmark wire sb12 --runs=3
# Narrow when needed:
fleury benchmark wire sb3 --peers=ratatui,opentui --runs=3
fleury benchmark wire sb5 --peer=ink --runs=3
# Inspect before running:
fleury benchmark wire sb3 --list-peers
fleury benchmark wire sb3 --help
```

Bare scenario IDs run every configured primary peer for that scenario. These
build the Fleury and peer wire apps, install fixture-local peer dependencies
when needed, capture paired PTY runs, and analyze Fleury against every selected
peer in one report. Capture artifacts are written under `profiling/caps/`.
`benchmarks/README.md` is the source of truth for scenario priority, focus, and
peer selection rationale.

Each `fleury benchmark wire ...` run also refreshes `scoreboard.md` inside the
selected capture directory. Regenerate or redirect it explicitly with:

```sh
fleury benchmark scoreboard --input=profiling/caps --output=profiling/caps/scoreboard.md
dart run scoreboard.dart --input=caps --output=caps/scoreboard.md --matrix-link=../../benchmarks/README.md
```

Lower-level manual helpers:

```sh
dart compile exe bin/fleury_sb4_wire.dart -o /tmp/fleury_sb4_wire
(cd ../peer-fixtures/bubbletea/sb4_log_region && go build -o /tmp/bubbletea_sb4_wire .)
dart run capture_pty.dart --out /tmp/fleury-sb4-wire --timeout 8 --cols 120 --rows 32 --ui-mode full-ui -- /tmp/fleury_sb4_wire --rows=200 --append=10 --steps=5 --interval-ms=100
dart run capture_pty.dart --out /tmp/bubbletea-sb4-wire --timeout 8 --cols 120 --rows 32 --ui-mode full-ui -- /tmp/bubbletea_sb4_wire --wire --rows=200 --append=10 --steps=5 --interval-ms=100 --size=120x32
dart run analyze.dart fleury=/tmp/fleury-sb4-wire bubbletea=/tmp/bubbletea-sb4-wire

dart compile exe bin/fleury_sb5_wire.dart -o /tmp/fleury_sb5_wire
(cd ../peer-fixtures/bubbletea/sb5_streaming_markdown && go build -o /tmp/bubbletea_sb5_wire .)
dart run capture_pty.dart --out /tmp/fleury-sb5-wire --timeout 15 --cols 120 --rows 32 --ui-mode full-ui -- /tmp/fleury_sb5_wire --rows=200 --steps=16 --interval-ms=50
dart run capture_pty.dart --out /tmp/bubbletea-sb5-wire --timeout 15 --cols 120 --rows 32 --ui-mode full-ui -- /tmp/bubbletea_sb5_wire --wire --rows=200 --steps=16 --interval-ms=50 --size=120x32
dart run analyze.dart fleury=/tmp/fleury-sb5-wire bubbletea=/tmp/bubbletea-sb5-wire
```

All Dart: `capture_pty.dart` uses `dart:ffi` (openpty + posix_spawnp) to run any
command under a real pseudo-terminal — no Python, no Flutter, no third-party pty
dep. `analyze.dart` runs every capture through fleury's `AnsiByteBreakdown`, so
the byte comparison is fair across languages. `--ui-mode strict-ui|full-ui`
keeps raw-buffer and layout-engine comparisons honest. Next phase:
per-framework self-driving scenario apps + Tier-C (real-terminal/SSH) numbers.

## Wire regression gate

`bin/fleury_wire_gate.dart` (or `fleury benchmark wire-gate`) re-runs a
fleury-only scenario subset — SB.1 (startup/session bytes), SB.6
(dashboard steady state), SB.9 (untrusted-output encoding) — and
compares medians against `wire_gate_baseline.json`. Byte axes
(totalBytes, bytes/frame, overhead percent) FAIL on regression beyond
tolerance; timing axes (TTFB, frame count) warn only, because PTY
timing is machine- and load-sensitive. SB.1 and SB.9 reproduce to the
byte; SB.6 varies under 1% run-to-run.

After an intentional, measured encoder change, refresh the baseline in
the same commit:

```sh
dart tool/fleury_dev.dart benchmark wire-gate --update-baseline
```

There is no CI in this repo yet; run the gate before any commit that
touches `ansi_renderer.dart`, `cell_buffer.dart`, or
`terminal_sequences.dart`. The byte-equivalence oracle covers
correctness; this gate covers cost.
