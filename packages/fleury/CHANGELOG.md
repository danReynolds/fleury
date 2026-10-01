# Changelog

## 0.1.0

- **The debug panel expands with `f` as well as F11.** VS Code's integrated
  terminal, Windows Terminal, GNOME Terminal, and macOS often take F11 before
  the app sees it. While the panel is open, `f` expands or docks it.

- **`FocusDetector` nests like CSS `:focus-within`.** Every detector around
  the focused widget reports focus, not only the nearest one. A `Panel` now
  accents while focus is inside a `LogRegion`, `DataTable`, or another widget
  that watches focus itself; nested panels all accent; and a `Tooltip` around
  such a widget shows.

- **"What has focus" names the node that holds it.** A semantic node's
  `focused` flag is also set by a region with focus inside it, such as a
  `Panel` around a focused `Button` or `LogRegion`, and that region comes
  first in tree order. The inspection snapshot's `focusedNodeId` (what agents
  read through `fleury_mcp`), `AccessibilitySnapshot.focusedNode`, the browser
  host's active semantic node, and the debug shell's focus rows named the
  panel. They now take the deepest focused node, which the new
  `SemanticTree.focusedNode` returns: the control with the keys, or the row a
  focused `DataTable` marks as current.

- **Debug tooling defaults on only for development runs.** A null
  `DebugConfig.enabled` (the default) enables the Ctrl+G debug shell, F12 logs,
  and the `read_frames`/`read_logs`/`read_errors` records when the Dart VM runs
  the app's `.dart` source entrypoint (`dart run bin/app.dart`, `fleury run`,
  and apps that `fleury serve --spawn` or `fleury_mcp` start that way) or
  assertions are enabled. Compiled code gets none: snapshots pub precompiles
  (`dart pub global activate` installs, and executables started by name with a
  bare `dart run` or `dart run <package>:<exe>`), `dart compile` output, and
  dart2js bundles. Previously every JIT run had it, so globally activated apps
  shipped the debug shell to their users. `DebugConfig.enabled` is now
  `bool?`; an explicit value still wins, and `DebugController.enabled` reports
  the session's answer.

- **Ctrl+Z is dispatched first.** In a native POSIX terminal, Ctrl+Z now
  reaches the application like any key: a focused `TextInput` or `TextArea`
  undoes, and application bindings fire. Only a press nothing handles suspends
  — the rule Ctrl+C already follows for exit. Suspending restores the
  terminal and stops the whole job the shell started, including the
  hot-reload supervisor of a plain `dart run` and the `fleury run` launcher,
  so one press returns the prompt and `fg` resumes the app; before, under
  either, the app stopped alone and the shell never got the terminal back.
  While the debug shell is expanded over the app, Ctrl+Z skips the hidden
  app; its open Logs search takes the key.
  `PosixTerminalDriver(suspendOnCtrlZ: false)` keeps an unhandled Ctrl+Z an
  ordinary key. Browser, served, and `fleury shell` sessions never suspend.

- **`fleury shell` relays every key, and the mouse.** The shell now puts its
  terminal in the same raw mode a native app uses, so Ctrl+C, Ctrl+Z, Ctrl+\\
  and Ctrl+S reach the attached app instead of signaling the shell. The app's
  `TerminalMode` now takes effect in the shell's terminal too: `mouse: true`
  brings clicks, drags, and the wheel (the `fleury create` counter's button
  can be clicked), `mouseMotion: true` adds hover, and bracketed paste, focus
  reports, and a legacy keyboard tier follow the app's choice, where the shell
  used to force paste and focus on and never turn the mouse on. The shell
  restores the terminal exactly on every exit path (the app exits or is
  killed, SIGINT, SIGTERM, SIGHUP, or a hangup, which now exits 129), keeps
  serving later runs until you press Ctrl+C with no app attached, and discards
  keys typed while no app was attached. It speaks a wire protocol of its own
  now, versioned apart from the browser's: an app and a shell from different
  Fleury versions are turned away with the reason, and `dart run fleury shell`
  in the app's package runs the matching shell.

