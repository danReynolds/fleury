# fleury TUI profiling harness

Compare fleury vs peer TUIs on language-agnostic, output-artifact axes (bytes on
the wire, frames, control overhead, ttfb) and band each: way-off / ballpark /
competitive / leading. Spec: `docs/implementation/profiling-harness.md`.

```sh
# 1. capture a framework's scenario app under a real pty
python3 capture_pty.py --out /tmp/fleury-scroll --timeout 5 -- <run command>

# 2. analyze one or compare several (same scenario)
dart pub get
dart run analyze.dart fleury=/tmp/fleury-scroll nocterm=/tmp/nocterm-scroll
```

`capture_pty.py` is framework-agnostic (any command). `analyze.dart` runs every
capture through fleury's `AnsiByteBreakdown`, so the comparison is fair across
languages. Next phase: per-framework self-driving scenario apps + Tier-C
(real-terminal/SSH) numbers.
