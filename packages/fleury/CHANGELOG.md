# Changelog

## Unreleased

- Automatic hot reload for plain `dart run` sessions: a built-in dev
  supervisor re-spawns the app with the VM service enabled, watches the
  package sources (root package + local path deps), and hot reloads on save
  — any editor, no flags, no extension. Reload telemetry and compile errors
  surface in the debug shell (Logs / Errors tabs). Opt out with
  `FLEURY_HOT_RELOAD=0` or `runApp(enableHotReload: false)`.
- Hot restart: `ext.fleury.restart` tears the app down gracefully and
  re-runs `main()` fresh in the same terminal session (for the edits reload
  can't apply). `ext.fleury.shutdown` and `ext.fleury.reloadReport` complete
  the dev-tooling service-extension surface.
- Apps spawned under `fleury serve --spawn` self-reload on save when the
  spawn command itself enables the VM service (e.g. `dart
  --enable-vm-service=0 run bin/main.dart`) — the browser preview updates
  live; restart is intentionally disabled there. Hot restart is also
  available from the debug shell: `Ctrl+G`, then `F5` (dev-supervisor
  sessions).

## 0.1.0

Initial public release.

A Dart-native terminal UI framework with Flutter-style ergonomics (widgets,
elements, state, layout) and terminal-native internals.

- **Widgets & layout** — a Flutter-shaped widget/element/render tree targeting a
  terminal cell grid.
- **Two surfaces** — render to a terminal, or serve the same app to a browser
  over a structured wire (`fleury serve`).
- **Semantics, built in** — interactive and content widgets contribute a
  meaningful semantic tree that powers the browser accessibility mirror, the
  testing API, and agent drivability (see the `fleury_mcp` package).
- **Fail-closed positional actions** — actionable positional nodes carry an
  app-issued per-element, per-slot target lease. Value/focus/ticking updates
  retain it; role/label/action changes, target removal, and contributor remount
  rotate it so a held browser/agent action cannot silently invoke an observably
  recycled target. A key or stable semantic id distinguishes semantically
  identical logical replacements that share framework identity.
- **Host SPI** — `fleury_host.dart` / `fleury_host_io.dart` expose the supported
  runtime, damage, semantics, and process-lifecycle contracts a platform host
  builds on.
- **Lockstep remote wire** — frame, codec, and transport contracts live in the
  explicitly unstable `fleury_wire.dart` / `fleury_wire_io.dart` entry points
  for first-party browser and agent peers built against the same Fleury version.
- **Bounded remote output** — the Unix-socket sender retains at most 64 MiB and
  4096 pending frames; a stalled peer that exceeds either bound tears down the
  session cleanly instead of growing the heap or dropping a diff frame.
- **Wire byte order** — DEBUG_RESPONSE sequence ids now obey the protocol's
  big-endian integer rule, guarded by an exact-byte test.
- **Testing** — the companion `fleury_test` package drives apps and asserts on
  the semantic tree without adding test libraries to production dependencies.
- **Developer CLI** — `fleury create` generates a tested application with a
  terminal-safe VS Code F5 setup, while `fleury shell` provides a guarded
  real-terminal fallback for debuggers that expose only a non-TTY output pane.
