# Changelog

## 0.1.0

- **`Scope<T>` replaces `InheritedWidget` and `InheritedNotifier`.** One
  tree-local state primitive: `Scope(value: model, child: ...)` shares an
  object its owner keeps, `Scope<T>.create(create: ..., dispose: ...)` lets the
  scope own one (created on mount, disposed on unmount, `ChangeNotifier`
  disposed automatically), and `Scope.of<T>(context)` / `Scope.maybeOf<T>`
  read the nearest scope of that type from `build`, `initState`, or a handler.
  A `Listenable` value notifies readers through the scope; a plain value
  notifies when replaced by a non-equal one (`updateShouldNotify`). Removed:
  `InheritedWidget`, `InheritedNotifier`, `InheritedElement`,
  `BuildContext.dependOnInheritedWidgetOfExactType`,
  `BuildContext.getInheritedWidgetOfExactType`, `StatusHost`, and
  `StatusHostScope` (the status bar reads `Scope.of<StatusController>`). The
  framework's scopes (`MediaQuery`, `TickerMode`, `ClipboardScope`,
  `KeyboardScope`, `TuiBindingScope`, `FleuryAppScope`, …) are `Scope<T>`
  subclasses with the same constructors; their duplicate value getters
  (`MediaQuery.data`, `KeyboardScope.notifier`, `ClipboardScope.clipboard`,
  `LogBufferScope.buffer`, `TuiBindingScope.binding`) are gone — read through
  `.of`. `DefaultTextStyle` is a `StatelessWidget` over a private scope value.
  `Theme.of`, `Focus.of`, `Form.of`, and friends are unchanged.

- **Pointer input and selection.** TextInput and TextArea support click-to-caret,
  drag selection, Shift-click, and word/line selection. TextInput fills bounded
  width; constrain it explicitly when an inline field should be narrower.
  Pointer focus follows the presented, clipped hit order. Explicit SelectionArea
  regions receive selection focus without an extra Focus wrapper and accept an
  optional caller-owned `focusNode`.
- **Pointer callback migration.** Position callbacks take `PointerDetails`
  (`localPosition`, `globalPosition`, button, modifiers); drag callbacks take
  `PointerDragDetails` with delta and the original press position. Replace
  `(col, row)` callbacks and `onTapDownWithModifiers` with these details;
  `PointerDownDetails` is replaced by `PointerDetails`. The tap family is primary
  button only; use `onSecondaryTap` for right clicks or `onPointerDown` for raw
  button presses. `onTapCancel` and `onDragCancel` handle interruption, and
  `onDragUpdate` receives the first movement. Replace `PointerScrollListener`
  with `MouseRegion.onScroll`, returning whether the wheel step was handled.
  Nested scrolling honors `EdgeBehavior`, hover includes ancestor regions, and
  `MouseRegion.cursor` supplies browser cursor hints.

- **Editable semantic state.** Text inputs publish `textEditable` independently
  of role, enabled, and read-only state, allowing compound and custom fields to
  participate in shared field queries.

- **Complete test frames.** `FleuryTester.pumpWidget` and `pump` now build,
  lay out, paint, and then run post-frame callbacks. Tests can use layout-time
  children and pointer targets immediately after mounting. `render(size: ...)`
  also resizes the ambient `MediaQuery` and subsequent frames. Framework tests
  that need separate phases can use `mountWidget`, `owner.flushBuild()`, and
  `render` explicitly; set the viewport before mounting size-sensitive trees.
- **Semantic diagnostics.** Semantic action targeting resolves identity before
  availability, distinguishing `ambiguous`, `notFound`, `disabled`, and
  `unsupported` results. `SemanticTree.single` throws a `SemanticQueryError`
  (a `StateError`) with selectors, match count, and a redacted tree summary.

Initial public release.

A Dart-native terminal UI framework with Flutter-style ergonomics (widgets,
elements, state, layout) and terminal-native internals.

- **Widgets & layout** — a Flutter-shaped widget/element/render tree targeting a
  terminal cell grid.
- **Derived geometry** — a render object's screen position is derived from
  layout (`RenderObject.screenGeometry()`, over the `childOffsetOf` /
  `childClipOf` / `presentsChild` contract) and never recorded during paint.
  `paint(buffer, offset)` is a non-virtual template that debug-checks child
  placement against the contract; render objects override `performPaint`.
  Pointer hit-testing walks the tree, `FocusNode.rect` / `caretRect` are
  derived getters, semantic bounds derive at collection, and `BoundsNotifier`
  publishes a `RenderGeometry`. There is no `screenOffset` or `clipRect` paint
  parameter (RFC 0024).
- **Two surfaces** — render to a terminal, or serve the same app to a browser
  over a structured wire (`fleury serve`).
- **Semantics, built in** — interactive and content widgets contribute a
  meaningful semantic tree that powers the browser accessibility mirror, the
  testing API, and agent drivability (see the `fleury_mcp` package).
- **Open role vocabulary** — `SemanticRole` is a value type identified by
  name. Core declares the generic set (`SemanticRole.values`); any package
  declares further roles with `SemanticRole('kanbanCard', base:
  SemanticRole.listItem)`, and every surface projects an unfamiliar role
  through its `coreRole`. Declared names are identifiers and must not shadow
  a core name (asserted at collection); only the name and its core root travel
  the wire. Inspection JSON and the serve wire carry an additive `coreRole`
  field for declared roles.
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

- **State-aware control styling.** Every core control keeps its existing
  `style: CellStyle(...)` common case and also accepts
  `CellStyle.interactive(...)` for focused, hovered, selected, disabled, and invalid
  treatments. `ThemeData.interactiveStyle` applies the same sparse policy
  app-wide.
  `TextInput.errorStyle` and `TextArea.errorStyle` are replaced by
  `style: CellStyle.interactive(invalid: ...)`; use `CellStyle.none` to suppress
  inherited invalid chrome without changing validation semantics.
  `CellStyle.none` replaces `CellStyle.empty` for an explicit no-paint state;
  the reverse-video attribute remains the `inverse` flag and now documents its
  foreground/background swap directly.

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
  `Keyboard.of(context)` (latched `snapshot` with `isHeld` / `wasPressed` /
  `wasReleased`, reactive `capabilities`, `nextKey`) — sampled edges expire on
  the clock that reads them, so a tap survives whatever else the app renders
  between the press and the tick that samples it,
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
