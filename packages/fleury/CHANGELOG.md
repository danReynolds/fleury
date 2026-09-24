# Changelog

- **Breaking:** `BuildOwner.rethrowContainedRenderErrors` is now
  `rethrowContainedErrors`, and it covers build errors as well as layout and
  paint. Under `FleuryTester`, a widget whose `build`, `initState`, or
  `didUpdateWidget` throws now fails the test instead of rendering an error
  panel. A test of the panel itself sets
  `tester.owner.rethrowContainedErrors = false`.
- **Breaking:** `BuildOwner.onBuildError` reports exactly the errors the
  `errorBuilder` contains. An error that propagates instead, on an owner with
  no `errorBuilder` or under `rethrowContainedErrors`, is no longer reported
  before it is rethrown.
- **Breaking:** `FleuryTester`'s build-only helpers (`mountWidget`, `sendKey`,
  `type`, `press`, `paste`, `sendMouse` and the other input helpers, and
  viewport changes) build as part of the next frame, as input does in the
  runtime. A subtree they remove is disposed when that frame renders (`pump`,
  `render`, `pumpAndSettle`, `settle`) or when the tester is disposed, not
  immediately after the helper returns.
- A child that throws while it mounts or updates (in `initState`,
  `didUpdateWidget`, a render object's create or update, or on a duplicate
  key) is contained like a thrown `build`. The nearest building ancestor
  shows the error panel in its place and the session keeps running. Before,
  the whole screen became an error, siblings could be lost, and a parent
  that rebuilt every frame tore the session down. A `LayoutBuilder` whose
  builder throws shows the panel in its own slot too; an `ErrorBoundary`
  above it no longer sees that error, as it never saw a thrown `build`.
- A resize whose root rebuild throws fails that frame and is retried on the
  next one. Before, the error escaped the frame driver on every later frame.
- Frames, animation ticks, and the error banner's dismiss timer run in
  `runApp`'s guarded zone, whoever requested them. A frame requested from a
  listener created in `main()` used to run outside the guard, so a failing
  post-frame callback killed the process and left the terminal raw. A host
  that builds its own runtime builds it inside the zone that guards it.
- A frame that a frame causes, such as a post-frame callback or a `setState`
  from a microtask the frame queued, renders when the event-loop turn ends.
  Input, timers, and signals now run between the frames of such a chain;
  before, the chain starved the event loop until it ended.
- Unkeyed children keep their State when siblings around them change. The
  reconcile keeps the unchanged top and bottom in place and matches the
  changed middle by type, in order. A `TextInput` draft survives an error
  line appearing above it, and a spinner above it going away while a hint
  below it becomes an error. A sliding window of mixed row types updates
  its rows in place instead of re-creating them.
- A `GlobalKey`'d subtree that moves into a `LayoutBuilder`, such as a panel
  maximized into one, keeps its State, whether `setState`, a terminal resize,
  or a `FleuryTester` helper caused the move. `BuildOwner` gains
  `beginFrame`/`endFrame`/`runFrame` for hosts whose frame starts with a
  build of their own; `FrameDriver` runs a resize's root rebuild in the frame
  it renders.
- A frame whose layout throws still disposes the subtrees its build removed.
- `LayoutBuilder` builds what its builder dirtied, such as the readers of a
  `Scope` fed from constraints, before its child lays out. Those readers show
  the current size instead of the previous one.
- `Animation.loop` keeps running through hot reload. Pulse, shimmer, and
  other repeating effects no longer freeze after the first reload.
- Debugger mode changes preserve application state and layout. Opening the
  shell starts a bounded 60-frame recording that continues while hidden;
  Rebuilds shows the worst frame's phase costs. Inspector reports scroll with
  Page Up/Down, Errors includes full traces, and Tree reports hyperlink and
  input/clipboard policies. Debugger tabs expose semantic activation, and the
  host SPI exports the optional diagnostics services used by the live guide.
- A keyed `ListView` that grows by appending validates and indexes only the
  new keys instead of rebuilding its key index; a duplicate in the append
  still throws and leaves the previous keys intact.
