# Pre-launch bug audit — 2026-07-17

**Scope:** full framework at `main` HEAD (81bc5ab, post PR #116) — all 8 packages, ~130k lines.
**Method:** 20 finder agents (16 subsystem beats + 4 cross-cutting lenses) → dedup → adversarial batch verification → independent second skeptic on every confirmed P1 lacking a repro → completeness critic + known-open-item status sweep. 56 agents, ~8.8M tokens across two windows.
**Baseline:** `check` fully green (analyze + tests + dart2js) and all 7 perf gates pass — i.e. **none of the findings below are caught by the existing suite**; every fix should land with a pinning test.

## Verdict summary

**62 confirmed findings: 0 P0 · 19 P1 · 26 P2 · 17 P3.** 12 were empirically reproduced by an agent running a failing repro at HEAD. All 14 independent second votes confirmed (5 with fresh reproductions by the second skeptic).

Confidence tiers: P1s are double-confirmed (or repro-backed) — treat as fact. P2/P3 carry a single adversarial-batch confirmation — high probability, but re-verify the trace when picking one up.

No finding leaves the terminal broken or destroys data at rest in a default configuration — the July teardown/restore hardening (PRs #96–#116) held: that entire failure class is absent. The bug surface is concentrated in five clusters: **GlobalKey reconciliation**, **focus/input edge paths**, **process/task lifecycle**, **fleury_widgets data entry**, and **error-reporting black holes**.

## P1 findings (19)

### Framework core — GlobalKey reconciliation cluster
1. **framework.dart:1896** [REPRO] — GlobalKey child wrapped in place within a multi-child parent: the stolen element stays in the reconcile's `keyedOlds`, gets deactivated out of its new home, State disposed, next rebuild crashes (`no render object`). *Fix: mirror Flutter's `_forgottenChildren` set (or re-check `identical(el._parent, this)`) in the leftover-cleanup and keyed-match paths.*
2. **framework.dart:596** [REPRO] — Reclaiming a GlobalKey nested inside an already-deactivated subtree double-deactivates it: assert crash in debug; in release the moved subtree goes permanently deaf to InheritedWidget changes. *Fix: guard `_deactivateRecursively` on `_lifecycle == active` (Flutter's `_InactiveElements.add` guard).*
   Related P2/P3 in the same cluster: spurious duplicate-GlobalKey StateError across two passes of one flush (framework.dart:1236); duplicate key nested under a new sibling bypasses every check → silent two-position corruption (framework.dart:1856). **One PR fixes all four.**

### Layout / rendering
3. **basic.dart:948** [REPRO] — ConstrainedBox re-breaks min≤max after the parent-min re-clamp → impossible constraints crash layout under `Expanded`/stretch. *Fix: re-raise max to min after the re-clamp (parent's tight bound wins), cols and rows.*
4. **render_repaint_boundary.dart:295** [REPRO] — Paint-only updates that shrink/move content leave stale ghost cells: `diffBounds` never covers vacated cells. *Fix: damage the union of previous and new cache bounds.*

### Focus / input
5. **focus.dart:374** — ExcludeFocus doesn't release focus already held inside the excluded subtree — typing keeps flowing into the hidden pane; programmatic focus into excluded subtrees also succeeds. *Fix: on marker register/update, drop focus held under the marker; deny requestFocus into excluded subtrees.*
6. **focus.dart:510** — `requestFocus` on a node whose Focus widget unmounted focuses a dead node: every keypress throws StateError **and the Ctrl+C exit guard is bypassed**. *Fix: clear `node._element`/`_manager` on the normal unregister path so dead nodes no-op per their own doc.*
7. **samples/bin/samples.dart:47** — Advertised **'q' quit never works in any sample app** (printables arrive as TextInputEvent, not KeyEvent — the known dual-consumer trap, in the launch demos and the teaching snippets). *Fix: widget-level KeyBinding('q') → requestExit(), scoped so a focused prompt still types 'q'; fix file_manager.dart:257 snippet + website examples too. Do NOT match TextInputEvent in onEvent (would exit while typing).*

### Terminal / remote / semantics
8. **posix_driver.dart:1059** [REPRO] — Startup probe replies leak into app input as a phantom **Shift+F3** whenever reply RTT exceeds ~150ms — i.e. any slow SSH session. *Fix: unambiguous per-exchange probe sentinel (tagged DA request or counted replies); drain through the last expected reply.*
9. **remote_driver.dart:171** — Warm-standby pre-spawned app **self-destructs after 10s** (enter()'s INIT timeout fires while idle), silently defeating the cold-start optimization. *Fix: explicit wait mode (`FLEURY_REMOTE_WAIT=supervised`) — serve-supervised spawns wait unbounded / arm timeout on first transport activity.*
10. **frame_semantics_pipeline.dart:274** [REPRO] — Retained-leaf semantic flush ships a stale tree (release) or throws the divergence StateError (debug) when a non-SemanticsElement contributor changes in the same frame as a leaf text update. *Fix: contributor state changes must `recordStructureDirty()` (DataTable, FleuryApp, CommandScope contributors), or enforce via a SemanticContributor hook.*

### Process / task lifecycle (effects/)
11. **process_task.dart:104** — `ProcessTaskController.dispose()` never kills the running child (verified live child after dispose). *Fix: dispose kills via cancel signal.*
12. **process_task.dart:161** — Any non-normal `ProcessStartMode` always fails the task and permanently orphans the just-spawned child. *Fix: pipe stdio only for connected modes or reject unsupported modes before spawning; spawn inside try/finally.*
13. **task.dart:206** [REPRO] — Restarting a running task makes cancellation unobservable to the superseded run: cooperative runners become CPU zombies; restart during the spawn window leaks an unkillable process. *Fix: `isCancellationRequested => !_isCurrent(_runId) || _cancelRequested`; track process per-run and kill stale-run spawns.*

### Animation
14. **animation.dart:232** — `TickerMode(enabled: false)` is silently ignored by Animation/AnimationBuilder — hidden subtrees keep animating and rebuilding. *Fix: resolve TickerMode + AnimationPolicy at subscribe and on dependency change; set `_ticker.muted`.*

### fleury_widgets — data entry & agent shell
15. **form.dart:1382** [REPRO] — FormPanel decimal fields **silently corrupt input: typing "1.5" submits 5** (in-progress "1." is force-rewritten). *Fix: don't rewrite number fields while focused / while text parses to the current value or is a valid in-progress token.*
16. **date_picker.dart:216** [REPRO] — Backward month/year paging lands in the wrong year (PageUp from January jumps 11 months forward; '[' is a no-op for Feb–Dec). *Fix: let `DateTime(y, m+delta, 1)` normalize; add backward-paging tests.*
17. **file_picker.dart:116** — Entering an unreadable/just-deleted directory throws uncaught PathAccessException → error banner + corrupted state. *Fix: mirror FileBrowser's FileSystemException handling; commit cwd/entries only on success.*
18. **message_list.dart:342** [REPRO] — A streamed append silently re-engages followTail after the app disengaged it, yanking the viewport to the tail mid-read. *Fix: preserve selection without the follow-coupling, or defer sync to the post-frame count-refresh path.*
19. **log_region.dart:177** — `jumpToIndex` is reverted on the next rebuild (viewport snaps back to the old selection). *Fix: move selection with the jump via non-coupling write (PatchReview pattern) or persist the jump anchor.*

## P2 (26) and P3 (17) — one-liners

**Terminal robustness:** unterminated bracketed paste now captures ALL input forever incl. Ctrl+C — idle-flush recovery was removed in the recent churn with no fallback (input_parser.dart:160, regression); DA-probe stall discards keystroke backlog incl. Ctrl+C in scripted/CI PTYs (posix_driver.dart:491); second Fleury session in one process crashes at enter() (posix_driver.dart:342); horizontal wheel misdecoded as vertical / extended buttons as clicks (input_parser.dart:642); ESC aborting an in-progress CSI is swallowed → next escape report becomes typed text (input_parser.dart:401).

**runApp error black holes:** build() errors never reported anywhere (run_app.dart:584); post-mount startup-buffer overflows leave runApp's future permanently unresolved and swallow the error (run_app.dart:1260, :1298); post-exit async errors silently discarded (run_app.dart:1277); FrameSemanticsPipeline.dispose strands awaitIdle() futures (frame_semantics_pipeline.dart:372).

**ListView cluster:** permanently blank after controller swap w/o itemCount change (list_view.dart:473, :487); leaks mounted item elements from anchor-probe/pre-jump walks (list_view.dart:1337); unbounded height silently renders nothing (list_view.dart:1274).

**Serve/web/MCP:** browser resize blanks the grid for a full RTT (wire_frame_source.dart:329); ExcludeSemantics defeated on serve — coverage fallback re-exposes excluded text to agents/AT (semantic_coverage.dart:110); MCP bridge misreads oversized payload as "app exited" and SIGTERMs the healthy app (app_bridge.dart:326); late action result attributed to the next action (app_bridge.dart:451); failed initial connect leaves serve page stuck at "connecting…" (remote_client.dart:16); DomRowFactory CSS caches grow without bound (dom_row_factory.dart:20); MCP set_value accepts impossible dates, widget silently normalizes (value_schema.dart:158).

**Rendering/wide-glyph:** inline-image placement severs wide-glyph pairs → row garble on probed-narrow terminals (cell_buffer.dart:697); clipped scratch blits spill a CJK continuation past the clip edge (render_effect.dart:245).

**fleury_widgets data:** NaN datapoint throws and replaces Sparkline/BarChart/Histogram/Heatmap with an error box (sparkline.dart:256); DiffView misparses deletions starting with `--`/`++` (diff_view.dart:206); LineChart deletes segments touching out-of-range points and can hang painting (line_chart.dart:1060); markdown plainText replaces styled spans with literal `$1` — corrupts semantic labels (markdown_text.dart:1322); CalendarHeatmap breaks across DST fall-back (calendar_heatmap.dart:531); scrollback trim shifts a scrolled-up reader's selection (terminal_output_region.dart:11).

**Framework/animation/testing:** ChangeNotifier invokes listeners removed during the same notify pass (change_notifier.dart:49); retarget-on-settling-tick snaps instead of animating (animation.dart:388); FleuryTester.renderToString drops overlay cells → image goldens encode wrong geometry (fleury_tester.dart:553); mutating tester.viewportSize mid-test leaves MediaQuery stale (fleury_tester.dart:766); FrameBuilder interval change resumes ticking inside muted subtree (frame_builder.dart:91); TextInput blink-config change while focused can freeze the cursor invisible (text_input.dart:772); key sequences with a printable continuation never complete while a text field is focused (input_dispatcher.dart:234).

**Security-adjacent (P3 but review):** readline kill ring stores password-field plaintext in a process-wide buffer yankable into any visible field (text_editing.dart:324).

**Apps:** `storybook help` opens the TUI instead of usage (storybook.dart:442); StorybookApp crashes on empty stories (storybook_app.dart:92); `fleury shell` with non-TTY stdin crashes unclean, leaving a stale handle (fleury.dart:319).

Full detail for every finding (failure scenarios, evidence, fix sketches, verifier reasoning): **2026-07-17-prelaunch-bug-audit-full.json** alongside this file.

## Known pre-freeze items — status sweep

| Item | Status |
| --- | --- |
| IME caret positioning | **FIXED** (PR #109 — CUP trailer repositions hardware cursor) |
| Inline-mode stub | **FIXED** (PR #89 removed the unimplemented `TerminalMode.inline`) |
| OSC 8 gating | **FIXED** — conservative allow-list shipped + `FLEURY_HYPERLINKS` override (not the garbage-probe) |
| Embed overlay (browser-embed error banner) | **OPEN** |
| Wire-protocol doc | **FIXED** (`docs/implementation/wire-protocol.md`, normative) |
| SIGTSTP/SIGCONT (F7) | **FIXED** (PR #73) |
| F11 — positional semantic-id churn on raw wire action path | **OPEN** |
| README animation example | **FIXED** (PR #99) |
| Perf-gate non-prod config blind spot | **PARTIAL** |

## Structural gaps (completeness critic — verified probes)

1. **`dart pub publish --dry-run` FAILS for the core package** — `lib/src/testing/fleury_tester.dart:38` imports `package:test/test.dart` (a dev-context package) from published lib code. **Release blocker if launch includes publishing.**
2. **Windows is half-shipped:** a real 549-line FFI `windows_driver.dart` exists and auto-selects on Windows, but CI is ubuntu-only, zero tests, no stated support policy; remote/serve/MCP stack is structurally POSIX-only. Decide + state the policy before launch.
3. **Boot under standard PTY automation crashes:** expect-style spawns leave pty winsize 0×0 → Dart reports `stdout.hasTerminal == false` → misdiagnosed "stdout looks piped or redirected" error. For an agent-first framework this breaks the core story. Fix: treat isatty-true + 0×0 winsize as a real terminal (poll/SIGWINCH for size).
4. **getting-started.mdx snippets are outside the compile-checked snippet harness** — the most-trafficked page is unguarded (currently correct).

## Suggested fix batches (audit-batch PR pattern)

| Batch | Contents | Why first |
| --- | --- | --- |
| A — release mechanics | pub publish failure; getting-started snippet fixture | blocks/protects launch itself |
| B — framework core | GlobalKey cluster (4 findings, one PR) | double-repro'd core crashes — **re-verified live at HEAD 2026-07-17** (both P1 repros fail post-#103; #103 fixed a third, different steal case) |
| C — focus & input | focus.dart pair, dispatcher sequences, samples 'q' | Ctrl+C bypass + broken demos — **IMPLEMENTED 2026-07-17** (+5th bug found: DataTable/Tree type-ahead swallowed printables → additive `typeahead` flag; navigator pop focus-restore now post-frame by contract) |
| D — process lifecycle | effects/ 3×P1 + task.dart:394 | agent-story credibility — **IMPLEMENTED 2026-07-17** (detached start modes now rejected by contract) |
| E — serve/remote/MCP | warm-standby, semantics pipeline, awaitIdle, ExcludeSemantics leak, MCP bridge pair | second surface + privacy |
| F — data entry | FormPanel decimal, DatePicker, FilePicker, NaN charts | visible data corruption — **IMPLEMENTED 2026-07-17** (FilePicker `initialDirectory` contract: error row instead of throw) |
| G — terminal robustness | probe phantom key, bracketed-paste regression, DA-stall, second-session, ESC-abort | SSH/CI users |
| H — rendering | ghost cells, wide-pair severing, clip spill, resize blank | visual correctness |
| I — agent shell | MessageList/LogRegion tail pair, scrollback selection | streaming UX |
| J — error observability | run_app black holes ×4 | debuggability |
| Decisions | Windows policy, PTY winsize, embed overlay, F11 | policy calls |