- **Key sequences work in dialogs, and Esc aborts them cleanly.** A
  multi-key sequence bound inside a `KeyBindings(modal: true)` scope, such as
  every dialog `Navigator.present` shows, now starts and completes there;
  bindings outside the modal scope stay out of reach. An unmodified Esc that
  can't continue a pending sequence aborts it: the held keys are dropped and
  the Esc does nothing else. `KeyBindings.cancelPending` aborts the same way.
  If focus moves away mid-sequence, as when a dialog opens in front of it, the
  sequence ends and the keys typed so far are dropped, so a held `y` can never
  answer a prompt that appeared after it was typed.

- The CLI reports its package version through `--version` and `diagnose`.
  `serve` reports invalid or occupied ports cleanly, releases startup resources,
  and prints the selected browser URL when `--port=0` chooses a free port.

- `LogBuffer`, `LogLine`, `LogSource`, `LogBufferScope`, `OutputCaptureView`,
  and `OutputCaptureConsole` are exported from `fleury_core.dart`, so browser
  apps can fill a log buffer and show it. `fleury.dart` still exports them.
- Keyed eager and lazy ListView rows retain semantic action targets across
  reordering. Owned overlays re-read previously missing optional scopes and
  propagate owner moves through nested floating content.

- Programmatic/autofocus requests reveal through the shared scroll-ancestor
  plan after layout; pointer focus stays stable. Lazy rows use their own build
  contexts, and eager/lazy ListView reveal partially visible items correctly.
- `TextEditingController.beginPaste` preserves an insertion anchor and one paste
  undo across intervening edits. `FleuryTester.sendTerminalBytes` tests actual
  fragmented parser input with an optional injected `terminalParser`.
- `OverlayEntry(owner: context)` keeps floating content attached to live local
  scopes and its owner's lifetime. `AppCommand.availability` optionally makes
  command presentation observable; invocation still checks current predicates.
- Flex culling respects cached descendant paint overflow. ASCII border cells
  retain decoration provenance through compositing and semantic-only changes.
- Keypad decimal meaning follows associated text or configured `keypadDecimal`
  (`FLEURY_KEYPAD_DECIMAL` in native drivers). Matching key-up keeps its identity.
  Legacy keypad KeyCode aliases are deprecated but remain position-aware; enum
  slots and the wire version are unchanged.

- `Semantics.stateBuilder` reads live model state when a semantic snapshot is
  collected. Pair it with `stateListenable` to publish model-only changes without
  rebuilding the child. Existing `state:` annotations remain supported.
- `ListController.viewChanges` reports cursor/content/scroll requests separately
  from completed viewport metrics; ordinary listeners still receive both.

- Segmented pastes keep their original input claimant when focus moves. A tail
  cannot spill into another field after its owner detaches or is replaced.
- POSIX teardown, suspend, and handoff enqueue input-report disables before
  yielding, without draining typeahead or popping protocol stacks early.
  Restoration remains single-flight if a synchronous output callback reenters it.
- Flex overflow and ScrollView use the shared cell/image compositor. A wide
  glyph clipped at the Flex edge now uses the same `?` replacement as other
  viewports, preserving the neighboring cell.
- `Button.onSecondaryPressed` handles a completed right click while retaining
  keyboard focus and the button's enabled state. `CellStyle.interactive(pressed:)`
  styles a held primary pointer press on activatable controls; release,
  cancellation, or disabling clears it. Keyboard and semantic activation remain
  immediate actions. Custom controls can also pass `pressed:` to `CellStyle.resolve`.

- Arrow navigation now reveals controls outside the current scroll viewport
  without scrolling away from the focused action. Descendant editors and lists
  retain their key handling. Scrollbars can hide when content fits with
  `showWhenFits: false` (`showScrollbarWhenFits` on `ScrollView`).
- Explicit native POSIX drivers now tolerate a full terminal output queue.
  Large frames no longer crash when stdin and stdout share nonblocking flags.
- Inline shutdown now resolves a pending terminal resize before clearing its
  region. Exiting during a resize removes the old UI without allocating another
  frame; missing cursor replies still use a bounded, conservative cleanup.

- Generated semantic IDs distinguish repeated row keys in separate unkeyed
  lists and keys with different value types. Keyed rows retain their IDs when
  reordered within a list; explicit semantic IDs and `Semantics(key:)` IDs are
  unchanged. Generated positional IDs remain opaque, session-scoped handles.
