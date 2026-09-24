# Core bug & perf sweep — 2026-09-23

**Scope:** `main` at #270, framework core through the widget, serve, and semantics packages.
**Method:** a multi-agent sweep, run twice, with finders split by subsystem. An independent verifier reproduced every finding with its own probe, and none was refuted. Findings are grouped into fix batches, most severe first within each.
**Tracking:** each batch lands as one reviewed PR. Batch A is the first (#274). Six findings wait on a product decision; they stay open until it is made.

## Status

| Batch | Severity | Finding | Status |
| --- | --- | --- | --- |
| A | high | Frames run in the zone of whatever code requested them, so errors skip runApp's guard: the process exits 255 and the terminal is never restored | Fixed |
| A | high | Lifecycle-hook exceptions skip per-element error containment: the whole screen is replaced, siblings vanish silently, and an animating parent makes it fatal | Fixed |
| A | high | Unkeyed multi-child reconcile destroys later stateful siblings when a child is inserted or swapped above them (TextInput drafts wiped) | Fixed |
| A | medium | A setState scheduled from a microtask makes frames chain as microtasks; SIGTERM, Ctrl+C and the grace force-exit never run | Fixed |
| A | medium | Hot reload permanently stops every Animation.loop(), freezing built-in Animate .pulse()/.shimmer()/repeat effects | Fixed |
| A | medium | N events delivered in one event-loop turn (one stdin read, one socket chunk) render N full frames | Decision pending: coalesce events into one frame |
| A | medium | On exit, mouse reports that arrive during teardown stay queued on the tty and the shell reads them as garbage | Decision pending: draining the tty before exit, Ctrl+Z, or handoff reads away typeahead; not draining leaves mouse reports for the shell |
| A | low | Rebuilds requested during a LayoutBuilder's layout-time build wait for the next frame: a Scope fed from constraints paints the previous size on every resize | Fixed |
| B | high | RenderText's layout cache goes stale after a single-line fast-path layout, so wrapped lines vanish after narrow→wide→narrow | Open |
| B | high | Soft-wrap drops leading whitespace at the start of every paragraph: multi-line Text and all RichText lose indentation (JsonView tree and nested Markdown lists render flat) | Open |
| B | medium | RenderFlex aligns children within the unconstrained content size instead of the final box, and on overflow spaceBetween/Around/Evenly produce negative gaps that overlap siblings | Open |
| B | medium | RepaintBoundary cache blits and ListView's clip path copy empty cells over the parent's paint, punching holes in backgrounds (every ListView item is wrapped in a boundary by default) | Open |
| B | low | RenderFlex's offscreen cull never fires for subtrees containing text, so a ScrollView paints its entire content every frame | Open |
| C | high | Holding Ctrl+C exits the app even when the press was handled, e.g. after copying a selection or an app's Interrupt binding | Open |
| C | high | The numeric keypad does nothing on kitty-protocol terminals (the default setup): digits are dropped, and KP Enter and NumLock-off navigation keys are ignored | Open |
| C | medium | Browser: printable keys reach detectors twice, and Shift+letter typeahead skips a match | Open |
| C | medium | Clicking in a text field while a large paste is still being applied inserts the rest of the paste at the click point, scrambling the order | Decision pending: paste ownership when focus moves |
| C | medium | Shift+Backspace (also Shift+Delete, Shift+Enter, Ctrl+Backspace) does nothing in TextInput/TextArea on kitty-protocol terminals and in the browser | Open |
| C | medium | Tab in an overflowing ScrollView form skips hidden fields and never scrolls to them | Open |
| C | medium | TextArea re-measures the whole document on every keystroke and caret move, then throws the result away | Open |
| D | high | Command shortcuts freeze `enabled`/`visible` at build time: the shortcut is dead or swallows the key while every other surface says the command is enabled | Open |
| D | high | Opening the debug panel (Ctrl+G -> docked, or Esc fullscreen -> docked) unmounts and re-creates the whole app: all State lost and navigation reset | Fixed: #273 keeps the app at one element path; this branch fixes the GlobalKey move into a LayoutBuilder underneath |
| D | high | Root route consumes Esc even when nothing can pop, so FleuryApp Esc commands, the Toaster's Esc-dismiss and app-level Esc bindings never fire | Open |
| D | medium | A status update made by a command is wiped when the command completes, and any later command wipes manual updates | Open |
| D | medium | AppCommand.run exceptions are silently swallowed on every interactive path, and semantic activation reports `completed` for a failed command | Open |
| D | medium | Dialog's semantic dismiss calls pop() unconditionally, bypassing barrierDismissible:false and PopScope guards | Open |
| D | medium | FleuryTester.lastCommandResult returns the app registry's stale result instead of the latest (scoped) invocation, so tests assert on the wrong command | Open |
| D | low | renderToString(emptyMark: '') hangs the test process forever, and multi-code-unit marks throw RangeError | Open |
| E | high | DataTable stops virtualizing under an unbounded height (e.g. as a Column child): every row is built each frame and the cursor moves off-screen | Decision pending: unbounded-height DataTable |
| E | high | FileBrowser strands the keyboard in an empty or unreadable directory: Left/Backspace go dead and there is no way back up | Open |
| E | high | Image re-decodes on every parent rebuild and resamples the full source on every paint (19–90 ms/frame); animated images restart and trip the one-ticker assert | Open |
| E | high | Left/Right bubbling out of any control inside a Tabs body switches tabs and drops focus | Decision pending: Tabs arrows only from the strip |
| E | high | Markdown inline parser treats intraword `_` and spaced `*` as emphasis, deleting characters from identifiers, filenames and math | Open |
| E | medium | Every first-party collection wrapper forces a second full frame per scroll step, undoing ListView's metrics-only no-rebuild guarantee | Open |
| E | medium | FileBrowser re-reads the directory from disk and resets the cursor to row 0 on every parent rebuild when entityFilter is an inline closure | Open |
| E | medium | JsonView deep-copies and re-sanitizes the whole JSON document on every build, so each arrow key costs O(document), collapsed parts included | Open |
| E | medium | LogRegion filtered view goes stale (wrong rows shown and copied) when a stable entries list is mutated in place at the same length | Decision pending: in-place list mutation |
| E | medium | SearchPanel reruns the full ranked search 2–4× per arrow key and re-indexes the old results on every update | Open |
| E | medium | Sparkline (also Heatmap, Canvas) skips repaint when handed the same data object, so a history list updated in place freezes inside Panel's default RepaintBoundary | Decision pending: in-place list mutation |
| E | medium | Toaster, Tooltip, Autocomplete and CompletionTextInput overlays ignore the app Theme and paint the fallback dark surface | Open |
| E | medium | Tree's top-level semantics (currentIndex, selectedKey, visibleRange) never update during keyboard navigation | Open |
| E | medium | TreeTable selection is positional: expand, collapse, filter or new roots silently move the cursor to a different node, and Enter/Ctrl+C act on it | Open |
| E | low | Any focus change rebuilds every focusable control in the tree, not just the two whose focus changed | Open |
| E | low | Every paint pass re-derives geometry for every mounted Semantics element (every Text), even in terminal-only apps where the result is thrown away | Open |
| E | low | FileBrowser, SearchPanel and DiffView recompute O(n) data on every build and every navigation call | Open |
| E | low | LineChart sorts and dedupes every x value on each series update or parent rebuild, even when not interactive, and repaints all points when the data is unchanged | Open |
| E | low | parseUnifiedDiff reads the `git format-patch` signature line (`-- `) as a deletion: phantom row, wrong counts, corrupt hunk copy | Open |
| F | high | A legal duplicate semantic id on a node with children makes the wire encoder drop the whole semantic tree. Serve's a11y DOM goes empty and MCP reports that the app never rendered. | Open |
| F | medium | A semantic action whose handler awaits UI (the `await context.present(Confirm())` idiom) blocks the served semantic-action queue, so the dialog can't be confirmed through a11y/MCP | Open |
| F | medium | SemanticDomPresenter re-inserts the whole content of every aria-live region on any structural change, so screen readers re-read the entire log for each appended line | Open |
| F | medium | The coverage fallback turns border glyphs (Panel, Dialog, Menu…) into hundreds of junk text nodes and keeps the semantics pipeline on its slow path | Open |
| F | medium | The semantic wire decoder (browser client and MCP bridge) rebuilds the whole tree for every one-node patch; the wire diff saves bytes but not peer CPU | Open |

A multi-agent sweep of `main` plus #270, run twice. An independent verifier reproduced every finding with a probe, and none were refuted. Findings are grouped into proposed fix batches, most severe first.

## A. Framework core & runtime (8)

### [high] Frames run in the zone of whatever code requested them, so errors skip runApp's guard: the process exits 255 and the terminal is never restored
`fleury/lib/src/runtime/frame_scheduler.dart:78`, bug, found by the runtime finder

**Claim.** FrameScheduler._defaultFlush schedules the flush with scheduleMicrotask(flush) or Timer(delay, flush). Both run in Zone.current of whoever called requestFrame, and requestFrame is reached from notifier listeners. So when a model is changed by a callback registered outside runApp, the whole frame runs in main()'s zone. That is the normal way to wire a data source: a socket, Timer or subprocess listener created in main() before runApp. Two things then escape runZonedGuarded. First, post-frame callback errors, which flushPostFrameCallbacks forwards to Zone.current.handleUncaughtError (ticker_scheduler.dart:235). Second, errors from any Timer or Future started during that frame, because they inherit its zone. The same drift happens in apps with no outside trigger once runApp survives one async error: runZonedGuarded's onError runs in the parent zone, and the reporter listener's scheduleFrame('runtime-error') (run_app.dart:639) schedules the banner frame there. That frame and everything it starts are unguarded. In the root zone the isolate dies with no cleanup, and because runApp redirected fd 2 into its capture pipe, the error message is never shown either.

**Reproduction.** In main(), before runApp, create `final model = ValueNotifier(0); Timer.periodic(100ms, (_) => model.value++);`. The app's build does context.listen(model) and, when v == 3, adds a post-frame callback that throws. Run it on a real PTY with the native driver (fd capture active). Control: create the same Timer in initState instead.

**Verifier evidence.** I reproduced this with three probes in the sweep worktree and deleted all three afterwards.

(1) FakeTerminalDriver, with runApp called inside an outer runZonedGuarded that stands in for main(). A ValueNotifier is bumped from the outer zone. When v==3, the build registers a post-frame callback that throws.
Outer trigger output: `{escaped: [Bad state: post-frame boom], log: [pfc zone=outer], bannerPainted: false}`.
Control, with the same bump done from runApp's onEvent (inside the zone): `Uncaught runtime error: Bad state: post-frame boom ... {escaped: [], bannerPainted: true}`. The stack shows the frame flush reached through `_CustomZone.bindCallbackGuarded` from the microtask queue, so the flush runs in the zone of whoever requested the frame.

(2) Drift without any outside trigger. All code runs in the guarded zone. A key handler starts a Timer that queues two microtasks: the first throws, the second does model.value++. The build then registers a post-frame callback that creates a Timer, and that Timer throws. The zone of the guarded run was taken from the first build. Output: `log=[build v=0 inGuarded=true, build v=1 inGuarded=false, pfc inGuarded=false] escaped=[Bad state: timer from drifted frame] firstBanner=true timerBanner=false`. Cause: onError runs in the parent zone, so the reporter listener's scheduleFrame('runtime-error') queues the next frame outside the guard. The app's own model change then coalesces into that frame. Its build, its post-frame callbacks and any Timer they start all run unguarded.

(3) Standalone `dart run` script using a marker TerminalDriver, with Timer.periodic(20ms, model.value++) created in main() before runApp. It printed `MARK enter`, then `Unhandled exception: Bad state: post-frame callback failed ... TickerScheduler.flushPostFrameCallbacks ... FrameDriver._renderNowBody`, then exited with code 255. There was no `MARK restore` and runApp never returned.
Control, with the same Timer created in initState: `MARK enter`, `Uncaught runtime error: ...`, `MARK restore`, `MARK runApp returned AppExit.requested`, exit 0.
I did not re-run the real PTY / fd-capture case myself. The finder's evidence for it is consistent with the exit-255-without-restore path shown here: raw mode and alt screen left behind, and the error text swallowed by the capture pipe.

**Proposed fix.** Tie the frame program to the runtime's zone. Capture Zone.current when FrameDriver/FrameScheduler is constructed (this already happens inside runZonedGuarded) and schedule with `_zone.scheduleMicrotask(flush)` / `_zone.createTimer(delay, flush)`; Flutter binds onBeginFrame to its zone the same way. Do the same for TickerScheduler's Timer.periodic and for RuntimeErrorReporter's auto-dismiss Timer, so every frame and tick runs under the guard wherever the request came from.

**Verifier notes.** Confirmed. The claimed severity of high stands. Creating a Timer, socket, stdin or subprocess listener in main() and then calling runApp is the standard way to feed a model, and in that setup any post-frame callback error, or any async error started during such a frame, kills the process with the terminal left raw and in the alt screen. The drift path (2) means even apps that keep everything inside runApp lose the guard after the first reported async error. It only needs another frame request to coalesce into the reporter's banner frame.

Root cause: FrameScheduler._defaultFlush calls the top-level scheduleMicrotask/Timer, so the flush runs in the requester's zone. The same pattern appears in TickerScheduler._startTimer (Timer.periodic, which starts in whatever zone registered the first ticker) and in the RuntimeErrorReporter auto-dismiss timer, which is created from onError in the parent zone.

The proposed fix is right. Capture the runtime zone when FrameDriver/FrameScheduler is constructed inside runZonedGuarded, and schedule the flush with `_zone.scheduleMicrotask` / `_zone.createTimer`. Apply the same change to TickerScheduler's periodic timer. For the reporter's auto-dismiss timer, capturing the zone at construction is enough, and it is simpler to create that timer via the runtime zone. Equivalent alternatives: wrap the whole flush in `_zone.run(...)`, or bind the flush with `_zone.bindCallbackGuarded`.

A regression test would be probe (1): call runApp inside an outer runZonedGuarded, trigger an update from the outer zone, and expect escaped to be empty and the banner to be painted. Probe (2) covers the drift case.

The probe files I created (test/runtime/_sweep_zoneverify_1_test.dart, _2_test.dart and test/_sweep_zoneverify_3_script.dart) are deleted. The other untracked _sweep_* files in the worktree belong to other agents.

### [high] Lifecycle-hook exceptions skip per-element error containment: the whole screen is replaced, siblings vanish silently, and an animating parent makes it fatal
`fleury/lib/src/widgets/framework.dart:1332`, bug, found by the core finder

**Claim.** Only build() and didChangeDependencies are wrapped by the per-owner errorBuilder. Exceptions from initState (1395), didUpdateWidget (1404), createRenderObject/updateRenderObject and Scope.create/createWithContext propagate out of ComponentElement.performRebuild: its updateChild catch at 1332 only fixes _child and rethrows. They leave flushBuild and reach FrameDriver's root backstop, and the flush loop comment at 1736 acknowledges they have no errorBuilder catch. In the frame loop this means three things. (a) That frame replaces the entire UI with a full-screen error. (b) Afterwards the failed widget, and unkeyed siblings the aborted reconcile had already deactivated, are gone with no in-place error; the thrower is not re-queued. (c) If the parent rebuilds on consecutive frames (AnimationBuilder, spinner, stream), each frame re-inflates the child and backstops again. After backstopStormLimit (8, frame_driver.dart:418) the driver sets renderUnrecoverable, and run_app.dart:1563 then tears the session down. The same exception thrown in build() renders an in-place ErrorWidget and the app keeps running. Flutter catches around updateChild and substitutes an ErrorWidget.

**Reproduction.** TuiRuntime + FrameDriver with a FakeTickerScheduler. Root: TuiBindingScope(child: _Drawer), where _Drawer builds AnimationBuilder<double>(open ? 1 : 0, curve: easeOut, duration: 400ms, builder: (_, t, __) => Column([Text('status bar'), if (t > 0) const _Panel()])). _Panel.initState does `context.scope<_Model>()` and no Scope<_Model> is provided, a common mistake. Open the drawer, then advance the scheduler 33 ms and call renderNow per tick. Single-shot variant: Column([Text('header'), if (show) const _ThrowsInInit(), Text('footer')]); set show = true, render, then render again later.

**Verifier evidence.** I wrote my own probes, separate from the finder's leftover _sweep_verify_lifecycle_1_test.dart, which I did not touch. They used TuiRuntime + TuiFrameLoop + FrameDriver with a text-capturing presenter and an 8-frame storm limit. Both probe files are deleted.

Probe 1 tree: _H builds Column[Text('top $n'), if (show) const _T(), Text('bottom')]. _T throws StateError('KABOOM') from initState in the 'init' variant and from build in the 'build' variant. Steps: set show=true, then call setState on _H once per frame, like an animating parent.
- init variant: `[init] backstops=8 unrecoverable=true fatal=Bad state: KABOOM ticks=6`. Frames f1 to f5 were all the full-screen error box `╭───╮ │⚠ Bad state: KABOOM │ ... ╰───╯`, and 'top N' and 'bottom' were gone. renderNow rethrew on the 8th backstop.
- build variant (control): `[build] backstops=0 unrecoverable=false fatal=null ticks=12`, with frames `top 0 [⚠ Bad state: KABOOM] bottom` through `top 12 [⚠ ...] bottom`. The error stayed in place and the app kept running.

Probe 2 tree: Column[_Clock, _H]. Set show=true once (single shot), then tick only the unrelated clock:
```
f0: clock 0 top bottom
f1: <full-screen ⚠ Bad state: KABOOM> backstops=1
tick0: clock 1 top   backstops=1 scheduled=false
tick1: clock 2 top   backstops=1 scheduled=false
```
'bottom' disappeared: the aborted Column reconcile had already deactivated it, and it was then finalized. No error is shown in place and nothing is re-queued, so the subtree is silently corrupted.

Extra finding from the same probe: a resize while show==true throws straight out of renderNow, with no backstop. The stack is FrameDriver.handleResize (frame_driver.dart:273) -> TuiRuntime.updateRoot -> ... -> _TS.initState. handleResize runs in _renderNowBody before the backstop try (line 364), so the throw goes to _onFrameError and then the zone. _lastSize is never updated, so every later frame retries the resize and throws again. fleury_web's run_tui_surface.dart:504 onFrameError starts teardown on the first such throw.

Code: ComponentElement.performRebuild (framework.dart:1330-1338) catches the updateChild failure only to clear _child, then rethrows. flushBuild's finally (1736) admits that initState and didUpdateWidget have no errorBuilder catch. ErrorBoundary and the implicit route/overlay boundaries contain layout/paint only, so these build-phase lifecycle errors escape everything until FrameDriver's backstop (frame_driver.dart:409-422, storm limit 8). run_app.dart:1563 tears the session down once renderUnrecoverable is set.

**Proposed fix.** When an errorBuilder is installed, catch updateChild failures in ComponentElement.performRebuild (and _LayoutBuilderElement._buildChild) as Flutter does: report through onBuildError, then install errorBuilder(e, s) in the child slot (updateChild(null, errorWidget) after the existing partial-tree cleanup). Keep propagating only for raw owners without a boundary, which preserves the TuiRuntime.updateRoot throw-and-safe-retry contract tested in tui_runtime_test.dart.

**Verifier notes.** I tried to refute it and could not. There is no build-phase boundary other than the per-owner errorBuilder in the build() catch. The behaviour is not a documented choice: the flushBuild comment treats it as a known gap, not as policy.

Severity: high is justified. A common mistake, such as a missing Scope read in initState or a throw in didUpdateWidget, kills the whole session within about 8 frames under any animating or streaming parent. Even a single throw silently drops siblings.

One precision on the claim: in the single-shot case, the full-screen error frame stays up until something rebuilds. Only frames driven by unrelated widgets show the corrupted 'top' without 'bottom'. When the parent itself rebuilds, it re-inflates the thrower and backstops again (backstops=2, 3, 4...).

Extra finding: the resize path (handleResize called before the backstop try) escapes the backstop entirely. A resize under a live lifecycle thrower sends an error to the zone on every frame, and it tears down the fleury_web in-browser host immediately. Whoever fixes this should also move handleResize inside the backstop, or keep it covered by the new containment.

The proposed fix is right and matches Flutter: ComponentElement.performBuild wraps `updateChild` in try/catch and substitutes `updateChild(null, ErrorWidget)`. Do this in ComponentElement.performRebuild and _LayoutBuilderElement._buildChild when owner.errorBuilder != null: call onBuildError, then run the existing partial-tree cleanup, then `_child = updateChild(null, builder(e, s))`. Rethrow only when no errorBuilder is installed, which keeps the raw-owner updateRoot contract. With this fix the nearest component ancestor (_H here) shows the error in place, so the lost-sibling state becomes a visible, contained error panel instead of a silent loss. The flushBuild finally comment should then be updated.

### [high] Unkeyed multi-child reconcile destroys later stateful siblings when a child is inserted or swapped above them (TextInput drafts wiped)
`fleury/lib/src/widgets/framework.dart:2290`, bug, found by the core finder

**Claim.** MultiChildRenderObjectElement._reconcileChildren matches unkeyed children by walking the unkeyed-old queue forward, and it deactivates every candidate that does not match (lines 2283-2292). There is no bottom-up suffix scan. So inserting an unkeyed child of a different type (`if (error != null) Text(error)`) or swapping one (`loading ? Text(..) : SizedBox()`) ahead of a stateful sibling deactivates that sibling while it searches. The sibling is then inflated fresh and its State is lost: owned controller text, owned FocusNode, cursor and local state. Flutter's updateChildren keeps such siblings through its bottom scan. The class doc calls the forward/backward walks an optimization to add 'if profiling demands it', but in fact the backward walk is what keeps this State. Existing tests (multi_child_reconciliation_test.dart) cover only same-type append, remove and reorder.

**Reproduction.** (1) Form: Column([Text('Name:'), if (error != null) Text(error!), TextInput(autofocus: true, onChanged: (t) => setState(() => error = t.length < 5 ? 'min 5 chars' : null))]). Type 'a', then 'b'. (2) Chat: Column([Text('# chat'), loading ? Text('loading...') : SizedBox(height: 1), TextInput(autofocus: true)]). Type 'hello', then set loading = true. (3) Generic: Column([Text('Name:'), if (err) Text(err), _Counter(), Text('footer')]). Bump the counter to 2, then set err.

**Verifier evidence.** Probe test packages/fleury/test/_sweep_vcore_reconcile_1_test.dart, deleted after the run, in the sweep-2026-09-23 worktree. Command: dart test on that file only. Output:
- Generic: `before: Name:|count=2|footer||| inits=1 disposes=0`, then `after:  Name:|bad|count=0|footer|| inits=2 disposes=1`. The _Counter State was disposed and re-created, so the count reset to 0.
- Form: `after a: Name:|min 5 chars| ||`, then `after b: Name:|min 5 chars|b ||`. The first keystroke is lost when the validation message is inserted above the TextInput.
- Chat: `typed: # chat||hello ||`, then `loading: # chat|loading...| ||`. Swapping SizedBox for Text above the TextInput wipes the draft.

Trace from the code at packages/fleury/lib/src/widgets/framework.dart:2283-2292:
- Old unkeyed queue is [Text(Name), _Counter, Text(footer)]. New is [Text, Text(err), _Counter, Text(footer)].
- i=1 Text(err) pops _Counter. canUpdate fails, so deactivateOld(_Counter) runs. It then pops Text(footer) and matches it.
- i=2 _Counter and i=3 footer find the queue empty and inflate fresh.
- _reconcileStableUnkeyedChildren bails because the lengths differ, so the fast path does not cover this.

Flutter's updateChildren keeps this State: its bottom-up scan matches footer and _Counter from the end, and only the inserted Text is inflated in the middle.

**Proposed fix.** Port Flutter's updateChildren shape: (1) update the matching prefix top-down, (2) find the matching suffix bottom-up, (3) reconcile only the middle with the keyed map plus the unkeyed queue, deactivating leftover unmatched olds at the end rather than while searching, (4) update the suffix in place. This stays O(n). Add tests for inserting or swapping a differently typed unkeyed child before a stateful sibling.

**Verifier notes.** Not intended behavior:
- The test header in multi_child_reconciliation_test.dart promises only "reorder = remount" for unkeyed children. An insertion is not a reorder.
- The class doc calls the prefix/suffix walks an optional optimization and says the current algorithm is "O(n) and correct". The suffix walk is actually what keeps State here.

Severity stays high:
- The pattern is very common: a conditional validation or error line, or a loading placeholder, above an input. The result is silent user-data loss (drafts, cursor, owned FocusNode, local state).
- It is mitigated only when the app owns the TextEditingController. Even then, State-owned cursor and focus state are lost.

On the proposed fix: porting Flutter's shape is right. Do the top prefix scan, the bottom suffix scan, then key-map the middle. Match Flutter on unkeyed olds in the middle: drop them (or keep the current queue for middle-only matching), and deactivate leftovers after the middle pass rather than greedily during the search. The current greedy loop has a second, smaller flaw worth covering in tests: Text(err) consumed the footer's Text element, which forced the real footer to re-inflate.

Needed regression tests:
- A differently typed unkeyed child inserted before a stateful sibling.
- A swap of such a child before a stateful sibling.
- Removal of an unkeyed child before a stateful sibling. This is symmetric: removing the error line should also keep the TextInput.

framework.dart is gated: run alloc-gate and paint-gate after the fix.

Also reported as: Unkeyed multi-child reconcile destroys later stateful siblings when a child is inserted or swapped above them (TextInput drafts wiped)

### [medium] A setState scheduled from a microtask makes frames chain as microtasks; SIGTERM, Ctrl+C and the grace force-exit never run
`fleury/lib/src/runtime/frame_scheduler.dart:77`, bug, found by the runtime finder

**Claim.** The scheduler only avoids a microtask flush while a render is on the stack (_renderDepth > 0). A setState issued from a microtask the frame itself scheduled arrives after the render returns (_renderDepth == 0), so it takes the microtask path again. Examples: Future.microtask or .then on an already-completed future inside build, or an async loop over already-completed futures. Frames then chain inside a single microtask drain and the event loop never turns. Stdin reads (Ctrl+C is a byte in raw mode), signal deliveries (the driver's SIGTERM/SIGINT watchers) and the driver's own 5 s grace force-exit Timer never run. If the chain doesn't end, only SIGKILL stops the process, which leaves raw mode and the alt screen behind. The file's own doc describes this failure ('a frame→frame microtask chain starves the event loop … no input, no Ctrl+C, no signal delivery') but only the render-on-stack case is fixed.

**Reproduction.** A StatefulWidget whose build does `scheduleMicrotask(() { if (mounted) setState(() => _n++); })`, run under runApp with a PosixTerminalDriver that uses the real signal watcher (fake stdin/stdout) in a child process. Wait for the first build, then send SIGTERM. For the bounded case, limit the chain to 3000 frames and arm a 1 ms Timer at start.

**Verifier evidence.** Code path: in packages/fleury/lib/src/runtime/frame_scheduler.dart:77, `_defaultFlush` takes `scheduleMicrotask(flush)` whenever `delay <= 0 && _renderDepth == 0`. runApp builds its FrameDriver with no flushScheduler (run_app.dart:1333), so it uses this default. A microtask queued during build runs after `_flush` has returned and decremented `_renderDepth` to 0. When that microtask calls setState, the next requestFrame takes the microtask branch again, so frame N+1 runs inside the same microtask drain as frame N.

Probe 1 used the real runApp with FakeTerminalDriver and a 1 ms Timer.periodic beacon, following the pattern of the existing test/integration/frame_chain_yields_test.dart:
  [microtask] frames=3000 chainMs=148 beaconTicksDuringChain=0 firstFrameAfterATick=null
  [asyncloop] frames=3000 chainMs=77 beaconTicksDuringChain=0 firstFrameAfterATick=null
In the microtask case, build calls scheduleMicrotask(() => setState(...)). In the asyncloop case, a loop runs `await Future.value(1); setState(...)`. Both rendered 3000 full frames and the timer never ran once between them.

Probe 2 was a child process running real runApp with FakeTerminalDriver. It had a ProcessSignal.sigterm.watch() listener that calls requestExit(), plus a 3 s Timer that calls exit(7). I sent SIGTERM after the first build:
  CHAIN=0: "SIGTERM delivered" / "runApp returned AppExit.requested" / exit code 0
  CHAIN=1: still alive 6 s after SIGTERM; the SIGTERM listener and the 3 s timer never ran, and it needed SIGKILL.
This matches the finder's result, with the same mechanism the PosixTerminalDriver's watcher and grace Timer depend on.

**Proposed fix.** Never run two microtask frames in one event-loop turn. After a flush, set a flag that a Timer.run clears; while it is set, schedule the next flush with a Timer (or always use a Timer for the idle flush, which also fixes the frame-per-event finding). Frames are still immediate for the first request in a turn, but chains yield to input, timers and signals between frames.

**Verifier notes.** The finding holds as claimed. Probe files are deleted. The untracked _sweep_* files still in the worktree belong to other agents.

Severity: medium is right, with two points to keep in mind:
- The unbounded case needs an app that does an unconditional setState from a microtask during build, which is already an infinite-rebuild bug. The framework makes it much worse than in Flutter: the app can't be stopped with Ctrl+C, SIGTERM or the grace force-exit. Only SIGKILL works, and that leaves raw mode and the alt screen behind.
- In the async-loop case, the starvation comes from the user's own loop: plain Dart would also drain those 3000 iterations as microtasks. What the framework adds is a full frame (build, layout, paint, encode) for every iteration instead of merging them into one. That is a real cost: 3000 frames in 77 ms of blocked isolate, with 3000 frames of output bytes instead of one.

The proposed fix is sound and addresses the root cause. Replace the `_renderDepth` check (or add to it) with an "already flushed this event-loop turn" flag: set it in `_flush`, clear it with `Timer.run`, and while it is set, schedule with `Timer(Duration.zero, flush)`. That keeps the first frame in a turn immediate, makes every chained frame yield, and subsumes the existing render-on-stack case, so `_renderDepth` could go. Always using a Timer for the idle flush is simpler, but it adds one event-loop turn of latency to every input-driven frame, so measure it with runtime-gate before choosing it. The fix also merges the async-loop setStates into one frame per turn.

Add a regression test next to frame_chain_yields_test.dart covering the microtask-from-build chain; the existing test only covers the post-frame-callback case. The fix touches lib/src/runtime/**, so `benchmark runtime-gate --gate` must pass.

### [medium] Hot reload permanently stops every Animation.loop(), freezing built-in Animate .pulse()/.shimmer()/repeat effects
`fleury/lib/src/animation/animation.dart:652`, bug, found by the core finder

**Claim.** _onReassemble treats a loop like a finite run: it sets _looping = false, calls _stop(canceled: true) and snaps to target. A loop has no natural end, and nothing restarts it. _AnimateState starts its loop only in initState (effects.dart:698), and didUpdateWidget re-loops only when loop-ness, duration or curve change. run_app also calls tickerScheduler.reassemble() after the tree walk, so a restart during that rebuild would be cancelled anyway. FrameTicker, by contrast, keeps running across reassemble. So after the first hot reload every looping effect in the app stays frozen until its widget is remounted.

**Reproduction.** pumpWidget(const Text('loader').animate().pulse()). Sample the first cell's style over 30 × 33 ms pumps. Run run_app's hot-reload order: tester.owner.reassembleApplication(); tester.binding.tickerScheduler.reassemble(). Sample again.

**Verifier evidence.** I ran the probe packages/fleury/test/_sweep_verify_loopreload_1_test.dart and have since deleted it. It uses the same call order as run_app.dart:1460-1467: tester.owner.reassembleApplication(), then tester.binding.tickerScheduler.reassemble(). The probe samples 30 frames 33 ms apart, before and after the reload.

Observed output:
- pulse before reload: activeTickers=1, styles {CellStyle(fg=null, bg=null), CellStyle(fg=null, bg=null, bold)}
- pulse after reload: activeTickers=0, styles {CellStyle(fg=null, bg=null)}
- pulse 5 s later: still only {CellStyle(fg=null, bg=null)}
- shimmer before: 2 distinct styles. shimmer after: 1 style, {CellStyle(fg=null, bg=null)}
- A user StatefulWidget that calls Animation.loop(between:(0,1), period:200ms) in initState and renders the value as text: 14 distinct values before. After: activeTickers=0 and the text stays at {1.00}.

Code path: animation.dart:652 `_onReassemble` sets `_looping = false; _queue = null; _stop(canceled: true); _snapToTarget();`. The only place `_AnimateState` (widgets/effects.dart:692-699) starts the loop is initState. didUpdateWidget re-loops only when loop-ness, duration or curve change. Nothing restarts the loop after a reload. FrameTicker._handleReassemble (frame_ticker.dart:149) takes a different approach: it re-anchors and keeps running. The existing reassemble_test.dart only covers finite to() runs and has no loop case.

**Proposed fix.** In _onReassemble, keep a running loop going: re-anchor the current leg (_curveStart = _lastElapsed) and leave the ticker active. Settle and cancel only finite to() chains.

**Verifier notes.** Confirmed as a real defect. Nobody documents or relies on a loop being stopped by a reload. The code comment says the goal is to start "freshly-loaded code ... from a defined state", but hot reload never re-runs initState, so a stopped loop stays stopped for good. This hits every built-in looping effect (.pulse(), .shimmer(), animate(repeat: true)) and any loop() a user starts in initState. Flutter's AnimationController.repeat keeps running through a reassemble.

Severity: medium is fair, with one caveat. It only happens in dev with hot reload, so production is unaffected. Still, after one reload every loader, shimmer and pulse in the app freezes until its widget is remounted, which looks like a framework bug during normal development.

On the fix: the proposed one is the right layer. Because run_app calls scheduler.reassemble() after the element-tree walk, restarting the loop from State.reassemble in _AnimateState would just be cancelled again. The fix belongs in Animation._onReassemble. When `_looping` is true, it should keep the ticker and the loop parameters and re-anchor the current leg, e.g. `_curveStart = _lastElapsed`, or restart from _loopA to match FrameTicker's deterministic reset. It should not cancel the loop's open future. Only finite to() chains should be settled and cancelled. That fix needs a loop case added to reassemble_test.dart.

### [medium] N events delivered in one event-loop turn (one stdin read, one socket chunk) render N full frames
`fleury/lib/src/runtime/frame_scheduler.dart:77`, perf, found by the runtime finder

**Claim.** When idle, _defaultFlush schedules the frame as a microtask. Dart's async stream controllers deliver each event in its own microtask. This covers the POSIX driver's broadcast event controller, sockets and LineSplitter. The frame microtask queued while event 1 is handled therefore runs before event 2 is delivered. Every event parsed from one read gets its own build → layout → paint → diff → stdout write, and intermediate states reach the wire. runApp's doc says 'Multiple updates within one event-loop turn already coalesce into one frame', but that is false for stream-delivered updates, which is nearly all of them: key repeat, trackpad wheel bursts, hover motion, SSH-coalesced typing, streamed log/token lines.

**Reproduction.** Use the real PosixTerminalDriver with a fake stdin/stdout (100x30) and a 28-row Column that advances a ValueNotifier on each arrow-down or wheel event. Push `'\x1B[B' * 40` (or 40 × `\x1B[<65;10;5M`) as a single stdin chunk and count builds and writes. Compare with frameInterval: 1ms. Separately, add 500 lines in one synchronous turn to a StreamController<String> consumed with setState per line.

**Verifier evidence.** I confirmed this with a probe in the sweep worktree. The probe file was packages/fleury/test/_sweep_verify_rt_1_test.dart and has been deleted. It used FakeTerminalDriver at 100x30 and a KeyDetector that calls setState on a 28-row Column, run through the real runApp and the real FrameScheduler. I compared frameInterval zero against 1 ms, interleaved over 3 reps. Each result is [builds, stdout bytes, µs until the first zero-delay Timer could fire].

40 arrow-down events enqueued in one synchronous turn:
- zero interval: [40, 15757, 46046], [40, 15757, 30396], [40, 15757, 18255]
- 1 ms interval: [2, 869, 3975], [3, 1258, 6228], [2, 869, 2531]

500 lines added in one turn to a StreamController<String>, with setState per line:
- zero interval: [500, 127526, 112168], [500, 127526, 92942], [500, 127526, 89714]
- 1 ms interval: [2, 1811, 2136], [2, 1811, 1365], [2, 1811, 4833]

Mechanism: the idle flush is a scheduleMicrotask (frame_scheduler.dart:77-80). An async (non-sync) broadcast controller delivers one event per microtask. That covers PosixTerminalDriver._events, where the stdin onData runs _parser.feed, which synchronously adds every parsed event to _ParserSink and then to _events.add. The frame microtask queued while event k is handled therefore runs before event k+1 is delivered. FakeTerminalDriver.enqueue uses the same broadcast async controller, so the probe exercises the same delivery path as the POSIX driver. A second probe (_sweep_verify_rt_2_test.dart, also deleted) showed 100 broadcast-controller events landing in 100 distinct microtasks.

**Proposed fix.** Schedule the idle flush as a macrotask (Timer.run / zero-duration Timer) so every microtask-delivered event in the turn lands in one frame. The added latency is one event-loop turn (microseconds). Alternatively, keep the microtask for the first frame of a turn but defer any follow-up frame in the same turn to Timer.run. The same change fixes the microtask-chain starvation finding.

**Verifier notes.** Confirmed for the driver input path (one stdin read that parses into N events) and for user StreamControllers. The doc sentence at run_app.dart:349, 'Multiple updates within one event-loop turn already coalesce into one frame', is false for stream-delivered updates.

One part of the claim is wrong: the LineSplitter case. utf8.decoder plus LineSplitter over one chunk delivers all of that chunk's lines inside a single microtask. My second probe saw 100 lines and 1 distinct microtask, so `Process.stdout.transform(utf8.decoder).transform(LineSplitter())` log streams do coalesce. The problem there only appears when the app re-emits through its own StreamController. I did not test the socket and serve paths.

Why it matters beyond a fast burst: this is a positive-feedback loop. If rendering falls behind key repeat or trackpad wheel input, the tty buffer backs up, and each later read holds several events. Each of those events then gets its own full frame and stdout write, so the app never catches up. Wheel bursts and SSH-coalesced input are the realistic triggers. Medium severity is right: it is uncapped by default and the cost is linear in burst size (40 events took about 18-46 ms here, versus about 3 ms coalesced, JIT).

The proposed fix is sound and matches the existing comment on the re-entrant case. It is to use a zero-duration Timer (a macrotask) for the idle flush too, so every microtask-delivered event in the turn lands before the frame, at the cost of one event-loop turn of latency. It covers both driver and user streams, so it is better than a driver-only fix. A driver-only fix would mean delivering the parsed batch in one event or using a sync controller, and it would leave user StreamControllers uncovered.

When applying the fix, check tests and harnesses that assume a frame follows after only a microtask. The doc at run_app.dart:349 should then become true as written.

### [medium] On exit, mouse reports that arrive during teardown stay queued on the tty and the shell reads them as garbage
`fleury/lib/src/terminal/posix_driver.dart:1280`, bug, found by the runtime finder

**Claim.** restore() cancels the stdin subscription (line 1280) and restores cooked mode (line 1296) before it writes the sequences that turn off mouse, focus and kitty reporting (line 1304), and it never drains input. Before that, runApp's cleanup runs its asynchronous teardown up to restore() (event-subscription cancel, runtime.dispose, and so on), and in the probe none of the reports that arrived in that window were read. So every report the terminal sends between the quit and the moment it processes ?1003l/?1000l stays in the tty input queue and is delivered to the shell prompt (for example `^[[<35;18;5M`). Over SSH this window grows by a full round trip.

**Reproduction.** PTY harness: a child app with TerminalMode(mouse: true, mouseMotion: true) that returns ExitRequested on 'q'. The harness answers DA1 and, like a real terminal, keeps sending SGR motion reports every 10–16 ms until it has read `\e[?1003l` from the app (plus 0 / 25 / 40 ms modelled one-way latency). It sends 'q', waits for exit, then reads the slave's pending input the way the shell would.

**Verifier evidence.** Code: in PosixTerminalDriver.restore() (packages/fleury/lib/src/terminal/posix_driver.dart), the order is: cancel _stdinSubscription (about line 1280), then _restoreCookedMode() (line 1296), then _stdout.write(_exitSequences(...)) (line 1304). Native restoreMode() calls tcsetattr(fd, TCSANOW, ...) (line 1464), so pending input is never flushed, and nothing drains stdin after the disables are written.

PTY repro: I compiled a probe app to kernel: runApp(Center(Text('ready')), enableHotReload:false, mode: TerminalMode(mouse:true, mouseMotion:true), onEvent returns ExitRequested on 'q'). A Python harness plays the terminal. It answers DA1 and CPR, sends SGR motion `\e[<35;x;5M` at a fixed interval until it has seen `\e[?1003l`, and has optional modelled one-way latency. The app runs under a shell-like wrapper process (the session leader). After the app exits, the wrapper puts the tty in raw mode with TCSANOW and reads what is left in the input queue.

Note on my first attempt: it showed 0 leaks, but that was a harness artifact. Python's tty.setraw defaults to TCSAFLUSH, which discarded the pending input. With TCSANOW the leaks show up:
- 10 ms interval, 0 latency: ?1003l after 15.2/18.0/18.3 ms; left for shell 1/1, 2/2, 2/2, e.g. b'\x1b[<35;139;5M\x1b[<35;140;5M'
- 16 ms, 0 latency: 1/1, 1/1
- 10 ms, 25 ms latency: 63.4 ms, 6 of 6 left
- 10 ms, 40 ms latency: 93.6 ms, 8 of 8 left
- 4 ms, 40 ms latency: 98.5 ms, 18 of 18 left

Every report sent after 'q' reached the shell. The app read none of them.

**Proposed fix.** Write the input-mode disables first: 1000/1002/1003/1006 off, 1004 off, the kitty pop and 2004 off. Ideally do this as runApp's first teardown step, before runtime.dispose. Follow them with a DA1 query and keep reading and discarding stdin until the DA1 reply arrives, with a bound of about 100–250 ms. Only then cancel stdin, optionally tcflush(TCIFLUSH), restore termios and leave the alt screen.

**Verifier notes.** Reproduced independently. The mechanism matches the claim. Once 'q' triggers exit, nobody reads stdin, and cooked mode is restored with TCSANOW before the mouse, focus and kitty disables are even written. So every report in flight until the terminal processes ?1003l stays in the tty queue. The shell reads it, and with ECHO back on it is also echoed to the screen. Locally the window is about 15–20 ms, so only 1–2 reports leak, and only if the mouse is moving at quit time. Over SSH it grows by a round trip; at 40 ms one-way I saw 8–18 leaked reports.

Severity medium is fair, maybe medium-low. The bytes are visible garbage at the prompt and no data is lost. The trigger is mouse motion during quit, which is common over SSH with mouseMotion or any-event tracking. Plain click mode (1000/1002 without 1003) only leaks button events, so exposure is narrower there.

The proposed fix is the right one. Write the input-mode disables first (1003/1002/1000/1006, 1004, 2004, kitty pop) while still in raw mode with stdin subscribed. Then send a DA1 sentinel and read and discard until its reply arrives, bounded at about 100–250 ms because DA1 costs a full round trip over SSH. After that, cancel stdin, restore termios with TCSAFLUSH (or tcflush(TCIFLUSH)), and leave the alt screen.

Two narrower options fall short. Reordering alone, writing the disables before cancel, only shrinks the window: reports sent before the terminal sees the disable still arrive a one-way latency later. TCSAFLUSH alone discards what has already arrived but not the reports still in flight. Both shortcuts leave the SSH case open, so the drain step is the part that matters. The same ordering should be checked in the Ctrl+Z suspend path (lines 1009–1011 and 1115–1117), which also restores cooked mode before writing the exit sequences.

Probe file packages/fleury/test/_sweep_verify_mouseleak_1_app.dart was deleted.

### [low] Rebuilds requested during a LayoutBuilder's layout-time build wait for the next frame: a Scope fed from constraints paints the previous size on every resize
`fleury/lib/src/widgets/layout_builder.dart:104`, bug, found by the core finder

**Claim.** _LayoutBuilderElement._buildChild runs the builder and updateChild during performLayout but never flushes rebuilds requested inside that build. When the builder updates a Scope below it, updateShouldNotify marks readers behind an identical/const widget dirty after this frame's only flushBuild (framework.dart:1876). Those readers lay out and paint with stale state. The frame ends with hasScheduledBuilds == true, which forces a second full frame to correct it. Flutter's LayoutBuilder runs its callback in a buildScope that also rebuilds dirty descendants within the same layout pass.

**Reproduction.** pumpWidget(LayoutBuilder(builder: (ctx, c) => Scope<_Width>(_Width(c.maxCols ?? -1), child: const _Reader()))), where _Reader builds Text('w=${context.scope<_Width>().cols}') and _Width has value equality. Then call renderToString(size: CellSize(10,1)) followed by renderToString(size: CellSize(20,1)).

**Verifier evidence.** I wrote my own probe at packages/fleury/test/_sweep_lbv2_1_test.dart and deleted it afterwards. Setup: LayoutBuilder(builder: (ctx,c) => Scope<_Width>(_Width(c.maxCols ?? -1), child: const _Reader())). _Width has value equality and _Reader builds Text('w=${context.scope<_Width>().cols}').

Output:
  initial (80 cols): w=80
  render@10: "w=80" dirty=true
  render@20: "w=10" dirty=true
  render@20 again: "w=20" dirty=false

Control with a non-const reader (a new widget instance each builder run): render@10: "w=10" dirty=false. The reader is rebuilt inline by updateChild, so the value is correct.

Reader behind a const Padding (a realistic deep subtree): render@10: "w=80" dirty=true.

Mechanism: BuildOwner._renderFramePhases (framework.dart ~1876) calls flushBuild() once, then rootRender.layout(). _LayoutBuilderElement._buildChild (layout_builder.dart:104) runs updateChild. The Scope update notifies dependents through markNeedsBuild -> scheduleBuildFor. Those dependents only go into _dirtyElements, and nothing flushes them before paint. The frame therefore paints stale state, and hasFrameWork stays true, so the runtime schedules a corrective frame.

**Proposed fix.** After updateChild in _buildChild, rebuild this element's dirty descendants inside the layout callback: a subtree-scoped flush of owner._dirtyElements sorted by depth, like Flutter's buildScope. RenderLayoutBuilder's attempt loop already tolerates re-entrant invalidation.

**Verifier notes.** Reproduced exactly as claimed. It is a real ordering defect. Flutter avoids it because LayoutBuilder's callback runs inside owner.buildScope, which also rebuilds dirty descendants during the layout pass.

I'm lowering severity from medium to low. The error corrects itself one frame later: scheduleBuildFor fires onScheduleBuild, and hasFrameWork is true, so the frame driver renders again right away. The user-visible effect is:
- a one-frame glitch on each constraint change, where the layout computed for the previous size is painted (clipped) at the new size;
- one extra full build/layout/paint frame, whose stale bytes also go out on the terminal diff and the serve wire.

During a continuous resize drag, every intermediate frame is one step behind. No state is lost and there is no loop. It only affects readers that updateChild does not rebuild inline (const or identical widgets, or readers deeper than the builder's direct output), which is the usual case for Scope readers.

The proposed fix is on target. After updateChild in _buildChild, flush the owner's dirty elements that are descendants of this element, sorted by depth, while still inside the layout callback. It needs a subtree-scoped variant of flushBuild; it should not drain the whole global set, because an element outside this subtree could be rebuilt mid-layout. The layout-time GlobalKey claims set must also be honoured. RenderLayoutBuilder's attempt loop already tolerates re-entrant invalidation, and _finalizeInactiveElements already runs after layout, so deactivations caused by the flush would still be finalized in the same frame.

## B. Text & rendering (5)

### [high] RenderText's layout cache goes stale after a single-line fast-path layout, so wrapped lines vanish after narrow→wide→narrow
`fleury/lib/src/rendering/render_objects.dart:314`, bug, found by the render finder

**Claim.** `_cachedConstraints`/`_cachedSize` (the slow-path cache) is keyed only on constraints. The single-line fast path (lines 291-308) overwrites `_lines`/`_lineWidths` but never invalidates that cache. When constraints return to the last wrapping constraints after a layout where the text fit, performLayout takes the cache hit at 314-316 and returns the cached 2-row size, while `_lines` still holds the one unwrapped line. Paint clips that line to the box width, and every wrapped line after the first disappears; with `overflow: ellipsis` it shows 'hell…'. The same-width `text=` reuse path can also leave a cache entry built for a different string.

**Reproduction.** `Text('hello world')` (default softWrap). Render at 5x3, then 20x3, then 5x3 again. Real triggers: the terminal widened and restored (tmux zoom toggle, maximize/restore), or a sidebar, status label or scrollbar toggling an Expanded text's width back and forth. The text stays truncated until its content or constraints change.

**Verifier evidence.** I wrote a probe at packages/fleury/test/_sweep_verify_rtcache_1_test.dart in the sweep worktree and have since deleted it. It laid out and painted the same retained render object at maxCols 5, then 20, then 5 (maxRows 3 each time).

RenderText (the bug):
  narrow1 size=5x2 rows=[hello|world]
  wide    size=11x1 rows=[hello world]
  narrow2 size=5x2 rows=[hello|     ]   <- 'world' is gone

RenderRichText (not affected, it has its own layout path):
  narrow1 5x2 [hello|world]; wide 11x1; narrow2 5x2 [hello|world]

Widget level: `tester.pumpWidget(const Text('hello world'))`, then `renderToString(size: CellSize(cols,3))` for cols 5, 20, 5:
  cols=5  => hello\nworld\n\n
  cols=20 => hello world\n\n\n
  cols=5  => hello\n\n\n

Same sequence with `overflow: TextOverflow.ellipsis`: `hello\nworld`, then `hello world`, then `hell…\n\n\n`.

Code path in packages/fleury/lib/src/rendering/render_objects.dart:
- The single-line fast path (lines 291-308) sets `_lines = [_text]` and `_lineWidths = const []` but never clears `_cachedConstraints`/`_cachedSize`.
- The slow path's cache hit (lines 313-316) returns the cached 2-row size without restoring `_lines`.
- Paint then draws the single unwrapped line, clipped to 5 columns, into a 2-row box.

**Proposed fix.** In the fast path, clear `_cachedConstraints`/`_cachedSize`, since the cache describes lines the fast path just replaced. Alternatively, store `_lines`/`_lineWidths`/`_moreLinesTruncated` with the cached size and restore them on a hit. Checked in a private copy: clearing the cache in the fast path makes the probe pass, and render_text_test, text_resize_test, measured_text_paint_test and text_max_lines_zero_fast_path_lock_test stay green (50 tests). Add a narrow→wide→narrow regression test.

**Verifier notes.** Confirmed, and high severity is fair. It is wider than the finder's examples. Resizing a terminal by dragging goes through every column width. Growing from the last width W that wraps to W+1 takes the fast path. Shrinking back to W then hits the stale cache, provided the other constraint fields (such as maxRows) match. So any horizontal drag across a Text's wrap threshold and back leaves the wrapped lines blank. The text stays wrong until its content or softWrap/maxLines/policy changes, or its constraints change to a different value that still wraps. Plain `Text` (RenderText) is affected; `RichText` (RenderRichText) is not.

On the same-width `text=` reuse path the finder mentioned: it only runs when the text fits the current width. Its last layout was then a fast-path layout, so once the fast path clears the cache, that path can no longer carry a stale entry. No separate fix is needed.

Fix: the proposed one is right and minimal. Call `_invalidateLayoutCache()` in the fast path, before both of its returns (maxLines<=0 and normal), because the cache describes `_lines`/`_lineWidths`/`_moreLinesTruncated`, which the fast path has just overwritten.

The same coupling matters for the `cached != null && !_softWrap` reuse branch (lines 317-329). That branch reads `_lines`/`_lineWidths` on the assumption that they still come from the last slow-path layout. Clearing the cache in the fast path keeps that assumption true, which makes this fix safer than restoring the cached state on a hit.

Regression test: add a narrow→wide→narrow case to test/rendering/text_resize_test.dart. It should compare the retained object against a fresh one, at the same constraints, for both layout size and painted cells. The existing loop there never returns to the same wrapping constraints after a fit.

I did not change the library code, so I did not rerun the finder's fixed-copy check myself.

Also reported as: RenderText's layout cache goes stale after a single-line fast-path layout, so wrapped lines vanish after narrow→wide→narrow

### [high] Soft-wrap drops leading whitespace at the start of every paragraph: multi-line Text and all RichText lose indentation (JsonView tree and nested Markdown lists render flat)
`fleury/lib/src/rendering/render_objects.dart:592`, bug, found by the render finder

**Claim.** `RenderText._wrapParagraph` drops empty tokens (spaces) whenever `currentWidth == 0`. That is meant for whitespace at a wrap break, but the start of every paragraph is also a line start, so authored indentation is stripped. `RenderRichText._wrapParagraph` (rich_text.dart:590-596, `isFirst = lineWidth == 0`) does the same. RenderText only takes this path for text that contains a '\n' or is wider than its box; the fast path and `softWrap: false` keep indentation, so indentation appears and disappears with width. RenderRichText always takes this path, so leading spaces vanish even on a single line that fits. Two stock widgets break: JsonView renders non-selected rows as RichText(prefix + preview) with the depth indent at the start of the prefix, and MarkdownText renders nested bullets as RichText('$indent• ...').

**Reproduction.** (1) `Text('Usage:\n  app --flag\n    nested')` at 40x3 (no wrapping needed). (2) `RichText(text: TextSpan(children: [TextSpan(text: '    '), TextSpan(text: 'child item')]))` at 40x1. (3) `JsonView(value: {'user': {'name': 'ada', 'tags': ['x','y']}, 'id': 7}, defaultExpandedDepth: 3)` in a 40x8 box. (4) `MarkdownText('- parent\n  - child\n    - grandchild')`.

**Verifier evidence.** I reproduced all four cases with probe tests in packages/fleury_widgets/test/_sweep_verifyindent_{1,2}_test.dart. Both files are now deleted.
(1) Text('Usage:\n  app --flag\n    nested') at 40x3 renders "Usage:/app --flag/nested". With softWrap:false it renders "Usage:/  app --flag/    nested". Text('   indented words here') keeps its indent at 40x1 ("   indented words here") but loses it at 12x2 ("indented/words here").
(2) RichText(TextSpan(children:[TextSpan(text:'    '), TextSpan(text:'child item')])) at 40x1 renders "child item". softWrap:false renders "child item" too, because RichText's empty-token branch applies `!isFirst` even when softWrap is off. The finder did not note that softWrap:false does not help RichText.
(3) JsonView({'user':{'name':'ada','tags':['x','y']},'id':7}, defaultExpandedDepth:3) at 40x8 renders every row flush-left: "▾ $ {object 2} / ▾ user {object 2} / name: \"ada\" / ▾ tags [array 2] / [0]: \"x\" / [1]: \"y\" / id: 7". After two arrowDown presses the selected row jumps right: "      name: \"ada\"". The other rows stay flush-left.
(4) MarkdownText('- parent\n  - child\n    - grandchild') renders "• parent/• child/• grandchild". MarkdownView(markdown: same) is also flat: "• parent/• child/• grandchild".
Cause: render_objects.dart:584-597 (`isFirstOnLine = currentWidth == 0` drops empty tokens) and widgets/rich_text.dart:589-596 (`isFirst = lineWidth == 0` drops the separator even with softWrap false).

**Proposed fix.** In both `_wrapParagraph` implementations, treat a paragraph start differently from a line start created by wrapping: keep leading whitespace at the paragraph start and drop whitespace only at a wrap break, matching the fast path and softWrap:false. Mind the split semantics: `'  x'.split(' ') == ['', '', 'x']` means two spaces. `_computeLoweredGroupsFlat` assumes the wrap only drops spaces at breaks, and that still holds. Add regressions for multi-line indentation, RichText indent spans, and JsonView nesting.

**Verifier notes.** Confirmed as the finder described it. High severity fits: two stock widgets render the wrong structure (JsonView nesting, Markdown nested lists in both MarkdownText and MarkdownView), and the JsonView selected row visibly jumps.

It is slightly worse than claimed. In RenderRichText the leading whitespace is lost even with softWrap:false, because the `!isFirst` guard on empty words ignores `_softWrap`. The finder's claim that softWrap:false keeps indentation is true only for RenderText. The fix should cover that case too.

The proposed fix is right. Track whether any token has been placed in the current paragraph, not whether the line width is 0. Keep leading empty tokens and separators at the paragraph start, one space per empty token plus the separator semantics. Drop them only at a line start created by a wrap. A subtle point: if the indent alone is wider than maxWidth, the wrap should still behave sanely, either clipping or wrapping the indent.

Other agents' _sweep_* files remain in the worktree. My own probe files were deleted.

Also reported as: Soft-wrap drops leading whitespace at the start of every paragraph: multi-line Text and all RichText lose indentation (JsonView tree and nested Markdown lists render flat)

### [medium] RenderFlex aligns children within the unconstrained content size instead of the final box, and on overflow spaceBetween/Around/Evenly produce negative gaps that overlap siblings
`fleury/lib/src/rendering/render_flex.dart:352`, bug, found by the render finder

**Claim.** performLayout computes `mainSlack = ownMain - usedMain` and cross offsets from `ownCross` (lines 347-386) BEFORE `constraints.constrain(...)` (line 390). When the incoming constraints force a larger box (Expanded or other tight flex, SizedBox, a stretch parent), center/end cross alignment, and main-axis alignment under MainAxisSize.min, place children within the content size rather than the Flex's own box. Flutter aligns against the constrained size. Separately, on overflow the negative slack flows into the spaceBetween/spaceAround/spaceEvenly gap arithmetic as negative gaps, so siblings paint over each other. Flutter and CSS clamp free space at 0 for these modes. In release builds the overflow marker is off, so the garbling is silent.

**Reproduction.** `Row([Text('|'), Expanded(child: Column(crossAxisAlignment: end, children: [Text('hi there'), Text('ok')])), Text('|')])` at 30x2. `Row([Expanded(child: Column(crossAxisAlignment: center, children: [Text('Title'), Text('a longer subtitle')]))])` at 40x2. `SizedBox(width:10, height:3, child: Row(crossAxisAlignment: center or end, children: [Text('hi')]))`. `SizedBox(width:10, height:1, child: Row(mainAxisSize: min, mainAxisAlignment: center, children: [Text('hi')]))`. Overflow: `Row(mainAxisAlignment: spaceBetween, children: [Text('LEFT-STATUS'), Text('RIGHT-STATUS')])` at 16x1.

**Verifier evidence.** I ran the probe packages/fleury/test/_sweep_flexverify_1_test.dart (since deleted) with renderToString; all 10 cases ran. Output:
A: Row[Text('|'), Expanded(Column(cross: end, [Text('hi there'), Text('ok')])), Text('|')] at 30x2 gave `|hi there····················|` / `·······ok`. The Column's children are right-aligned only within its 8-column content width. They should sit against the right bar.
B: Row[Expanded(Column(cross: center, [Text('Title'), Text('a longer subtitle')]))] at 40x2 gave `······Title` / `a longer subtitle`. The block is pinned to the left instead of centred in 40 columns.
F (control, no Expanded): a Column(cross: stretch) parent holding the same centred Column gives the same left-pinned output. So any tight or stretched cross constraint triggers it, not only Expanded.
C: SizedBox(10x3, Row(cross: center)) and SizedBox(10x3, Row(cross: end)) both put 'hi' on row 0.
D: SizedBox(10x1, Row(mainAxisSize: min, mainAxisAlignment: center, [Text('hi')])) puts 'hi' at column 0.
E: Row([Text('LEFT-STATUS'), Text('RIGHT-STATUS')]) at 16x1 renders as follows. start: `LEFTSTATUSRIGHT` style truncation `LEFT-STATUSRIGHT`. spaceBetween: `LEFTRIGHT-STATUS`. spaceAround: `EFT-STARIGHT-STA`. spaceEvenly: `FT-STATRIGHT-STA`. The negative gap overlaps siblings, and spaceAround/spaceEvenly also push the first child to a negative position, cutting its start.
Code trace (render_flex.dart:347-392): ownMain is `usedMain` under MainAxisSize.min. ownCross is `maxCross` unless the alignment is stretch. mainSlack and crossOffset are both computed from these content sizes. Only after that does `constraints.constrain(...)` grow the box. So when a tight or min constraint grows the box, the extra space is never used for alignment. For the space* modes, mainSlack goes negative and nothing clamps it.

**Proposed fix.** Compute `size = constraints.constrain(...)` first, then derive main-axis free space and cross offsets from `_mainExtent(size)` and `_crossExtent(size)`. For the space* modes, clamp the distributed gap at 0 when free space is negative. Keep the start/end/center overflow direction, which flex_overflow_test 'end-aligned overflow retains an image leading slice' deliberately pins. Checked in a private copy: all probes are fixed, and render_flex_test, flex_overflow_test, derived_geometry_contract_test, layout_test, render_layout_test, list_view_test, scroll_view_test, scrollbar_test and goldens_test pass (174 tests).

**Verifier notes.** Every case in the finding reproduces exactly as reported. I found nothing that documents or tests the current behaviour as intended: the enum docs say nothing, and the finder reports that the existing flex tests pass with the fix. The four in-repo sample usages of cross center (ansi_sprite_studio, neon_asteroids) are not affected, because each is wrapped in Center or has a loose parent. The bug does hit very common TUI layouts: right-aligned chat bubbles in an Expanded pane, centred headers in a stretch or Expanded column, and vertical centring in a fixed-height row.

Severity: medium is right. The alignment half is silently wrong layout on everyday compositions. The overflow half only shows up once content already overflows, but it corrupts both labels instead of truncating the trailing one, and there is no marker in release.

On the proposed fix, which I agree with:
- Compute `size = constraints.constrain(...)` first, then take main-axis slack and cross offsets from `_mainExtent(size)` and `_crossExtent(size)`.
- Clamp the space* free space to 0 when it is negative, so those modes fall back to start behaviour, as Flutter and CSS do.
- Keep negative slack for end and center, because flex_overflow_test pins the end-aligned leading-slice behaviour.
- One more detail: with stretch the cross size already equals crossMax, so using the constrained size changes nothing there.

I did not apply the fix myself, to avoid mutating library files in the shared sweep worktree. I am relying on the finder's report that 174 tests pass with it.

Also reported as: RenderFlex aligns children within the unconstrained content size instead of the final box, and on overflow spaceBetween/Around/Evenly produce negative gaps that overlap siblings

### [medium] RepaintBoundary cache blits and ListView's clip path copy empty cells over the parent's paint, punching holes in backgrounds (every ListView item is wrapped in a boundary by default)
`fleury/lib/src/rendering/render_repaint_boundary.dart:321`, bug, found by the render finder

**Claim.** Both RenderRepaintBoundary.performPaint (`buffer.copyRectFrom(cache, bounds, ...)`) and `_paintListViewport`'s clip path (list_view.dart:1357, `buffer.copyFrom(scratch, offset)`) go through `_copyRect`/`_copyCellRange`, a raw `setRange`. That copies the source's Cell.empty cells over whatever ancestors or earlier siblings already painted. Painting the child directly leaves those cells alone. So `RepaintBoundary(child: X)` renders differently from `X` whenever X's bounding box has gaps (ragged multi-line text, a Row with a Spacer), and ListView wraps every item in one by default. `_RenderFilledBox` re-applies its background only to leading cells (applyCellBackground skips empty cells), so the holes stay. The clip path, taken whenever a multi-row item straddles the viewport edge (the norm for chat or markdown lists), blits the whole viewport. The container background then wipes out and returns as the user scrolls. Cache verification cannot catch this, because the cache itself matches a fresh repaint.

**Reproduction.** `Container(color: RgbColor(0,0,200), child: SizedBox(width: 8, height: 2, child: RepaintBoundary(child: Text('ab\nabcdef'))))` at 8x2. `ListView(selectable: false, children: [Text('ab\nabcdef'), Text('xy\nxyz')])` in a filled 8x4 box. `ListView(children: [Text('a1\na2'), Text('b1\nb2'), Text('c1\nc2')])` in a filled 10x3 box (item 2 straddles the bottom edge). The same holes appear in Navigator dialogs (Container.filled) holding such lists.

**Verifier evidence.** I ran a probe at packages/fleury/test/_sweep_verify_rb_1_test.dart (since deleted). It prints a background map from tester.render(): B means the cell has a background, . means none.

1) Container(color: RgbColor(0,0,200), child: SizedBox(8x2, child: X)), where X is Text('ab\nabcdef'):
   - Direct paint: BBBBBBBB / BBBBBBBB
   - RepaintBoundary(child: X), first paint: BB....BB / BBBBBBBB
   - Same boundary, cache hit: BB....BB / BBBBBBBB
   - renderToString shows 'ab····', so the hole cells are Cell.empty.
2) ListView(selectable:false, children:[Text('ab\nabcdef'), Text('xy\nxyz')]) in a filled 8x4 box:
   - addRepaintBoundaries true (the default): BB....BB / BBBBBBBB / BB.BBBBB / BBBBBBBB
   - addRepaintBoundaries false: all B
3) ListView(children:[Text('a1\na2'), Text('b1\nb2'), Text('c1\nc2')]) in a filled 10x3 box, where item 2 straddles the bottom edge:
   - BB........ on all 3 rows, both with and without repaint boundaries and with the default selectable list.
   - So the straddle case comes from the clip path alone.

How it happens: _RenderFilledBox fills the box with ' ' cells that carry the background. It then paints the child and calls applyCellBackground, which only restyles leading cells.

Both composites use CellBuffer._copyCellRange, a raw setRange. It overwrites the fill with the source's Cell.empty cells. The composites are RenderRepaintBoundary.performPaint (render_repaint_boundary.dart:321, copyRectFrom) and _paintListViewport's clip path (list_view.dart ~1357, copyFrom of the whole viewport). A direct paint leaves those cells alone.

**Proposed fix.** Make the boundary and list composites transparent, as `replayCellFrom` already is: skip empty source cells, for example with a `setRange` per run of non-empty cells, evicting wide-character neighbours at run edges. Keep the raw copy only where an exact mirror is needed (`AnsiRenderer._renderScrollUp`). Add a test that `RepaintBoundary(child: X)` paints identically to `X` over a filled background.

**Verifier notes.** Confirmed as reported, and the medium severity is right. Two defects share one root cause, and they are independent.

1. **The boundary blit is not transparent.** Every ListView item is wrapped in a boundary by default, so ragged multi-line items leave holes. Cache verification cannot catch this, because the cache matches a fresh repaint.
2. **ListView's clip path copies the whole viewport scratch.** Any list with a partly visible item wipes the parent's background across the entire viewport. This happens even with addRepaintBoundaries:false, so turning off boundaries does not work around it.

ScrollView composites its scratch buffer with replayCellFrom, which already treats empty cells as transparent (scroll_view.dart:584). ListView's clip path is the one composite that doesn't.

Fix:
- **ListView clip path:** switch to transparent compositing, either replayCellFrom as ScrollView does or a transparent rect copy.
- **_copyRect / copyRectFrom:** add a transparent mode that does a setRange per run of non-empty source cells. It needs to evict wide-character neighbours at each run edge. The existing slice-edge continuation/leading fix-ups can stay.
- **Keep the raw mirror copy for AnsiRenderer._renderScrollUp**, which needs an exact copy of the previous frame.

Transparency is safe here because the destination is either a freshly cleared frame buffer or a parent's freshly cleared cache. The comment on copyFrom already assumes the region was cleared.

Also add a regression test that RepaintBoundary(X) and a clipped ListView over a filled background paint the same as X painted directly.

Practical impact: any coloured surface holding a list shows holes, for example a dialog, a panel with color, or a chat pane. Chat and markdown lists nearly always have a straddling item, so the whole viewport loses its background, and the background reappears only when scrolling brings every item fully into view.

Also reported as: RepaintBoundary cache blits and ListView's clip path copy empty cells over the parent's paint, punching holes in backgrounds (every ListView item is wrapped in a boundary by default)

### [low] RenderFlex's offscreen cull never fires for subtrees containing text, so a ScrollView paints its entire content every frame
`fleury/lib/src/rendering/render_flex.dart:452`, perf, found by the render finder

**Claim.** `performPaint` skips a child outside the paint buffer only when `_subtreeNeedsOffscreenPaint` finds no Selectable in its subtree. Every Text is a Selectable (RenderText/RenderRichText), so the cull effectively never runs, and each offscreen child additionally pays a subtree walk. ScrollView lays its child out in full and paints it into a viewport-sized scratch buffer, so paint cost is O(content), not O(viewport). The exception dates from the initial commit, when selection geometry was recorded during paint. Geometry is now derived from layout (screenGeometry), and Selectable registration happens in updateRenderObject, so nothing needs offscreen paint.

**Reproduction.** `ScrollView(controller: ScrollController(initialOffset: n~/2), child: Column(children: [for i<n: Padding(padding: EdgeInsets.symmetric(horizontal: 1), child: Row([Text('$i'), Expanded(child: Text('settings entry number $i with a label'))]))]))` at 80x24. Time repeated `tester.render()` frames, and separately `column.paint(...)` into an 80x24 buffer.

**Verifier evidence.** Code trace (packages/fleury/lib/src/rendering/render_flex.dart:452-490): the offscreen skip applies only when `!_subtreeNeedsOffscreenPaint(c)`, and that function returns true for any subtree containing a `Selectable`. RenderText and RenderRichText both mix in SelectableTextMixin, so any row with text is never culled. Each offscreen child also pays a subtree walk before it is painted anyway. Nothing requires those paints. `selectionPaintRect` and `selectionClipRect` are `screenGeometry()?.bounds` / `.clip` (render_objects.dart:700-703), which RenderObject._resolveScreenGeometry derives from layout (childOffsetOf/childClipOf) and memoizes against the geometry epoch. The only thing paint does for selection is call getSelectionRange() → _refreshEdgesIfLinesChanged(). That refresh is documented as lazy and is also reached from copy (getSelectedContent), hit-testing and isOffsetSelected. An offscreen RenderText/RenderRichText performPaint returns right after that call (`offset.row >= buffer.size.rows || offset.row + visibleRows <= 0`). ScrollView's performPaint (scroll_view.dart:562-568) paints its whole child into a viewport-sized scratch buffer at -scroll.

Probe (test-only CullColumn whose RenderFlex subclass culls on bounds alone using public childOffsetOf/visitRenderChildren; falls back to super when overflow clip is active). Run with `dart run` so asserts are off. Two FleuryTesters, interleaved ABAB/BABA rounds, scroll ±1 per frame, median of 6. Output buffers were compared at offsets 0, n/3, n/2 and n and matched in every case:
asserts=false
n=24   frame stock=85us   cull=117us (min 71/76)       | column paint stock=19us   cull=14us
n=200  frame stock=218us  cull=143us (min 173/130)     | column paint stock=67us   cull=31us
n=2000 frame stock=2438us cull=1921us (min 1756/1446)  | column paint stock=625us  cull=108us
n=8000 frame stock=14258us cull=7454us (min 11028/5886)| column paint stock=6130us cull=648us
Paint through the viewport is O(content): about 0.3 us per offscreen row, and 6-9x slower than the culled version at 2000-8000 rows. Probe file deleted.

**Proposed fix.** Delete `_subtreeNeedsOffscreenPaint` and cull on bounds alone. Optionally binary-search the first and last intersecting child, since offsets are monotonic along the main axis, so the walk is O(visible + log n). Run alloc-gate and paint-gate after the change.

**Verifier notes.** The mechanism is confirmed: the Selectable exception defeats the cull for every text-bearing child, and derived geometry means no Selectable needs to be painted offscreen. I am downgrading severity from medium to low for three reasons.
(1) The whole-frame gain is modest at realistic sizes: about 75 us/frame at 200 rows and about 0.5 ms/frame (about 20%) at 2000 rows. Only at 8000 rows does it halve the frame (14.3 ms to 7.5 ms).
(2) Even with the cull, frames stay O(content). At 8000 rows about 7 ms/frame of other O(n) work remains, which is not paint. So "ScrollView paints its entire content" is true, but fixing it does not make ScrollView O(viewport).
(3) Large lists should use the virtualized ListView. Scroll-driven repaint in a non-virtualized ScrollView is the only workload this affects.

The fix is right as proposed: delete `_subtreeNeedsOffscreenPaint` and cull on bounds alone. The optional binary search over monotonic child offsets would take the remaining O(n) bounds loop down to O(visible + log n). The finder reports that selection plus scroll suites pass with the exception removed; I did not rerun those suites.

One subtle behavioural difference I found by reading (not tested): with a live drag selection, the lazy `_refreshEdgesIfLinesChanged` re-relate for text that relaid out while offscreen would run at the next copy or on-screen paint instead of at the offscreen paint. That already matches the documented "runs lazily" contract, so I do not see it as a regression. As CLAUDE.md requires for rendering changes, run alloc-gate and paint-gate after the change.

## C. Input & editing (7)

### [high] Holding Ctrl+C exits the app even when the press was handled, e.g. after copying a selection or an app's Interrupt binding
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/runtime/run_app.dart:739`, bug, found by the input finder

**Claim.** The quit guard exits on any Ctrl+C KeyEvent that is not an `up` and was not handled. With kitty flag 2, which is set in both non-legacy tiers, holding Ctrl+C past the OS key-repeat delay sends `CSI 99;5:2u` (type repeat). KeyBindings skip repeats by default (`_phaseEligible`, includeRepeats: false). So a Ctrl+C that a binding handled on the press is followed by a repeat the dispatcher reports as `ignored`, and the guard quits. This hits the always-on DefaultRootSelection copy binding with no app code: select text, press Ctrl+C slightly too long, and the app copies then exits. It also hits any app Interrupt/Cancel binding on Ctrl+C, the pattern the decision log says keeps the app alive. The guard fences `up` ('once per physical press') but not `repeat`.

**Reproduction.** Scenario 1: `runApp(KeyBindings(bindings: [KeyBinding(KeySequence.ctrl.c, onTrigger: (_) => interrupts++)], child: Focus(autofocus: true, child: Text('agent running'))), driver: FakeTerminalDriver(keyboardCapabilities: KeyboardCapabilities.full))`. Enqueue `KeyEvent(char c, {ctrl})`, then `KeyEvent(char c, {ctrl}, type: repeat)`. Scenario 2: `runApp(const Text('hello world'))`; drag-select from col 0 to col 5 with MouseEvents; send Ctrl+C down, then Ctrl+C repeat.

**Verifier evidence.** I ran the probe packages/fleury/test/_sweep_verify_ctrlc_1_test.dart in the sweep worktree and have since deleted it. It used runApp with FakeTerminalDriver and enableHotReload:false.
(a) Parser: the bytes `ESC[99;5u ESC[99;5:2u ESC[99;5:3u` parse as `[KeyEvent(ctrl+c), KeyEvent(ctrl+c repeat), KeyEvent(ctrl+c up)]`, so a real kitty flag-2 terminal delivers the repeat. The default keyboard mode is lifecycle (flags 31), and the disambiguated tier asks for flags 1|2.
(b) Scenario 1 (KeyBinding(KeySequence.ctrl.c) inside Focus(autofocus), KeyboardCapabilities.full): "after press: interrupts=1 exited=false active=true", then "after repeat: interrupts=1 exited=true active=false".
(c) Legacy control (FakeTerminalDriver default caps, two plain downs): "legacy: interrupts=2 exited=false". Only the repeat-tagged event exits.
(d) Scenario 2 (runApp(const Text('hello world')), no app bindings, mouse down/drag/up over cols 0-4, then Ctrl+C): "after press: exited=false active=true", then "after repeat: exited=true active=false". The existing regression test 'unhandled Ctrl+C resolves AppExit.requested' shows that Ctrl+C with no selection exits on the down. So the press staying alive here means the default selection copy binding handled it, and the repeat then quit the app. (The fake driver showed no OSC 52 bytes, so the probe could not check the clipboard contents directly.)
Code: in run_app.dart around lines 733-745, the guard is `event.type != KeyEventType.up && ... && dispatchResult != handled`. In input_dispatcher.dart:1098, `_phaseEligible` returns false for repeats unless `includeRepeats` is set, so a repeat of a handled press comes back `ignored`.

**Proposed fix.** Make the guard require `event.type == KeyEventType.down`. A repeat of an unhandled press is always preceded by a down that already exits. Alternatively, record whether the originating down was handled and treat its repeats the same way.

**Verifier notes.** The finding holds as described. It only needs a real terminal that sends kitty event types, which is the default lifecycle tier; the browser/serve path is exempt through surfaceSink. The trigger is holding Ctrl+C past the OS key-repeat delay (about 250-600 ms). The app then exits with no confirmation and the session is lost. It affects the always-on selection copy path with no app code, and it affects the documented pattern where an Interrupt binding on Ctrl+C keeps the app alive, which is common in agent TUIs. I'm keeping severity at high.

The proposed fix is right: change the guard to `event.type == KeyEventType.down` in place of `!= KeyEventType.up`.
- An unhandled press always arrives first as a `down` and exits there, so its repeats never need to trigger the exit.
- On legacy terminals every auto-repeat arrives as a plain `down`, so behavior there does not change.
- A binding with includeRepeats:true that handles the repeat was already safe.
- Tracking whether the originating down was handled is not needed; the down-only check covers it because repeats never initiate anything.

Suggested regression test: KeyboardCapabilities.full plus a Ctrl+C binding. Send a down, a repeat and an up, and assert the app is still active afterwards.

### [high] The numeric keypad does nothing on kitty-protocol terminals (the default setup): digits are dropped, and KP Enter and NumLock-off navigation keys are ignored
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/terminal/input_parser.dart:977`, bug, found by the input finder

**Claim.** By default runApp negotiates the kitty protocol at the lifecycle tier (flags 1|2|4|8|16). Flag 1 is also set in the disambiguated tier. With disambiguate on, kitty keeps keypad keys as their private-use (PUA) key numbers: key_encoding.c only folds them to normal keys when `!disambiguate && !report_text`. Under report-all, a text-producing keypad key arrives as `CSI 57400;129;49u` (KP_1, NumLock bit, associated text "1"). `_emitKittyKey` maps the PUA code through `_kittyFunctionalKey` and returns a bare `KeyEvent(keypad1)`, so the associated text is thrown away. Nothing downstream folds keypad codes. TextEditingKeymap matches only `KeyCode.enter/arrowLeft/home/...`, `FocusableControl._onKey` (focusable_control.dart:129) and ListView (list_view.dart:908) check `KeyCode.enter`, and `_KeyStep.matches` compares specials exactly. The results: numpad digits and operators insert nothing, numpad Enter does not submit a TextInput, activate a Button or select a ListView row, and NumLock-off keypad navigation (KP_Left/Up/Home/End/PgUp/Delete) does nothing. The browser backend folds NumpadEnter to `KeyCode.enter` and numpad digits to text, so this also breaks terminal/browser parity.

**Reproduction.** Feed kitty lifecycle bytes through `InputParser` and dispatch the events into a tester with a focused `TextInput(onSubmit: ...)`, and separately a focused `Button`: `\x1b[49;;49u` (main-row 1), `\x1b[57400;129;49u` (KP_1), `\x1b[57413;129;43u` (KP_+), `\x1b[57414;129u` (KP_Enter). With a TextInput holding 'abc' and the caret at 3, send `\x1b[57417u` (KP_Left).

**Verifier evidence.** I ran a probe at packages/fleury/test/_sweep_verifyinput_kp_1_test.dart (now deleted). It fed kitty CSI-u bytes through the real InputParser and passed each event to tester.dispatcher.dispatch.

Parser output:
- `[49;;49u` gives `InputBatch(KeyEvent(1) + "1")`
- `[57400;129;49u` gives `KeyEvent(keypad1 @numpad1)`, and the associated text "1" is dropped
- `[57413;129;43u` gives `KeyEvent(keypadAdd @numpadAdd)`, and the text "+" is dropped
- `[57414;129u` gives `KeyEvent(keypadEnter @numpadEnter)`
- `[57417u` gives `KeyEvent(keypadLeft)`

TextInput('abc', caret at 3):
- KP_Left: caret stays at 3.
- `CSI 1;129D` (ArrowLeft with the NumLock bit): caret moves to 2. So the lock bit is not the cause; the keypad identity is.
- KP_1: text stays 'abc'. KP_+: text stays 'abc'.
- Main-row `CSI 49;129;49u`: text becomes 'a1bc'.
- KP_Enter: submitted=[]. Main Enter `CSI 13;129u`: submitted=[a1bc].

Button (autofocus): 0 presses after KP_Enter, 1 after Enter.

ListView.builder(onSelect): selected=[] after KP_Enter. After KP_Down (`CSI 57420u`) then Enter, selected=[0], so KP_Down did not move the highlight either.

Downstream code does nothing with keypad keys. Keypad codes appear in lib/ only in key_tables.dart, events.dart and input_parser.dart. The DOM backend (fleury_web dom_input_source.dart:1078) maps by `event.key`, so NumpadEnter becomes `KeyCode.enter` and numpad digits arrive as text. Terminal and browser therefore behave differently.

Default exposure: resolveKeyboardTier (posix_driver.dart:1548) returns lifecycle unless inside a multiplexer or overridden by FLEURY_KEYBOARD. Inside a multiplexer the tier drops to disambiguated, which still sets flag 1, and the kitty spec reports every keypad key as a PUA CSI-u code under flag 1. In that tier there is no associated text at all (flag 16 is off), so keypad digits are lost there too.

**Proposed fix.** In `_emitKittyKey`, when a keypad functional key carries valid associated text and no actionable modifier, emit `InputBatch(key: KeyEvent(keypadN, position: ...), committedText: text)`, the same shape as the printable branch. That keeps keypad identity and still delivers the text. For the non-text keypad keys, add one logical fold (keypadEnter→enter, keypadLeft→arrowLeft, keypadHome→home, keypadDelete→delete, …). Consult it from `TextEditingKeyBinding.matches`, `FocusableControl`, ListView and special-step matching, or fold in the parser while keeping `position: numpadEnter`, which is what the DOM backend already does.

**Verifier notes.** The finding holds as claimed. The parser's "KP Enter deliberately distinct, nothing silently folded" comment (input_parser.dart:974) is only half the design. Keeping keypad identity is fine. But nothing downstream maps keypad keys to their logical meaning, and `_emitKittyKey` throws away valid associated text for keypad keys. The printable branch keeps it, and RFC 0020 §8.7 lists associated text as parsed data. Typed digits vanish silently in any TextInput on kitty, Ghostty, WezTerm (kitty mode) or foot with a numpad keyboard, and KP Enter does not submit, activate or select. That is lost user input, so high severity stands, though it only affects users who type on a numpad.

Suggested root-cause fix, refining the proposal:
1. In `_emitKittyKey`, a keypad text key (keypad0-9, Decimal, Divide, Multiply, Subtract, Add, Equal, Separator) with no actionable modifier and type != up should emit `InputBatch(key: KeyEvent(keypadN, position), committedText: associatedText ?? canonicalChar)`. The canonical-char fallback is needed because the disambiguated/multiplexer tier sends no flag-16 text. Kitty already distinguishes KP_4 from KP_LEFT by NumLock, so a KP digit code always means the digit.
2. Give keypad nav/Enter keys one logical equivalence (keypadEnter→enter, keypadLeft/Right/Up/Down/Home/End/PageUp/PageDown/Insert/Delete→their main keys). Apply it in one place, in the binding/special-step matcher, so TextEditingKeymap, FocusableControl (focusable_control.dart:129), ListView (list_view.dart:908) and KeyBindings all get it. Doing it per widget would spread the fix across several places. The event keeps `position: numpadEnter` so keypad-specific bindings still work.

Also update the existing test at input_parser_test.dart:1243 (`KP Enter is distinct from Enter`), which pins the parser half on purpose. The legacy DECKPAM path (`ESC O M`, `ESC O p`) returns the same unfolded keypad codes and would benefit from the same equivalence.

Also reported as: Kitty-protocol numpad: digits are never typed and keypad Enter does nothing

### [medium] Browser: printable keys reach detectors twice, and Shift+letter typeahead skips a match
`fleury/lib/src/runtime/input_dispatcher.dart:248`, bug, found by the input finder

**Claim.** In the browser, one printable press arrives as a keydown KeyEvent and then an `input` TextInputEvent. The keydown's identity is lowercased by `_shortcutChar`, with Shift kept in the modifiers (dom_input_source.dart:1047, 1107); the input event carries the real text. The dispatcher runs the key half past every detector (input_dispatcher.dart:271-292). It then calls `_dispatchText` with `keyAlreadyWalked: false`, so `_dispatchPlain(..., visitDetectors: !keyAlreadyWalked)` (line 837) runs every detector a second time with a KeyEvent rebuilt from the text. That contradicts the dispatcher's own comment that DOM text "visits binding scopes only". The one guard, `_suppressNextText`, stores `event.code.character` ('d') at line 288 and compares it exactly with the typed text ('D') at line 248, so it never matches uppercase letters or Caps Lock. Result: every unclaimed printable reaches each KeyDetector twice, and a Shift+letter a detector consumed is delivered again. The Tree, DataTable, Select and Menu typeaheads consume printables, so their typeahead runs twice.

**Reproduction.** Set KeyboardCapabilities.full (the DOM profile) and build KeyDetector(records the key, consumes 'd'/'D') > Focus(autofocus). Send what DomInputSource emits for one press: KeyEvent(KeyCode.char('d'), modifiers: {shift}), then TextInputEvent('D'). Widget-level check: a Tree with roots Alpha, Delta, Dog, Echo (autofocus), the same Shift+D pair, then Enter.

**Verifier evidence.** I checked that the browser really sends the two events separately. In packages/fleury_web/lib/src/input/dom_input_source.dart, keyEventFromBrowser (around line 1045) emits KeyEvent(KeyCode.forCharacter(_shortcutChar(key)), modifiers incl. shift). _shortcutChar lowercases A-Z. _handleInput (line 481) then emits TextInputEvent(data) as its own event. Nothing pairs the two into an InputBatch: run_tui_surface.dart:363 passes each event straight to inputDispatcher.dispatch, and both hosts declare KeyboardCapabilities.full.

In input_dispatcher.dart, the bare-KeyEvent branch (271-292) walks detectors on the key lane. When a detector consumes the key it sets `_suppressNextText = event.code.character` ('d'). The TextInputEvent branch (244-250) only drops the text on an exact match (`event.text == suppressed`). Otherwise it calls `_dispatchText(event)` with the default keyAlreadyWalked=false, and line 837 then runs `_dispatchPlain(..., visitDetectors: true)`. The comment at 826-832 says the opposite ("On correlated and DOM input the key view already visited detectors, so the text view visits binding scopes only").

Probe 1 (packages/fleury, KeyboardCapabilities.full, KeyDetector > Focus(autofocus), dispatching the DOM pair):
consume=true key=d{} text=d -> [d]
consume=true key=d{shift} text=D -> [d+shift, D]
consume=true key=x{} text=x -> [x, x]
consume=false key=d{} text=d -> [d, d]
consume=false key=d{shift} text=D -> [d+shift, D]

Probe 2 (fleury_widgets, Tree with roots Alpha/Delta/Dog/Echo, autofocus, then Enter):
shift=false DOM pair -> onSelect [Delta]
shift=false legacy text-only -> [Delta]
shift=true DOM pair -> [Dog]   <-- wrong
shift=true legacy text-only -> [Delta]

Both probe files were deleted afterwards.

**Proposed fix.** Treat the DOM split pair like an InputBatch. Record that the preceding split key half already walked the detectors, and dispatch the matching TextInputEvent with `keyAlreadyWalked: true` so it visits binding scopes only. Compare the suppression token case-insensitively, or against the DOM `event.key` text rather than the lowercased identity. Cleanest option: have DomInputSource pair keydown and input into one InputBatch.

**Verifier notes.** I reproduced the bug as reported. There are two defects with one root cause: the dispatcher never pairs a DOM split keydown with the `input` event that follows it.

(a) Every printable that no detector consumes reaches each KeyDetector twice in the browser: once as the key half and once as a KeyEvent rebuilt from the text. This happens for lowercase letters too, not only Shift (`[x, x]`, `[d, d]`). Any detector that acts without consuming therefore fires twice.

(b) When a detector consumes a Shift+letter, the suppression token is the lowercased identity ('d'). It is compared exactly with the typed text ('D'), so the text is not dropped and the detector gets the key again. Caps Lock goes through the same path, since _shortcutChar lowercases 'D' with no Shift held. Typeahead in Tree, DataTable, Select and Menu advances twice, so Shift+D skips the first matching row. On the terminal and in legacy text-only mode the result is correct ([Delta]), so this only affects the browser.

Medium severity is right. The effect is visible but not destructive: typeahead skips a row and non-consuming detectors see duplicate keys. No data is lost and nothing crashes.

On the fix: comparing case-insensitively only repairs (b). The proper fix is to remember that the preceding split key half already walked the detectors. Store the walked KeyEvent, not a text token. Then dispatch the next TextInputEvent (when it is the first event after that key) with `keyAlreadyWalked: true, keyView: thatKey`, so it visits binding scopes only. If the key half was consumed, drop the text no matter its case or layout. That clears the token whatever the outcome and fixes (a) and (b) together. Doing the pairing in DomInputSource by emitting an InputBatch is also clean, but keydown and `input` arrive in separate DOM tasks, so the source would have to buffer the key until the input event arrives. Doing it in the dispatcher is simpler.

Possible related gap (not probed): when an armed nextKey capture takes the split key half (line 265), it returns before `_suppressNextText` is set. The paired `input` text may then still reach the focused field or bindings.

### [medium] Clicking in a text field while a large paste is still being applied inserts the rest of the paste at the click point, scrambling the order
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/widgets/text_area.dart:673`, bug, found by the input finder

**Claim.** TextPasteDriver applies pastes larger than largePasteThreshold (8192 code units) over several frames. Every keyboard, text and semantic path calls `_paste.finish()` before touching the selection. `_pointerDown` and `_pointerDrag` in TextArea (673) and TextInput (1624/1640) do not: they assign `_controller.selection` directly. The next post-frame step then inserts the remaining text at the clicked caret, so the pasted content is split around the click, and the paste also becomes two undo transactions. This differs from the known focus-move split: it happens in the same field, with no focus change and no parser segmenting, for any paste over 8 KB.

**Reproduction.** Set viewport 40x10; `TextArea(controller: c, autofocus: true)`; `tester.paste(20000 code units of 'line NNNN\n' lines)`; `tester.pump()` once. Send left MouseEvent down and up at (0,0), pump 20 frames, then compare `c.text` to the pasted string.

**Verifier evidence.** I wrote a probe at packages/fleury/test/_sweep_verify_input_paste_click_1_test.dart (now deleted). It pastes 2000 lines of 'line NNNN\n' (20000 code units) into a focused field, sends a left mouse down and up at (0,0), pumps 20 frames, then presses Ctrl+Z until the field is empty. Output:
TextArea:
  after paste(): 2048/20000 caret=2048
  caret after click: 0, len=2048
  final len 20000, equals: false
  diverge at 0 got=4\nline 0205\nline 0206... exp=line 0000\nline 0001...
  undos to empty: 2
TextInput (expected text is prepareInput(singleLine: true)):
  after paste(): 2048/20000 caret=2048
  caret after click: 0, len=2048
  final len 20000, equals: false
  diverge at 0 got=4 line 0205 line 0206... exp=line 0000 line 0001...
  undos to empty: 2
Control probe (_2, also deleted):
- Pressing Home mid-paste leaves the final text equal to the paste, because the key path calls _paste.finish() first.
- An uninterrupted paste undoes in 1 step.
So in both widgets the click moves the caret to 0 while about 18 KB of the paste is still queued. The remaining text is then inserted ahead of the text already applied, so the lines come out in the wrong order, and the one paste needs two undo steps.

**Proposed fix.** Call `_paste.finish()` at the top of `_pointerDown` and `_pointerDrag` in both TextInput and TextArea, as the keyboard paths already do. Alternatively, have the driver anchor its insertion offset and apply the tail at that anchor.

**Verifier notes.** I traced the root cause as the finding describes.
- `_pointerDown` and `_pointerDrag` assign `_controller.selection` directly: text_area.dart:673/689 and text_input.dart:1624/1640.
- `_onChange` only calls `_paste.discardAtomic()`, which leaves an ordinary paste running.
- The next post-frame step of `TextPasteDriver` then applies the rest of the text at the current selection.
- Every keyboard path calls `_paste.finish()` before it edits, and the finish() doc comment says it exists to keep order before the next editing transaction. The pointer path skipping it is a missed barrier, not intended behavior.

Real-world exposure: pastes over 8192 code units are applied in steps that grow with the document. That takes O(log n) frames, a few frames for tens of KB, and the event loop turns between steps by design, so a click in that window really can arrive. The window is short, which limits how often this happens. The result, though, is silently scrambled user text with no error, so I'm keeping the severity at medium.

Fix: call `_paste.finish()` at the top of `_pointerDown` and `_pointerDrag` in both widgets, before computing the offset and after the enabled/clickable guard. That matches the keyboard paths and keeps the paste as one edit ahead of the new selection. The alternative the finding suggests (anchoring the insertion offset inside the driver) is worse:
- It would still produce two undo transactions.
- It could conflict with a user selection that overlaps the unapplied region.

A better long-term fix at the root would be for the controller's selection setter, or `_onChange`, to act as the barrier, so any future path that sets selection outside the paste is covered. `_onChange` can't simply call finish(), though, because the driver's own edits also fire `_onChange`. It would need a flag that marks edits coming from the driver. Another probe file (`test/_sweep_verify_shiftbs_1_test.dart`) belongs to a different agent and I left it alone.

### [medium] Shift+Backspace (also Shift+Delete, Shift+Enter, Ctrl+Backspace) does nothing in TextInput/TextArea on kitty-protocol terminals and in the browser
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/editing/text_keymap.dart:187`, bug, found by the input finder

**Claim.** The editing keymap bindings for backspace, deleteForward, submit and insertNewline (lines 187/191/251/288/292/362) only match an unmodified key. `allowShift` defaults to false and the event's modifiers must be a subset of the binding's. Legacy terminals send Shift+Backspace as plain 0x7F, so it works there. kitty sends `CSI 127;2u` whenever flag 1 is set: its encode_function_key only emits 0x7f with no modifiers or with report_text off. The DOM backend emits `KeyEvent(backspace, {shift})`. The keymap resolves to null and the key is silently ignored. A common trigger is correcting a capital letter while Shift is still held. The same applies to Shift+Enter (a single-line field stops submitting; the default TextArea inserts no newline), Shift+Delete, and Ctrl+Backspace (legacy 0x08 does a plain backspace; kitty `CSI 127;5u` does nothing).

**Reproduction.** Mount `Column(TextInput(controller: 'HELLO', autofocus: true), TextArea(controller: 'HELLO', focusNode: f))`. Dispatch the parsed `\x1b[127;2u` to the focused TextInput. Focus the TextArea and dispatch the same bytes, then `tester.sendKey(KeyEvent(KeyCode.backspace, modifiers: {shift}))` (the DOM shape).

**Verifier evidence.** I ran a probe (packages/fleury/test/_sweep_verify_shiftbs_1_test.dart, now deleted) that fed bytes through the real InputParser, dispatched the events to a focused TextInput or TextArea, then pumped.

Parser output:
- 0x7f gives KeyEvent(backspace).
- `\x1b[127;2u` gives KeyEvent(shift+backspace @backspace).
- `\x1b[127u` gives KeyEvent(backspace @backspace).
- `\x1b[13;2u` gives KeyEvent(shift+enter @enter).
- `\x1b[3;2~` gives KeyEvent(shift+delete @delete).
- `\x1b[127;5u` gives KeyEvent(ctrl+backspace @backspace).

TextInput with controller text 'HELLO':
- after kitty plain Backspace (`\x1b[127u`): "HELL"
- after kitty Shift+Backspace (`\x1b[127;2u`): "HELLO", nothing deleted
- after Ctrl+Backspace (`\x1b[127;5u`): "HELLO"
- after moving the caret left and sending Shift+Delete (`\x1b[3;2~`): "HELLO"
- after dispatching `\x1b[13u` then `\x1b[13;2u` with onSubmit set: submits = [HELLO]. Only the plain Enter submitted; Shift+Enter did nothing.

TextArea with 'HELLO', sending the DOM shape KeyEvent(backspace, {shift}): "HELLO". DOM Shift+Enter: the code units stay [72,69,76,76,79], so no newline. A plain backspace afterwards gives "HELL".

Code trace: in text_keymap.dart, TextEditingKeyBinding.matches rejects any event modifier that is not in `modifiers`, except Shift when `allowShift` is set. The backspace and deleteForward bindings (lines 187/191 and 288/292) and the submit and insertNewline bindings (251/362) have no allowShift. The default KeyboardProtocolMode is lifecycle (flags 1|2|4|8|16), and the parser keeps shift on CSI-u backspace. The browser keyEventFromBrowser in fleury_web dom_input_source.dart:1009 passes `_modifiersFromKeyboard(event)` straight through with KeyCode.backspace.

**Proposed fix.** Set `allowShift: true` on the backspace and deleteForward bindings, and on submit/insertNewline in the non-chat presets, which matches what legacy terminals deliver. Consider binding Ctrl+Backspace / Alt+Backspace to a word delete instead of leaving them inert.

**Verifier notes.** The finding holds. The tests pin Ctrl+Enter resolving to null in the chat preset on purpose. No test or doc says Shift+Backspace or Shift+Delete should be inert, so this looks like an oversight in the bindings.

Severity stays medium. Lifecycle is the default request, so every kitty-protocol terminal (kitty, Ghostty, WezTerm, foot, recent iTerm2) and the browser surface are affected. The failure is silent: the edit is just lost.

Corrections to the finding:
- Shift+Delete also fails on plain legacy terminals. xterm-style terminals send `CSI 3;2~` for it, which parses to shift+delete. This is not limited to kitty and the browser.
- Ctrl+Backspace is less clear-cut. On legacy terminals 0x08 gives a plain backspace. Whether it should delete a word is a policy choice (the emacs presets already have killWordLeft), so it is weaker evidence of a bug.
- Shift+Enter in the default presets is partly a design choice. Submitting from a single-line field and adding a newline in a multiline field are the natural readings. The chat preset already binds Shift+Enter explicitly ahead of plain Enter, so it is unaffected.

Fix: add `allowShift: true` to the backspace and deleteForward bindings in `_defaultSingleLine` and `_defaultMultiline`. Also add it to the plain Enter submit and insertNewline bindings in the default presets. The chat preset's explicit Shift+Enter newline binding comes first in its list, so it still wins there. A regression test should dispatch the parsed `\x1b[127;2u` and `\x1b[3;2~` to a focused field, not only resolve synthetic events, because synthetic events hide the modifier shape the parser actually produces.

Also reported as: Shift+Backspace, Shift+Delete and Shift+Enter do nothing in text fields on kitty-protocol terminals and in the browser

### [medium] Tab in an overflowing ScrollView form skips hidden fields and never scrolls to them
`fleury/lib/src/widgets/focus.dart:881`, bug, found by the input finder

**Claim.** `FocusNode.rect` returns null for any node clipped out of its ScrollView viewport (focus.dart:203-211). `_traversalOrder` sorts every null-rect node after all painted nodes (focus.dart:875-887). `_cycleFocus` (843-856) then just calls `requestFocus` on the next entry. Nothing scrolls it into view: `revealInScrollViews` exists, but its only caller is Form's focus-the-invalid-field path. So in a form inside a ScrollView that overflows, Tab goes from the last visible field to controls outside the scroll view (Submit, footer) before any hidden field. When a hidden field does get focus, it stays scrolled out of view, so the user types into a field they cannot see, with no caret.

**Reproduction.** FocusTraversalGroup > Column[SizedBox(height: 4, child: ScrollView(controller, child: Column(8 TextInputs f0..f7, f0 autofocused))), Focus(focusNode: submit, child: Text('[ Submit ]'))]. Render at 20x6, press Tab 6 times, and after each press record the focused node and scroll.offset.

**Verifier evidence.** I wrote a probe at packages/fleury/test/_sweep_tabscroll_1_test.dart and deleted it after the run. The tree was FocusTraversalGroup > Column[SizedBox(height:4, ScrollView(controller, Column(8 TextInputs f0..f7 with placeholders, f0 autofocus))), Focus(submit, Text('[ Submit ]'))], rendered at 20x6. I pressed Tab 9 times and re-rendered after each press. Result: `[f0@0, f1@0, f2@0, f3@0, submit@0, f4@0, f5@0, f6@0, f7@0, ?(ScrollView)@0]`. After the last presses the screen showed only field0..field3 and '[ Submit ]' while f7 had focus, and ScrollController.offset never left 0. Code paths: FocusNode.rect (focus.dart:203-211) returns null when geometry.visible == null. _traversalOrder (focus.dart:866-888) sorts null-rect nodes after every painted node. _cycleFocus (843-856) only calls requestFocus. revealInScrollViews (scroll_view.dart:26) is called only from fleury_widgets/lib/src/form.dart, and ScrollView has no focus listener that would reveal a focused descendant.

**Proposed fix.** Order Tab traversal per scrollable: treat each ScrollView as a traversal group and order its descendants by their unclipped layout position in the content (or by tree order), rather than pushing clipped nodes to the end. After Tab or arrow traversal moves focus, reveal the new node after layout with `revealInScrollViews(node.context!.findRenderObject()!)`, as Form already does for invalid fields.

**Verifier notes.** I reproduced this exactly as described. Tab goes from the last visible field to Submit before any field clipped out of the viewport. The hidden fields then get focus with the viewport still at offset 0, so the user types into a field they cannot see. After the last field, Tab lands on the ScrollView's own focus node, which the finding did not mention. Its rect is null because the Column child sizes that node's Focus (it's a quirk, not a separate bug).

The rect doc comment says a clipped node is one "you scroll to, you don't arrow to". That rationale covers directional arrows and is intended. It does not justify Tab order depending on the current scroll offset, and nothing documents it for Tab. The order is also unstable: which fields go "last" changes as the user scrolls.

I'm lowering severity from high to medium. No data is lost and nothing crashes. It is a real usability and accessibility defect on a common pattern (a long form in a ScrollView), and an app can only work around it by revealing fields itself in onFocusChange.

Better fix, rooted in the cause:
1. Order by content position. Order Tab by each node's layout position within the scroll content, ignoring clipping: compute bounds without the visible-clip test, i.e. use geometry.bounds even when visible is null but the node is still presented (not an inactive route or IndexedStack child). Tab order then no longer depends on scroll state. Keep the visible-only rect for directional arrows and click-to-focus.
2. Reveal on focus. Put the reveal in the focus path, not in _cycleFocus alone. For example, have ScrollView (or the Focus render host) listen for a focused descendant and call revealInScrollViews after the next layout. That covers Tab, programmatic requestFocus and autofocus, not only Form's invalid-field path.

### [medium] TextArea re-measures the whole document on every keystroke and caret move, then throws the result away
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/widgets/text_area.dart:1096`, perf, found by the input finder

**Claim.** `RenderTextArea.performLayout` segments every grapheme of every line and resolves its width to compute `widest`. That value is only used when the width is unbounded (`cols = hasBoundedWidth ? maxCols : widest`), so in the normal bounded layout it is discarded. The `selection` setter calls markNeedsLayout, so every arrow key, typed character and click pays a full-document grapheme scan. Separately, every caret move rebuilds TextEditingValue through `copyWith`, which re-runs the O(n) `sanitizeMultiline` scan on text that has not changed.

**Reproduction.** `TextArea` in a 100x30 viewport with N lines of ~70 chars, caret near the top. Time 100 alternating arrow keys plus `pump()`, and 100 `type('x')` plus `pump()`. Separately, time a replica of the widest loop (`line.characters` → `widthOfGrapheme(safeEditingGrapheme(g))`) over the pre-split lines, and time `TextEditingController.moveCursorRight/Left` alone.

**Verifier evidence.** Code read (packages/fleury/lib/src/widgets/text_area.dart). `performLayout` (around line 1096) loops `_lineDisplayWidth(line)` over every line to compute `widest`. It then uses it only in `cols = constraints.hasBoundedWidth ? constraints.maxCols! : widest`. The `selection` setter (line 1016) calls `markNeedsLayout()`, so a caret move with no text change still runs the whole scan. The line split is memoized by string identity, but the width scan is not. `TextEditingValue.copyWith` (text_editing.dart) always goes through the public constructor, which calls `sanitizeMultiline(text)`. That in turn calls `isSanitizedMultiline`, an O(n) code-unit scan, even when the text is unchanged.

Probe: packages/fleury/test/_sweep_verify_textarea_1_test.dart, since deleted. Setup: JIT `dart test`, 100x30 viewport, lines of about 70 ASCII characters, caret on line 0, 40 warmup iterations, then 5 interleaved reps of 100 iterations each, reporting the median.
- Per arrow key: sendKey + pump.
- Per typed character: type('x') + pump.
- widestScan: a replica of the widest loop over the pre-split lines.
- copyWithSel: `ctl.value.copyWith(selection:)` alone.

Results:
n=30    codeUnits=2179   arrow=276.8us   typed=241.8us   widestScan=44.0us    copyWithSel=2.7us
n=500   codeUnits=36889  arrow=990.4us   typed=1089.3us  widestScan=786.8us   copyWithSel=39.9us
n=2000  codeUnits=148889 arrow=3561.6us  typed=3821.3us  widestScan=3090.1us  copyWithSel=163.4us
n=8000  codeUnits=598889 arrow=14433.3us typed=15453.3us widestScan=12574.0us copyWithSel=664.1us

With the visible content held constant, the per-keystroke frame cost grows linearly with document size. Frame cost minus the discarded widest scan stays small: about 0.2 ms at 500 lines and about 1.9 ms at 8000 lines. So the unused scan is roughly 80-87% of each keystroke's cost at 500 lines and above. The copyWith re-sanitize is real but secondary: about 0.66 ms at 600K code units, about 4.6% of the frame.

**Proposed fix.** Compute `widest` only when `!constraints.hasBoundedWidth`, or cache it per `_cachedLines` identity. Let selection-only `copyWith` reuse the already-canonical text through the private constructor instead of re-sanitizing.

**Verifier notes.** Reproduced with numbers that closely match the finder's (theirs: 1.29/3.99/14.23 ms arrow at 500/2000/8000 lines; mine: 0.99/3.56/14.43 ms). Medium severity is about right. At 500 lines (about 37K code units, a realistic large TextArea) the discarded scan adds about 0.8 ms per keystroke in JIT, and at 2000 lines about 3 ms. AOT will shrink the absolute numbers, but the cost stays linear in document size for work whose result is thrown away.

This is not a true patched-code A/B. I did not patch lib/, to avoid disturbing other agents using the shared worktree. The attribution rests on a replica of the scan timed interleaved in the same process, plus the doc-size scaling with a constant viewport.

Fix notes:
1. Primary fix: compute `widest` only when `!constraints.hasBoundedWidth`. The unbounded case is rare, and there a cache keyed by `_cachedLinesSource` identity (next to the existing split memo) removes the rescan on caret moves too.
2. `_syncHorizontalScroll` and `_cursorLineCol` stay O(lines). `_cursorLineCol` only sums lengths, which is cheap, and `_syncHorizontalScroll` scans a single line. Neither is material.
3. For copyWith: when `text` is null or identical to `this.text`, call the private `TextEditingValue._` constructor to skip `sanitizeMultiline`. This is safe because `this.text` is already canonical, or deliberately preserved when `preserveText` is set. It is a small secondary win (under 5% of the frame).

Typing still pays one unavoidable re-split per text change, and after the fix it should pay no full-document width scan.

Also reported as: TextArea re-measures every line of the document on each keystroke and throws the result away

## D. App, commands & navigation (8)

### [high] Command shortcuts freeze `enabled`/`visible` at build time: the shortcut is dead or swallows the key while every other surface says the command is enabled
`fleury/lib/src/app/commands.dart:421`, bug, found by the app finder

**Claim.** CommandScope._bindings (commands.dart:407-429) and _FleuryAppState._bindings (app.dart:339-363) evaluate `command.visible` and `command.enabled` once, during build, and store the result in `KeyBinding.enabled`, a plain bool. A disabled KeyBinding never matches. Nothing rebuilds these scopes when the predicate's inputs change. CommandScope rebuilds only when its parent rebuilds or its parent registry notifies. FleuryApp's _ContextBuilder rebuilds only on FocusManager notifications. Meanwhile palette rows, semantic command nodes, CommandRegistry.invoke/invokeCommand and tester.invokeCommand all evaluate the predicate live. Result: a command like Undo that becomes enabled because of model state has a dead Ctrl+Z, while semantics, the palette and tests report it enabled and invokable. The reverse also happens: a command that becomes disabled keeps an enabled binding that consumes the key, records `disabled`, and never lets the key bubble to an outer binding. Any app-level command whose predicate reads app state is affected, because FleuryApp is normally the never-rebuilt root. The same goes for a CommandScope whose state lives below it.

**Reproduction.** _History extends Notifier { bool canUndo=false; }. Pump FleuryApp(commands:[AppCommand(id:'edit.undo', shortcuts:[KeySequence.ctrl.z], enabled:(_)=>h.canUndo, run:(_)=>h.undos++)], home: NotifierBuilder(notifier:h, builder:(_,h)=>Focus(autofocus:true, child: Text('canUndo=${h.canUndo}')))). Call h.setCanUndo(true) and pump(). The screen shows canUndo=true and the Undo semantic node reports enabled=true. sendKey(Ctrl+Z) leaves undos at 0, but tester.invokeCommand(edit.undo) completes. The same happens with a CommandScope wrapping a child that owns the state. Reverse: canUndo goes true then false under KeyBindings([Ctrl+Z → outer++]); after Ctrl+Z, outer=0 and lastResult=disabled.

**Verifier evidence.** I wrote my own probe at packages/fleury/test/_sweep_vfycmd_1_test.dart, ran only that file, and deleted it afterwards. It has 5 cases, including 2 controls, and all ran.

Setup: `_History with Notifier { canUndo, undos }`. `AppCommand(edit.undo, shortcuts:[Ctrl+Z], enabled:(_)=>h.canUndo, run: undos++)`.

1. App-level command, with the state read below FleuryApp through NotifierBuilder. After `h.setCanUndo(true)` and `pump()`:
   `screen: canUndo=true`
   `semantic enabled: true`
   `app undos after Ctrl+Z: 0 last=null`
   `invokeCommand: CommandInvocationStatus.completed undos=1`
2. Control: the same app, but with the NotifierBuilder above FleuryApp so FleuryApp rebuilds.
   `control undos after Ctrl+Z: 1`
   So the shortcut works only when something rebuilds the scope.
3. CommandScope with the state below it:
   `scope semantic enabled: true`
   `scope undos after Ctrl+Z: 0`
4. Reverse case: an outer `KeyBindings(Ctrl+Z → outer++)`, canUndo starts true, then `setCanUndo(false)` and `pump()`, then Ctrl+Z:
   `reverse: undos=0 outer=0 last=CommandInvocationResult(edit.undo, CommandInvocationStatus.disabled)`
   The stale enabled binding swallows the key.
5. Control for the reverse case: the command is disabled at build time.
   `control reverse: undos=0 outer=1`
   Here the key bubbles as it should.

Code path:
- `_CommandScopeState._bindings` (commands.dart:407-429) and `_FleuryAppState._bindings` (app.dart:339-363) snapshot `command.visible` and `command.enabled` into `KeyBinding.enabled`, which is a plain bool, at build time.
- key_bindings.dart:398 does `if (!binding.enabled) return;`.
- `onTrigger` calls `registry.invoke`, which evaluates the predicate live (commands.dart:261-265) and records `disabled` without bubbling.
- The palette, CommandButton, semantic command nodes and tester.invokeCommand all evaluate the predicates live.
- The commands guide (website/src/content/docs/guides/commands.mdx) promises that "palette rows, buttons, and shortcuts always share the same command and enabled state". The reproduction breaks that promise.

**Proposed fix.** Evaluate predicates when the shortcut fires. Install a dispatch-enabled binding for each command that has shortcuts, and in onTrigger check registry.isVisible/isEnabled(command, buildContext: source); if either is false, call event.bubble() so the key propagates exactly as a disabled binding would. To keep hint-bar flags current, either rebuild bindings when the registry notifies or let KeyBinding take an enabled predicate instead of a bool.

**Verifier notes.** I tried to refute this and could not: all three claims reproduced (the dead shortcut, the enabled semantics while the key does nothing, and the swallowed key in the reverse case).

- **Why the shipped samples miss it:** packages/samples/lib/src/commands_showcase.dart keeps `_isDirty` in the State that builds the CommandScope, so `setState` rebuilds the scope. That is the only reason the samples work.
- **Who is affected:** any app whose predicate reads a model that is not owned above the scope. FleuryApp is usually the root and is never rebuilt, so app-level commands are the common case.
- **Why tests hide it:** `tester.invokeCommand` bypasses the keyboard path and passes, so tests written against the documented testing API stay green.
- **Severity:** high is fair. The workaround (own the state above the scope) is undocumented, and the failure is silent: no error and no hint. The worst variant is the reverse one, where a key the app binds at an outer level stops working.

**Fix direction:** the proposed fix is right. Rebuilding bindings when the registry notifies would not help, because the predicate inputs are app state and not the registry.
- Evaluate `visible`/`enabled` inside `onTrigger`, using the same source context that `invoke` uses (`_commandSourceContext`).
- If either predicate is false, call `event.bubble()`. Bubbling is honoured only during synchronous handler execution, and the predicates are synchronous, so this works. Keep the async `invoke` for the run step only.
- A cleaner root-cause fix is to let `KeyBinding` take an enabled predicate (`bool Function()`) that the dispatcher checks at match time (key_bindings.dart:398 and the hold path at :589). Then chord-prefix matching and hint bars see live state too.
- One caveat with the bubble-in-onTrigger version: a disabled multi-key chord would still capture its prefix keys. The predicate-on-KeyBinding version avoids that.
- Hint-bar labels still use the build-time snapshot. The palette and semantics are already live.

I deleted the probe file; no other files were modified.

Also reported as: FleuryApp/CommandScope shortcuts snapshot `AppCommand.enabled` at build: a command that becomes enabled keeps a dead shortcut while semantics/palette report it enabled

### [high] Opening the debug panel (Ctrl+G -> docked, or Esc fullscreen -> docked) unmounts and re-creates the whole app: all State lost and navigation reset
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/debug/debug_shell.dart:85`, bug, found by the app finder

**Claim.** In docked mode DebugShell inflates the app (`widget.child`, whose Overlay carries runApp's GlobalKey) inside a LayoutBuilder builder, so the app is built at layout time. Switching into docked rebuilds the NotifierBuilder in the build phase, which deactivates the old app subtree. Docked is the default `_lastOpen`, so this happens on Ctrl+G from off, and also on Esc from fullscreen.

`BuildOwner.flushBuild()` then unmounts all inactive elements at its end (framework.dart:1754). That happens before layout runs the LayoutBuilder, so the GlobalKey can no longer be reclaimed. The app is built from scratch: every State re-runs initState, Navigator stacks reset to home, and text, scroll and focus are lost. Flutter defers `finalizeTree` until after layout and paint for exactly this case.

Transitions that stay in the build phase (off<->fullscreen, docked->fullscreen) do keep state, which hides the bug. runApp creates `DebugController(const DebugConfig())` (run_app.dart:453), which is enabled in every JIT/dev run. So every dev session that opens the inspector wipes the screen it wanted to inspect.

**Reproduction.** DebugShell(controller: DebugController(DebugConfig(enabled: true)), child: Overlay(key: GlobalKey<OverlayState>(), initialEntries: [OverlayEntry(builder: (_) => FleuryApp(title: 't', home: Home()))])).

Steps:
1. Push a Detail route and pump.
2. `tryConsumeDebugKey(controller, KeyEvent(KeyCode.char('g'), modifiers: {ctrl}))`, then pump.
3. Push Detail again, press F11 (to fullscreen), then Esc (back to docked).

A second probe counts initState/dispose of a StatefulWidget inside the entry. It gives the same result with an unkeyed wrapper between the shell and the Overlay, which is the native TerminalSessionScope shape.

**Verifier evidence.** I wrote the probe test packages/fleury/test/_sweep_verifyds_1_test.dart (now deleted). It mounts DebugShell(controller: DebugController(DebugConfig(enabled: true)), child: Overlay(key: GlobalKey<OverlayState>(), initialEntries: [OverlayEntry(builder: (_) => Probe())])). Probe is a StatefulWidget that counts initState and dispose. I ran it twice: once with the Overlay directly under the shell, and once with an unkeyed StatelessWidget wrapper in between (the TerminalSessionScope shape). Each transition is driven by tryConsumeDebugKey followed by tester.pump(). The tester uses the same BuildOwner.renderFrame path as tui_runtime.dart:151.

Both variants print the same output:
- initial: inits=1 disposes=0
- off->docked (Ctrl+G): inits=2 disposes=1
- docked->fullscreen (F11): inits=2 disposes=1
- fullscreen->docked (Esc): inits=3 disposes=2
- docked->off (Ctrl+G): inits=3 disposes=2
- off->docked (Ctrl+G): inits=4 disposes=3

So every entry into docked mode disposes the app's State and creates it again. Transitions that stay in the build phase (into fullscreen, into off) keep the State.

I then tested the proposed root fix by editing framework.dart temporarily and restoring it from a backup; git diff on lib/ is clean. The edit skips _finalizeInactiveElements inside the flushBuild call in _renderFramePhases and leaves the existing finalize after layout (framework.dart ~1908) in place. With that change every transition in both variants stays at inits=1 disposes=0, so the key reclaim works once finalize waits until after layout.

**Proposed fix.** Root cause: stop unmounting inactive elements in the build phase of renderFrame. Call `flushBuild` without the finalize step from `_renderFramePhases` and rely on the finalize that already runs after layout (framework.dart ~1908). This matches Flutter's finalizeTree timing and lets a GlobalKey move from a build-time slot into a layout-time builder.

Independently, give DebugShell a stable app slot in every mode, for example `Stack([child, if (mode != off) LayoutBuilder(builder: ... Positioned panel)])`. Then only the panel is built at layout time.

**Verifier notes.** The root cause is as the finder described. _flushBuild (framework.dart ~1760) calls _finalizeInactiveElements at the end of the build phase. The docked branch of DebugShell (debug_shell.dart:85) only inflates widget.child inside a LayoutBuilder builder, which runs later, at layout. By then the GlobalKey'd Overlay subtree that NotifierBuilder deactivated during build has already been unmounted, so it cannot be reclaimed.

Severity: high is justified.
- It hits every dev (JIT) session: DebugConfig.enabled defaults to !dart.vm.product, and tui_root.dart:85 always installs DebugShell when given a controller. Opening the inspector with Ctrl+G, or pressing Esc from fullscreen, wipes all State: navigation, text, scroll and focus. That wipes the screen the developer wanted to inspect.
- It is also a general framework defect, not only a debug-shell one. Any app that moves a GlobalKey'd subtree from a build-time slot into a LayoutBuilder loses its state the same way.
- Release builds are unaffected through DebugShell, because it is disabled there by default.

Fix: the proposed root fix is right and I verified it. Defer finalize in renderFrame's build phase to the finalize that already runs after layout, which matches Flutter's finalizeTree timing. Keep the finalize at the end of flushBuild for callers outside a frame (mountRoot, updateRoot, reassembleApplication), or make sure they drain afterwards; the frame path already drains after layout.
- Because this touches framework.dart and the per-frame path, CLAUDE.md requires alloc-gate, paint-gate and runtime-gate to pass after the change.
- One more thing to check: an exception in layout would leave elements deactivated at build time in _inactiveElements until the next frame or drainInactiveElements.
- The finder's second fix is also worth doing: give DebugShell a stable child slot in every mode, e.g. Stack([SizedBox.expand/child, if (mode != off) LayoutBuilder(panel)]). Then only the panel is built at layout time, and the app's state no longer depends on key reclaim across phases.

Also reported as: GlobalKey bookkeeping ends at flushBuild, before LayoutBuilder builds during layout: opening the debug shell docked (Ctrl+G/F12) disposes and re-creates the entire app

### [high] Root route consumes Esc even when nothing can pop, so FleuryApp Esc commands, the Toaster's Esc-dismiss and app-level Esc bindings never fire
`fleury/lib/src/widgets/navigator.dart:908`, bug, found by the widgets finder

**Claim.** Every active page route installs `KeyBinding(KeySequence.escape, onTrigger: (_) => navigator.maybePop())`. The handler never calls `event.bubble()`, so at depth 1 Esc is still consumed even though maybePop() returns false. Nothing that binds Esc above the Navigator ever sees it while focus is in the root route. That includes FleuryApp's own command KeyBindings, which app.dart installs directly above its root Navigator. It also breaks the Toaster's documented behaviour: 'Esc dismisses the most recent toast ... it only fires here when ... nothing inner handled it' (the WCAG 2.1.1 path). A persistent toast then cannot be dismissed from the keyboard.

**Reproduction.** (1) Toaster(child: Navigator(home: Focus(autofocus: true, child: Text('home')))). Call Toaster.show(ctx, 'Saved', persistent: true), send Esc. Repeat with Toaster(child: FleuryApp(title:'t', home: ...)). (2) KeyBindings([KeyBinding(KeySequence.escape, onTrigger: (_) => quit++)], child: Navigator(home: ...)), send Esc. (3) FleuryApp(home: ..., commands: [AppCommand(shortcuts: [KeySequence.escape], run: (_) => ran++)]), send Esc.

**Verifier evidence.** I wrote a probe at packages/fleury_widgets/test/_sweep_escverify_1_test.dart (since deleted). Every case autofocuses a Focus on the home screen and sends KeyEvent(KeyCode.escape). Output:
TOASTER[plain] before=1 after=0
TOASTER[navigator] before=1 after=1
TOASTER[app] before=1 after=1
BINDING[nav=false] hits=1
BINDING[nav=true] hits=0
APPCMD[home=false] ran=1
APPCMD[home=true] ran=0
All 7 tests passed.

- "plain" is Toaster(child: home). "navigator" is Toaster(child: Navigator(home:)). "app" is Toaster(child: FleuryApp(home:)). Each shows a persistent toast before Esc.
- "BINDING" is KeyBindings([Esc]) placed above the home, with and without a root Navigator.
- "APPCMD" is FleuryApp with an AppCommand(shortcuts: [KeySequence.escape]), once with child: and once with home:.

Code path: navigator.dart:905-911 installs `KeyBinding(KeySequence.escape, onTrigger: (_) => navigator.maybePop())` for every active dismissible route, including the root. The return value is thrown away and `event.bubble()` is never called. At depth 1, maybePop() (lines 541-559) returns false because `canPop` is false (`depth > 1`), yet the key still counts as handled. app.dart:408 wraps `home` in `Navigator(...)` below the command KeyBindings, so the canonical FleuryApp(home:) shape swallows every Esc command. toaster.dart:440-443 documents that Esc dismiss "only fires here when a toast is showing and nothing inner handled it", but inside any Navigator the root route always handles it.

**Proposed fix.** Bubble when there is nothing to pop and no guard vetoed. For example: onTrigger: (e) { final top = navigator._topLive; if (!navigator.canPop && (top == null || top.guards.every((g) => g.allowsPop))) { e.bubble(); return; } navigator.maybePop(); }. This keeps root PopScope interception (the 'intercept a would-be app exit' case) working. Add a test with an Esc binding above a Navigator at depth 1.

**Verifier notes.** I tried to refute this and could not. No test in navigator_test.dart asserts that Esc at the root is consumed. The Esc tests cover popping a pushed route, non-dismissible modals, and PopScope veto/allow. Nothing documents the root swallow as intended. The file header says `context.maybePop(); // Esc/back pops if not at the root`, which implies a no-op at the root, not a swallow.

The same bug also breaks nested Navigators: an inner Navigator at depth 1 eats the Esc that should pop the outer one.

On severity: high is fair. It is not a crash or data loss. But it hits the default FleuryApp(home:) shape. It silently kills every app-level Esc binding and command, and a persistent toast with no action cannot be dismissed from the keyboard, which breaks the documented WCAG 2.1.1 keyboard path.

On the fix: the proposal (bubble when !canPop and no guard vetoes) is correct and keeps the root PopScope "intercept app exit" case working. A cleaner root-cause fix is to have maybePop report why nothing happened (popped, vetoed, or nothing to pop), for example with a small enum or a private helper. The binding then does `if (result == nothingToPop) e.bubble();`. That keeps the guard logic in one place rather than duplicating it in the binding. Two details:
- A root route with only an allowing PopScope must still bubble. The proposal handles this through its allowsPop check.
- The barrierDismissible check doesn't matter here: a non-dismissible modal gets no binding, and a presented route is modal:true, so the key would not propagate anyway.

Add regression tests for three cases:
- an Esc binding above a depth-1 Navigator fires
- a blocking PopScope at the root still consumes Esc
- nested Navigators: inner at the root, outer at depth 2, and Esc pops the outer

Also reported as: Navigator's per-route Esc binding swallows Escape when there is nothing to pop (root routes), killing app-level Esc commands, root selection clearing, and Esc-back out of nested navigators; The root route swallows Esc, so app-level and ancestor Esc handlers never fire and nested navigators cannot Esc out of the outer page

### [medium] A status update made by a command is wiped when the command completes, and any later command wipes manual updates
`fleury/lib/src/app/app.dart:316`, bug, found by the app finder

**Claim.** _FleuryAppState registers `_commands.addListener(_syncStatus)` (app.dart:316). `_syncStatus` (app.dart:335) calls `_status.update(_appStatusItems(widget, _app))`, which rebuilds the status list from the status builder and extensions only. `CommandRegistry._record` (commands.dart:295-300) calls notify() after every invocation, and that happens after `await command.run(context)` (commands.dart:271-275). So whatever a command writes through the advertised command-context status access (`context.status!.update(...)`) is overwritten one microtask later by the builder's output. An imperative `FleuryApp.of(ctx).status.update(...)` is overwritten the next time any command runs or FleuryApp rebuilds. For async commands, progress written before the await does show, but the final result (for example 'FAILED') never survives. The shipped test 'commands can update status through command context' (test/app/fleury_app_test.dart:909) passes only because it asserts synchronously right after sendKey, before the invoke continuation runs. In production the frame microtask scheduled during run() goes first (frame_scheduler._defaultFlush), so the update is visible for at most one frame and is replaced in the same event-loop turn.

**Reproduction.** 1) FleuryApp(commands:[AppCommand(id:'refresh', shortcuts:[KeySequence.ctrl.f], run:(c)=>c.status!.update([StatusItem.success('Task', id:'task', value:'done')]))], child: Column([Expanded(Focus(autofocus:true, Text('Body'))), AppStatusBar(emptyText:'Idle')])). Then sendKey(Ctrl+F); await Future.delayed(Duration.zero); pump(). Result: the status bar shows 'Idle'. 2) Async variant with status builder (_) => [StatusItem.text('Branch', value:'main')] and a command whose run is: update([Deploy: running]); await 10ms; update([Deploy: FAILED]). 3) Manual variant: FleuryApp.of(ctx).status.update([Build: ok]), then await tester.invokeCommand(anyOtherCommand); 'Build: ok' is gone.

**Verifier evidence.** I wrote a probe at packages/fleury/test/_sweep_statusv_1_test.dart in the sweep worktree, ran it, and deleted it afterwards. It had three cases, and each one reproduces the claim:

A) There is no status builder. A command bound to Ctrl+F runs `c.status!.update([StatusItem.success('Task', id:'task', value:'done')])`. The output was:
  "A sync: task=true"
  "A after microtask+pump: task=false idle=true"
  renderToString gave "Body / (blank) / Idle".

B) The builder is `(_) => [StatusItem.text('Branch', value:'main')]`. An async command writes Deploy: running, waits 10ms, then writes Deploy: FAILED. The output was:
  "B during: running=true"
  "B after: failed=false branch=true"

C) There is no builder. `FleuryApp.of(ctx).status.update([Build: ok])` is followed by `tester.invokeCommand(otherNoopCommand)`. The output was:
  "C after manual: true"
  "C after unrelated cmd: build=false idle=true"

How it happens: after `await command.run(context)`, `CommandRegistry._record` (commands.dart ~295) calls `notify()`. That runs `_FleuryAppState._syncStatus` (app.dart:335), which does `_status.update(_appStatusItems(widget, _app))` and replaces the whole list with only the builder and extension items. When there is no builder, that list is `[]`. `didUpdateWidget` calls `_syncStatus` too, so any rebuild of FleuryApp also wipes imperative status.

The shipped test at test/app/fleury_app_test.dart:909 checks the result synchronously right after sendKey, before the invoke continuation runs, so it never sees the overwrite.

This is also a regression against intent that was written down. docs/implementation/execution-journal.md (~line 1918) says: "When a `FleuryApp.status` builder is absent, command-context status updates must not be cleared by unrelated command registry notifications."

**Proposed fix.** Keep builder/extension-derived items separate from imperative ones. For example, StatusController could hold a derived layer (replaced by _syncStatus) plus an imperative overlay keyed by item id that update()/set() writes, with `items` merging the two. Then re-deriving after a command, which the 'status builder renders' test depends on, no longer destroys command-written status. Also change the fleury_app_test case to await a microtask and pump before asserting.

**Verifier notes.** Severity is lowered from high to medium. The advertised command-context and imperative status path does not work at all: a command's final status never persists, and any later command wipes manual updates. However, apart from the one flawed test, nothing in the repo calls `context.status!.update` or `FleuryApp.of(ctx).status.update` (I searched packages, website/examples and docs). The derived `FleuryApp.status` builder path works, and apps can put their state behind it as a workaround. There is no crash and no data loss beyond the status display.

On the fix: the proposed layering is the right root cause, and it matches the journal finding that "derived status and imperative status updates need different behavior". StatusController should keep two layers:
- a derived layer that only `_syncStatus` replaces;
- an imperative overlay, keyed by item id, that `update()` writes.
`items` would merge the two, with imperative items overriding derived items that share an id.

A narrower patch that skips `_syncStatus` when there is no builder or extension would restore only the documented no-builder case. Case B, with a builder, would still lose the command's result, so the layered fix is the better choice.

The test at fleury_app_test.dart:909 should also `await Future.delayed(Duration.zero)` and pump before asserting. As written, it passes against the bug.

### [medium] AppCommand.run exceptions are silently swallowed on every interactive path, and semantic activation reports `completed` for a failed command
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/app/commands.dart:276`, bug, found by the app finder

**Claim.** `CommandRegistry.invokeCommand` catches every error from `command.run` and only records it in `lastResult`. Every interactive caller throws that result away:
- the FleuryApp and CommandScope shortcut bindings (`unawaited(_commands.invoke(...))`, app.dart:352 and commands.dart:423)
- CommandButton, CommandPalette rows and status-item actions
- both semantic contributors (`await ...invokeCommand(...); return true;`, app.dart:654-658 and commands.dart:550-554).

So a throwing command never reaches runApp's `errorReporter`, the error overlay that a throwing plain KeyBinding does reach (run_app.dart:719-728). It also never reaches runZonedGuarded, and nothing is logged. A failed save therefore looks exactly like a no-op. Because the contributor returns true, `invokeSemanticActionFromElement` reports `completed`, so these callers are all told a failed command succeeded: `tester.invokeSemanticAction`, fleury_test's fail-on-incomplete wrapper and `target(...).press()`, and MCP agents. A command that became disabled between the snapshot and the dispatch is also reported as `completed`.

**Reproduction.** FleuryApp(commands: [AppCommand(id: CommandId('file.save'), title: 'Save', shortcuts: [KeySequence.ctrl.s], run: (_) => throw StateError('disk full'))], home: CommandScope(label: 'Editor', commands: [AppCommand(id: CommandId('editor.format'), title: 'Format', run: (_) async => throw FormatException('bad input'))], child: Focus(autofocus: true, child: Text('doc')))).

Then call `await tester.invokeSemanticAction(SemanticAction.activate, role: SemanticRole.command, label: 'Save')`, do the same with label 'Format', and then call `tester.press(KeySequence.ctrl.s)`. For the control, run a plain `KeyBinding(ctrl+s, onTrigger: (_) => throw StateError('disk full'))`.

**Verifier evidence.** Probe: packages/fleury/test/_sweep_verify_cmd_1_test.dart (now deleted). It used the finder's reproduction: a FleuryApp with a sync-throwing 'Save' command bound to Ctrl+S, and a CommandScope with an async-throwing 'Format' command. The whole test ran inside runZonedGuarded, with a control test that used a plain KeyBinding. Output:
- `semantic Save: SemanticActionInvocationStatus.completed error=null`
- `semantic Format: SemanticActionInvocationStatus.completed error=null`
- `Ctrl+S thrown=null attempts=3`
- `app state: [{}, {commandCount: 1, statusCount: 0, lastCommandId: file.save, lastCommandStatus: failed}]`
- `zone errors: []`
- control: `plain KeyBinding thrown=Bad state: disk full`

Code paths I checked:
- commands.dart:271-284 catches every error into CommandInvocationResult.failed.
- The contributors at commands.dart:550-554 and app.dart:654-658 ignore the result and `return true`.
- These interactive callers drop the result: the bindings at app.dart:352 and commands.dart:423 (`unawaited`), command_button.dart:72, command_palette.dart:318 and status.dart:205.
- run_app.dart:1513-1522: the zone handler, after mount, calls errorReporter.report and keeps running. run_app.dart:1062 also reports semantic-action faults. So a throw that reached either path would paint the overlay, as the control case does.

**Proposed fix.** Keep returning the failed result, but make the failure visible:
- In both semantic contributors, turn a `failed` result into `Error.throwWithStackTrace(result.error!, result.stackTrace!)` so the dispatch reports `failed`. Return false (or throw) for `disabled` and `notFound`.
- For the fire-and-forget surfaces (bindings, CommandButton, palette, status actions), send failed results to `Zone.current.handleUncaughtError(error, stack)`, for example through one shared `invokeFromUi` helper on CommandRegistry. runApp's guarded zone then shows it in the error overlay, the same way it does for a throwing KeyBinding.

**Verifier notes.** I reproduced this exactly as claimed. A failed command reaches neither the error overlay nor the zone, and `invokeSemanticAction` reports `completed` for both the app-level command and the scoped one. From the code, the same mapping applies to a command that became disabled or not-found between the snapshot and the dispatch: invokeCommand returns a disabled/notFound result, but the contributor still returns true.

Why I lowered the severity from high to medium:
1. Recording results instead of throwing is a documented decision. See decision-log.md 2026-06-02: commands "record completed or failed results" and shortcut dispatch is fire-and-forget.
2. The failure is not completely invisible. FleuryApp's root semantic node shows `lastCommandStatus: failed`, as the probe output shows, so an agent reading state can see it. That only covers the app registry, though; the CommandScope node exposes only commandCount.
3. The framework loses no data itself. The harm is that errors are hidden and callers get a false `completed`.

The semantic `completed` for a failed, disabled or not-found command is clearly wrong and misleads tests and MCP agents. The missing overlay, while a throwing plain KeyBinding does get one, is a real inconsistency.

The proposed fix is sound, and runApp supports both halves:
- In the contributors, rethrow failed results with `Error.throwWithStackTrace` so the dispatch reports `failed`. On the live wire this also flows into `reportSemanticActionFault`, which calls errorReporter.report. For disabled and notFound, return false or throw, rather than returning true.
- For the fire-and-forget surfaces, `Zone.current.handleUncaughtError` is safe after mount. The runApp zone handler reports the error and keeps running; it is fatal only before mount or during an error storm.

Better root-cause shape: add one helper on CommandRegistry, for example `invokeFromUi`, that reports failed results through the zone. Then route the two bindings, CommandButton, the palette and status items through it, and have both semantic contributors map CommandInvocationStatus to the semantic outcome in one shared function. That replaces the current five-plus duplicated `unawaited(...)` call sites.

### [medium] Dialog's semantic dismiss calls pop() unconditionally, bypassing barrierDismissible:false and PopScope guards
`fleury_widgets/lib/src/dialog.dart:76`, bug, found by the widgets finder

**Claim.** Dialog advertises SemanticAction.dismiss and handles it with `Navigator.maybeOf(context)?.pop()`. The navigator deliberately makes every semantic/back path respect non-dismissible modals and PopScope ('A non-dismissible modal refuses semantic/back dismissal on EVERY consult path', navigator.dart ~552-556, and the test 'semantic route close respects a blocking PopScope'). This action reopens that hole. An MCP/semantics driver can dismiss a must-answer confirmation or an unsaved-changes modal: present<T>() completes with null and onBlocked never runs. It also pops the navigator's top route rather than the dialog's own route.

**Reproduction.** Navigator.of(ctx).present<bool>(Dialog(title: 'Confirm', child: Text('must answer')), barrierDismissible: false). Send Esc, then invoke SemanticAction.dismiss on the route, then on role dialog 'Confirm'. Also present(Dialog(title: 'Edit', child: PopScope(canPop: false, onBlocked: () => blocked++, child: ...))). Send Esc, then the dialog dismiss.

**Verifier evidence.** Probe test packages/fleury_widgets/test/_sweep_dlgverify_1_test.dart, run in the sweep worktree and deleted afterwards.
Case 1: present<bool>(Dialog(title:'Confirm'), barrierDismissible:false).
  after Esc depth=2
  routes: [_Host sel=false actions={}, Dialog sel=true actions={SemanticAction.navigate}]  (the route correctly withholds dismiss)
  dialog actions: {SemanticAction.dismiss}  (the Dialog node still advertises dismiss)
  dialog dismiss completed=true
  after dialog dismiss depth=1 done=true res=null  (the must-answer modal closed; the future completed with null)
Case 2: present(Dialog(title:'Edit', child: PopScope(canPop:false, onBlocked: blocked++, ...))).
  after Esc depth=2 blocked=1
  dialog dismiss completed=true
  after dialog dismiss depth=1 blocked=1  (guard bypassed silently; onBlocked did not fire)
Source: packages/fleury_widgets/lib/src/dialog.dart:76 calls `Navigator.maybeOf(context)?.pop()`. NavigatorState.maybePop (packages/fleury/lib/src/widgets/navigator.dart:541-560) checks guards and barrierDismissible. Route semantics (navigator.dart ~977-998) only advertise dismiss when `navigator.canPop && dismissible` and route it through maybePop. The Dialog node skips both checks.

**Proposed fix.** Route the action through `maybePop()`. Better, only advertise dismiss when the enclosing route is dismissible, or drop Dialog's own action and rely on the route-level dismiss, which already honours barrierDismissible and guards. CommandPalette._dismiss/_invokeCommand use the same raw pop().

**Verifier notes.** Reproduced exactly as the finder described. The existing dialog_test 'semantic dismiss pops a presented dialog' only covers the dismissible case, which is why this was missed. Medium is the right severity: only a semantics/MCP driver can trigger it, but agent driving is a headline pillar, and for an agent the Dialog node is the obvious dismiss target. Because the route node hides dismiss, the Dialog node is the only dismiss the agent can see.
The same raw pop() appears in packages/fleury_widgets/lib/src/command_palette.dart:453 and :458. I did not test those. The one at :458 follows a command invocation, where an unconditional pop may be intended.
A secondary effect I did not probe: a Dialog used inline inside a pushed page, not presented, still advertises dismiss, and invoking it would pop the host page.
Better fix: remove Dialog's own dismiss action and onAction, and let the route-level dismiss handle it. That path already honours barrierDismissible and PopScope and targets the right route. If the Dialog node must keep an action, advertise it only when the enclosing route is dismissible and call maybePop(). A quick maybePop() swap alone would leave dismiss advertised on a non-dismissible modal, so the agent sees an action that does nothing. Add a regression test that covers barrierDismissible:false and a blocking PopScope.

### [medium] FleuryTester.lastCommandResult returns the app registry's stale result instead of the latest (scoped) invocation, so tests assert on the wrong command
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/testing/fleury_tester.dart:966`, bug, found by the app finder

**Claim.** `lastCommandResult` returns `FleuryApp.maybeOf(ctx)?.commands.lastResult ?? CommandRegistryScope.maybeOf(ctx)?.lastResult`. After any app-level command has run once, the app registry's result is non-null for good. Results recorded by nearer CommandScope registries, which is where screen commands record, are therefore never returned: the getter reports whatever app command ran last.

A test that triggers a failing or disabled screen command by keyboard and then asserts `tester.lastCommandResult?.completed` (the pattern used in website/examples/test/doc_snippets_test.dart:462 and packages/fleury/test/app/*) passes against the earlier app command. This compounds the first finding, where lastResult is the only place a command failure is recorded.

**Reproduction.** FleuryApp(commands: [AppCommand(id: CommandId('app.palette'), title: 'Palette', shortcuts: [KeySequence.ctrl.k], run: (_) {})], home: CommandScope(commands: [AppCommand(id: CommandId('editor.save'), title: 'Save', shortcuts: [KeySequence.ctrl.s], run: (_) => throw StateError('disk full'))], child: Focus(autofocus: true, child: Text('editor')))).

Then `tester.press(ctrl.k)`, await a microtask, `tester.press(ctrl.s)`, await a microtask, pump, and read `tester.lastCommandResult`.

**Verifier evidence.** I ran a probe at packages/fleury/test/_sweep_verify_lcr_1_test.dart and deleted it afterwards. The tree was FleuryApp(commands: [app.palette on Ctrl+K, run: no-op]) with child CommandScope(commands: [editor.save on Ctrl+S, run throws StateError('disk full')]) wrapping Focus(autofocus) > Text. I sent Ctrl+K, awaited a zero delay, sent Ctrl+S, awaited again and pumped. Output:
  after ctrl+k: app.palette CommandInvocationStatus.completed
  after ctrl+s: app.palette CommandInvocationStatus.completed      <- lastCommandResult is stale
  nearest registry lastResult: editor.save CommandInvocationStatus.failed   <- the real latest result
A second case pressed only Ctrl+S, with no app command run before it. There the getter correctly returned `editor.save failed`. So the bug appears only after an app-level command has recorded a result.

Cause, from fleury_tester.dart:962-967: `FleuryApp.maybeOf(ctx)?.commands.lastResult ?? CommandRegistryScope.maybeOf(ctx)?.lastResult`. The app registry is checked first, and once it holds a result that result is never null again, so the `??` fallback never reaches the nearer registry. CommandScope._bindings (commands.dart ~l.420) calls `registry.invoke` on the scope's own registry, and `_record` (l.295) writes only to that registry's `_lastResult`. The app registry never sees the scoped result.

**Proposed fix.** Return the most recent result across the whole registry chain. For example, stamp each result with a global monotonic sequence number in `CommandRegistry._record`, walk from the nearest registry up through `parent`, and return the highest sequence. Also record `tester.invokeCommand` results in the registry that owns the command, not the nearest one (`_resolveCommandForTester`'s fallback).

**Verifier notes.** Reproduced exactly as reported. It is a real defect in the public testing API (FleuryTester, re-exported through fleury_test): it silently returns the wrong command's result. A test that asserts `lastCommandResult?.completed` or `?.status == completed` after pressing a screen or scope shortcut can pass against an earlier app command's result while the screen command actually failed or was disabled. That is a false green.

Medium severity is fair. It affects tests only, not runtime behaviour. But it hides failures instead of reporting them, and the doc-recommended pattern (website/examples/test/doc_snippets_test.dart:462, packages/fleury/test/app/app_shell_test.dart) relies on this getter. None of the existing in-repo assertions I checked appear to be falsely green today: they either run a single command or use `same(result)`.

The proposed fix is on the right track. Stamp each result in `CommandRegistry._record` with a monotonic sequence number (one static counter is enough), walk from the nearest `CommandRegistryScope` up the `parent` chain, and return the result with the highest stamp. That gives "latest invocation visible from the focus context", which is what the getter's doc claims. The app registry sits at the root of that parent chain, so the separate `FleuryApp.maybeOf` lookup is no longer needed. A simpler option is for the tester to record the result itself in the harness each time a command runs, but commands triggered by key bindings do not go through the tester, so a registry-side stamp is the more robust fix.

I did not independently verify the secondary claim that `tester.invokeCommand` records in the wrong registry through `_resolveCommandForTester`'s fallback. The sequence-number walk would make that moot anyway.

Also reported as: 'Last command' reporting (app semantics, debug panel, a11y/MCP, tester.lastCommandResult) reads only the app registry and goes stale after scoped or palette invocations

### [low] renderToString(emptyMark: '') hangs the test process forever, and multi-code-unit marks throw RangeError
`fleury/lib/src/testing/fleury_tester.dart:1182`, bug, found by the app finder

**Claim.** _rstrip loops `while (end > 0 && s.substring(end - mark.length, end) == mark) end -= mark.length;`. With an empty mark the substring is always '' == '', and `end -= 0` never advances, giving a synchronous infinite loop on the first non-empty row. Because the loop is synchronous, package:test's per-test Timeout cannot fire, and a single SIGTERM or Ctrl+C only prints 'Waiting for current test(s) to finish' while the isolate keeps spinning, so CI hangs until SIGKILL or the job timeout. With a mark longer than a row's remaining content (any 2-code-unit mark such as '..' or an emoji, against a row holding one character), `end - mark.length` goes negative and substring throws RangeError.

**Reproduction.** 1) tester.pumpWidget(const Text('Count: 0')); tester.renderToString(emptyMark: '', size: CellSize(20, 2)), with the test given Timeout(Duration(seconds: 5)) and run under `timeout 60 dart test`. 2) tester.pumpWidget(const Text('x')); tester.renderToString(emptyMark: '🟦' or '..', size: CellSize(6, 2)).

**Verifier evidence.** I ran the probe packages/fleury/test/_sweep_verify_rstrip_1_test.dart (deleted afterwards) under `timeout 60 dart test`.
- Case 1: tester.pumpWidget(const Text('x')), then renderToString(emptyMark: M, size: CellSize(6,2)). With M = '..', '🟦' and 'ab' it printed "threw: RangeError (start): Invalid value: Not in inclusive range 0..11: -1" each time. With Text('xy') and '..' it rendered correctly, so the failure depends on how the content length lines up with the mark length.
- Case 2: Text('Count: 0'), then renderToString(emptyMark: '', size: CellSize(20,2)), with the test given Timeout(Duration(seconds: 5)). It printed "before" and never returned. The 5 s test timeout never fired. At 60 s, `timeout` sent SIGTERM and the runner printed "Waiting for current test(s) to finish. Press Control-C again to terminate immediately." The dartvm process was still alive at 2:16 elapsed, and I had to kill -9 it (exit 137).
- Extra case: Text('a..') with emptyMark '..' also throws RangeError (range 0..9: -1). Content glyphs that match the mark get eaten as if they were empty cells.
- Related, same root cause: with the default mark, Text('a·') renders as "a", so a real '·' glyph at the end of a row is dropped from the snapshot.
- Code: fleury_tester.dart:1182, `while (end > 0 && s.substring(end - mark.length, end) == mark) end -= mark.length;`. With an empty mark, `end` never changes. When `end < mark.length`, the start index goes negative.

**Proposed fix.** if (mark.isEmpty) return s; then loop with `while (end >= mark.length && s.startsWith(mark, end - mark.length)) end -= mark.length;`, or reject an empty emptyMark with an ArgumentError.

**Verifier notes.** Confirmed, but I'm lowering severity from medium to low. This is test-only API (FleuryTester.renderToString). Every caller in the repo passes the default '·' or ' ', both one code unit, so no current test triggers it. An empty mark is an unusual choice, and it would collapse column geometry anyway. The hang is the worst part: a synchronous spin that the per-test Timeout can't stop and SIGTERM doesn't kill, so CI waits until the job timeout. That is a real footgun, but it only hits when someone opts into an odd argument.

Better fix than the proposed one: trim at the cell level instead of stripping the string after the fact. In the row loop, record the index of the last cell that is not CellRole.empty, and write empty marks only up to that column (or build the row and truncate to the length recorded at the last non-empty cell). This removes _rstrip entirely. It fixes the empty-mark hang and the RangeError for multi-code-unit marks. It also fixes the fidelity bug where a real glyph equal to the mark gets trimmed ('a·' becomes 'a' with the default mark; 'a..' throws with '..'). The docs promise that "trailing empty cells" are trimmed, which is a statement about cells, not characters. The proposed `if (mark.isEmpty) return s;` plus startsWith guard stops the crash and the hang, but still eats real content that matches the mark. Optionally, also reject an empty emptyMark with an ArgumentError.

## E. Widgets & collections (19)

### [high] DataTable stops virtualizing under an unbounded height (e.g. as a Column child): every row is built each frame and the cursor moves off-screen
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury_widgets/lib/src/data_table.dart:2023`, perf, found by the collections finder

**Claim.** RenderDataTable.performLayout sets bodyRows = _rowCount when constraints.maxRows == null, so _visibleRows becomes the whole row count. That happens for any Column child, which is the natural 'title above table' layout, and for a ScrollView child through the same maxRows==null path. performPaint then calls _cellBuilder and _clipToWidth (sanitize + RegExp + grapheme walk) for every row×column on every paint. Its `y >= size.rows` break never fires because size.rows is the full natural height, and _writeCell checks buffer bounds only after the text has been built. buildSemanticNode also emits a row node plus cell nodes for every row. The reveal logic treats every row as visible, so arrow keys move the cursor off-screen without scrolling. The class doc and the lists guide say the table asks cellBuilder only for visible rows. ListView throws a descriptive error in this situation, and CodeView/TreeTable/FileBrowser cap their height; DataTable does neither.

**Reproduction.** DataTable(rowCount: 100000, columns: name+size, autofocus: true, cellBuilder counting calls) inside Column(children: [Text('Files'), table]) at 60x24. Press Down 5 times, pumping after each. Then call tester.semantics() and renderToString(60x6). Compare with the same table in SizedBox(height: 20).

**Verifier evidence.** The code at packages/fleury_widgets/lib/src/data_table.dart:2022-2028 does what the finding says: `bodyRows = maxRows == null ? _rowCount : ...`. `_syncVisibleRange(bodyRows)` then sets `_visibleRows = _rowCount`, and the natural height is headerRows + _rowCount. performPaint's `if (y >= size.rows) break;` never fires, because size.rows covers every row. So `_cellBuilder` runs for every row and column.

Probe: packages/fleury_widgets/test/_sweep_verify_dt_1_test.dart, now deleted. Setup: DataTable(rowCount: 100000, two fixed columns, autofocus), with a counting cellBuilder. The bounded case is Column[Text, SizedBox(height:5, table)]; the unbounded case is Column[Text, table]. Each case pressed Down 5 times with a pump after each key. Output:
- `inColumn=false: 1.4004 ms/key, calls/key=6.0`, `semantics 8 ms`. The render scrolled to show file_2, file_3 and file_4.
- `inColumn=true: 329.991 ms/key, calls/key=200000.0`, `semantics 1369 ms`. The render still shows file_0 to file_3 after 5 Downs, so the cursor row is off-screen and the table never scrolled.

That is about 235 times slower per key and 33,000 times more cellBuilder calls, and the cursor is lost.

The class doc (data_table.dart:589-591) says the table "asks [cellBuilder] only for the visible body rows". ListView throws a descriptive error for the same unbounded case (list_view.dart:1134: "unbounded $dimension (a ScrollView, or a Column/Row child ... Every item would be ..."). DataTable fails silently.

**Proposed fix.** Treat an unbounded main axis the way ListView does (throw a StateError that points at Expanded/SizedBox), or cap it with a maxVisible parameter using CodeView's LayoutBuilder pattern. In performPaint, only iterate rows that intersect the target buffer, checking bounds before calling cellBuilder/_clipToWidth. Limit semantic rows to the on-screen window.

**Verifier notes.** Reproduced on my own machine, and the numbers match the finder's (330 ms vs 278 ms per key, 200000 calls per key, about 1.4 s for semantics). High severity is justified. DataTable is sold as the virtualized widget for large collections. Column[title, table] is the most natural layout for it, and in that layout the table fails silently: the frame takes about 330 ms per key at 100k rows, and arrow-key navigation is broken, not only slow.

A better root-cause fix is to reject an unbounded main axis the way ListView does: throw a StateError that points at Expanded or SizedBox. Do that in RenderDataTable.performLayout when constraints.maxRows == null, and cover the ScrollView-child case too. Per the prelaunch policy, this should be a hard cut, not a conservative default. The proposed paint-side mitigation, iterating only rows that intersect the buffer, would be a band-aid. The table's own size would still be 100k rows tall, so the reveal/scroll logic still could not keep the cursor on screen (the parent clips it, and no viewport exists). The paint loop and semantics already cover only _visibleRows, so once the layout contract is fixed, those problems go away with it.

A capped maxVisible parameter using CodeView's LayoutBuilder pattern is a reasonable alternative if an intrinsic height is wanted, but throwing matches ListView.

Minor, not part of this finding: in the bounded probe, after 5 Downs the rows shown were 2 to 4. That may be explained by autofocus or the first-key semantics; I did not investigate.

### [high] FileBrowser strands the keyboard in an empty or unreadable directory: Left/Backspace go dead and there is no way back up
`fleury_widgets/lib/src/file_browser.dart:520`, bug, found by the collections finder

**Claim.** The KeyDetector that maps Left/Backspace to `_goUp` and Right to activate, and the Focus holding `_focusNode`, exist only in the non-empty ListView branch of build(). When the user enters an empty directory, or one whose listing throws (permission denied), the body becomes a plain `Text('(empty)')` or error Text. Focus drops to null and no navigation key is ever delivered. There is no '..' row or clickable parent for the mouse, and no semantic go-up action for agents (`navigate` only refocuses; `open` does nothing with no selection). Keyboard, mouse and agent users are all stuck until the app itself calls `controller.openDirectory`. FilePicker gets this right: it keeps its KeyDetector/Focus around the listing even when it is empty.

**Reproduction.** Temp dir containing an `empty/` subdirectory (or `aaa_locked/` after `chmod 000`) and one file. Mount FileBrowser(initialDirectory: tmp, controller: c, autofocus: true); row 0 is the directory. Press Enter, then Backspace, then ArrowLeft, and read c.currentDirectory.

**Verifier evidence.** I ran a probe at packages/fleury_widgets/test/_sweep_fbv_1_test.dart (now deleted). Setup: a temp dir holding `empty/` and `z.txt`, and FileBrowser(initialDirectory: tmp, controller: c, autofocus: true). Output:
start: …/fbv_3mngdS
after Enter: …/fbv_3mngdS/empty   (render shows the path, then "  (empty)")
after Backspace: …/fbv_3mngdS/empty
after Left: …/fbv_3mngdS/empty
tree actions: {SemanticAction.focus, SemanticAction.navigate} focused=true
Control case: after c.openDirectory('…/full') on a non-empty dir, ArrowLeft goes back to …/fbv_3mngdS, so the key handling works when there are rows.
Code (file_browser.dart build(), around line 520): `body = _error != null ? Text(error) : order.isEmpty ? Text('  (empty)') : KeyDetector(onKey: _onNavigationKey, child: Focus(child: ListView.builder(focusNode: _focusNode, autofocus: …)))`. The KeyDetector and the only focusable node (the ListView holding _focusNode) exist only in the non-empty branch. The error branch (listing throws) has the same structure, so a chmod-000 directory strands the user the same way. I did not run that case separately because the code path is the same.
The semantic go-up claim holds: _handleBrowserAction maps navigate/focus to `_focusNode.requestFocus()` only, and `open` calls `_activateSelected()`, which returns early when nothing is selected. FilePicker (file_picker.dart ~313-383) wraps the whole body, empty state included, in KeyDetector and Focus, and adds a clickable parent-directory row, so the claimed contrast is accurate.

**Proposed fix.** Keep the KeyDetector and a `Focus(focusNode: _focusNode, autofocus: …)` around the whole body, including the list, empty and error states, as FilePicker does, so Left/Backspace reach `_goUp` when `order` is empty. Also expose a semantic go-up action on the browser node so agents can leave an empty directory.

**Verifier notes.** Reproduced as claimed. Entering an empty directory is an everyday action, and afterwards the keyboard and mouse have no way back up; only an app-side controller.openDirectory call gets out. That breaks the widget's core job, so I kept the severity at high. No data is lost.

One more defect the finder did not mention: the tree node still reports `focused=true` after the ListView has unmounted, because `_focusNode.hasFocus` goes stale while no widget holds the node. An agent reading semantics sees a focused browser that ignores every key.

Suggested fix, extending the finder's: as FilePicker does, own `_focusNode` in an outer `Focus(focusNode: _focusNode, autofocus: widget.autofocus)` wrapped in the KeyDetector, placed around the whole body, including the list, empty and error states. Then pass the ListView a child node, or set canRequestFocus so the list still receives arrow keys through the same node. Also add a parent-directory row, or a semantic go-up action (for example `SemanticAction.navigate` with a parent target, or a dedicated action), so mouse and agent users can leave too. Check that `_goUp` resets `_error`: it does, because `_openDirectory` calls `_reloadCurrentDirectory`. So the only thing missing is getting the key event to it.

### [high] Image re-decodes on every parent rebuild and resamples the full source on every paint (19–90 ms/frame); animated images restart and trip the one-ticker assert
`fleury_widgets/lib/src/image.dart:346`, perf, found by the widgets finder

**Claim.** (a) Image.bytes/.file/.decoded build a new ImageSource on each widget construction, and didUpdateWidget compares sources by identity. The docs say 'the widget itself is cheap to rebuild', but every parent rebuild calls decode() again. For Image.bytes that is a full JPEG/PNG decode; on placement surfaces the new decoded instance also clears RenderImage's cached PNG, so it is re-encoded and re-hashed. The same path disposes and recreates the animation ticker at frame 0. An animated image whose parent rebuilds faster than its frame duration never advances. With asserts on (tests, `fleury run --enable-asserts`), createTicker throws the SingleTickerProviderStateMixin 'only one Ticker' assertion. (b) Independently, the glyph-art paint path samples every source pixel on every paint. RenderImage is not a repaint boundary and non-boundary nodes repaint every frame, so a static image costs O(source pixels) on every app frame. The storybook's own Image story (Image.bytes of a 900x600 JPEG in build) hits both.

**Reproduction.** A Host StatefulWidget that setStates once per frame and builds Column[Text('tick $t'), SizedBox(76x22, Image.bytes(storybook samplePhoto))]. Compare with Image(source: <stable ImageSource>) and with no image. Repeat with a 640x480 PNG in 40x12 under MediaQuery(images: placements). Animated case: Image.bytes(encodeGif(2 frames @100ms)) under a parent that rebuilds.

**Verifier evidence.** Probe packages/fleury_widgets/test/_sweep_imgv_1_test.dart (now deleted). A Host StatefulWidget calls setState before each tester.pump() and builds Column[Text('tick $t'), SizedBox(w,h, child)]. Each variant got 3 warmup frames and 20 timed frames, and the whole set ran 3 times with the variants interleaved in each round. The test images were synthetic noise: a 900x600 JPEG and a 640x480 PNG.
- 900x600 JPEG in 76x22: no image 0.11/0.08/0.06 ms/frame; stable ImageSource 20.51/20.18/20.22; Image.bytes built in build() 100.13/101.07/99.81.
- 640x480 PNG in 40x12, glyph art: none 0.05/0.04/0.05; stable 10.30/11.42/10.03; Image.bytes 27.49/28.92/24.77.
- 640x480 PNG in 40x12, MediaQuery images: placements: stable 0.11/0.06/0.08; Image.bytes 25.96/25.14/23.82. The only Image.bytes cost on this surface is the new decoded instance, which clears RenderImage's cached PNG in the `decoded` setter so it is re-encoded and re-hashed.
- Animated case: Image.bytes(encodeGif of 2 frames @100ms) under a parent that rebuilds every 50ms throws "Failed assertion: line 191 pos 7: '_ticker == null': SingleTickerProviderStateMixin permits only one Ticker" (tui_binding.dart:191). The call path is didUpdateWidget, then _maybeStartAnimation, then createTicker. The mixin's _ticker is never cleared when image.dart disposes the old ticker.
Code confirms the cause. image.dart:348 checks `if (!identical(widget.source, oldWidget.source))`, and Image.bytes/.file/.decoded build a new ImageSource in their initializer lists. When that check fires, it calls decode() again, resets _frameIndex/_accumulatedMs to 0, and disposes the ticker and creates a new one. render_object.dart:250-252 says non-boundary nodes always repaint, and RenderImage has no isRepaintBoundary override. Its halfBlock performPaint samples every target half-pixel through _samplePixel, which area-averages the source, so a static image costs O(source pixels) on every frame that paints its boundary.

**Proposed fix.** Give the built-in sources value equality (identical bytes / canonical path / identical img.Image) or compare the decoded result before resetting. Only reset the frame and ticker when the decoded image actually changed; reuse the ticker (or use a multi-ticker mixin) instead of calling createTicker again. Cache the glyph-art raster keyed by (decoded, size, fit, glyph, colorMode, backgroundColor, glyphTier) and replay the cells, or make RenderImage a repaint boundary, so a static image costs O(cells) per frame.

**Verifier notes.** Confirmed, with some limits on the scope:
1. The re-decode happens only with Image.bytes / ImageSource.bytes built in build().
   - Image.file hits _FileSource's static cache, which is keyed by canonical path. The same img.Image comes back and RenderImage.decoded short-circuits on identical, so there is no decode and no PNG reset. Each rebuild still pays a canonicalPath call.
   - Image.decoded(sameImage) returns the same instance and costs nothing extra.
   - For .file and .decoded, the real defect is the animation reset and the ticker assert: frame index and ticker are reset on every parent rebuild. With asserts off, an animated image whose parent rebuilds more often than its frame duration never advances.
2. Part (b), the per-frame O(source pixels) glyph-art resample, happens whenever anything else in the same repaint boundary repaints, for example a spinner or clock next to the image. That alone is about 20ms/frame for the storybook-sized photo, over a 60fps budget, even with a stable source. On placement surfaces the stable case is cheap (0.1ms).
3. Severity stays high. A setState anywhere above an Image.bytes costs about 80-100ms for a 900x600 JPEG, and animated images crash in debug/test builds.

Suggested root-cause fixes:
- Give _BytesSource/_FileSource/_DecodedSource value equality: identical bytes buffer, canonical path, identical image. Compare with == in didUpdateWidget.
- Only reset frame and ticker when the decoded result is not identical.
- Reuse the existing ticker instead of dispose-and-createTicker, since the Single mixin never clears _ticker.
- For (b), cache the sampled/quantized cell raster in RenderImage, keyed by (decoded, size, fit, glyph, colorMode, backgroundColor, glyphTier), and replay the cells. Alternatively, make RenderImage a repaint boundary so a static image costs O(cells) or a blit per frame.

Also reported as: Image glyph-art path re-resamples the full-resolution source every frame (38 ms/frame for a 1280x720 image); Image.file/bytes/decoded create a new ImageSource per build: animated images freeze (and assert in debug), Image.bytes re-decodes and re-encodes on every parent rebuild

### [high] Left/Right bubbling out of any control inside a Tabs body switches tabs and drops focus
`fleury_widgets/lib/src/tabs.dart:189`, bug, found by the input finder

**Claim.** Tabs wraps one KeyDetector around a Focus that holds both the tab strip and the active tab's content (tabs.dart:249-256). `_onKey` (186-206) handles Left, Right, Home and End without checking that the strip itself has focus. Detectors run deepest-first for every focused descendant, so any arrow a content control lets through reaches Tabs before the enclosing FocusTraversalGroup. TextInput passes Left through at offset 0 and Right at the end by design (text_input.dart:1429-1442 and 1494-1503). So pressing Left in an empty field, or one extra Right at the end of the text, switches tabs. The field ends up under ExcludeFocus and loses focus. Buttons, checkboxes and vertical lists that don't consume horizontal arrows are hit the same way, so directional focus movement inside a tab body never works. The file is in fleury_widgets, but the trigger is the in-scope TextInput edge bubbling plus the dispatcher's detector order.

**Reproduction.** FocusTraversalGroup(child: Tabs(controller: c, tabs: [TabItem(label: 'One', content: Text('one')), TabItem(label: 'Two', content: TextInput(focusNode: field))])). Set c.index = 1, call field.requestFocus(), pump, then send KeyEvent(KeyCode.arrowLeft) with the caret at 0.

**Verifier evidence.** I ran a probe at packages/fleury_widgets/test/_sweep_tabsverify_1_test.dart (now deleted). Every Tabs case was wrapped in FocusTraversalGroup.
1) Tab 2 holds an empty TextInput. I set c.index=1, focused the field and sent arrowLeft. Output: `before: index=1 field.hasFocus=true` then `after Left: index=0 field.hasFocus=false`.
2) Tab 1 holds a TextInput with text 'hi' and the caret at the end (End was handled by the field, so the index stayed 0). Left then Right: `index=0 focus=true`. One more Right: `after extra R: index=1 focus=false`.
3) Control case, a Row of two Buttons with no Tabs: Right moves focus directionally, `outside tabs: a=false b=true`.
4) The same Row as tab 1 content: Right switches tabs instead, and nothing in the tree keeps focus: `inside tabs: idx=1 a=false b=false`.
Code: tabs.dart:249-256 wraps one KeyDetector around a Focus that holds both the strip Row and the content IndexedStack. `_onKey` (186-206) handles Left, Right, Home and End with no focus check. TextInput returns ignored at the boundaries on purpose (`_shouldBubbleHorizontalBoundary`, text_input.dart ~1429-1503), so the key bubbles up to Tabs.

**Proposed fix.** Handle strip navigation only while the strip's own node is focused: in `_onKey`, return ignored unless `_focusNode.hasFocus`. Alternatively, put the KeyDetector and Focus around the strip Row only and leave the content outside them. The Alt+1..9 bindings can stay tab-area-wide.

**Verifier notes.** The behavior contradicts Tabs' own doc comment: "When the strip is focused, Left/Right switch tabs". The existing test (tabs_test.dart:130) only covers the strip-focused case, so this was never caught.

Impact:
- Any text field inside a tab switches tabs at the caret boundaries.
- A row of buttons or checkboxes inside a tab cannot use arrow-key focus movement at all.
- Home/End also switch tabs from any content control that doesn't consume them.
- After the switch, focus lands under ExcludeFocus and ends up on nothing.

No data is lost, because tab state stays mounted. The effect on a common widget is still severe, so I'm keeping severity at high.

The proposed fix is correct. In Fleury, `FocusNode.hasFocus` means this exact node has focus (focus.dart:278, `_manager?.focusedNode == this`), not that a descendant does. So adding `if (!_focusNode.hasFocus) return KeyEventResult.ignored;` at the top of `_onKey` limits Left/Right/Home/End to the strip. The cleaner structural fix is to wrap only the strip Row in the KeyDetector and Focus and leave the content outside them. Alt+1..9 and Ctrl+PageUp/PageDown already live in the outer KeyBindings, so they stay tab-area-wide either way. Add a regression test with a TextInput and a Button row inside a tab.

Also reported as: Tabs remounts every tab's content when the tab count crosses 1↔2 or a tab is removed, losing drafts, scroll and selection state; Tabs takes Left/Right/Home/End from its content (switches tab, leaves nothing focused) and gives content unbounded height

### [high] Markdown inline parser treats intraword `_` and spaced `*` as emphasis, deleting characters from identifiers, filenames and math
`fleury_widgets/lib/src/markdown_text.dart:1298`, bug, found by the widgets finder

**Claim.** `_inline` treats any single `*` or `_` as an italic delimiter that closes at the next matching character. It has no CommonMark flanking or intraword rules and accepts empty spans. The delimiters are dropped from the output, so snake_case identifiers, dunder paths and `a * b * c` lose characters in MarkdownText and MarkdownView. The same regexes in `_plainInlineText` (~lines 1411-1416) build each MarkdownView block's semantic label (line 916), so agents and screen readers also get the corrupted text. This is the agent-output renderer, and the file-manager sample uses it for file previews.

**Reproduction.** tester.pumpWidget(MarkdownText('Edit __init__.py to export it')), also 'Rename user_id and group_id', 'Compute 2 * 3 * 4 now', 'See snake_case_name here', and MarkdownView(markdown: 'Edit __init__.py and user_id or group_id'). Then renderToString.

**Verifier evidence.** Probe packages/fleury_widgets/test/_sweep_mdverify_1_test.dart (since deleted) used tester.pumpWidget, then renderToString(size: CellSize(60,3)), then read the markdownBlock semantics nodes. Output:
MarkdownText in=[Edit __init__.py to export it] out=[Edit init.py to export it]
MarkdownText in=[Rename user_id and group_id] out=[Rename userid and groupid]
MarkdownText in=[Compute 2 * 3 * 4 now] out=[Compute 2  3  4 now]
MarkdownText in=[See snake_case_name here] out=[See snakecasename here]
MarkdownText in=[Use *emphasis* here and _this_ too] out=[Use emphasis here and this too]   (legit emphasis still works)
MarkdownView out=[Edit init.py and userid or groupid]
block label=[Edit _init.py and userid or group_id] value=[Edit __init__.py and user_id or group_id]
Code cause: in markdown_text.dart around line 1298, `_inline` treats any `*` or `_` as an italic opener and closes it at `src.indexOf(ch, i + 1)`. There is no flanking check and no intraword check, and an empty span is allowed. `__` therefore becomes an empty italic span and both underscores are dropped. `_plainInlineText` (lines 1412-1416) uses `_([^_]+)_` and `\*([^*]+)\*`, and its output feeds each block's semantic label.

**Proposed fix.** Apply CommonMark delimiter rules in `_inline` and `_plainInlineText`. `_` must not open after an alphanumeric or close before one (no intraword underscore emphasis). `*` must not open before whitespace or close after whitespace. Never produce empty emphasis (`__`, `**` with nothing inside); leave the delimiters as literal text. In the regex path, use lookarounds, e.g. (?<![A-Za-z0-9])_(?!\s)([^_]+?)(?<!\s)_(?![A-Za-z0-9]).

**Verifier notes.** Reproduced exactly as claimed. It gets worse in one respect. The semantic label is built by a separate regex path, and that path corrupts the text differently from the visible render: 'Edit _init.py and userid or group_id' versus the rendered 'Edit init.py and userid or groupid'. The screen text, the a11y/agent label and the source (block.value) all disagree. The file_manager sample (packages/samples/lib/src/file_manager.dart:114) renders file previews through MarkdownView, so a README that mentions __init__.py or snake_case names displays incorrectly there. I am keeping severity high. Nothing crashes and the source is preserved (the block's value is correct). But this silently deletes characters in the primary agent-output renderer, and it will show up constantly on day one because agent prose is full of snake_case, dunder names and `a * b`. Better fix than the one proposed: patching the two regex sets separately keeps them drifting apart, as the label mismatch shows. Put the CommonMark left/right-flanking rules in one delimiter scanner: `_` cannot open after an alphanumeric or close before one, `*` cannot open before whitespace or close after whitespace, and an empty span stays literal. Derive plainText from that same span tree (concatenate the TextSpan texts) instead of running a second regex pass. Rendering and semantics then cannot disagree. Add regression cases for __init__.py, user_id, 2 * 3 * 4 and snake_case_name, and assert that the label matches the render.

Also reported as: Markdown inline parser deletes intraword `_` and spaced `*` (MAX_RETRY_COUNT renders as MAXRETRYCOUNT), on screen and in semantics

### [medium] Every first-party collection wrapper forces a second full frame per scroll step, undoing ListView's metrics-only no-rebuild guarantee
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury_widgets/lib/src/code_view.dart:144`, perf, found by the collections finder

**Claim.** ListView deliberately does not rebuild itself for post-frame viewport-metrics notifications; list_view_metrics_rebuild_test asserts 'reported viewport metrics do not schedule a second list build'. The first-party wrappers undo this. The CodeView, DiffView, FileBrowser, TaskGraph, TreeTable, LogRegion and MessageList controllers forward every ListController notification with `_list.addListener(notify)`, and SearchPanel listens to its raw ListController the same way. Each forwarded notification calls setState on the widget. The wrapper then rebuilds and creates a new ListView; didUpdateWidget bumps _dataRevision, and _LazyListBody.update re-runs itemBuilder for every mounted row and calls markNeedsLayout. The result is a second full frame after every scroll step, only to refresh visibleRangeStart/End in semantics, and it doubles any O(n) per-build work (previous finding, plus the known LogRegion cost).

**Reproduction.** CodeView.document over 5,000 lines inside SizedBox(height: 50). Move the cursor to the bottom edge, then press Down 200 times. After each pump(), check tester.owner.hasScheduledBuilds and time the extra frame. Repeat with a bare ListView.builder over the same rows.

**Verifier evidence.** Probe file: packages/fleury_widgets/test/_sweep_colverify_1_test.dart, now deleted. It uses a 5,000-row document inside SizedBox(height: 50) with viewport 80x60. It moves the cursor to the bottom edge with 49 Downs, then sends Down 200 times, calling pump() after each key and checking owner.hasScheduledBuilds before a second pump(). Each variant ran 6 interleaved rounds and the first was discarded.
- code (CodeView.document): second-frame steps=200/200, frame1=0.411ms, frame2=0.362ms
- bare (ListView.builder, same kind of Semantics+Text rows): second-frame steps=0/200, frame1=0.107ms, frame2=0.036ms, rowBuilds=10200
- nocache (test wrapper that listens to the ListController, calls setState and builds a new ListView each build, the same pattern CodeView uses): second-frame steps=200/200, frame1=0.112ms, frame2=0.272ms, rowBuilds=20200, i.e. 2x the itemBuilder calls
- cache (same wrapper, but it reuses the same ListView widget instance): second-frame steps=200/200, frame1=0.106ms, frame2=0.037ms, rowBuilds=10200, same as bare

Code path: in code_view.dart:144 the CodeViewController runs `_list.addListener(notify)`, and _CodeViewState._onControllerChange calls `setState(() {})`. ListView._onControllerChange skips a rebuild when `_lastViewRevision == _controller._viewRevision`, which is the metrics-only case, but the wrapper's rebuild creates a new ListView. didUpdateWidget then bumps _dataRevision, _LazyListElement.performRebuild re-runs itemBuilder for every mounted row, and updateRenderObject calls markNeedsLayout. The same `_list.addListener(notify)` forwarding appears in 14 files: code_view, conversation_navigator, context_panel, diff_view, file_mention_picker, file_browser, json_view, message_list, log_region, markdown_text, patch_review, task_graph, trace_timeline and tree_table.

**Proposed fix.** Expose a public way to tell metrics-only notifications apart on ListController, e.g. a separate metrics Listenable or a notification kind. Wrappers would then refresh only their Semantics state for those. Alternatively, cache the inner ListView widget instance in each wrapper so a metrics-only rebuild passes an identical widget and skips the row rebuild and relayout.

**Verifier notes.** Confirmed as a real perf regression across the first-party wrappers. On this workload the second frame makes each CodeView scroll step cost about 1.9x (0.41 + 0.36 ms against 0.41 ms). In the controlled wrapper test it doubles row builds, 20,200 against 10,200. Per step the absolute cost is under a millisecond for a 50-row viewport. Medium severity holds because the cost is systemic, it affects every scroll step in 14 widgets, and it doubles any O(n) per-build work. That work includes the known LogRegion O(entries) build, which makes the extra frame scale with data size. The second frame most likely writes few or no terminal bytes, since its paint output is identical.

The finder listed 7 wrappers plus SearchPanel. The pattern is wider: JsonView, ContextPanel, FileMentionPicker, ConversationNavigator, MarkdownText, PatchReview and TraceTimeline forward the same way.

Fix: the "cache" variant shows that reusing the inner ListView instance on a metrics-only rebuild brings frame 2 back to bare cost (0.037 ms, no extra row builds) while the wrapper's Semantics state (visibleRangeStart/End) still refreshes. That is the cheapest per-widget fix. The root-cause fix is in ListController: expose whether a notification is metrics-only, for example a separate metrics Listenable or a public kind flag based on the existing private _nextNotificationIsMetrics / _viewRevision. Wrappers could then refresh only their semantics or skip rebuilding the list subtree. Caching the widget is fragile: every other input to the list, such as document, focusNode or copyEnabled, has to invalidate the cache. A controller-level signal also lets ListView's own guarantee cover wrappers without each one handling it. I deleted my probe; the other _sweep_* files in the worktree belong to other agents.

### [medium] FileBrowser re-reads the directory from disk and resets the cursor to row 0 on every parent rebuild when entityFilter is an inline closure
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury_widgets/lib/src/file_browser.dart:283`, bug, found by the collections finder

**Claim.** didUpdateWidget compares entityFilter by identity. An inline closure, the natural way to pass a predicate, is a new instance on every parent build, so any unrelated parent rebuild runs _reloadCurrentDirectory(). That does a synchronous Directory.listSync plus statSync per entry on the UI isolate, and _resetSelection() (without preserveCurrent) moves the cursor and viewport back to row 0. In a picker+preview layout, onActivate calls parent setState, and the cursor jumps from the activated file back to the first entry. The same reset happens on a legitimate showHidden toggle instead of keeping the selected path. entityFilter has no test and no caller anywhere in the repo.

**Reproduction.** Stateful parent: Column[FileBrowser(initialDirectory: dir, autofocus: true, entityFilter: (e) => !e.path.endsWith('.tmp'), onActivate: (e) => setState(() => preview = e.name)), Text(preview)]. dir contains a..e.txt and x.tmp. Press Down×3 to reach d.txt, then Enter. Second case: a 20,000-file directory with 10 unrelated parent setStates, comparing an inline closure against a top-level function tear-off.

**Verifier evidence.** Probe (packages/fleury_widgets/test/_sweep_fbverify_1_test.dart, now deleted). The stateful host renders Column[FileBrowser(controller: c, autofocus, entityFilter: ..., onActivate: setState(preview=name)), Text(preview)]. The directory holds a..e.txt and x.tmp. The test presses ArrowDown x3, then Enter.
- Top-level tear-off: 'inline=false before Enter idx=3' / 'inline=false after Enter idx=3 filterCalls=0 previewLine=preview: d.txt'
- Inline closure: 'inline=true before Enter idx=3' / 'inline=true after Enter idx=0 filterCalls=6 previewLine=preview: d.txt'. The directory was re-listed (6 filter calls) and the cursor jumped from d.txt to row 0.
Interleaved A/B on a 20,000-file dir, 10 unrelated parent setStates each:
round=0 inline=false 3.9 ms/rebuild idx=5 | round=0 inline=true 180.5 ms/rebuild idx=0
round=1 inline=false 1.9 ms/rebuild idx=5 | round=1 inline=true 166.7 ms/rebuild idx=0
Code path: file_browser.dart:283 compares `widget.entityFilter != oldWidget.entityFilter` by identity, then calls `_reloadCurrentDirectory()` (sync listSync + statSync per entry, :326/:350) and `_resetSelection()` with preserveCurrent=false (:381-391), which sets currentIndex to 0. grep finds no caller or test that passes entityFilter.

**Proposed fix.** Don't reload when only the entityFilter identity changed. Document that it is read at load time and add an explicit FileBrowserController.reload(). When a reload does happen (showHidden toggle, explicit reload), keep the selection by entry path instead of resetting to index 0.

**Verifier notes.** The finding reproduces exactly, but I rate it medium rather than high. The cursor reset happens every time on the most natural call shape (an inline predicate plus any parent setState, including the widget's own onActivate), so it is a real UX bug. The cost at 20k entries is about 170 ms per rebuild, but on typical directories of a few hundred entries it is sub-millisecond to a few ms. Nothing in the repo passes entityFilter yet, so no shipped surface is affected today.

Better root-cause fix than the one proposed:
(1) Stop keying the disk reload on entityFilter identity. Treat the predicate as load-time input (document it) and add an explicit FileBrowserController.reload(). Or apply entityFilter at order-build time over cached entries so a changed closure only re-filters in memory and never touches disk.
(2) showHidden does not need a disk read at all. `hidden` is derived from the name, and buildFileBrowserEntryOrder already filters hidden entries. _readEntries dropping hidden entries at read time (:333) is redundant, and that redundancy is what forces a re-list. Load hidden entries once and let the order filter handle showHidden, so a toggle becomes a pure re-filter.
(3) Whenever the order changes (reload, showHidden, query), restore the selection by entry path instead of forcing index 0.

### [medium] JsonView deep-copies and re-sanitizes the whole JSON document on every build, so each arrow key costs O(document), collapsed parts included
`fleury_widgets/lib/src/json_view.dart:531`, perf, found by the perf finder

**Claim.** `_JsonViewState._rows` is a getter that calls `buildJsonViewRows(widget.document.value, ...)` on every build. Every cursor move (`_onControllerChange` → setState, line 514) and every focus change rebuilds the widget. `buildJsonViewRows` then does three expensive things. (1) It deep-copies the entire document with `_normalizeJsonValue(value)` (line 268). (2) For every visible container row it calls `_jsonValueNeedsSanitization(node)` (lines 317 and 969). That call recursively re-sanitizes every key and string in the row's whole subtree, including collapsed subtrees, at 3 replaceAll plus sanitizeForDisplay per string. (3) `_pathSegment` builds a new RegExp for each row (line 996). No row model is cached, unlike TreeTable's `_ensureRows`. So a JSON viewer on a large payload is unusable even when almost everything is collapsed.

**Reproduction.** FleuryTester 100x30, `SizedBox(height: 28, child: JsonView.document(document: JsonViewDocument.value(v), autofocus: true))`. Alternate arrowDown/arrowUp with sendKey + pump and time each. Shape A: v is a list of N records {id, name, active, score, tags: [3], owner: {team, email}}; the root is expanded and about 28 rows are visible. Shape B: v = {status, count, meta: {...}, items: [N records]}, which shows only 5 visible rows with `items` collapsed.

**Verifier evidence.** I read the code in packages/fleury_widgets/lib/src/json_view.dart. `_JsonViewState._rows` (line 531) is an uncached getter that calls `buildJsonViewRows(widget.document.value, ...)`, and `build` (line 654) reads it. JsonViewController forwards every ListController change through `_list.addListener(notify)` (line 114), and `_onControllerChange` calls setState. So each arrow key triggers one full `buildJsonViewRows`. That function deep-copies the document with `_normalizeJsonValue` (line 268). For every emitted row it also calls `_jsonValueNeedsSanitization(node)` (line 317), which walks the node's whole subtree, collapsed parts included. On the root row that is the entire document. `_pathSegment` also compiles a new RegExp for every row (line 996).

Probe 1 (FleuryTester 100x30, `SizedBox(height: 28, JsonView.document(JsonViewDocument.value(v), autofocus: true))`) used shape B: {status, count, meta, items: [N records]}, with items collapsed, so only 5 rows are visible. I alternated arrowDown/arrowUp with sendKey+pump and interleaved the three sizes across 3 rounds. Median ms per arrow key:
round 0: N=100 0.97 | N=10k 40.4 | N=100k 397
round 1: N=100 1.20 | N=10k 40.2 | N=100k 414
round 2: N=100 1.31 | N=10k 41.8 | N=100k 470
`buildJsonViewRows` alone, averaged over 3 runs: N=100 (5 rows) 0.33 ms, N=10k (5 rows) 39.8 ms, N=100k (5 rows) 617 ms. The per-key cost is almost exactly one `buildJsonViewRows` call and grows linearly with document size even though only 5 rows are visible.

Probe 2 attributed the N=10k cost with copies of the private helpers, over 4 runs. Normalize took 4.7–13.8 ms. One subtree sanitization scan took 15–28 ms. The whole `buildJsonViewRows` took 32–47 ms. The scan runs on the root row and again on the collapsed `items` row, so the two scans plus normalize explain nearly all of the time. I deleted both probe files afterwards; the other untracked _sweep files in the worktree belong to other agents.

**Proposed fix.** Normalize once per document, lazily in JsonViewDocument or in State keyed by identical(document). Cache the flattened rows in State the same way as TreeTable._ensureRows, keyed on document identity, the controller's expansion revision, defaultExpandedDepth and maxLineLength, so cursor and focus rebuilds reuse them. Compute a per-node 'needs sanitization' flag once per document in one bottom-up pass (identity map), or scope `outputSanitized` to what the row actually shows (its label and primitive preview) instead of rescanning subtrees on every build. Move `RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')` to a top-level final.

**Verifier notes.** The finding is real: the per-keystroke cost is O(document), collapsed subtrees included, and nothing is cached across cursor or focus rebuilds. I lowered the severity from high to medium because the magnitude is smaller than the finder's figures. Their 82–113 ms at N=10k and 1.6–3.2 s at N=100k were inflated by machine load. On a quieter run I measured about 40 ms per key at 10k records (roughly 1.5 MB of JSON), which is already more than 2 frame budgets, and about 0.4–0.47 s at 100k records. Documents of 1k records or fewer stay at a few ms and feel fine. This is a clear scalability defect for a JSON viewer, whose main use is inspecting large payloads, but it does not affect small or medium documents.

Recommended fix, in order of payoff:
1. Normalize once per document identity, either lazily on JsonViewDocument or in State keyed by identical(widget.document).
2. Replace the per-row subtree `_jsonValueNeedsSanitization` with a flag per node computed once per normalized document in one bottom-up pass (an Expando or identity map). Alternatively, narrow `outputSanitized` to what the row actually renders (label and preview); that also removes the O(depth x subtree) repeated work on nested expanded rows.
3. Cache the row list in State keyed on document identity, an expansion revision (the controller would need to bump a counter only in expand/collapse/toggle, not on currentIndex changes), defaultExpandedDepth and maxLineLength, so cursor and focus rebuilds reuse it, as TreeTable._ensureRows does.
4. Hoist the identifier RegExp to a top-level final (a minor win).
Fixes 1 and 2 alone would bring the collapsed case down to O(visible rows) per key once combined with fix 3.

### [medium] LogRegion filtered view goes stale (wrong rows shown and copied) when a stable entries list is mutated in place at the same length
`fleury_widgets/lib/src/log_region.dart:371`, bug, found by the collections finder

**Claim.** `_entryOrder()` caches the filtered order keyed only on `identical(entries)`, `entries.length` and the filter. LogRegionSearchIndex's docs tell apps to "Keep the [entries] list stable and call [refresh] after appending or replacing entries", and the example console does mutate its list in place. Whenever such an in-place change keeps the length (replacing entries, or a capped rolling window of `removeAt(0)` + `add`), the cache hits. The stale source indices are then applied to the new contents: non-matching rows are shown, new matches are hidden, and Ctrl+C / onCopy copy the wrong entry. The cache is checked before the search index, so `index.refresh()` does not help. This is a correctness bug in the cache, separate from the known O(entries)-per-build cost.

**Reproduction.** (a) Stable list [boot ok, ERROR disk, tick, ERROR net, tick], filter query 'error'; the view shows the two ERROR rows. Then `entries.removeAt(0); entries.add(LogEntry(message: 'ERROR cpu'))` and pumpWidget the parent with the same list.
(b) Stable list [download 10%, ERROR retrying, download 20%] with `LogRegionSearchIndex(entries)` and filter 'error'. Replace entries[1]='retry ok' and entries[2]='ERROR checksum', call `index.refresh()`, rebuild, press Ctrl+C.

**Verifier evidence.** I wrote a probe at packages/fleury_widgets/test/_sweep_verify_logcache_1_test.dart, ran it, then deleted it. It rendered with showPrefix:false and used filter LogRegionFilterDescriptor(query:'error').

(a) Rolling window. Stable list [boot ok, ERROR disk, tick, ERROR net, tick], then `removeAt(0); add(ERROR cpu)` and pumpWidget with the same list:
BEFORE: "ERROR disk / ERROR net"
AFTER: "tick / tick"
Recomputing with buildLogRegionEntryOrder on the same list gives [ERROR disk, ERROR net, ERROR cpu].

(b) Search index with in-place replacement. [download 10%, ERROR retrying, download 20%] with LogRegionSearchIndex(entries). Set entries[1]='retry ok' and entries[2]='ERROR checksum', call index.refresh(), pumpWidget, then Ctrl+C:
BEFORE: "ERROR retrying"
AFTER: "retry ok"
index.entryOrder(filter) = [2], i.e. [ERROR checksum]
onCopy: "[INFO] retry ok" with entryIndex=1, and the clipboard gets the non-matching row.

Code path: log_region.dart:370-376. `_entryOrder()` returns `_cachedOrder` whenever the list is identical, the length is unchanged and the filter matches (`_sameFilter`). It does this before it reaches `searchIndex.entryOrder(filter)`. That method calls `refresh()` itself, and `currentPrefixMatches()` would have caught the replacement. Nothing else clears the cache. It stays wrong until the length or the filter changes, and every rebuild in between (selection moves, controller notifications) reuses the stale indices.

**Proposed fix.** Stop treating (identity, length) as a content key. When a searchIndex is attached, key the cache on a revision the index bumps in `appendFrom()`/`refresh()`. Without an index, either recompute (it is O(n), like the rest of build) or at least also compare the first and last entries by identity, which catches rolling windows but not a mid-list replacement.

**Verifier notes.** Tried to refute it, but it holds. Mitigating context:
- In-repo callers are not affected. TerminalOutputRegion builds a fresh list on every build (buildTerminalOutputLogEntries). The example console only appends, and appending changes the length, which misses the cache.
- The unfiltered path has no cache, so in-place mutation renders correctly there. The bug only shows up once a filter is active, which makes it easy to miss.
- The search index's own docs invite the pattern ("Keep the [entries] list stable and call [refresh] after appending or replacing entries").
- A capped rolling window over a stable list is a realistic app pattern.

Wrong rows are shown and Ctrl+C / onCopy copy the wrong data, so medium is right: not a crash, but silent wrong data.

Fix: the proposed first/last-identity check is weaker than it needs to be, because it misses case (b), a mid-list replacement.
- With a matching searchIndex: skip the widget-level cache and delegate to the index. Its `refresh()` already runs an O(n) identity prefix check. Better still, have the index expose a revision that appendFrom bumps, so the widget can key its cache on (index, revision, filter).
- Without an index: key the cache on a shallow snapshot of the entry identities, e.g. `List.of(entries)` compared element-by-element with `identical`. That is O(n) pointer compares, which is still much cheaper than re-running the filter (the filter sanitizes and lowercases every entry), and it catches every in-place replacement or roll. Alternatively, drop the cache: build is already O(n) because of `_stableIds`.

### [medium] SearchPanel reruns the full ranked search 2–4× per arrow key and re-indexes the old results on every update
`fleury_widgets/lib/src/search_panel.dart:374`, perf, found by the collections finder

**Claim.** `_currentOrder` is a getter that reruns the whole ranked search (sanitized exact/prefix/contains/subsequence over every result) on each access. It is read in `_move`, `build`, `_onQueryChange`, `_activateSelected` and `_copySelection`. `_move` then sets `currentIndex`, which triggers `_onListChange`, setState and another search in build. When the viewport scrolls, ListController's post-frame metrics notification triggers `_onListChange` again, costing another full search. Separately, `didUpdateWidget` (line 337) builds a fresh `SearchResultIndex(oldWidget.results)`, re-sanitizing every field of every old result, just to find the previous selection, even though `_searchIndex` already indexes that exact list.

**Reproduction.** (1) SearchPanel over 2000 results with a counting matcher, query 'item', query field focused: send ArrowDown and count matcher calls; then send 10 ArrowDowns that scroll past the 20-row viewport.
(2) Default ranker, 50k file-like results, query 'wdgt': time ArrowDown + frame.
(3) Streaming search: pumpWidget with a new list of 50k+1 results.

**Verifier evidence.** Probe packages/fleury_widgets/test/_sweep_verify_sp_1_test.dart (now deleted). Setup: SearchPanel, maxVisible 20, query field focused and autofocused.

(1) 2000 results, counting matcher, query 'item':
- "arrowDown #0/#1/#2 matcher calls = 4000", so 2n per key.
- "30 more arrowDowns (scrolling): matcher calls = 120000, per key = 2.0n"
- "enter: matcher calls = 4000"

(2) Default ranker over file-like results (title, subtitle path, category, source), query 'wdgt'. Each round interleaves one bare order() call with one ArrowDown plus pump, 15 rounds:
- n=500: median order() 299us; median arrowDown+frame 8848us.
- n=50000 (all 50000 match through the subsequence rank): median order() 39837us; median arrowDown+frame 89338us. About 2 × order() = 80ms of the 89ms key cost is redundant re-ranking.

(3) Results update, pumpWidget with a new list of n+1:
- n=50000: median SearchResultIndex build 192547us; median update pump 502435us.
- n=500: build 1787us; update 22067us.
- didUpdateWidget builds SearchResultIndex(oldWidget.results) (~190ms) even though _searchIndex already holds that list. Then _currentOrder builds the new index and ranks, and build ranks again.

Code path: `_currentOrder` (search_panel.dart:374) is an uncached getter calling `_resultIndex.order(...)`. `_move` reads it once. Setting `_list.currentIndex` fires `_onListChange` → setState, and `build` reads it again. `_onQueryChange` plus build likewise rank twice per keystroke.

**Proposed fix.** Memoize the order on (index identity, sanitized query text, matcher identity), so navigation, activation and copy reuse it and only a query or results change recomputes. In didUpdateWidget, reuse `_searchIndex` when `identical(_indexedResults, oldWidget.results)`, or simply remember the selected SearchResult or sourceIndex, instead of indexing the old list again.

**Verifier notes.** Confirmed as perf, severity medium. It only costs noticeably on large lists; below a few thousand results each ranking pass stays under 1ms.

The finder's "4.2n per key while scrolling" did not reproduce. I measured a steady 2.0n per key, including keys that scroll past the 20-row viewport. The extra pass from the post-frame metrics notification did not appear in this harness. Their 2n baseline and the ms-scale numbers hold: I measured 89ms per ArrowDown at n=50k with the default ranker, against their 74ms.

Enter/submit and Ctrl+C also rank the list again (`_activateSelected` / `_copySelection` → `_currentOrder`). Typing a query ranks twice per keystroke (`_onQueryChange` plus build). The fix below would halve that as well.

The proposed fix is right:
- Memoize the order on (identical index, sanitized trimmed query, matcher identity).
- In didUpdateWidget, capture the previously selected SearchResult from the cached order before invalidating it, or reuse `_searchIndex` when `identical(_indexedResults, oldWidget.results)`. Do not rebuild an index over the old list.

With memoization, an ArrowDown should cost about one frame (~9ms here) rather than ~89ms at n=50k. A results update should drop by roughly one index build (~190ms of ~500ms). The rest of the update cost (the new index plus one ranking) is inherent unless indexing becomes incremental.

### [medium] Sparkline (also Heatmap, Canvas) skips repaint when handed the same data object, so a history list updated in place freezes inside Panel's default RepaintBoundary
`fleury_widgets/lib/src/sparkline.dart:176`, bug, found by the widgets finder

**Claim.** RenderSparkline.data returns early when the new list is identical to the old one. A parent setState after mutating a retained history buffer therefore marks nothing. That is the pattern Fleury's own samples use: samples/lib/src/dashboard.dart `_push` (add/removeAt) and fleury_widgets/example/dashboard_demo.dart (`_rps.removeAt(0); _rps.add(...)`). Outside a boundary it works by accident, because every frame repaints non-boundary nodes. Inside a Panel (addRepaintBoundary defaults to true) the boundary cache stays clean and blits the stale sparkline indefinitely, while the Semantics wrapper reports the new latest value. RenderHeatmap.values and RenderCanvas.painter use the same identity check. In the samples dashboard the bug is hidden only because sibling Gauges in the same Panel dirty the boundary.

**Reproduction.** State holds `final rps = List<num>.filled(8, 10, growable: true)`. build: Panel(title: 'req/s', child: SizedBox(height: 1, child: Sparkline(data: rps, max: 100))). Four times: setState(() { rps.removeAt(0); rps.add(100); }); pump. Then renderToString(size: CellSize(12,5)). Repeat without the Panel.

**Verifier evidence.** I wrote a probe at packages/fleury_widgets/test/_sweep_spkv_1_test.dart (since deleted). A StatefulWidget holds `List<num>.filled(8, 10, growable: true)`. It pushes 100 four times, calling setState and pump each time, then calls renderToString(size: CellSize(12,5)). I ran four variants: with and without a Panel, and mutating the list in place versus replacing it with a new list.
- No Panel, in place: '▁▁▁▁▁▁▁▁' became '▁▁▁▁████' (correct).
- No Panel, new list: '▁▁▁▁████' (correct).
- Panel, in place: the output stays '│·▁▁▁▁▁▁▁▁·│' before and after (stale), while semantics().single(role: chart).value == '100'.
- Panel, new list: '│·▁▁▁▁████·│' (correct).
Cause: `set data` in RenderSparkline (sparkline.dart:175) returns early on `identical(_data, v)`. Panel wraps its body in a RepaintBoundary because addRepaintBoundary defaults to true (panel.dart:41/99), so the clean boundary replays its cached stale cells. The screen and the semantic tree then disagree. Heatmap (heatmap.dart:258) and BarChart `_bars` (bar_chart.dart:313) use the same identity check. My Heatmap probe was inconclusive: the chart draws only with color, so renderToString showed nothing either way.

**Proposed fix.** When the render object is updated from a rebuilt widget, markNeedsPaintOnly unconditionally for list/painter inputs. This only runs when the parent rebuilt, so it is cheap. Alternatively compare contents. For Canvas, add a shouldRepaint or repaint-Listenable contract. Also fix dashboard_demo's fixed-length `_rps` (see coverage).

**Verifier notes.** The finding holds for Sparkline, and Fleury's own samples use the in-place history-buffer pattern (samples dashboard `_push`, which is hidden there by sibling repaints). The Sparkline docs never say the list must be treated as immutable, so this is a real footgun. Medium severity is about right: the display silently goes stale with no error, but the workaround (pass a new list) is simple.

The Canvas part is overstated. Canvas.painter's doc says explicitly to "Replace the painter instance when its drawing inputs change so the render object schedules a repaint", so identical-painter skipping is the documented contract there, not a bug.

Better fix: in the widget's updateRenderObject, repaint whenever the data is the same object. updateRenderObject only runs when the parent rebuilt, so this costs nothing in steady state. The alternatives are a cheap element-wise compare in the setter, or documenting immutability.

Also, example/dashboard_demo.dart:69 declares `_rps = List.filled(24, 0)`, which is fixed-length, so `_rps.removeAt(0)` at line 152 would throw UnsupportedError on the first tick. I only read this, I did not run it.

All probe files are deleted.

### [medium] Toaster, Tooltip, Autocomplete and CompletionTextInput overlays ignore the app Theme and paint the fallback dark surface
`fleury_widgets/lib/src/toaster.dart:189`, bug, found by the widgets finder

**Claim.** runApp mounts the app, including FleuryApp's theme, inside the root Overlay's first entry, so sibling overlay entries do not inherit the app Theme. Menu and Select explicitly thread `Theme(data: theme)` into their entries. Toaster (_buildLayer), Tooltip (tooltip.dart:51), Autocomplete (autocomplete.dart:256) and CompletionTextInput (completion_text_input.dart:307) do not; ColorPicker's hex popover threads only borderStyle. Their Container.framed therefore resolves ThemeData.fallback: dark surface RGB(18,18,20), default text style, fallback selection/cursor styles. With ThemeData.light() or any custom surface/textStyle, toasts, tooltips and suggestion lists render as near-black boxes with terminal-default text, which is dark-on-dark on a light terminal.

**Reproduction.** Theme(data: ThemeData.light(), child: Toaster(child: app)). Call Toaster.show(ctx, 'Saved') and read the toast cell's background. Repeat for a Tooltip around an autofocused Button, an Autocomplete after typing 'Z', and a Select opened with Enter.

**Verifier evidence.** I wrote a probe at packages/fleury_widgets/test/_sweep_themev_1_test.dart (since deleted). It mounted each widget under Theme(data: ThemeData.light()) and read the background of the first cell of the overlay's text:
- toast (Theme wrapper): row=14 col=53 bg=RgbColor(18, 18, 20) fg=null
- toast with FleuryApp(title:'t', theme: ThemeData.light(), child: Toaster(...)): bg=RgbColor(18, 18, 20) fg=null
- tooltip (autofocused Button inside Tooltip): row=2 col=1 bg=RgbColor(18, 18, 20) fg=null
- autocomplete (options Zebra/Zulu, typed 'Z'): row=3 col=3 bg=RgbColor(18, 18, 20) fg=null
- select (autofocused, opened with Enter), same theme: row=3 col=3 bg=RgbColor(242, 242, 244), the correct light surface.
Structure checked in the code: run_app.dart:1256 mounts the user root, and so FleuryApp's _AppTheme (app.dart:435/501), inside rootEntry. Navigator has no Overlay of its own, so Overlay.of(context) from inside the app always resolves to the root Overlay, above the app Theme. Menu (menu.dart:122-130, 429-434) and Select (select.dart:205-210) capture Theme.of(context) and wrap their entry in Theme(data: theme). Toaster._entry (toaster.dart:189, _buildLayer), Tooltip._show (tooltip.dart:51), Autocomplete (autocomplete.dart:256), CompletionTextInput (completion_text_input.dart:307) and ColorPicker's hex entry (color_picker.dart:307, which threads only borderStyle) do not. Toaster._toastContent reads Theme.of(context) with the State's own context, so only the action label and hint get the app theme; the frame, fill and message text fall back to the default theme.

**Proposed fix.** Capture Theme.of(context) (and DefaultTextStyle) in the owning State at build/insert time and wrap each entry's content in Theme(data: captured), as Menu and Select do. Call entry.markNeedsBuild() when the captured theme changes. For Toaster, read the theme in Toaster.build, store it, and use it in _buildLayer.

**Verifier notes.** The claim holds as reported: with a light theme (set directly or through FleuryApp.theme), toasts, tooltips and suggestion lists render as the fallback near-black RGB(18,18,20) box with terminal-default foreground. On a light terminal that gives dark text on a dark box. Custom surface, textStyle and selection styles are dropped the same way. Medium is right: the fault is visible in every light- or custom-themed app, but no data is lost.

Better root-cause fix: the per-widget capture the finder proposes (as Menu and Select do) is the fifth or sixth copy of the same pattern, and whoever writes the next overlay widget will forget it. The same gap probably affects core `Anchored` (anchored.dart:167 builds `widget.overlay` in a plain OverlayEntry). My Anchored probe did not locate the text in one pump, so that part is unverified. A systemic fix would carry inherited themes across the Overlay boundary once, at insert time. Something like Flutter's InheritedTheme.capture(from: insertingContext) would work: OverlayState.insert, or an OverlayEntry constructed from a context, records Theme and DefaultTextStyle from the inserter and wraps the builder output. That would fix all these widgets and user-authored OverlayEntry uses, and Menu and Select could drop their manual wrap. Whichever route is taken, the entry must rebuild (markNeedsBuild) when the captured theme changes, e.g. on a runtime light/dark toggle. Menu and Select currently capture only at open time, so a theme change while one is open would go stale as well.

Also reported as: Toasts, tooltips, Autocomplete/CompletionTextInput dropdowns and the ColorPicker hex popover ignore FleuryApp(theme:): dark surface fill on light themes

### [medium] Tree's top-level semantics (currentIndex, selectedKey, visibleRange) never update during keyboard navigation
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury_widgets/lib/src/tree.dart:277`, bug, found by the collections finder

**Claim.** _TreeState creates a ListController (line 93) but never listens to it. The tree-level Semantics state (currentIndex, selectedKey, visibleRangeStart/End) is therefore only computed when the Tree itself rebuilds, which happens on expand/collapse or a parent rebuild. Arrow keys, clicks and typeahead only rebuild the inner ListView, so the tree node keeps reporting the old selection. An agent or MCP client reading the tree's selectedKey gets the wrong node. visibleRange is also missing after the first mount, because it is null at the first build, until some unrelated rebuild. TreeTable and FileBrowser avoid this through their wrapper-controller listeners.

**Reproduction.** Tree<String>(autofocus: true, roots: [alpha, beta, gamma, delta]) at 40x10. Press Down twice, pumping after each. Read semantics().single(role: SemanticRole.tree).state and the treeItem rows whose selected flag is true.

**Verifier evidence.** Probe test packages/fleury_widgets/test/_sweep_treesem_1_test.dart (now deleted). It mounts Tree<String>(autofocus: true, roots: alpha, beta, gamma, delta), renders at 40x10, sends arrowDown twice (pump + render after each), then sends the typeahead key 'd'. Output:
initial: {collectionRowCount: 4, rootCount: 4, expandedCount: 0, currentIndex: 0, selectedKey: 0}
after 2nd render: {... currentIndex: 0, selectedKey: 0}   <- visibleRange still missing after two full frames
after 2 downs: tree={... currentIndex: 0, selectedKey: 0} selectedRows=[gamma]
after typeahead d: tree={... currentIndex: 0, selectedKey: 0} selectedRows=[delta]
A dump of all nodes shows app, tree and text nodes and no separate list node. The inner ListView adds no collection-level node of its own, so the tree node is the only source of cursor and viewport state, and it is stale.
Code: in packages/fleury_widgets/lib/src/tree.dart, _TreeState owns `final ListController _list` (line 93). It never calls addListener. build() snapshots _list.visibleRange, currentIndex and _selected into SemanticState (lines ~277-285). Arrow keys (handled inside ListView), _typeahead, and the parent-jump branch of _collapseOrParent only set _list.currentIndex, so the Tree never rebuilds.
Consumers: packages/fleury/lib/src/semantics/accessibility.dart. _viewState announces 'selected ${state.selectedKey}' (line 1325), which stays stale. _collectionState only prints 'visible start-end' when visibleRangeStart is present (line 1040), so Tree never reports it. MCP and agent clients reading the graph get the same stale values.

**Proposed fix.** Add _list.addListener(() => setState(() {})) in initState and remove it in dispose, or derive the tree-level semantic state lazily from _list rather than snapshotting it at build time.

**Verifier notes.** Confirmed as described. Medium severity is fair: nothing crashes and the per-row treeItem `selected` flags are correct, but the collection-level currentIndex and selectedKey are wrong after any keyboard, typeahead or click navigation. Accessibility output and agent/MCP readers therefore report the wrong node, and visibleRange never appears unless something else rebuilds the tree.

Better root-cause fix: follow the TreeTable pattern (tree_table.dart:1068, `_controller.addListener(_onControllerChange)` with `setState(() {})`). Add `_list.addListener(_onListChange)` in initState and remove it in dispose before `_list.dispose()`. This is safe because ListController delivers viewport-metric changes through _notifyAfterFrame (list_view.dart ~line 320), so the setState does not happen during layout. The cost is one Tree rebuild per cursor move, which re-runs _flatten (O(visible rows)). That is acceptable. If it ever matters, the flat list could be cached and invalidated only on _expanded or roots changes. A regression test should check the tree node's selectedKey after arrowDown and after typeahead, and check that visibleRangeStart is present after the first frame. My probe file is deleted; the other _sweep_* files in the worktree belong to other agents.

### [medium] TreeTable selection is positional: expand, collapse, filter or new roots silently move the cursor to a different node, and Enter/Ctrl+C act on it
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury_widgets/lib/src/tree_table.dart:1348`, bug, found by the collections finder

**Claim.** TreeTableNode.key is documented as 'Stable row identity used by expansion, selection, copy, and semantics'. In practice the selection is only ListController.currentIndex into the flattened rows. The inner ListView.builder gets no itemKeyBuilder, and _ensureRows never remaps the cursor when it re-flattens. Any structural change above the cursor leaves the index where it was, so the cursor lands on another node. Triggers: controller.expand/collapse/collapseAll, a filter change such as typing in a search box, or new roots. Enter (onSelect/toggle) and Ctrl+C (onCopy) then target the wrong node. The existing test 'selection clamps against the cached model after collapse' passes only because 'docs' is the last root, so clamping happens to land on it.

**Reproduction.** roots = [app{search, logs}, docs, notes, readme]. (a) TreeTableController(initialIndex: 2) puts the cursor on 'notes'; call controller.expand('app'), pump, press Enter with onSelect recording. (b) expandedKeys {'app'}, initialIndex 4 ('notes'), then controller.collapseAll(). (c) initialIndex 2 ('notes'), then re-pump with filter: TreeTableFilterDescriptor(query: 'o'), which still matches 'notes'. Read tree.state['selectedKey'] each time.

**Verifier evidence.** I wrote my own probe at packages/fleury_widgets/test/_sweep_verify_treetable_1_test.dart (now deleted). Roots were [app{search, logs}, docs, notes, readme]. I read tree semantics state before and after each change:
- (a) initialIndex 2, then controller.expand('app') and Enter: "a before: notes idx=2" / "a after: logs idx=2" / "a Enter activated: [logs]".
- (b) expandedKeys {'app'}, initialIndex 4, then collapseAll(): "b before: notes" / "b after: readme".
- (c) initialIndex 2, then re-pumped with filter query 'o': "c before: notes" / "c after: docs rows=4". The rendered rows were app, logs, docs, notes, so 'notes' still matched but the cursor was on 'docs'.
- (d) initialIndex 2, then re-pumped with a new root 'aaa' prepended (a data refresh): "d before: notes" / "d after: docs".

Code path: _ensureRows (tree_table.dart:1129) re-flattens without touching the cursor. _selectedRow and _currentIndex only clamp controller.currentIndex. The ListView.builder at line 1348 gets no itemKeyBuilder, so ListView's identity-aware remap (list_view.dart around line 693, _remapCurrentIndex) never runs. Only LogRegion and MessageList pass itemKeyBuilder. The existing test 'selection clamps against the cached model after collapse' (tree_table_test.dart:807) passes only because 'docs' is the last root. Clamping index 3 to 1 happens to land on it.

**Proposed fix.** When _ensureRows rebuilds the model, capture the selected row's key first. If that key survives, write its new index to the ListController; clamp only if it is gone. This costs O(rows) only on structural change. Alternatively pass itemKeyBuilder: (i) => rows[i].key to the ListView.builder, but that adds an O(rows) key capture on every TreeTable build. Add a regression test with a root after the cursor.

**Verifier notes.** Confirmed on all four triggers, including prepending a root, which the finder did not test. The API says selection follows TreeTableNode.key ("Stable row identity used by expansion, selection, copy, and semantics"), and the code doesn't do that.

I lowered severity from high to medium. The tree's own keyboard and mouse actions never trigger this. Enter and Right expand the selected row, which only adds rows below the cursor. Left moves to the parent before it collapses. Clicking a row sets currentIndex to that row first. So the cursor moves only when:
- the app calls expand, collapse or collapseAll programmatically,
- the filter changes (for example, typing in a search box), or
- the roots change (a data refresh or file watcher).

The filter and data-refresh cases are realistic, and then Enter (onSelect) or Ctrl+C (onCopy) acts on a different node than the one the user picked. The highlight does visibly move, though, so the user can see it before acting.

On the fix:
- The alternative (itemKeyBuilder: (i) => rows[i].key) is the worse choice. ListView reads every item key on each updated ListView. TreeTable rebuilds on every controller change, including each arrow key, so this would bring back the O(rows)-per-keystroke cost that the _ensureRows cache removed (the ~100k-row SB.11 shape).
- The better fix is the finder's first option. In _ensureRows, only when the cache misses, remember the old selected key, find its new index in the new rows, and clamp only if the key is gone.
- One caveat: _ensureRows runs during build. Setting controller.currentIndex there calls notify, which calls _onControllerChange, which calls setState during build. The remapped index needs to be written without notifying (for example, directly to ListController._currentIndex or a pending-reveal field), or the remap should happen in didUpdateWidget / _onControllerChange before build.
- Rewrite the existing clamp test so a root sits after the cursor, since that is the case that exposes the bug.

Also reported as: TreeTable selection is positional: live data, filter or external expand/collapse makes Enter/copy act on a different node

### [low] Any focus change rebuilds every focusable control in the tree, not just the two whose focus changed
`fleury/lib/src/widgets/text_input.dart:1069`, perf, found by the perf finder

**Claim.** `TextInput.didChangeDependencies` calls `FocusManager.maybeOf(context)` only to be told about focus changes. That call is `dependOnScope<FocusManager>` (focus.dart:400), which subscribes to every manager notification. Many other widgets do the same: FocusableControl (focusable_control.dart:101, which covers Button, Checkbox, Switch and Radio), TextArea (text_area.dart:292), Select (select.dart:140/507/670), Menu (menu.dart:185/530), Tabs (tabs.dart:233), DatePicker (date_picker.dart:129), RangeSlider (range_slider.dart:130) and Focus.maybeOf (focus.dart:1285). So one Tab press or click-to-focus rebuilds all of them, including off-screen ones inside a ScrollView.

**Reproduction.** FleuryTester 100x40 with `ScrollView(Column of N TextInput(placeholder: ...))`. Call `tester.focusManager.focusNext()`, then `owner.flushBuild()` (read rebuiltElementCount), then pump; time the whole step.

**Verifier evidence.** Code: TextInput.didChangeDependencies (text_input.dart:1069) and FocusableControl.didChangeDependencies (focusable_control.dart:101) call `FocusManager.maybeOf(context)`, which is `dependOnScope<FocusManager>` (focus.dart:400-401). requestFocus() calls `notify()` on the manager (focus.dart:777), so every such dependent is dirtied on every focus move. The manager also notifies on focus-trap/ExcludeFocus changes and on KeyBindings hint-content changes (notifyBindingsChanged), and those rebuild every control too.

Probe 1 (packages/fleury/test/_sweep_focusv_1_test.dart, now deleted): ScrollView(Column of N TextInput), focusNext() then owner.flushBuild():
n=20   rebuilt per move=[20,20,20,20,20]      focusStep=1.022ms idlePump=0.106ms
n=200  rebuilt per move=[200,200,...]         focusStep=2.097ms idlePump=0.091ms
n=1000 rebuilt per move=[1000,1000,...]       focusStep=10.320ms idlePump=0.253ms
Off-screen fields inside the ScrollView are rebuilt as well.

Probe 2: interleaved A/B, 6 rounds, first round discarded, medians. Control = the same number of focus nodes as `Focus(child: Text)`, which uses the identity dependency. Times are build (focusNext+flushBuild) / render (pump), JIT:
n=80:   TextInput 0.705/0.084ms (80 rebuilt) vs control 0.024/0.043ms (0 rebuilt); form of TextInput+2 Buttons per row 2.109/0.468ms (240 rebuilt)
n=200:  TextInput 2.111/0.212ms (200) vs control 0.081/0.082ms (0); form 5.764/1.281ms (600)
n=1000: TextInput 11.17/1.15ms (1000) vs control 0.456/0.331ms (0); form 30.8/9.95ms (3000)

**Proposed fix.** Have each control depend on its own node's focus state instead of the whole manager: listen to its FocusNode, or to a per-node notification the manager fires only for nodes whose hasFocus/hasPrimaryFocus actually changed. Use maybeOfIdentityDependency or maybeOfWithoutDependency where only the manager instance is needed. Keep the broad subscription only for consumers that really depend on global focus, such as KeyBindings.activeOf and KeyHintBar.

**Verifier notes.** Reproduced. On every focus change, every TextInput, TextArea and FocusableControl in the tree rebuilds, visible or not. For the 240-control form that is 240 rebuilds per Tab, about 2.6 ms under JIT, against about 0.07 ms for the same number of focus nodes without the broad dependency. The cost is linear in the number of controls, so the finder's numbers hold.

I rate it low, not medium. Typical TUI forms have 10 to 40 controls, which comes to about 0.1 to 0.4 ms per Tab under JIT and less under AOT. That is far below one frame. It only becomes material with hundreds of mounted controls, such as a non-virtualised form of 200 or more rows, where it reaches about 7 ms per Tab. The same broad subscription also fires on focus-trap and ExcludeFocus changes and on KeyBindings hint-content changes. So a KeyBindings with a changing label (a live counter, say) rebuilds every control too. That is a small extra amplifier.

Fix: FocusNode has no listener API. The simplest root-cause fix keeps `maybeOfIdentityDependency` and adds a manager listener, following the pattern already used at focus.dart:1958. The listener caches `node.hasFocus` / `hasPrimaryFocus` and calls setState only when that value flips. That is still O(N) cheap callbacks per move, but only 2 rebuilds. A cleaner option is a per-node notification that the manager fires only for nodes on the old and new focus ancestry (via `_focusedAncestry`), which is O(depth). Keep `FocusManager.maybeOf` for true global consumers (KeyHintBar, KeyBindings.activeOf, Navigator). Focus.maybeOf (focus.dart:1285) is a static helper that only matters if user code calls it; the Focus element itself already uses the identity dependency.

All probe files have been deleted.

### [low] Every paint pass re-derives geometry for every mounted Semantics element (every Text), even in terminal-only apps where the result is thrown away
`fleury/lib/src/semantics/semantics.dart:1418`, perf, found by the perf finder

**Claim.** `SemanticsElement.mount` (line 1605) registers every element in `_geometryElements` of `owner.semanticDirtyTracker`. That tracker's `.attached` constructor (line 1402) registers `refreshGeometry` as a paint-pass listener, and `RenderDamageTracker.endPaintPass` (render_object.dart:179) runs it after every root paint. `Text` wraps every string in a Semantics (basic.dart:142). So each frame walks every mounted Text, including off-screen ScrollView content and routes under opaque routes, calling findRenderObject() and screenGeometry(). Because beginPaintPass advances the geometry epoch, every ancestor chain is resolved again each frame. In terminal runApp no FrameSemanticsPipeline exists; it is only created on the structured path (run_app.dart:1323). The tracker's `_requiresFullRebuild` is set at the first mount and never cleared, because only takeDirtySnapshot/reset clear it. `recordLeafDirty` therefore returns immediately, and `buildSemanticNode` re-derives bounds itself (line 1770), so the refresh has no observable effect. It also undoes repaint-boundary pruning: frame cost follows the whole tree's Text count even when one cell changes.

**Reproduction.** FleuryTester 100x40 with `Column[Text driven by a Notifier (clock), Expanded(ScrollView(Column of 5000 Text lines))]`. Fire the clock and pump each frame. A/B in interleaved rounds by calling `owner.renderDamageTracker.removePaintPassListener(owner.semanticDirtyTracker.refreshGeometry)` and adding it back.

**Verifier evidence.** I reproduced this with my own probe: `dart run`, JIT, asserts off, FleuryTester at 100x40. A Notifier-driven clock Text ticked and pumped each frame. I ran 6 interleaved A/B rounds, toggling the listener with `owner.renderDamageTracker.removePaintPassListener(owner.semanticDirtyTracker.refreshGeometry)` and adding it back. Numbers are µs/frame.
- ScrollView with 5000 Text lines, 50 frames per round: with the listener 1145, 1062, 1033, 1068, 1492, 1355. Without it 442, 362, 365, 468, 514, 477. One direct `refreshGeometry` call after an epoch bump costs 715 µs.
- ScrollView with 500 lines: with 155, 184, 142, 129, 135, 135. Without 110, 106, 122, 91, 92, 91. The direct call costs 40 µs.
- ScrollView with 100 lines: with 87, 88, 85, 85, 83, 86. Without 82, 72, 76, 71, 75, 74. The direct call costs 7.8 µs.
- 40x16 grid of Text behind a RepaintBoundary, plus the clock: with 66, 80, 95, 90, 84, 91. Without 33, 16, 15, 18, 15, 20. The direct call costs 70 µs.
- In every case `tracker.hasDirt` was still true at the end. `_requiresFullRebuild` stays set because nothing called `takeDirtySnapshot` or `reset`.

The code path matches the claim:
- Only `run_app.dart:1323` (structured or serve path) and `fleury_web/run_tui_surface.dart:268` create a FrameSemanticsPipeline. These are the only callers of `takeDirtySnapshot` and of the tracker's `reset()`, so in terminal `runApp` the full-rebuild flag stays set forever.
- `recordLeafDirty` returns early while that flag is set.
- `refreshBounds` has only two side effects: it updates `_bounds` and nulls `_cachedSemanticNode`. `buildSemanticNode` re-derives bounds itself (line 1770) and checks `cached.bounds == bounds`, so the refresh changes nothing observable in terminal mode.
- `beginPaintPass` increments `_geometryEpoch` (render_object.dart:169), so every `screenGeometry()` call re-resolves the ancestor chain on every pass.
- The code already admits the case in its own comment at semantics.dart:1611: "Ordinary terminal hosts also leave that dirt pending when they have no semantic presenter."

**Proposed fix.** Return early from refreshGeometry when `_requiresFullRebuild` is pending. The next consumer rebuilds every node from fresh geometry anyway, so this makes terminal mode O(1) per frame. The structural fix is to add the paint-pass listener only while a semantics consumer (FrameSemanticsPipeline or an MCP/debug presenter) is attached. In serve mode, also skip passes where the epoch only moved because of beginPaintPass, with no layout or scroll since the last refresh.

**Verifier notes.** The waste is real: every terminal-only app runs this for every mounted Semantics element on every paint pass. It also defeats repaint-boundary pruning. In the grid case, a clock-only frame goes from about 17 to about 85 µs, roughly 4-5x.

I lowered the severity from medium to low because the absolute cost on realistic trees is small:
- The cost scales with the number of mounted Semantics elements, not with what is visible. Large lists normally use the virtualized ListView, which mounts only the visible rows, so the cost stays near the viewport's Text count.
- At that size it is about 5-40 µs per frame, against a 16-33 ms frame budget. The finder's own sample-app numbers show deltas of about 1-16 µs.
- It only reaches about 0.7 ms per frame in the pathological case of a non-virtualized ScrollView holding thousands of Text widgets.
- The tester frame excludes ANSI diff and encode, so the percentage share is somewhat overstated compared with a real terminal frame.

It is still worth fixing because the fix is cheap.

On the proposed fix:
- The early return in `refreshGeometry` while `_requiresFullRebuild` is pending is correct and makes terminal mode O(1) per frame. The pending full rebuild re-derives `_bounds` for every node it visits.
- The early return does nothing for serve mode, because the pipeline clears the flag on every flush. The better root-cause fix is the finder's structural option: register the paint-pass listener only while a consumer is attached. Concretely, `FrameSemanticsPipeline` would call `addPaintPassListener` on construction and `removePaintPassListener` on dispose, instead of `SemanticDirtyTracker.attached` registering it unconditionally.
- For serve mode, a further step is to skip passes whose epoch moved only because of `beginPaintPass`, with no layout or scroll since the last refresh. That would need a separate layout-epoch counter.

I created one probe file, `packages/fleury/test/_sweep_semverify_1_test.dart`, and deleted it. The other `_sweep_*` files in the worktree belong to other agents.

### [low] FileBrowser, SearchPanel and DiffView recompute O(n) data on every build and every navigation call
`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury_widgets/lib/src/file_browser.dart:395`, perf, found by the collections finder

**Claim.** These widgets rebuild O(n) derived data from scratch each time instead of caching it against the data's identity. FileBrowser._currentOrder re-runs buildFileBrowserEntryOrder (sanitizeSingleLine + toLowerCase + contains + subsequence per entry) in build, _activateSelected, _copySelection and the row callbacks. SearchPanel._currentOrder (search_panel.dart:374) re-ranks every result (exact/prefix/contains/subsequence) in build and in _move. DiffView.build (diff_view.dart:634) calls _diffGutterWidth(rows), which walks every row and allocates two int.toString() per row. Each scrolling arrow key triggers two builds (see the wrapper double-frame finding), so the cost is paid twice per step.

**Reproduction.** FileBrowser over a 20,000-file directory, filter query 'file', maxVisible 20. SearchPanel with 20,000 results and query 'widget'. DiffView.document over a 100,003-row diff, with and without showLineNumbers. In each, press Down repeatedly (sendKey + pump + pump), after warm-up.

**Verifier evidence.** I ran a probe at packages/fleury_widgets/test/_sweep_collverify_1_test.dart (deleted afterwards). Each step was sendKey(arrowDown) + pump + pump, with 30 warm-up steps and then 100 timed steps. Separately, I timed the O(n) function on its own over the same data.

FileBrowser, 20,000 real files, maxVisible 20:
- query="file": 19.20 ms per step. buildFileBrowserEntryOrder alone takes 8.16 ms, so it runs about 2.4 times per step.
- query="" (the same 20k loop, but it costs only 0.36 ms): 1.64 ms per step. This is roughly what a memoized order would cost, so the query path is about 12x slower.

SearchPanel (title, subtitle and category set):
- n=200, q="widget": 1.03 ms per step, order() 0.008 ms.
- n=20000, q="widget": 5.24 ms per step, order() 1.291 ms, about 4.1 calls per step.
- n=20000, q="": 2.78 ms per step, order() 0.611 ms, about 4.5 calls per step.

DiffView.document, 100,004 rows:
- showLineNumbers=true: 9.069 ms per step. _diffGutterWidth alone takes 2.70 ms, about 3 calls per step.
- showLineNumbers=false: 0.749 ms per step.
- 1,004 rows: 0.982 ms (true) vs 0.607 ms (false).

The code matches the claim. _currentOrder is a getter with no cache (file_browser.dart:395, search_panel.dart:374). DiffView.build calls _diffGutterWidth(rows) on every build (diff_view.dart:634). Only the SearchResultIndex object is cached, keyed on results identity; the order computed from it is not.

**Proposed fix.** Memoize each value. FileBrowser order keyed on (_entries identity, query, showHidden). SearchPanel order keyed on (_resultIndex identity, query text, matcher). DiffView gutter width computed once per DiffDocument, either stored by parseUnifiedDiff or cached against widget.document identity.

**Verifier notes.** Reproduced: every arrow-key step recomputes this O(n) data several times. I'm lowering severity from medium to low. The cost only matters at sizes that are unusual for these widgets: a flat directory of more than 10k entries with an active filter, a diff of 100k+ rows, or 20k+ search results. At normal sizes (under 2k entries or rows) each step costs 1 ms or less.

The SearchPanel number is overstated: I measured 5.24 ms per step at 20k results, not the 16.59 ms reported. Even the worst case, FileBrowser at about 19 ms per step, fits inside a ~33 ms key-repeat interval. It uses most of the frame budget but does not drop inputs.

The proposed fix is right. Memoize:
- FileBrowser's order on (_entries identity, sanitized query, showHidden).
- SearchPanel's order on (index identity, query text, matcher).
- DiffView's gutter width once per DiffDocument, either as a field computed in parseUnifiedDiff/DiffDocument or cached against document identity.

A better root-cause fix for FileBrowser: precompute each entry's lowercase search text when the directory loads. Today _entryMatches builds a list, maps it through sanitizeSingleLine, joins and lowercases it for every entry on every call. That also makes typing a filter character cheaper (about 8 ms per keystroke at 20k), which memoization alone does not help.

The ~2-4 calls per step also depend on the separate double-build-per-key finding. Fixing that would roughly halve these numbers even without memoization.

### [low] LineChart sorts and dedupes every x value on each series update or parent rebuild, even when not interactive, and repaints all points when the data is unchanged
`fleury_widgets/lib/src/line_chart.dart:362`, perf, found by the perf finder

**Claim.** `_LineChartState.didUpdateWidget` calls `_rebuildCursorXs()` whenever `widget.series` is not identical. The usual call site is `series: [LineSeries(points)]`, which is a new list on every parent rebuild, so this runs on every rebuild. `_rebuildCursorXs` (line 372) puts every x value into a Set<num> and sorts it, which is O(P log P). `_cursorXs` is only read when `interactive` is true, so non-interactive charts pay this for nothing. Each build also runs `_lineChartSemanticState` (line 477), which scans all points twice for extents. `RenderLineChart.series` (line 738) repaints on any non-identical list, so a rebuild with unchanged data pays the full rasterization too.

**Reproduction.** `SizedBox(width: 100, height: 20, child: LineChart(series: [LineSeries(points)]))` inside a StatefulWidget. Case (a): setState slides a P-point window by one point. Case (b): setState with the same `points` list. Time notify plus pump.

**Verifier evidence.** I wrote a probe at packages/fleury_widgets/test/_sweep_vperflc_1_test.dart and deleted it afterwards. It uses a FleuryTester with a 120x30 viewport. A host StatefulWidget calls setState and then tester.pump(), with the same `points` every time, so the data never changes. Each result is the median of 5 interleaved rounds, and all configurations ran within every round.

Configurations compared:
- **fresh-list:** the usual call site, `LineChart(series: [LineSeries(points)])`.
- **identical-list:** a series list the host keeps and reuses.
- **+const-palette:** also passes `palette:` a const list.
- **cached-widget:** the host reuses the whole LineChart widget instance.
- **cursorXs alone / extents x2 alone:** copies of `_rebuildCursorXs` and of `_lineChartExtents` (run twice), timed on their own.

Run 1, no RepaintBoundary around the chart (ms per rebuild):

| P | fresh-list | identical-list | +const-palette | cached-widget | cursorXs alone | extents x2 alone |
|---|---|---|---|---|---|---|
| 300 | 0.241 | 0.209 | 0.228 | 0.191 | 0.024 | 0.003 |
| 2000 | 0.872 | 0.670 | 0.659 | 0.623 | 0.196 | 0.023 |
| 10k | 4.69 | 3.12 | 3.47 | 3.18 | 1.49 | 0.14 |
| 100k | 60.3 | 35.2 | 39.3 | 30.7 | 22.7 | 5.8 |

Run 2, the chart wrapped in RepaintBoundary (ms per rebuild):

| P | fresh-list | identical-list | +const-palette | cached-widget |
|---|---|---|---|---|
| 300 | 0.302 | 0.230 | 0.047 | 0.026 |
| 2000 | 0.922 | 0.733 | 0.062 | 0.018 |
| 10k | 4.58 | 3.08 | 0.187 | 0.015 |
| 100k | 60.2 | 38.4 | 3.21 | 0.015 |

In both runs the fresh-list minus identical-list gap roughly matches the time `_rebuildCursorXs` takes on its own. That is 1.4–1.6 ms at 10k and 20–25 ms at 100k.

**Proposed fix.** Build the cursor x-list lazily, and only when `widget.interactive` (on first focus or cursor key). Build it incrementally rather than through a Set plus sort, for example as a k-way merge, since each series' points are usually x-sorted. Memoize extents and pointCount per `LineSeries.points` identity. Make the `series` setter compare element-wise, by the identity of each LineSeries or its points, so a fresh wrapper list over the same series does not repaint. Optionally decimate to plot resolution (per-column min/max) when P is much larger than the plot width.

**Verifier notes.** **What holds.** The first half of the finding reproduces.
- `didUpdateWidget` (line 362) calls `_rebuildCursorXs` whenever the series list is not the same object. That method dedupes every x value through a Set and sorts it, O(P log P).
- The result, `_cursorXs`, only matters when `interactive` is true, yet non-interactive charts pay for it on every parent rebuild.
- That waste is about 30–37% of a same-data rebuild at 10k–100k points, 21% at 2k and 10% at 300.
- In a sliding-window update the data really changes, so the repaint is unavoidable and the cursor-x work is the only waste.

**What is wrong in the repaint claim.** The finding blames the `RenderLineChart.series` identity check (line 738) and proposes comparing series element-wise. That would not stop any repaint:
1. **Without a RepaintBoundary** (the common case), the chart repaints on every frame the host rebuilds, even when the host reuses the exact LineChart widget: cached-widget costs about the same as identical-list. That is the framework's general cost of repainting everything when there is no boundary, not something LineChart causes.
2. **With a RepaintBoundary,** passing the identical series list still repaints fully (3.08 ms at 10k). The reason is `build()` (around line 430): when no palette is given it creates a new default list, `[cs.primary, cs.info, cs.warning, cs.success, cs.error]`, on every build. The `palette` setter also compares by identity and calls `markNeedsPaintOnly`. Only with both the series and the palette stable did the cost drop to 0.187 ms at 10k.

So the repaint fix has to cover the palette too: cache the default palette per theme, or compare palettes element-wise. It is only worth anything for charts under a RepaintBoundary.

**Minor.** `_lineChartSemanticState` scans all points twice for extents, which costs 2–4% (0.12 ms at 10k).

**Recommended fixes, in order:**
1. Compute `_cursorXs` lazily, only when `widget.interactive` is true (on focus, a key press or a semantic action). This removes the main waste with a very small change.
2. Give the default palette a stable identity, or compare palettes element-wise, and compare series element-wise, so boundary-wrapped charts skip repainting unchanged data.
3. A k-way merge, memoized extents and decimation are optional.

**Severity: low, down from medium.** At realistic sizes (300–2k points, updating at 1–10 Hz) the waste is 0.02–0.2 ms per rebuild. It only becomes material at 10k points and above (about 1.5 ms at 10k and about 22 ms at 100k, which exceeds a frame budget). At those sizes, painting 100k points in a 100-column plot already costs about 30 ms. The fix is cheap.

### [low] parseUnifiedDiff reads the `git format-patch` signature line (`-- `) as a deletion: phantom row, wrong counts, corrupt hunk copy
`fleury_widgets/lib/src/diff_view.dart:356`, bug, found by the collections finder

**Claim.** The parser deliberately keeps a hunk open until the next @@, `diff --git` or non-body line, ignoring the @@ line counts. So the `-- ` e-mail signature delimiter that `git format-patch` / `send-email` append after the last hunk matches `inHunkBody && line.startsWith('-')` and becomes a deletion of the old file's next line. DiffView shows a phantom red `-- ` row with an old line number, and deletionCount is off by one per patch. Copying that hunk (DiffViewCopyMode.hunk) exports a corrupt hunk with one more deletion than its header declares. PatchReview's per-file +/- stats, built from the same rows, report the phantom deletion too.

**Reproduction.** In this repo: `git format-patch -1 --stdout 93816cde` → parseUnifiedDiff(patch). Compare additionCount/deletionCount with `git show --numstat 93816cde`. Inspect the last deletion row, `exportDiffSelection(doc, rowIndex: thatRow, options: DiffViewCopyOptions(mode: DiffViewCopyMode.hunk))`, and `buildPatchReviewFiles(doc).last`.

**Verifier evidence.** I ran a probe at packages/fleury_widgets/test/_sweep_verify_diffsig_1_test.dart and deleted it afterwards.
(1) A minimal format-patch (one hunk `@@ -1,2 +1,3 @@` with ` a`, ` b`, `+c`, then the `-- ` / `2.50.1` signature) parses to add=1 del=1. The row list ends with `DiffLineKind.deletion "-- " old=3 new=null hunk=0` and then `metadata "2.50.1"`. Copying the hunk (`exportDiffSelection` with `DiffViewCopyMode.hunk`) returns "@@ -1,2 +1,3 @@\n a\n b\n+c\n-- ", which has one more deletion than the header declares. `buildPatchReviewFiles(doc).last` reports "f.txt +1 -1" when the real change is +1 -0.
(2) Real patch: `git format-patch -1 --stdout 93816cde` parses to add=2495 del=2444. The same commit through `git show --format=` parses to add=2495 del=2443, which matches `git show --numstat` (2495 2443). The last PatchReview file is "packages/fleury/test/rendering/width_resolver_test.dart +39 -1"; numstat says 39 0.
Cause: at diff_view.dart:356, `inHunkBody && line.startsWith('-')` runs whenever `currentHunkIndex != null`. The remainingOld/remainingNew counters are 0 at that point, but they are only used to decide file headers, never to close the hunk.

**Proposed fix.** Inside an open hunk whose remainingOld and remainingNew are both 0, treat a line that is exactly '-- ' (the format-patch signature separator) as the end of the hunk and emit it as metadata. Keep the existing understated-count tolerance for every other +/-/space line, so diff_hunk_understate_lock_test still holds.

**Verifier notes.** The behavior reproduces exactly as the finder described. It is not documented as intended: the parser's own comments name "emailed and pasted diffs" as input it is meant to handle.

I lowered severity from medium to low. The damage is one phantom `-- ` row per patch, and it only appears when the input is `git format-patch` / mbox output. There is no crash and no content is lost. The visible effects are a deletion count that is off by one, the same error in PatchReview's per-file stats, and a hunk copy with one trailing line too many.

The proposed fix is sound and narrow: when both counters are exhausted (remainingOld == 0 && remainingNew == 0), a line exactly equal to `-- ` closes the hunk and becomes metadata. None of the existing lock tests has a `-- ` line with exhausted counters. diff_view_test.dart:75 covers `-- drop old comment` inside a hunk that still has counts left, so it is unaffected, and diff_hunk_understate_lock_test keeps its tolerance for every other line.

Remaining risk: a genuine deleted line whose content is exactly "- ", such as an empty markdown bullet with a trailing space, falls through only if it sits in an understated hunk after the counters reach zero. That case is negligible.

A slightly more general version of the same fix: once the counters reach zero, stop at any line that cannot be diff body in mbox context, i.e. the `-- ` separator. I would keep it to just that literal rather than trusting the counters in general.

## F. Serve, semantics & a11y (5)

### [high] A legal duplicate semantic id on a node with children makes the wire encoder drop the whole semantic tree. Serve's a11y DOM goes empty and MCP reports that the app never rendered.
`fleury/lib/src/remote/remote_semantics.dart:618`, bug, found by the remote finder

**Claim.** `_semanticFlatGraphIsValid` rejects a tree when any repeated id has children. On a second visit it returns false unless the node is a leaf. It also rejects when last-wins flattening leaves orphaned flat nodes. `_encodeFull`/`_finishPatch` then call `_rejectCandidate` (which resets the encoder), and `RemoteTerminalDriver.presentSemantics` (remote_driver.dart:465) returns null without any report.

Duplicates like this come from ordinary trees:
- `Semantics(key: ValueKey(x))` becomes `key:x` with no ancestor context (semantics.dart:1690).
- Keyed rows in two lists that share a data id get the same `auto:` anchor, because positional segments above a key are dropped. `_indexOwnedIds` already calls this out as a real case.

The result: the peer never receives a single SEMANTICS frame, or keeps a frozen, stale tree if the duplicate appears mid-session. Every semantically dirty frame re-flattens the whole tree only to reject it again (about 3.9 ms at 2.2k nodes).

**Reproduction.** 1. Build `Row([Expanded(ListView(children:[_FileRow(key: ValueKey('a.txt'))])), Expanded(ListView(children:[_FileRow(key: ValueKey('a.txt')), _FileRow(key: ValueKey('b.txt'))]))])`, where `_FileRow` = `Semantics(role: listItem, label: name, child: Row([Expanded(Text(name)), Button(text:'Open')]))`.
2. Serve it with `runApp(driver: RemoteTerminalDriver(transport))`, or drive it with `FleuryAppBridge` + `McpServer` over an in-memory codec round-trip pipe.
3. Call `get_ui`.

**Verifier evidence.** I ran two probe tests in packages/fleury/test/remote/ and deleted both afterwards. Both used real widgets: `_FileRow` = `Semantics(listItem, label, Row[Expanded(Text), Button('Open')])`, with keyed rows inside two unkeyed `ListView`s in a `Row`.

**Probe 1: the first frame is dropped**
- Disjoint keys: `shared=false nodes=16 dups={} bytes=3752`.
- One shared key: `shared=true nodes=16 dups={auto:OverlayEntry#5kd88t/a.txt/~0/listItem: 2, .../text: 2, .../pointerCursor: 2, .../button: 2} bytes=null`. `SemanticsWireEncoder.encodeTree` returns null, so the peer gets no FULL frame at all.
- Because `_rejectCandidate` resets the encoder, each later call runs a full flatten and a full validation again. 20 re-encodes of this 16-node tree took about 4 ms.

**Probe 2: a duplicate that appears mid-session freezes the peer**
I fed the encoder output to a `SemanticsWireDecoder`:
```
right=c.txt status=status-1 bytes=2811 peer=status-1,a.txt,a.txt,Open,c.txt,c.txt,Open
right=a.txt status=status-2 bytes=null peer=status-1,...,c.txt,...   (stale)
right=a.txt status=status-3 bytes=null peer=status-1,...,c.txt,...   (stale: unrelated status change lost too)
right=d.txt status=status-4 bytes=2811 peer=status-4,...,d.txt,...   (recovers only once the duplicate goes away)
```

**Code path**
- `_semanticFlatGraphIsValid` (remote_semantics.dart:588) returns false on a second visit to a node that has children.
- `_encodeFull` and `_finishPatch` then call `_rejectCandidate`, which runs `reset()`, and return null.
- `RemoteTerminalDriver.presentSemantics` (remote_driver.dart ~465) does `if (bytes == null) return;`. Nothing reports the rejection.
- The fleury_mcp message the finder quoted exists at mcp_server.dart:2506: "The app connected but never rendered a UI (no semantic frame…)". An app with this tree hits exactly that path.

**Framework context**
The rest of the framework treats duplicates as a tolerated, degraded state:
- The `_flattenTree` doc says so ("the framework tolerates duplicates … as a degraded state").
- `_indexOwnedIds` names this exact case (a reused key under distinct unkeyed parents folds to one `auto:` id) and fails closed only for dispatch.
- MCP flags the id as ambiguous.

Only the wire encoder turns the duplicate into "drop the entire tree".

**Proposed fix.** Don't reject the whole tree for a duplicate on the producer side. In `_flattenTree` and the validation, keep the first occurrence of a repeated id that has children. Drop the later subtree, or give it a deterministic `#n` suffix, and record the ambiguity so MCP can still flag it. The decoder's guard against a branching graph can stay. At minimum, report the rejection through the error reporter instead of silently returning null on every frame.

**Verifier notes.** The rejection itself is deliberate. The existing test 'a structurally unrepresentable tree is skipped before send' (remote_semantics_sender_test.dart:201) checks a hand-built duplicate-internal-id tree, and the check guards the decoder against expanding-DAG input. What is wrong is the outcome: an app tree that is otherwise legal loses serve's a11y DOM and every MCP tool. It happens without any warning. The trigger is an ordinary pattern: two unkeyed lists or panes whose keyed rows share a data id (for example "recent" and "all files"), or `Semantics(key: ValueKey(x))` used in two places. Recovery happens only once the duplicate disappears. I kept severity high because the failure is total and silent, and it hits the agent/remote surface. How often it is triggered depends on the app's key choices.

On the fix, the finder's proposal (dedupe inside the encoder) is a band-aid on one consumer. The root cause is at id generation or snapshot build. `semanticAnchorOf` drops the positional tail above a key, so identical keys under different unkeyed parents collide, even though its own doc claims folding the keyed chain keeps ids "globally unique". Better: make the ids unique when the SemanticTree snapshot is built. Give later occurrences of a repeated id a deterministic suffix and record the ambiguity. That way the wire, the MCP ambiguity guard, dispatch (`_indexOwnedIds`) and the debug oracle all see the same unique ids, and the encoder's structural guard and the decoder's guard can stay strict. Also report producer-side rejections through the error reporter instead of `return null` on every frame.

I left alone the untracked file packages/fleury/test/_sweep_remoteverify_1_test.dart at the package test root. I did not create it; it probably belongs to another agent. Both of my own probe files are deleted.

### [medium] A semantic action whose handler awaits UI (the `await context.present(Confirm())` idiom) blocks the served semantic-action queue, so the dialog can't be confirmed through a11y/MCP
`fleury/lib/src/runtime/run_app.dart:1157`, bug, found by the remote finder

**Claim.** Inbound SEMANTIC_ACTIONs are chained on `semanticActionTail`, and each link awaits `invokeSemanticActionFromElement`. That call awaits the handler's Future: `Semantics.onAction` does `await callback(action)` (semantics.dart:1823), and command nodes await `invokeCommand` → `command.run`.

A handler that awaits a presented route holds the tail until that route pops. The route's own button can only be activated by a later queued action, so the semantic channel is stuck until someone uses the keyboard. No RESULT is sent for the first action either.

Over MCP, `FleuryAppBridge` times out after 2 s and tombstones its single correlation slot (app_bridge.dart:341-364). Every later `invoke_action`/`set_value` then throws `FleurySemanticActionBusyException` until the dialog is dismissed with `press_key`.

**Reproduction.** 1. `runApp(Navigator(home: Semantics(id:'delete', role: button, actions:{activate}, onAction: (_) async { final ok = await context.present<bool>(const Confirm()); … })))`, where `Confirm` = `Semantics(id:'confirm', actions:{activate}, onAction: (_) => context.pop(true))`.
2. Serve it over RemoteTerminalDriver.
3. Send SEMANTIC_ACTION(delete, activate), then SEMANTIC_ACTION(confirm, activate).

**Verifier evidence.** I wrote a probe at packages/fleury/test/remote/_sweep_verify_remote_1_test.dart, ran it, and then deleted it. It uses runApp over RemoteTerminalDriver with a fake transport and Navigator(transition: none). The home screen is a Semantics('delete', activate) whose onAction does `await context.present<bool>(_Confirm())`. _Confirm is a Semantics('confirm', activate) whose onAction calls context.pop(true).

Test 1, raw Semantics onAction. Output:
  confirm in peer tree: true
  after 2s: results=[] resultCalled=false deleted=null
After I sent an InputEventFrame(KeyEvent(escape)):
  confirm handler ran
  after Esc: results=[delete:completed, confirm:completed] resultCalled=true deleted=null

Test 2, AppCommand path. The dialog comes from a CommandScope + AppCommand whose run does `await c.buildContext!.present<bool>(_Confirm())`, and the command is activated through its semantic node `command-scope:.../command:del`. Output:
  confirm in peer tree: true
  cmd after 2s: results=[] resultCalled=false deleted=null

The code path matches the claim. run_app.dart:1157 chains each link on semanticActionTail and awaits invokeSemanticActionFromElement. That function (semantics.dart:1123) awaits the dispatch Future. Semantics.handleSemanticAction does `await callback(action)` (semantics.dart:1823). The command contributors (commands.dart:550, app.dart:641) await invokeCommand, and invokeCommand awaits command.run (commands.dart:272). On the MCP side, app_bridge.dart _expectActionResult times out after 2 s and leaves a tombstone in _pendingAction. _requireActionSession then throws FleurySemanticActionBusyException for every later invoke_action/set_value until the late result arrives, which only happens once the dialog is dismissed by non-semantic input.

**Proposed fix.** Hold the queue only for the snapshot and the synchronous start of the dispatch. Release the tail once the handler has started (or after a short deadline), and send the RESULT when its Future settles. Alternatively, add sequence-numbered or started/completed results, so the MCP bridge doesn't have to tombstone its only slot for a long-running handler.

**Verifier notes.** The defect is real, but it reaches less code than the finding suggests. The common app idiom, `Button(onPressed: () async { await context.present(...) })` (storybook catalog.dart:2013 uses it, and fleury_widgets dialog.dart documents it), does NOT wedge the queue. FocusableControl's onAction calls `_activate()` → `widget.onActivate!()` synchronously and never awaits onPressed (focusable_control.dart:118, 201-211). Only two kinds of handler are affected:
- raw `Semantics(onAction:)` or `onSetValue:` handlers that await UI;
- AppCommands (CommandScope / app command registry) whose `run` awaits a presented route, such as a "Delete…" command that asks for confirmation. Commands are exposed as semantic command nodes to MCP and the browser a11y DOM, so this is a realistic path.

Medium severity is right: agents and screen-reader users are stuck on the semantic channel until someone uses the keyboard (MCP press_key or Esc), but no data is lost.

The probe also showed a second hazard. After Esc dismissed the dialog, the stale queued `confirm` activation still ran ("confirm handler ran" after the dismissal). It called context.pop(true) against a route that was already dismissed. On a deeper stack that pop could pop the screen underneath. It happens because the link re-snapshots the live tree before the pop has rebuilt it.

On the fix: releasing the tail as soon as the handler starts, as proposed, would reintroduce F16. setValue handlers that mutate after an await (the existing test in remote_surface_driver_test.dart:947) rely on the next action waiting for the body to finish. A better fix is to hold the tail until the handler's Future settles OR the dispatch has pushed a route / committed a frame (or a short deadline passes, whichever comes first), and send the RESULT when the Future settles. The RESULT needs a per-action sequence number or nonce so FleuryAppBridge can correlate late results without tombstoning its single slot. Alternatively, send an 'accepted/started' result right away and a 'completed' result later. Any fix should also re-check the target node after the frame that follows a preceding link, so a queued action can't fire on a route that is being dismissed.

All probe files I created were deleted. The other untracked _sweep_* files in the worktree belong to other agents.

### [medium] SemanticDomPresenter re-inserts the whole content of every aria-live region on any structural change, so screen readers re-read the entire log for each appended line
`fleury_web/lib/src/semantics/semantic_dom_presenter.dart:159`, bug, found by the remote finder

**Claim.** Any added or removed node sends `present` down the full path (line 177). It clears `_root.textContent` (line 61) and `_nodeElement` sets `element.textContent = ''` on every reused element (line 159), then re-appends all children. Element identity is kept, but every node is detached and reinserted.

Live regions are exposed with aria-live: status/progress polite, notification assertive, and log polite with `aria-relevant="additions text"`. Their full content therefore shows up as fresh additions whenever anything structural changes anywhere: a log line appended, a list item added, a toast or dialog opening.

This presenter is shared by `fleury serve` and the embed host. Its header comment says "stable nodes do not churn every frame", which is only true of element identity, not of DOM position.

**Reproduction.** 1. `present(tree{status 'Build: passing', log(50 text lines), list(2 items)})`.
2. Attach MutationObservers (childList, subtree) to the status and log elements.
3. Present the same tree with list(3) and count added nodes.
4. Repeat with log 50→51 lines.

Run in Chrome with `dart test -p chrome`.

**Verifier evidence.** I wrote a Chrome probe (`dart test -p chrome`) in packages/fleury_web/test/_sweep_remoteverify_1_test.dart, since deleted. It drives SemanticDomPresenter with the update that SemanticsOwner.update produces, the same path wire_frame_source.dart:688 uses. The tree is app{status 'Build: passing', log(50 text lines), list(2 items)}. MutationObservers (childList, subtree, characterData) watched the status element, the log element and the root, and recorded addedNodes, plus removedNodes for the log.

Output:
```
log aria-live=polite relevant=additions text
status text change (incremental): {status: 0, log: 0, all: 0, logRemoved: 0}
list 2->3: {status: 1, log: 101, all: 111, logRemoved: 101}
log 50->51: {status: 1, log: 102, all: 113, logRemoved: 101}
log element same: true
```
The control is a label-only change, which takes the incremental path and causes zero childList churn. Adding one item to an unrelated list detaches and re-adds all 101 nodes inside the aria-live log: 50 spans plus 50 text nodes plus the log's own label text. The status region's text node is re-added too. Appending one log line re-adds 102 nodes in the log, where only the new span and its text are needed. Element identity is preserved (`log element same: true`), but the nodes really are removed and re-inserted (logRemoved=101), not left in place.

**Proposed fix.** Make structural updates incremental. Insert or remove only the added/removed ids under their parents, and move an element only when it is not already at the target position (the same `orderCursor` approach `InlineImageOverlay.apply` uses). Never clear `textContent` of unchanged reused elements. At a minimum, keep live-region subtrees attached when their own nodes did not change.

**Verifier notes.** Root cause, confirmed by reading the code:
- `_canPresentIncrementally` returns false whenever `update.added` or `update.removed` is non-empty. The full path in `present` then clears `_root.textContent`, and `_nodeElement` sets `element.textContent = ''` on every content-hosting element before re-appending all children.
- The finding understates one part. `_nodeElement` also calls `_textNodesById.remove(id)`, so `_setOwnText` creates a brand-new Text node for every node on every structural frame. Text-node identity is therefore not preserved at all, only element identity.

Consequences:
- The log region is aria-live=polite with aria-relevant="additions text". Every structural change anywhere, such as a new log line, a list item, or a toast or dialog opening, presents the whole region's content to the accessibility layer as fresh additions.
- It is also O(tree) DOM churn per structural frame, and structural frames are common on a tailing log.

What I did not verify: the actual announcement with NVDA or VoiceOver. How Blink maps a DOM removal plus re-insertion in the same task onto AX node identity and live-region events is browser- and AT-dependent. Still, remove-and-reinsert inside a live region is the known trigger for re-announcement, so medium severity is fair (accessibility on the browser surfaces: serve and embed). It is not high, because what is shown on screen is correct.

Better fix: keyed child reconciliation inside `_nodeElement`.
- Never clear `_root.textContent` or `element.textContent`.
- Keep the text node per id and update its `.data`.
- For each parent, walk the desired children with a cursor. Call `insertBefore` only when the element at the cursor is not the desired one (the same `orderCursor` pattern `InlineImageOverlay.apply` uses). After the loop, remove any trailing children or stale elements.
- Put the own-text node at a fixed position, before the child elements.
- With this in place the incremental/full split mostly disappears, and an appended log line becomes exactly one insertion.

I removed my probe file. The other untracked _sweep_* files in the worktree belong to other agents.

### [medium] The coverage fallback turns border glyphs (Panel, Dialog, Menu…) into hundreds of junk text nodes and keeps the semantics pipeline on its slow path
`fleury/lib/src/semantics/semantic_coverage.dart:307`, bug, found by the remote finder

**Claim.** `_fallbackCandidateWidth` counts every non-whitespace leading cell as readable text. Panels and other bordered containers are role region, which gives no readable coverage. So box-drawing chrome ('│', '╭────╮', '╰──╯') becomes `__fleury_text_fallback_*` role-text nodes on serve and in the web mirror.

Effects:
- Screen readers and MCP agents get a flood of glyph nodes.
- `_lastCoverageAudit.hasUncoveredText` is permanently true for any bordered app. That disables the retained-output and retained-leaf fast paths (frame_semantics_pipeline.dart:263 and :289).
- `_semanticCoverageRows` then forces a full-screen coverage scan on every flush.

So every visual frame (for example a clock tick) does a full `SemanticTree.fromElement` walk, a full-screen coverage scan and a full diff.

**Reproduction.** 1. Pump `Row([Expanded(Panel(title:'Services', child: Column(12 Texts))), …3 panels])` at 120x40.
2. Run `applySemanticTextFallback(tree: tester.semantics(), buffer: tester.render())`, as the serve/web pipeline does.
3. Separately, drive `FrameSemanticsPipeline` (asserts off) over a ticking clock `Text` plus N `Text` rows, with and without a `Panel` wrapper, and one dirty row per tick.

**Verifier evidence.** Two probes, both deleted afterwards.

**1. Node flood** (fleury_widgets/test/_sweep_verifyremote_2_test.dart, real `Panel` plus `applySemanticTextFallback(tree: tester.semantics(), buffer: tester.render())`):
- Single Panel at 30x6: `real=5 fallback=10`. The fallback nodes are exactly the chrome: `(0,0) 30x1 "╭──…──╮"`, eight 1x1 `"│"` nodes at cols 0 and 29 on rows 1–4, and `(0,5) "╰──…──╯"`.
- 3-panel Row of Expanded Panels (12 Texts each) at 120x40: `real=43 fallback=154`, labels `{╭───…: 1, │: 76, ││: 76, ╰───…: 1}`. This matches the finder's numbers exactly.

**2. Slow path, measured** (fleury/test/_sweep_verifyremote_1_test.dart, run with `dart run` so asserts are off):
- Setup: a real `BuildOwner` + `TuiFrameLoop` + `FramePresentationPlanner` + `FrameSemanticsPipeline` with the fallback on. A clock `Text` plus N static Text rows. One setState tick per frame, then `flushNow`, 200 ticks per run, runs interleaved in both orders, 3 reps.
- Arms: the same tree with or without a core `Semantics(region) > Container(border: BoxBorder(rounded))`. That is Panel's exact chrome, without the FocusDetector.
- 30 rows: 30–140 µs vs 196–277 µs per flush, 66 fallback nodes.
- 60 rows: 27–30 µs vs 172–223 µs, 126 fallback nodes (tree 11→41–87, coverage 0→67–73, diff 11→56–64).
- 300 rows: 124–164 µs vs 814–872 µs, 606 fallback nodes (tree ~54–81→217–263, coverage 2→~300, diff ~65→~295).
- Unbordered, the leaf and retain paths hold: coverage is about 0–3 µs and no fallback nodes appear. Bordered, `hasUncoveredText` stays true every flush, so each tick pays a full `SemanticTree.fromElement`, a full-screen coverage scan and a full diff.
- On serve, run_app.dart:1323 wires the pipeline with `MicrotaskSemanticFlushScheduler`, so this cost lands in the same event-loop task as every frame.

**Proposed fix.** Stop treating decorative glyph-only runs as readable text:
- Exclude Box Drawing (U+2500–U+257F), Block Elements (U+2580–U+259F) and similar ornament ranges from fallback candidacy.
- Or have border-painting widgets emit the existing `semanticExcluded` exclusion-shadow node over their frame cells.
- Base the gating of the retained-output/leaf paths only on fallback text that is actually readable.

**Verifier notes.** **Mechanism confirmed**
- `Panel` wraps its `Container(border:)` in `Semantics(role: region)`. `_providesReadableCoverage` returns false for region, and `_fallbackCandidateWidth` (semantic_coverage.dart:297–314) accepts any non-whitespace leading cell. So every border glyph becomes a `__fleury_text_fallback_*` text node.
- `hasUncoveredText` is then permanently true, which:
  - disables `canRetainSemanticOutput` (frame_semantics_pipeline.dart ~263);
  - disables `canApplyRetainedLeafUpdates` (~289);
  - makes `_semanticCoverageRows` return a full scan.
- The same applies to any bordered, non-readable container: Dialog, Menu, and anything else that uses `BoxBorder` under a structural role.

**Partially pre-known.** docs/audits/2026-09-21-agent-guide-dx.md, finding 2, already notes that `get_ui` spends "a large part of the first model read on border glyphs". It proposes an MCP-only `compact` projection and explicitly avoids weakening coverage. The performance consequence (fast paths disabled for every framed app) is not recorded there and is new.

**Severity lowered from high to medium**
- It is an accessibility/agent noise problem plus a performance cost of about 150–200 µs per semantic flush on realistic 30–60-row screens, and about 0.7 ms at 300 rows.
- It does not crash, lose data or produce wrong terminal bytes. It does not affect the plain terminal path; it affects serve, embed, the web mirror and MCP.
- My absolute numbers are 2–5x lower than the finder's. They probably ran with asserts on; the relative 5–7x blow-up and the node counts reproduce.

**On the fix**
- A Unicode-range exclusion alone is incomplete. The ASCII glyph tier draws borders as `+`, `-` and `|` (basic.dart reads `MediaQuery.glyphTierOf`), and Block Elements also carry meaning in unlabeled gauges.
- Better root cause: have `RenderBorder`/`BoxBorder` painting publish its frame cells as covered-without-text. That reuses the existing `semanticExcluded` shadow-node mechanism (semantics.dart:2064–2083), keyed to the border ring, not the whole box.
- Alternatively, have the coverage pass consult a per-cell "decorative" mark that border paint sets.
- Either way the gating stays correct. The retained-leaf ban exists because fallback labels mirror live buffer text. Once chrome no longer produces fallback nodes, the fast paths re-engage for bordered apps without weakening that invariant.

Probe files were deleted (`git status` shows none).

### [medium] The semantic wire decoder (browser client and MCP bridge) rebuilds the whole tree for every one-node patch; the wire diff saves bytes but not peer CPU
`fleury/lib/src/remote/remote_semantics.dart:879`, perf, found by the remote finder

**Claim.** For every PATCH, `SemanticsWireDecoder.apply` does all of the following:
- copies the full flat map (line 792);
- re-nests every node into fresh maps (`nest`, line 879);
- parses the full `SemanticInspectionSnapshot.fromJson(...).toSemanticTree()` (line 902);
- builds several more O(n) sets and maps.

The serve client then runs an O(tree) `SemanticsOwner.update` diff on the result (wire_frame_source.dart:688). `FleuryAppBridge` decodes every frame even when no agent is reading (app_bridge.dart:592). That contradicts its own comment at lines 83-85 about avoiding a per-frame snapshot rebuild.

The server encodes in O(changed). The peers pay O(tree) per semantically dirty frame, which is 60 Hz for any animating semantic value.

**Reproduction.** Build a status node plus N table rows × 8 cells. Change only the status label each iteration. Time `SemanticsWireEncoder.encodeTree(update)` against `SemanticsWireDecoder.apply` + `SemanticsOwner.update` with `dart run` (asserts off), 200 iterations.

**Verifier evidence.** I wrote a probe and ran it with `dart run`, so asserts were off. It builds a SemanticTree with an app root, a 'clock' status node, and a table of N rows × 8 cells, all with bounds. Each iteration changes only the clock label. Per iteration it runs the server path (`SemanticsOwner.update`, then `SemanticsWireEncoder.encodeTree(t, update:)`) and the client path (`SemanticsWireDecoder.apply`, then `SemanticsOwner.update`). All phases were timed in the same loop: 50 warmup iterations, then the mean of 200.

Every patch was `changedIds=[clock] patch=159B`:

| Nodes | Server owner.update | Server encodeTree | Client decoder.apply | Client owner.update |
| --- | --- | --- | --- | --- |
| 453 | 150 µs | 40 µs | 662 µs | 155 µs |
| 2,253 | 959 µs | 79 µs | 4,615 µs | 1,459 µs |
| 9,003 | 8,502 µs | 177 µs | 35,725 µs | 10,293 µs |

Code trace:
- **`remote_semantics.dart`:** `apply` does `Map.of(_flat)` (line 792). `nest()` then allocates a fresh map for every reachable node. It builds a full `SemanticInspectionSnapshot.fromJson(...).toSemanticTree()` (line ~902), then builds `previousIds` as `_flat.keys.toSet()`, rebuilds the `reachable` map, and does `_flat.clear()`/`addAll`. All of that is O(tree) on every PATCH.
- **`wire_frame_source.dart` (`_presentSemantics`):** runs `_semanticsOwner.update(tree)`, a full-tree diff, even though the decoder already exposes `changedIds`/`removedIds`/`wasFull`.
- **`app_bridge.dart` (`_onFrame`):** calls `_decoder.apply` on every SemanticsFrame, whether or not an agent is reading. The comment at lines 83-85 only makes the snapshot lazy; the full tree is still rebuilt every frame.
- **Cadence:** the wire presenter uses `MicrotaskSemanticFlushScheduler`, so the peer does this work once per semantically dirty frame.

**Proposed fix.** Keep the decoded `SemanticNode` per id and rebuild only the changed nodes and their ancestor path (path copying), reusing unchanged subtrees. Pass the decoder's `changedIds`/`removedIds` directly as the presenter update instead of re-diffing with `SemanticsOwner`. In `FleuryAppBridge`, apply patches to the flat map and materialize the tree lazily when the snapshot is read.

**Verifier notes.** The finding holds, and my numbers match the finder's within noise. The client decode alone costs about 4 to 60 times the server's encodeTree (4-17x on the smaller trees), and more than the server's own O(tree) `owner.update` fallback. The 159-byte patch saves bandwidth but not peer CPU.

Two corrections to the framing:
1. **The server is not always O(changed).** `frame_semantics_pipeline.dart` uses `updateRetainedNodes`, which is O(changed), only when retained leaf updates apply and no coverage-fallback tree is substituted. Otherwise it falls back to `_owner.update`, which is O(tree): 8.5 ms at 9k nodes. The peer is still about 4-5 times worse than even that fallback.
2. **Medium is right, not higher.** Virtualized lists keep typical semantic trees in the hundreds of nodes, which costs about 0.8 ms per frame on the VM client. The cost only becomes large (about 6 ms at 2.2k nodes, 46 ms at 9k) for big non-virtualized tables or trees with heavy coverage fallback. dart2js in the browser will likely be slower; I did not measure it.

Fix direction: the proposed fix is sound, with some refinements.
- **Decoder:** keep a per-id decoded `SemanticNode` and parent links. On a patch, rebuild only the changed nodes and their ancestor path, reusing unchanged subtree objects.
- **Drop the snapshot round-trip:** stop going through `SemanticInspectionSnapshot.fromJson`. Build `SemanticNode`s straight from the normalized flat maps.
- **Reachability and removed ids:** only a structural change (a childIds edit or a root change) needs the full reachability walk. A label-only patch can skip it.
- **Web client:** feed the presenter an update built from `changedIds`/`removedIds`/`wasFull` (using the retained-node style of `updateRetainedNodes`) instead of a full `SemanticsOwner.update`.
- **MCP bridge:** add an apply mode that updates only the flat map and accumulates the delta, and materialize the tree lazily on read. Its validation still needs a cycle/depth check, but that can be limited to structurally touched subtrees.

The probe file is deleted. The other `_sweep_*` files in the tree belong to other agents.

## Low severity, not independently verified (13)

- After a GlobalKey move, descendant render objects keep configuration read from the old position's scopes (`fleury/lib/src/widgets/framework.dart`)
- A Row's cross-axis intrinsics ignore flex allocation, so IntrinsicHeight around Expanded wrapping text reports too little height and drops lines (`fleury/lib/src/rendering/render_flex.dart`)
- No SGR reset on entry or re-entry: ESC[2J and unstyled text inherit whatever attributes the terminal already had (`fleury/lib/src/terminal/terminal_sequences.dart`)
- The full-repaint screen clear is written outside the DEC 2026 synchronized-update block (`fleury/lib/src/terminal/ansi_frame_presenter.dart`)
- Semantic ids are sanitized lossily on the wire, so actions on ids derived from keys with control characters always come back notFound (`fleury/lib/src/semantics/inspection.dart`)
- buildDataTableRowOrder re-tokenizes the filter query (RegExp split) once per row (`fleury_widgets/lib/src/data_table.dart`)
- An open debug panel never goes idle: it renders 2 frames every ~1.2 s forever while the app is idle (`fleury/lib/src/debug/debug_panel.dart`)
- TextInput walks the whole value's graphemes 5–7 times on every caret move and keystroke (`fleury/lib/src/widgets/text_input.dart`)
- A keyed ListView calls itemKeyBuilder for every item on every wrapper rebuild, so MessageList pays O(messages) per arrow key (`fleury/lib/src/widgets/list_view.dart`)
- Undo history keeps a full copy of the document for every non-typing edit, capped only by count (200) (`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/widgets/text_input.dart`)
- `fleury serve --spawn` on a busy port crashes with an unhandled SocketException and leaks /tmp/fleury-spawn-*  (`fleury/bin/fleury.dart`)
- Serve client bundle is sent as 403 KB uncompressed, no-store, and base64-decoded on every request, including every reconnect reload (`fleury/bin/fleury.dart`)
- `fleury create .` always fails ("\".\" is not a valid Dart package name") even in a validly named empty directory (`/Users/dan/Coding/fleury/.claude/worktrees/sweep-2026-09-23/fleury/lib/src/cli/create_command.dart`)

