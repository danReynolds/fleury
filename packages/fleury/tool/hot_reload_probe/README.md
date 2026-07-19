# Hot reload probe

Validates the three load-bearing assumptions that fleury's
state-preserving hot reload depends on, before any framework code is
written:

1. **Type identity across reload.** Is `instance.runtimeType` after a
   `reloadSources` cycle still `==` (and ideally `identical`) to a
   freshly-constructed instance's `runtimeType`? The widget reconciler
   compares widget types by `runtimeType`; if this property breaks,
   the reconciler would re-mount everything on every reload and
   discard `State<T>`.
2. **Instance identity.** Does an object reference captured before
   reload still point at the same heap object after reload? This is
   how `Element` and `State<T>` survive.
3. **Field preservation + method-body refresh.** Do the fields on a
   surviving instance keep their pre-reload values, while method
   bodies dispatch to the post-reload code?

## Files

- [`target.dart`](target.dart) — the program under test. Allocates a
  `Counter`, sets its value, and registers an `ext.fleury.probe`
  service extension that reports identity, type, fields, and current
  method output.
- [`driver.dart`](driver.dart) — spawns `target.dart` with the VM
  service enabled, captures the pre-reload snapshot, mutates the
  source by changing a string literal inside one of `Counter`'s
  methods, calls `reloadSources`, captures the post-reload snapshot,
  restores the source, and prints a structured before/after report.

## Running

From the package root:

```sh
dart pub get
dart run tool/hot_reload_probe/driver.dart
```

The driver:

1. Keeps the original `target.dart` contents in memory.
2. Restores those contents in a `finally` block on completion or handled error.
3. Exits non-zero if any of the three properties fails.

The probe is self-contained — no fixtures, no external services. The
target keeps itself alive on a short timer so the driver has time to
snapshot, reload, and snapshot again.