- `FleuryTester.invokeCommand` and `invokeSemanticAction` pump requested frames
  while awaiting a handler, so post-frame validation no longer deadlocks them.
  Test time remains under the caller's control, and a dialog still needs an
  explicit answer. Disposal and frame failures release pending invocations.

- **Breaking:** `requestExit()` is now `exitApp()`, the counterpart to
  `runApp()`. It starts orderly UI shutdown; await `runApp` for terminal
  restoration to finish. It does not terminate the host process.
- **Breaking:** Removed `TerminalMode(alternateScreen: ...)`. Choose
  `TerminalMode.fullScreen()` or `TerminalMode.inline(rows: ...)` instead.
  The unnamed constructor still defaults to full-screen. Screen choice is
  reported by `isFullScreen` and `isInline`.
- Added a shutdown-and-signals guide with an interactive browser illustration
  and runnable native examples for ordinary exits and app-owned cleanup.
- **Breaking:** Unhandled Ctrl+C now returns
  `AppExit.signal(AppSignal.interrupt)` from `runApp`, matching SIGINT, instead
  of `AppExit.requested`. CLI callers can preserve exit code 130. A widget
  that handles Ctrl+C, such as copying selected text, still takes precedence.
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
- `TerminalMode.inline(rows: ...)` runs a bounded command UI in the main
  terminal buffer on macOS/Linux. `TerminalSession.resizeInline` changes its
  height; mouse/caret offsets, resize, subprocess handoff, suspend/resume, and
  development restart/crash cleanup share the owned-region lifecycle. Existing
  full-screen sessions remain the default. See `doc/inline_terminal.md`.
- Native macOS/Linux TTY applications can await successive `runApp` calls,
  with ordinary prompts or inherited-stdio children between them. Each call
  owns fresh input and runtime state; overlapping sessions are rejected.
  A cleanup timeout keeps new sessions blocked until actual restoration,
  capture shutdown, and output replay finish. Windows and redirected stdin
  retain the one-session restriction.
- Failed terminal entry, handoff, and suspend/resume retain restoration
  ownership and close the affected session. A child that outlives a cleanup
  deadline keeps its capture handles until the handoff finishes. A throwing
  `onStrayOutput` hook is disabled and reported inside the runtime guard;
  the failed line and later output are retained for replay after exit.

- Wrapped `Text` keeps its lines through a resize. Widening a wrapped text
  until it fit one line and then narrowing it again showed only its first
  line.
- A paragraph's leading spaces are its indentation, and wrapping keeps them.
  Multi-line help text, `JsonView` nesting, and nested Markdown bullets
  render indented instead of flush left. An indent that leaves no room for
  the paragraph's first word gives way to it rather than taking a row of its
  own.
- `Row` and `Column` align their children within the space they are given,
  not within their content. `CrossAxisAlignment.end` in an `Expanded` pane
  reaches the pane's edge, a row in a taller `SizedBox` centers vertically,
  and a `mainAxisSize: min` flex that is forced wider centers along its main
  axis. When the children overflow, `spaceBetween`, `spaceAround`, and
  `spaceEvenly` leave no gaps instead of painting siblings over each other.
- A `RepaintBoundary`, and a `ListView` item clipped at the viewport edge,
  paint over their parent as their child would directly: a cell the child
  left empty shows what lies beneath it. Ragged text in a filled panel no
  longer punches holes in the panel's background (every `ListView` item has
  a boundary). An overlay entry that paints no fill of its own now shows the
  app beneath its empty cells too; the built-in dialogs, menus, and popups
  all paint an opaque fill.
- A `ScrollView` over a `Column` no longer paints the rows of text that are
  scrolled out of view.
- Holding Ctrl+C no longer quits an app that handled the press, such as a
  copy of the selection or the app's own interrupt binding. Only an
  unhandled press quits; its key repeats do not.
- The numeric keypad works on kitty-protocol terminals. Digits and operators
  type, KP Enter submits and activates, and the NumLock-off keys move the
  caret and delete. A keypad key reports what it means, as it does in the
  browser, and carries the keypad on its position (`KeyPosition.numpad1`,
  `KeyPosition.numpadEnter`): a binding for the keypad key itself uses the
  position.
