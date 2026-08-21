# Changelog

## Unreleased

- **State-aware control styling.** Every core control keeps its existing
  `style: CellStyle(...)` common case and also accepts
  `CellStyle.state(...)` for focused, hovered, selected, disabled, and invalid
  treatments. `ThemeData.controlStyle` applies the same sparse policy app-wide.
  `TextInput.errorStyle` and `TextArea.errorStyle` are replaced by
  `style: CellStyle.state(invalid: ...)`; use `CellStyle.empty` to suppress
  inherited invalid chrome without changing validation semantics.

- **Focus boundaries.** `FocusScope.modal` is now `trapFocus`, describing its
  single responsibility: Tab, spatial traversal, pointer focus, and direct
  focus requests stay inside the subtree. Key propagation is independent;
  `KeyBindings.modal` remains the unmatched-key boundary, and
  `Navigator.present` composes both automatically. Focus traps use activation
  order so nested and sibling overlay popups hand focus off predictably.

- **Systematic terminal negotiation (RFC 0021).** `TerminalDriver.enter()` now
  returns one immutable semantic session profile and a sealed ANSI/structured
  presentation choice, so `runApp` no longer assembles capability truth from
  post-enter temporal getters. POSIX terminal queries share the input parser:
  typed CSI/OSC/DCS/APC replies go to a serialized, deadline-bounded query
  runner while ordinary interleaved user input continues; ambiguous response
  prefixes use a bounded late-reply quarantine. Terminal cleanup now records
  the effective selected mode, fixing Kitty fallback across suspend/handoff.
  Legacy coverage adds
  xterm modifyOtherKeys, SS3 keypad identity, Linux-console F-key sequences,
  and a prefix-safe `LegacyKeySequence` data seam without making terminfo a
  dependency.

- **Keyboard lifecycle (RFC 0020).** Key releases and held-state work out of
  the box: `runApp` requests the full Kitty keyboard protocol and capable
  drivers negotiate down transactionally — no flags, no tiers to declare, and a
  terminal that only partly honours the protocol is rolled back to the safe
  tier before the app sees a keystroke (inside tmux/screen the automatic ask
  stops at the safe tier; `FLEURY_KEYBOARD` overrides). New DX surface:
  `Keyboard.of(context)` (frame-latched `snapshot` with `isHeld` /
  `wasPressed` / `wasReleased`, reactive `capabilities`, `nextKey`),
  `KeyDetector`, `KeyBinding.hold`, `KeyPosition` spatial selectors,
  `aliases:`, `modal:`, and `includeRepeats:` — bindings now fire once per
  physical press, not once per auto-repeat. A surface caught claiming phase
  reporting it does not deliver demotes itself to press-only and the tree
  re-branches reactively; in debug builds the framework names controls that
  cannot work on the current surface. Breaking: `KeyBinding.event` /
  `KeyBinding.any` folded into the single `KeyBinding(...)` constructor
  (`onTrigger` receives the `KeyBindingEvent`), `FocusWithin` renamed
  `FocusDetector`, `Focus.onKey` replaced by `KeyDetector`.

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
