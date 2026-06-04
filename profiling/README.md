# fleury TUI profiling harness (all-Dart)

Compare fleury vs peer TUIs on language-agnostic, output-artifact axes (bytes on
the wire, frames, control overhead, ttfb) and band each: way-off / ballpark /
competitive / leading. Spec: `docs/implementation/profiling-harness.md`.

```sh
dart pub get
# 1. capture a framework's scenario app under a real pty (dart:ffi; POSIX)
dart run capture_pty.dart --out /tmp/fleury-scroll --timeout 5 -- <run command>
# 2. analyze one, or compare several captures of the same scenario
dart run analyze.dart fleury=/tmp/fleury-scroll nocterm=/tmp/nocterm-scroll
```

All Dart: `capture_pty.dart` uses `dart:ffi` (openpty + posix_spawnp) to run any
command under a real pseudo-terminal — no Python, no Flutter, no third-party pty
dep. `analyze.dart` runs every capture through fleury's `AnsiByteBreakdown`, so
the comparison is fair across languages. Next phase: per-framework self-driving
scenario apps + Tier-C (real-terminal/SSH) numbers.