- In the browser, a printable key reaches each `KeyDetector` once, and a
  consumed Shift+letter no longer types its capital as well. `Tree`,
  `DataTable`, `Select`, and `Menu` type-ahead jump to the first match.
- A click in a text field while a large paste is still being applied
  finishes the paste first: it stays whole, undoes in one step, and the
  caret lands on what was clicked.
- Shift+Backspace, Shift+Delete, and Shift+Enter work in text fields on
  kitty-protocol terminals and in the browser. Ctrl+Backspace and
  Alt+Backspace delete the word before the caret.
- Tab through a form in a `ScrollView` follows the form's order and scrolls
  each field into view, however far the form is scrolled. `focusNext` and
  `focusPrevious` reveal the node they move to, and so does arrow
  traversal.
- `TextArea` no longer measures its whole document on every caret move, or
  on every keystroke unless it sizes to its content's width.
- A key held on the keypad and the main-block key with the same meaning
  (KP 4 with NumLock off, and Left) are tracked as two keys.
- A letter typed after an abandoned key chord reaches `KeyDetector`s, such
  as a list's type-ahead, on kitty-protocol terminals and in the browser.
- A command's shortcut asks the command's `visible` and `enabled`
  predicates when its key is pressed, as the palette, semantics, and
  `invoke` do. A command that becomes enabled after its scope built fires on
  its shortcut, and one that becomes disabled lets its key through to an
  outer binding. A hint bar asks them too: the frame after an answer changes
  shows the change, even when nothing rebuilt for it.
- Esc at a navigator's root, where there is nothing to pop, reaches what
  binds Esc above the navigator: FleuryApp's own Esc commands, the Toaster's
  Esc dismiss, and an outer navigator. A blocking `PopScope` at the root
  still intercepts it.
- **Breaking:** `StatusController` keeps what FleuryApp derives from its
  `status` builder and extensions apart from items an app or command sets.
  Status a command reports through `context.status` survives the command's
  completion, and a later command no longer wipes it. `put` and `remove` set
  and clear one item beside the items others set. `update` replaces only the
  set items, so `items` no longer equals what was last passed to it; don't
  write `items` back through `update`, which would freeze the derived items
  at their current values. Use `put`.
- A command that throws is reported. From a shortcut, a button, or a palette
  row it reaches runApp's error overlay, as a throwing key binding does.
  `CommandRegistry.dispatch` and `dispatchCommand` start a command this way
  for custom command surfaces and return whether it started; one that
  throws before it returns throws from them, and a later failure of its
  future reaches the zone.
- A semantic action reports what it did. A handler declines by throwing the
  new `SemanticActionDeclined`, which reports `unsupported` rather than
  `completed`.
  - A command node or a status item runs its command: one that failed
    reports `failed`, and one that is disabled, hidden or gone reports
    `unsupported`. `CommandRegistry.invokeFromSemantics` and
    `invokeCommandFromSemantics` do the same for custom semantic handlers.
  - A control's `activate` is a press, as Enter or a click is: nothing waits
    on the work it starts, whose failure reaches the error overlay. A press
    that throws reports `failed`, a `CommandButton` or palette row whose
    command throws included; one whose command turned disabled, hidden or
    gone since it built reports `unsupported`, and a palette stays open.
  - A route dismissal a `PopScope` refuses reports `unsupported`.
- runApp stops on a storm of uncaught errors only when they recur with no
  input between them. Holding a key whose command or async handler fails,
  typing fast into a field whose async handler fails, or an agent repeating
  such an action, reported 24 errors inside three seconds and ended the
  session. Bare pointer motion doesn't count as input, so moving the mouse no
  longer keeps a genuine error loop alive.
- `FleuryTester.lastCommandResult` and the app node's `lastCommandId` are
  the latest command visible from the focused context, scoped or app-level.
  Both kept reporting the app's last command after a screen command ran.
- `NavigatorState.topScreen` is the screen widget of the top route, so a
  screen that closes itself can tell being presented from being shown
  inline.
- `FleuryTester.renderToString` trims each row's trailing empty cells rather
  than trailing copies of the mark. An empty mark no longer hangs the test,
  a mark of several characters works, and a glyph equal to the mark stays.
