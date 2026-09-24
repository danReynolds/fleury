# Reusable terminal input: architecture probes

These standalone experiments support
[RFC 0026](../../../docs/rfcs/0026-reusable-native-sessions.md). They do not change
Fleury's shipping input backend. Run from the repository root after resolving
`packages/fleury` dependencies. Python uses only its standard library.

```sh
python3 tool/experiments/reusable_terminal_input/check_probe.py --dart dart
python3 tool/experiments/reusable_terminal_input/check_probe.py --dart dart --reopen-tty
python3 tool/experiments/reusable_terminal_input/check_probe.py --dart dart --pause-handoff
python3 tool/experiments/reusable_terminal_input/check_probe.py --dart dart --file-stream
```

The default and reopened variants should report `PASS`. `--file-stream` is a
counterexample: `BLOCKED_CANCEL` means Dart file-stream cancellation did not
finish within two seconds while an idle PTY read was outstanding. The runner
terminates only its own process group, then closes its disposable PTY.

The flow warms one worker, checks 100 idle acquisition/release cycles and failed
entry for fd leaks, reads in raw mode, returns to a plain stdin prompt, runs a
shell child with inherited stdin, reads another plain prompt, starts another
raw reader, then verifies Dart stdin can still take its first async subscription.
It checks final termios/blocking mode and requires natural process exit. The
prototype measures warm transport startup/stop only; UI negotiation is absent.

For compiled-binary validation:

```sh
dart compile exe tool/experiments/reusable_terminal_input/input_probe.dart \
  --packages=packages/fleury/.dart_tool/package_config.json \
  -o /tmp/fleury-input-probe
python3 tool/experiments/reusable_terminal_input/check_probe.py \
  --executable /tmp/fleury-input-probe
```

`stale_exit_probe.dart` records a separate lifecycle regression: a timer from
the first UI used to exit the second UI. With invocation isolation it reports
`stale exit accepted=false`, and the second UI lasts approximately 700 ms.
The source prints the observed result; deterministic regression coverage lives
in `test/runtime/run_app_invocation_test.dart` inside `packages/fleury`.

```sh
dart --packages=packages/fleury/.dart_tool/package_config.json \
  tool/experiments/reusable_terminal_input/stale_exit_probe.dart
```

## Limits

This is not a production-ready reader. Worker failure/parent death, acquisition
rollback, callback exceptions, concurrent/idempotent stop, hangup/EOF, partial
Unicode, paste throughput, query boundaries, descriptor inheritance races, and
supervisor crash recovery still need integrated implementation and tests.
The reopened variant has no production device-identity validation. The
duplicate variant temporarily changes the shared `O_NONBLOCK` bit while active;
production must include it in restoration and supervised crash recovery.

Only the lowest 4,096 descriptors are counted. A blocking non-leaf FFI `poll`
occupies a worker thread while active. The design supports one native UI owner;
it is not a multiplexed terminal service.

The fixture uses actual POSIX PTYs with synthetic input and no controlling-shell
job control. It does not draw a Fleury UI, qualify Windows, or replace the
existing terminal lifecycle/real-terminal checks.