- A list that follows its tail keeps its cursor on the newest item:
  `ListController(followTail: true)` starts on the last item and carries the
  cursor along as items arrive, until an arrow key, click, or `currentIndex`
  places it; End, or `jumpToEnd` on a following list (as `LogRegion` and
  `MessageList`'s `scrollToBottom` do), puts it back on the tail. Previously the cursor stayed on the
  first item, off-screen, so Ctrl+C in a tailing log copied the oldest line and
  the first arrow key jumped the view back to the start. The default
  `initialIndex` is now `ListController.natural` (the first item, or the last
  for a following list); an explicit index or null behaves as before.
- **Breaking:** a scope is read one way, as a call or as a widget:
  `context.scope<T>()` or `ScopeBuilder<T>`, which behave the same.
  `Scope.of` and `Scope.maybeOf` are removed; an optional scope is read with a
  nullable type, `context.scope<T?>()` / `ScopeBuilder<T?>`. A scope can be
  read in `build`, `initState`, `didChangeDependencies`,
  `createRenderObject` / `updateRenderObject`, and `Scope.createWithContext`
  factories; event handlers and callbacks use a value read there. A reader
  stays subscribed until it leaves the tree — a read in
  `didChangeDependencies` is no longer dropped by the next `setState`, and a
  `GlobalKey` move carries the subscription to the same scope type at the new
  position (an `initState` read used to go deaf). `context.listen` in
  `didChangeDependencies` now throws: it subscribes a build.
- **Breaking:** reading `Animation.value` in build subscribes the widget the
  way `context.listen` does, so a widget whose build stops reading an
  animation is no longer rebuilt on every tick. `Element.dependOnExternal` and
  `Animation.debugDependentCount` are removed; test with `hasListeners`.
  Widgets that keep reading the same listenables skip the per-build
  reconcile walk.
- **Breaking:** compatibility names are gone, with no aliases: `ChangeNotifier`
  (use `Notifier`), `notifyListeners()` (override and call `notify()`),
  `ListenableBuilder` and `ValueListenableBuilder` (use `NotifierBuilder` or
  `context.listen`; where `child:` kept a subtree from rebuilding, build that
  widget once outside the builder and reference it inside), and
  `ListController.pinToBottom` (use `followTail` and `isFollowing`). The
  vertical spellings `atTop` / `atBottom` / `jumpToBottom` on `ListController`
  and `atTop` / `atBottom` / `scrollToTop` / `scrollToBottom` on
  `ScrollController` are removed in favour of `atStart` / `atEnd` /
  `jumpToEnd` / `scrollToStart` / `scrollToEnd`.
- **Breaking:** `RenderObject.markNeedsPaint()` is removed. It invalidated
  layout as well as paint, as a safe default for unaudited setters; call
  `markNeedsLayout()` when a change can affect size, constraints, or offsets,
  and `markNeedsPaintOnly()` when it cannot.
  `RenderDamageTracker.recordLayoutOrConservativePaint()` is now
  `recordLayout()`.
- **Breaking:** the remote wire is lockstep in the app as well as in its peers.
  The app rejects a structured peer of any other protocol version at INIT —
  after echoing its own so the peer can report the skew — instead of serving
  it down-shifted plans. Links and clipped-image windows are always encoded,
  decoders reject unknown frame types and image fits, and
  `semanticActionTargetTokenProtocolVersion` is removed from `fleury_wire.dart`.
- **Breaking:** remote wire protocol v7: every frame is fixed-shape. Key
  events always carry their position/synthesized pair, a paste always carries
  its phase, `SEMANTIC_ACTION` always carries its token-presence byte, and PLAN
  flag bit 2 is gone (placements always carry their window). INIT requires `v`,
  `color`, `glyph`, `image`, and `tmux`, and rejects an unrecognized value for
  any param instead of defaulting it.
- **Breaking:** `AppSignal` gains `hangup`. A terminal hangup (window closed,
  SSH session dropped) — seen as SIGHUP or as the terminal's input ending —
  now arrives once as `SignalEvent(AppSignal.hangup)`, so the app exits through
  its normal path with its cleanup intact (exit code 129 by convention).
  Previously SIGHUP's default action killed the process before any cleanup.
  Only a read error that says the terminal is gone (EIO, ENXIO) counts as a
  hangup; any other terminal read error reaches the app's event stream.
- `CellBuffer.writeGrapheme` writes only the first grapheme cluster of its
  argument, so a string carrying a control sequence can no longer reach the
  terminal through it; use `writeText` for text.
- Layout and paint error panels sanitize the error text like any other
  displayed string.
- A grapheme cluster that opens with zero-width code points, such as a Prepend
  mark (U+0600 ARABIC NUMBER SIGN and the other prepended concatenation marks),
  is as wide as its first spacing character. It measured zero cells, so the
  visible character was never painted. Terminals disagree about such clusters,
  so `hasUncertainWidth` now reports them and the renderer pins the next cell.
- `widthOfText` always equals the sum of its clusters' widths. Its ASCII fast
  path no longer splits an ASCII character from a spacing mark or other
  joining mark that follows it.
- `fleury serve` never runs a network bind without a token: without
  `--token`, it generates one for the run. The ready banner prints the full
  browser URL including the token (IPv6 hosts bracketed), and the token check
  is constant-time.
- The `runApp` shutdown example uses the real `onEvent:` parameter.
- Add `Notifier.notify()`, typed `NotifierBuilder`, `ScopeBuilder`, and
  `context.listen(model)` / `context.scope<T>()` readers. `context.listen`
  detaches sources a later build no longer reads. `ValueNotifier` uses the
  same consumers.
- **Breaking:** scopes now take their value or factory positionally:
  `Scope(model, child: ...)` and `Scope.create(Model.new, child: ...)`.
  Context-dependent factories use
  `Scope.createWithContext((context) => ..., child: ...)`.
- Update first-party controllers, examples, Storybook, showcases, and guides
  to the local, tree, and global state APIs.

- `ListView` using the built-in `ListController` no longer rebuilds again after
  publishing its completed viewport metrics. Listeners still receive those
  metrics, and commands and explicit refreshes issued during delivery still
  update the list. Controller subclasses retain their existing rebuild behavior.

- Add `TextEditPolicy` to `TextEditingController` for bounded fields: reject
  invalid edits before commit, preserve selection and undo/redo, and admit
  streamed pastes atomically without buffering beyond the configured limit.

## 0.1.0

- Inline images respect later text and opaque popup backgrounds across cached,
  web, remote and terminal composition. Visible slices retain the original fit
  box; transparent and letterboxed areas inherit the painted background.
  Image-only visibility changes invalidate retained frames.
- Browser cell rendering supports the four outer-edge corner glyphs
  U+1FB7C–U+1FB7F, including their single-cell surrogate-pair encoding.

- Repaint caches remain invalid after a paint exception, including nested
  caches. Focus and semantic geometry now honor the cache's layout-size clip,
  including when caching is enabled or disabled at runtime.
- Keyed `ListView.builder` and `.separated` reuse their reverse lookup when
  a parent rebuild leaves the ordered keys unchanged. Every key is still
  checked, including offscreen duplicates, and visible row content updates.
- `Align` and `Center` loosen child constraints even when one axis is
  unbounded. Links in stretching columns retain their content width, and
  alignment still applies on the bounded axis.

- **Breaking:** `Button.label` is now `Button.text`. Provide exactly one of
  `text` or the new `child` slot; both and neither are rejected, including
  when building with assertions disabled. Both forms retain the button frame,
  focus/hover/disabled styling and keyboard, pointer and semantic activation.
  `semanticLabel` names composed content without announcing decorative text.
  `ButtonAppearance.plain` removes the frame and left-aligns content while
  retaining the same keyboard, pointer, focus and semantic behavior.

- `Container.color` changes, including null transitions, preserve stateful
  descendants. The stable background layer paints nothing when color is null;
  editors retain text/selection/focus and lists retain their viewport.

- **Breaking:** `Focus.of` / `Focus.maybeOf` now return the nearest enclosing
  `FocusNode` instead of the `FocusManager`. The manager moved to
  `FocusManager.of` / `FocusManager.maybeOf`. An item builder can now render
  from the focus state of the region it is inside — `Focus.of(context).hasFocus`
  — instead of comparing `FocusManager.focusedNode` against a node the caller
  had to thread in by hand. Reading either still subscribes the caller to focus
  changes, so a build method can keep `FocusNode.hasFocus` current without a
  detector. `hasFocus` is identity with the focused node; `FocusDetector`
  remains the descendant-inclusive signal. `KeyBindings` and `KeyDetector`
  join the input chain without being `Focus` targets, so `Focus.of` from
  inside them returns the enclosing focusable region rather than a mailbox
  whose `hasFocus` is always false.

- Add `scrollDirection: Axis.horizontal` to all `ListView` constructors,
  `ScrollView`, and `Scrollbar`. Horizontal views support left/right navigation,
  native horizontal wheel input, Shift+wheel, clipping, and bottom scrollbars.
- Add axis-neutral controller edge helpers (`atStart` / `atEnd`,
  `scrollToStart` / `scrollToEnd`, and `ListController.jumpToEnd`). Existing
  vertical spellings remain supported.

- ListView applies the theme's current-row text highlight in all constructors.
  Plain Text children and builders no longer need to paint their own cursor;
  explicit child styles and the builder flag remain available for customization.

- **Text controller cleanup.** Disposal now releases the current value as well
  as editing history; getters read empty state after disposal. Assigning equal
  text or an equal editing value still resets undo/redo and composition history.
  Listeners are notified when that reset changes history, even if text is unchanged.
- **Sensitive multiline input.** `TextArea.obscureText` masks display and
  redacts semantic values and clipboard capture, while preserving an explicit
  disabled clipboard policy. Reveal/hide keeps the same editing controller;
  masked mouse selection does not disclose word boundaries.
- **Application-owned suspension.** `PosixTerminalDriver(suspendOnCtrlZ: false)`
  delivers Ctrl+Z to the application. Raw startup fails if native termios is
  unavailable, rather than silently restoring kernel-owned suspension.
  Terminal restoration uses an owned close-on-exec descriptor even after
  stdin closes.
- **RichText spaces.** Ordinary spaces retain their source span's styling,
  including inverse highlights, backgrounds and underline across span edges.
- **Separated-list pointer behavior changed.** Clicking a separator no longer
  moves the cursor or selects the preceding item. Only completed clicks on items
  select; keyboard indices and navigation are unchanged.
- **Paste lifetime.** `TextPastePolicy.immediate()` applies each received segment
  synchronously for bounded forms. Default chunked paste still discards pending
  work on unmount; surviving external controllers do not own that pending work.
- **Core Button.** `Button` and `ButtonVariant` now come from `fleury_core.dart`
  (also reexported by `fleury.dart`), without the companion image dependency.
  Existing `fleury_widgets` imports reexport the same implementation.

- Navigation controllers use one-time constructor seeds: `ListController(initialIndex:)`
  and `ScrollController(initialOffset:)`. Their live `currentIndex` and `offset`
  properties remain mutable. Each viewport controller accepts one active owning
  view and releases it on deactivation, including replacement and GlobalKey moves.
- TextInput and TextArea `onChanged` now report user and semantic edits only.
  Programmatic controller writes still update views, form state, and controller
  listeners. Observe the controller for changes from every origin. Shared text
  controllers emit the interaction callback only on the field that was edited.
- Completion and history browsing expose `currentIndex`; completion also uses
  `currentOption`, `focusOption`, and `moveCurrent`. Accepting a suggestion remains
  a separate operation from browsing to it. Semantic completion state exposes
  `completionCurrentIndex` in place of `completionSelectedIndex`.

- **List scrolling and navigation.** Wheel, scrollbar, and `jumpToIndex` move the
  viewport without moving the cursor; jumps survive rebuilds. Keyboard navigation
  reveals the current item. Oversized rows can scroll within an item.
  `ListController` now exposes `scrollBy`, fractional scrollbar metrics, and
  post-frame viewport notifications; `ScrollController` also notifies after its
  layout metrics change.
- **Following output.** Use `followTail` for the enabled policy and `isFollowing`
  for its current state. Leaving the end pauses following; returning resumes it
  only when enabled. Following appends preserve the current item. `jumpToEnd`
  does not enable following on ordinary lists.
- **List interaction.** Primary down moves the cursor and focuses the list;
  a completed click or Enter selects the item. Dragging away, cancellation, or
  removing the keyed item cancels the choice. Replace `ListView.onActivate` with
  `onSelect`, `onSelectionChanged` with `onFocusedItemChanged`, and
  `ListController.selectedIndex` with `currentIndex`. Browsing reports a changed
  current item; repeated choices still call `onSelect`. Controller writes and
  scrolling do not emit either callback. An explicit null initial cursor is
  honored; `selectable: false` leaves interaction to child controls. The builder's
  `highlighted` boolean always marks the current item, including while keyboard
  focus is elsewhere; `selectionActive` / `highlightCurrentItem` are removed.
- **Keyed lists.** Supply only `itemKeyBuilder`; `findChildIndexCallback` and
  `ListItemIndexCallback` are removed. ListView builds and validates the reverse
  map once per widget configuration in O(itemCount) time and space, including
  offscreen keys. Row widgets still mount lazily. `ListController(initialIndex:
  n)` reveals its initial item without firing callbacks or taking focus.

- **`Scope<T>` replaces `InheritedWidget` and `InheritedNotifier`.** One
  tree-local state primitive: `Scope(value: model, child: ...)` shares an
  object its owner keeps, `Scope<T>.create(create: ..., dispose: ...)` lets the
  scope own one (created on mount, disposed on unmount, `ChangeNotifier`
  disposed automatically), and `Scope.of<T>(context)` / `Scope.maybeOf<T>`
  read the nearest scope of that type from `build`, `initState`, or a handler.
  A `Listenable` value notifies readers through the scope; a plain value
  notifies when replaced by a non-equal one (`updateShouldNotify`). Removed:
  `InheritedWidget`, `InheritedNotifier`, `InheritedElement`,
  `BuildContext.dependOnInheritedWidgetOfExactType`, and
  `BuildContext.getInheritedWidgetOfExactType`. The framework's scopes
  (`MediaQuery`, `TickerMode`, `ClipboardScope`, `KeyboardScope`,
  `TuiBindingScope`, `FleuryAppScope`, …) are `Scope<T>` subclasses with the
  same constructors; their duplicate value getters (`MediaQuery.data`,
  `KeyboardScope.notifier`, `ClipboardScope.clipboard`,
  `LogBufferScope.buffer` / `.notifier`, `TuiBindingScope.binding`,
  `SelectionScope.registrar`, `FleuryAppScope.notifier`,
  `CommandRegistryScope.notifier`) are gone — read through `.of`;
  `PointerRouterScope.router` and `TerminalSessionScope.session` stay.
  `DefaultTextStyle` is a `StatelessWidget` over a private scope value.
  `Theme.of`, `Focus.of`, `MediaQuery.of`, and friends keep their signatures;
  `Form.of` readers now rebuild when the controller notifies (see the
  fleury_widgets changelog).
- **Unicode shortcuts.** Legacy Alt input retains its modifier across UTF-8
  reads instead of becoming ordinary text input.
- **Focus ownership.** Retained controls, traps, and exclusion scopes follow
  manager replacement; focus requests reject nodes owned by another session.
- **Reentrant paste.** Synchronous model listeners can start another paste
  without truncating accepted content or splitting its undo transaction.
- **Navigation cancellation.** Removing an entering replacement or stack-clear
  route no longer lets its cancelled transition delete the revealed route.
- **Overlay ownership.** Invalid insertions and initial entry lists are checked
  before attachment, preserving the original owner and allowing safe retries.
- **Remote startup.** Teardown resolves pending handshakes, overlapping startup
  calls are rejected, and peer failures cannot reactivate a closing session.


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