- A focus move rebuilds the controls whose focus changed, not every
  `TextInput`, `TextArea` and button in the tree (41 elements per Tab in a
  20-row form). `FocusNode` is a `Listenable` that notifies when its own
  focus flips, including when its `Focus` unmounts while focused; a control
  shows a focus cue with `context.listen(node)`. `Focus.of` read in a build
  rebuilds its caller for that node's focus only. A click in a text field
  no longer subscribes it to every focus move.
- `ListController.moveCursor(index, itemCount:)` places the cursor in a list
  its owner is rebuilding to a new number of items, where `currentIndex`
  would clamp against the old count; a later `currentIndex` supersedes it,
  and `cursorFor(itemCount:)` reads it back before the list shows it.
- An `Anchored` float paints the theme where it sits, not the fallback theme
  of the overlay above the app's `Theme`.
- A terminal-only app no longer re-derives the screen geometry of every
  mounted `Semantics` node (every `Text`) on every paint pass; nothing reads
  it until a semantics consumer takes a full rebuild.
- **Breaking:** a served app says why it could not send its semantic tree.
  The encoder rejects a tree it cannot carry, most often two nodes that
  derive the same id from one `Key` used under different unkeyed parents,
  and the serve driver dropped it silently: the browser's accessibility tree
  and agents over MCP saw nothing, or a tree frozen at the last one sent.
  runApp now reports it as a developer warning, once per episode.
  `RemoteSurfaceSink` gained `onDeveloperWarning`, which an implementation
  must provide.
- A served semantic action whose handler awaits UI no longer holds up the
  actions behind it. The `await context.present(Confirm())` idiom in a
  `Semantics` handler or an `AppCommand` finishes only once a later action
  answers the dialog, and that action queued behind it forever. The queue
  now waits for a handler for at most 500 ms, and the handler's RESULT goes
  out when it finishes. Actions still apply in order when each finishes
  within that; one slower than it can be overtaken by the next.
- A framed app no longer floods its served accessibility tree and MCP with
  its frame. The coverage fallback, which exposes painted text that has no
  semantics, counted drawing glyphs (box drawing, block elements, braille,
  sextants, octants) as text: a panel's frame became dozens of `│` nodes,
  and every framed app kept the semantics pipeline off its fast paths,
  walking the whole tree and scanning the whole screen every frame. Text
  inside a frame still falls back, without the frame; an ASCII frame (`+`,
  `-`, `|`) still reads as text.
- A semantic patch that only changes content (labels, values, state; no
  node added or removed, no child list changed) costs its peer about what it
  changed. `SemanticsWireDecoder` rebuilds only those nodes and their
  ancestors, reusing the rest of the tree, and names them in
  `contentReplacements`; `SemanticTreeUpdate` no longer copies the node
  maps. A one-label patch on a 2,253-node tree now decodes and updates its
  owner in about 0.2 ms rather than 5.7 ms. A structural patch still
  rebuilds the tree.
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
  `ScrollController` are removed in favor of `atStart` / `atEnd` /
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
  turns off the suspend fallback, so an unhandled Ctrl+Z is only a key (every
  session delivers Ctrl+Z to the application first). Raw startup fails if
  native termios is unavailable, rather than silently restoring kernel-owned
  suspension.
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
  route no longer lets its canceled transition delete the revealed route.
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
  terminal that only partly honors the protocol is rolled back to the safe
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
- Hot restart: Ctrl+G, then F5, while the dev supervisor runs the app, tears
  the app down gracefully and re-runs `main()` fresh in the same terminal
  session (for the edits reload can't apply). The `ext.fleury.restart`,
  `ext.fleury.shutdown` and `ext.fleury.reloadReport` service extensions are
  the supervisor's hooks, not an entry point for other tools.
- Apps spawned under `fleury serve --spawn` self-reload on save when the
  spawn command itself enables the VM service (e.g. `dart
  --enable-vm-service=0 run bin/main.dart`) — the browser preview updates
  live; restart is intentionally disabled there. Hot restart is also
  available from the debug shell: `Ctrl+G`, then `F5` (dev-supervisor
  sessions).
