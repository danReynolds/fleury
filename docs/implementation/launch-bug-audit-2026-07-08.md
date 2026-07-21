# Launch-hardening bug audit (2026-07-08)

**Status:** Findings report (no code changes in this pass)  
**Date:** 2026-07-08  
**Tree:** branch `fleury-main-sync` (behind `origin/main` by 7 commits at audit start)  
**Purpose:** First-principles bug audit of Fleury’s launch-critical surfaces against the **current tree**, with live re-runs of health gates. Not a restatement of planning audits (`launch-hardening-audit.md`, `mvp-completion-audit.md`, etc.) — those were used only as context for the launch bar.

## Launch bar used for severity

From MVP / cut-list docs:

- **In bar:** robust reactive TUI, example demo path, terminal I/O on POSIX, text editing/input, semantics + serve/remote as shipped, `dart tool/fleury_dev.dart check`, perf gates.
- **Out of bar (deferred, not invent-as-bugs):** full Windows real-TTY matrix, extended multi-terminal matrix, `fleury_acp`, full replay/devtools, public launch collateral, plugin ecosystem.

Severity guide:

| Level | Meaning |
| --- | --- |
| **blocker** | Launch claim cannot honestly be made until fixed or scope narrowed. |
| **high** | Likely user-visible failure on a launch path (TTY, SSH, demo, default serve). |
| **medium** | Real defect or race; impact narrower, intermittent, or gated on less common configs. |
| **low** | DX / edge consistency / hardening polish. |
| **note** | Observation, intentional tradeoff, or stale-doc correction. |

---

## Executive summary

The local launch stack is **functionally green after dependency bootstrap**: full `check` exit 0, demo and widgets suites green, integration green (job-control PTY cases skipped without opt-in), and fast perf gates green. That is **not** the same as “no launch bugs.”

The highest-value defects are **wiring and lifecycle holes** that headless happy-path suites systematically miss or only partially cover:

1. **OSC 52 clipboard is broken under default POSIX fd-capture** (SSH copy path).
2. **Layout-time deactivation can delay or skip `State.dispose`.**
3. **Dirty-queue / `_dirty` invariant breaks after flush abort**, permanently stranding rebuilds.
4. **SIGTSTP restore is not exclusive of frame writes** the way editor handoff is.
5. **Serve spawn has no session cap and INIT has no timeout** — process DoS if serve is shared.

None of these invent product features; they are defects or gaps in already-shipped launch paths.

### Priority-ordered must-fix list

| P | ID | Title | Severity |
| --- | --- | --- | --- |
| P0 | F6 | OSC 52 clipboard goes to captured stdout, not the real TTY | high |
| P0 | F1 | Layout-time deactivation may never run `State.dispose` | high |
| P0 | F2 | `flushBuild` abort permanently strands dirty elements | high |
| P0 | F7 | SIGTSTP suspend does not suppress frame writes | high |
| P0 | F8+F9 | Serve spawn: no session cap; no INIT handshake timeout | high (if serve shared) |
| P0 | Ops | `check` fails without `bootstrap` (git `stdio` dep) | high (ops) |
| P1 | F5 | Runtime dispose does not drain inactive subtrees | medium |
| P1 | F3 | Duplicate sibling keys orphan live elements | medium |
| P1 | F4 | Input can re-enter the tree mid-frame | medium |
| P1 | F10 | Ambiguous-width probe can paint main screen in inline mode | medium |
| P1 | F11 | Semantic action IDs churn for unkeyed widgets (serve AT) | medium |
| P1 | F13 | CR and LF each become Enter (no CRLF collapse) | medium |
| P1 | F14 | HTTPS reverse-proxy same-origin always assumes `http://` | medium |
| P1 | F15 | Debug wire default-on over serve in non-product builds | medium |
| P2 | F12 | Windows `clip` fed UTF-8; expects UTF-16LE | medium (Windows deferred) |
| P2 | — | Windows signal / Quick Edit parity gaps | coverage / deferred platform |

---

## Baseline health (re-run evidence)

| Check | Result | Notes |
| --- | --- | --- |
| `dart tool/fleury_dev.dart check` **without** bootstrap | **FAIL** exit 3 | `package:stdio/stdio.dart` URI does not resolve |
| `dart tool/fleury_dev.dart bootstrap` | OK | Pulls git dep `stdio` into package config |
| `dart analyze` in `packages/fleury` after bootstrap | No issues | |
| `dart tool/fleury_dev.dart check` after bootstrap | **PASS** exit 0 | Includes analyze-all-packages, unit suites, integration, asset freshness, dart2js smoke |
| fleury unit (`dart test -x integration`) | **1978 passed** | |
| fleury_widgets full suite | **932 passed** | |
| fleury_example_console | **26 passed** | |
| integration tag (standalone) | **23 passed, 2 skipped** | Skips need `FLEURY_PTY_JOB_CONTROL=1` on a real controlling terminal |
| embedded client asset freshness | **PASS** | Comments in `tool/fleury_dev.dart` still call this “chronic red” — **stale vs this tree** |
| `dart tool/fleury_dev.dart benchmark gates` (fast suite) | **all pass** | serve-semantics-gate, image-bench, bundle-size, alloc-gate. Heavier `wire-gate` / `serve-wire-live` are **not** auto-run |

---

## Surfaces reviewed

| Surface | Primary paths |
| --- | --- |
| Reactive runtime / reconcile | `packages/fleury/lib/src/widgets/framework.dart`, `runtime/tui_runtime.dart`, `tui_frame_loop.dart`, `frame_driver.dart`, `frame_scheduler.dart` |
| Layout / paint | `widgets/layout_builder.dart`, `rendering/render_object.dart`, `cell_buffer.dart`, `ansi_renderer.dart` |
| Terminal I/O | `terminal/posix_driver.dart`, `windows_driver.dart`, `native_driver.dart`, `input_parser.dart`, `capabilities.dart`, `terminal_probe.dart` |
| Editing / input | `editing/text_editing.dart`, `widgets/text_input.dart`, `text_area.dart`, `key_bindings.dart`, `runtime/input_dispatcher.dart`, `system_clipboard.dart` |
| Semantics / remote / serve | `semantics/*`, `remote/*`, `bin/fleury.dart` serve path, web remote client as serve consumer |
| Demo / widgets | `packages/fleury_example_console/**`, `packages/fleury_widgets/**` (via suite + selective source) |

---

## Assumption validation

| # | Assumption | Verdict | Justification |
| --- | --- | --- | --- |
| A1 | Headless tests adequately proxy real-TTY safety | **UNKNOWN / partial** | Fake driver + unit signal tests are strong. Real PTY integration exists (`test/integration/pty_run_app_test.dart`) and boots / resize / SIGINT / SIGTERM / restore **passed** in this audit. **Job-control** (SIGTSTP/SIGCONT, editor handoff) is **skipped** unless `FLEURY_PTY_JOB_CONTROL=1` on a real controlling terminal — not proven in this run. Windows real-TTY is deferred by product decision. |
| A2 | Dispose / lifecycle cannot leave corrupt or stuck state | **FAIL** | Layout-time deactivate finalization only runs at end of `flushBuild` (not after layout); idle frame skip can leave inactive elements undead. Flush-abort clears dirty queue without healing `_dirty`. Duplicate sibling keys can orphan live elements. Runtime dispose unmounts only the root. See F1, F2, F3, F5. |
| A3 | Wire / semantics protocol is stable under representative frames | **PASS with caveats** | Integration + transport parity + serve semantics gate green; payload/size clamps present. Caveats: protocol skew is warn-only on client; unkeyed semantic ids are snapshot-local; no INIT handshake deadline; spawn unlimited sessions. See F8–F11. |
| A4 | Perf gates and `fleury_dev check` are green when re-run | **PASS** (after bootstrap) | Full check exit 0; fast gates all pass. **Pre-bootstrap check fails** on git dep `stdio` — operational hazard for clean clones / CI without bootstrap. |
| A5 | Default `runApp` on POSIX TTY restores terminal and does not corrupt frames with stray output | **PASS (mostly)** | PTY tests assert restore sequences on SIGINT/SIGTERM/crash-containment; fd-capture design is sound for frames. **Clipboard OSC 52 is the exception** (F6). |
| A6 | Serve path is production-hardened against hostile peers | **PARTIAL FAIL** | Grid clamp, payload cap, origin policy, bridge single-session, backpressure: solid. Spawn multi-session DoS, missing INIT timeout, optional token off-loopback (warn only), debug wire default-on in non-product builds: remaining launch risk for shared/exposed serve. |
| A7 | Input parser recovers from malformed input | **PASS** | Deterministic suite + seeded fuzz (amplification bounds) present in `input_parser_test.dart` — supersedes older “zero fuzz” claim in `test-quality-assessment.md` (that doc is stale on this point). |
| A8 | Demo / example path is launch-ready | **PASS** | 26 demo-console semantic journey tests green; widgets suite green. Residual: semantic id stability for unkeyed widgets under serve AT (F11). |

---

## Findings (priority ordered)

Findings are ordered by launch priority (P0 first), then severity within band. Each entry includes: severity, title, evidence, assumption challenged, first-principles rationale, classification, and recommended fix direction.

---

### P0 — Must fix or re-prove before launch claims

---

#### F6 — OSC 52 clipboard writes go to captured stdout, not the real TTY

| Field | Detail |
| --- | --- |
| **Severity** | **high** |
| **Priority** | P0 |
| **Class** | Confirmed wiring bug |

**What happens**

On POSIX with a real TTY, `runApp` starts fd-level stdout/stderr capture (`package:stdio`) so stray `print` / native writes cannot corrupt the rendered frame. Frame bytes correctly go through the terminal driver (the saved real-terminal handle). The default clipboard does not.

Default construction is bare `SystemClipboard()` with no `stdoutWrite` override. That class defaults OSC 52 emission to `stdout.write` — the **captured** descriptor. Under SSH, platform tools (`pbcopy` / `xclip` / …) are deliberately skipped so they do not copy on the remote machine; OSC 52 is then the **only** path to the user’s local clipboard. That path is swallowed as “stray output” and only replayed after the app exits (useless for clipboard).

**Evidence**

- `packages/fleury/lib/src/runtime/run_app.dart` — fd capture start and driver wiring (~291–311); default clipboard `SystemClipboard()` (~702–706).
- `packages/fleury/lib/src/runtime/system_clipboard.dart` — `_stdoutWrite = stdoutWrite ?? stdout.write` (~19–26); OSC 52 emit (~101); SSH skips platform tools (~46–52, 117–120).
- Frames correctly use `_DriverSink` → `driver.write` (`run_app.dart` sink classes; `posix_driver.dart` `write`).

**Assumption challenged**

“Any stdout-bound escape (OSC 52) under default `runApp` reaches the user’s terminal.”

**First-principles rationale**

Clipboard is a launch-critical user action (selection copy, log copy, table copy). Local macOS often masks the bug via `pbcopy`. Remote SSH sessions get a silent false success: the write report can claim `osc52` while the host clipboard never updates. That is worse than a hard failure — users trust copy that did not work.

**Recommended fix**

Construct `SystemClipboard(stdoutWrite: usedDriver.write)` (or equivalent terminal-handle write) when fd capture is active. Add a regression that asserts OSC 52 bytes are **not** delivered as stray-output capture lines under fd-capture, and that they do reach the driver write path.

---

#### F1 — Layout-time deactivation may never run `State.dispose` until a later build (or never on idle exit)

| Field | Detail |
| --- | --- |
| **Severity** | **high** |
| **Priority** | P0 |
| **Class** | Confirmed lifecycle bug + coverage gap |

**What happens**

Flutter-style inactive-element bookkeeping deactivates children into `BuildOwner._inactiveElements`, then permanently unmounts leftovers via `_finalizeInactiveElements`. Finalize runs **only at the end of `flushBuild`**.

`LayoutBuilder` rebuilds its child **during layout** via `updateChild` inside `RenderLayoutBuilder.performLayout`. That path can deactivate a stateful subtree **after** the current frame’s build flush has already finished. `BuildOwner.renderFrame` order is:

1. `flushBuild` (finalize happens here for *this* pass’s inactive set — empty for layout-time deactivations that have not happened yet)
2. layout (LayoutBuilder may deactivate here)
3. paint  
   — **no post-layout finalize**

If the app then goes idle — no dirty builds, no visual dirt — `FrameDriver` **skips** the next frames entirely and never calls `flushBuild`. Inactive elements sit forever. `TuiRuntime.dispose` unmounts only the mounted root and never drains `_inactiveElements`.

**Evidence**

- `packages/fleury/lib/src/widgets/layout_builder.dart` — layout-time builder / `updateChild` (~104, 189–213).
- `packages/fleury/lib/src/widgets/framework.dart` — `_deactivateChild` / `_inactiveElements` (~496–504); `_finalizeInactiveElements` only from `flushBuild` (~1184, 1197–1203); `renderFrame` build → layout → paint (~1275–1310).
- `packages/fleury/lib/src/runtime/frame_driver.dart` — no-change skip path does not flush (~304–313).
- `packages/fleury/lib/src/runtime/tui_runtime.dart` — dispose unmounts root only (~124–130).

**Assumption challenged**

“Deactivated elements are always unmounted at end of the same frame / on shutdown.”

**First-principles rationale**

`dispose` is the contract for releasing focus nodes, tickers, stream subscriptions, controllers, and file/process handles. A constraint-driven swap (resize, sidebar collapse, responsive layout) that replaces a stateful child can leave those resources alive across idle and past “clean” exit. Headless tests often mask this because every `tester.render()` / interaction forces another `flushBuild`.

**Recommended fix**

Finalize inactive elements after layout (or at end of `renderFrame`) **and** on runtime dispose. Tests: LayoutBuilder child type/key swap → assert `dispose` same frame or immediately after one idle skip; runtime dispose with pending inactive set.

---

#### F2 — `flushBuild` abort permanently strands dirty elements

| Field | Detail |
| --- | --- |
| **Severity** | **high** |
| **Priority** | P0 |
| **Class** | Confirmed bug (recovery hole) |

**What happens**

The dirty-queue invariant is: an active element with `_dirty == true` is in `_dirtyElements` (or will rebuild this pass). Two abort paths break that:

1. **Convergence cap** (`_maxBuildPasses = 512`): clears `_dirtyElements`, then throws `FleuryError`, **without** clearing each element’s `_dirty` flag.
2. **Mid-pass throw**: the set is snapshotted and cleared, then each element `rebuild()`s. `rebuild` clears `_dirty` only when it *starts* that element. If `performRebuild` throws, remaining snapshot members keep `_dirty == true` but are no longer in the set.

`markNeedsBuild` short-circuits when `_dirty` is already true, so stranded elements **never re-enqueue**. `reassembleApplication` only calls `markNeedsBuild`, so hot reload cannot heal them either.

**Evidence**

- `packages/fleury/lib/src/widgets/framework.dart` — flush loop and cap (~1149–1182); `markNeedsBuild` (~683–688); `rebuild` clears `_dirty` before `performRebuild` (~701–707).

**Assumption challenged**

“Failing a flush is recoverable on the next frame / hot reload.”

**First-principles rationale**

Fail-loud on rebuild storms is correct. Permanently freezing parts of the tree afterward is not. Launch symptom: “app stopped updating after an error / after a bad frame,” while the session may still show a backstop or partial UI and accept input that no longer rebuilds the broken subtrees.

**Recommended fix**

On abort: either clear `_dirty` on every still-dirty active element, or re-enqueue survivors; ensure reassemble forces rebuild of stranded nodes. Tests: max-pass storm recovery; mid-snapshot throw then later `setState` / reassemble still rebuilds remaining elements.

---

#### F7 — SIGTSTP suspend does not suppress frame writes (handoff does)

| Field | Detail |
| --- | --- |
| **Severity** | **high** |
| **Priority** | P0 |
| **Class** | Confirmed race / incomplete teardown symmetry |

**What happens**

Editor handoff (`runWithTerminalHandoff`) sets `_handoffActive = true` and `write()` becomes a no-op while the terminal is restored for a child process. SIGTSTP (`_suspend`) writes exit sequences, restores cooked mode, flushes, then re-raises the stop signal — **without** setting `_handoffActive` or any equivalent write gate. The frame loop can still call `write()` between “restore” sequences and the process actually stopping.

**Evidence**

- `packages/fleury/lib/src/terminal/posix_driver.dart` — handoff sets `_handoffActive` (~417); `write` no-ops when handoff active (~525–528); `_suspend` has no write gate (~388–398); `_suspend` is async without a single-flight guard (re-entrancy under signal storms).
- Job-control PTY tests exist (`test/integration/pty_run_app_test.dart`) but skip unless `FLEURY_PTY_JOB_CONTROL=1` — **not re-proven in this audit environment**.

**Assumption challenged**

“Ctrl+Z restore is exclusive of app output the way editor handoff is.”

**First-principles rationale**

Job control is a daily TUI habit. Interleaved frame + restore sequences leave the shell with mouse tracking, Kitty keyboard protocol, alt-screen, or hidden cursor still partially on. That is the classic “my shell is broken after Ctrl+Z” failure mode and destroys trust in the framework on first real use.

**Recommended fix**

Make suspend single-flight and write-exclusive (reuse `_handoffActive` or a dedicated suspend gate). Cancel/coalesce in-flight frames. Re-run PTY job-control tests on a real controlling terminal and keep the evidence.

---

#### F8 — Serve spawn mode has no concurrent-session cap

| Field | Detail |
| --- | --- |
| **Severity** | **high** (when serve is shared or bound beyond loopback) |
| **Priority** | P0 for exposed serve; P1 for loopback-only demos |
| **Class** | Confirmed hardening gap |

**What happens**

`fleury serve --spawn` pairs each browser WebSocket with a full app subprocess (warm standby + cold fallback). There is no `maxSessions`, rate limit, or admission queue. Tests explicitly allow multi-browser isolation.

**Evidence**

- `packages/fleury/bin/fleury.dart` — `_runServeSpawn` claims warm standby and spawns per `/ws` (~974–1018).
- `packages/fleury/test/remote/serve_spawn_test.dart` — concurrent browsers / independent subprocesses.

**Assumption challenged**

“Serve multi-user is safe to bind beyond loopback once token/origin are set.”

**First-principles rationale**

Anyone who can open `/ws` (and know the token, if set) can open hundreds of sockets and spawn hundreds of Dart VMs. Warm-standby replenish multiplies cost. Classic launch DoS for “share this URL” demos.

**Recommended fix**

Hard cap concurrent sessions (with clear rejection), optional rate limit, and document capacity. Default conservative caps on non-loopback binds.

---

#### F9 — No INIT / handshake timeout on remote driver

| Field | Detail |
| --- | --- |
| **Severity** | **high** (multiplies F8) |
| **Priority** | P0 for exposed serve; P1 for loopback-only |
| **Class** | Confirmed bug (missing deadline) |

**What happens**

`RemoteTerminalDriver.enter` awaits `_handshake!.future` with **no timeout**. Disconnect fails the handshake; silence does not. Spawn times out connect-to-socket (~10s) but not INIT. A peer that connects and never sends INIT leaves `runApp` blocked in enter indefinitely.

**Evidence**

- `packages/fleury/lib/src/remote/remote_driver.dart` — unbounded `await _handshake!.future` (~135–147).

**Assumption challenged**

“A connected peer will complete the handshake or drop.”

**First-principles rationale**

Combined with F8: open many WS connections, never send INIT → N hung app processes. Warm standbys already wait for INIT by design; a silent client turns every claim into a permanent leak until process kill.

**Recommended fix**

Bounded INIT deadline; fail closed (BYE / destroy session / free slot). Tests for silent peer and slow peer.

---

#### Ops — `check` does not bootstrap; clean trees fail analyze on git `stdio`

| Field | Detail |
| --- | --- |
| **Severity** | **high** (operational / CI) |
| **Priority** | P0 process |
| **Class** | Confirmed toolchain footgun |

**What happens**

`packages/fleury` depends on git-hosted `stdio` for fd capture. `dart tool/fleury_dev.dart check` runs `dart analyze` without ensuring `pub get` / bootstrap. On a clean or stale package config, analyze reports `Target of URI doesn't exist: 'package:stdio/stdio.dart'` and aborts check before tests.

**Evidence**

- Pre-bootstrap: check exit 3 on `run_app.dart` import of `package:stdio/stdio.dart`.
- Post-`bootstrap`: analyze clean; full check exit 0.
- `packages/fleury/pubspec.yaml` — `stdio` git dependency; `tool/fleury_dev.dart` — separate `bootstrap` vs `check` commands.

**Assumption challenged**

“`fleury_dev check` is a self-contained health gate on a fresh clone.”

**First-principles rationale**

Launch gates that fail for the wrong reason train people to ignore them or skip bootstrap. CI and contributor onboarding must either auto-bootstrap or fail with an explicit “run bootstrap” message before analyze.

**Recommended fix**

Auto-run bootstrap (or at least `pub get` for packages with unresolved git deps) at the start of `check`, or detect missing package config entries and print a hard error naming `bootstrap`.

---

### P1 — Should fix soon (launch polish / secondary paths)

---

#### F5 — Runtime dispose does not drain inactive / stranded subtrees

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 (P0 when fixed with F1) |
| **Class** | Confirmed lifecycle bug (compounds F1) |

**What happens**

`TuiRuntime.dispose` / tester dispose unmount the active root only. There is no `BuildOwner` path that finalizes leftover `_inactiveElements` at shutdown.

**Evidence**

- `tui_runtime.dart` dispose (~124–130); no `_finalizeInactiveElements` on dispose.

**Assumption challenged**

“Disposing the runtime tears down every once-mounted `State`.”

**First-principles rationale**

Even if F1 is narrowed so idle frames eventually flush, process exit must not rely on luck. Hosts that reuse isolates or embed multiple sessions need a definitive teardown.

**Recommended fix**

Drain inactive elements (and assert no stranded dirty) in runtime dispose; share the same helper as F1’s post-layout finalize.

---

#### F3 — Duplicate sibling keys orphan live elements

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 |
| **Class** | Confirmed bug (app-error handling) + coverage gap |

**What happens**

Multi-child reconcile partitions old children into a `Key → Element` map. On duplicate keys in the **old** list, later entries overwrite earlier ones. Leftovers only deactivate `keyedOlds.values` — the overwritten first element is neither matched nor deactivated. It stays “active” with live `State` but drops out of the parent’s child list. GlobalKey dual-mount has debug asserts; local key collisions do not.

**Evidence**

- `packages/fleury/lib/src/widgets/framework.dart` — partition (~1542–1550); leftover deactivate (~1598–1606); GlobalKey asserts (~136–149, ~1062–1074).

**Assumption challenged**

“Keyed multi-child always unmounts every old child.”

**First-principles rationale**

Duplicate keys are a common app author bug. The framework’s job is fail-loud (or at least dispose both). Silent orphans leak State and can leave dangling render participation until the whole runtime dies.

**Recommended fix**

Debug assert on key collision while partitioning; deactivate *all* old elements that are not claimed (e.g. track discarded overwrites). Test: two children with the same `ValueKey`, then rebuild without them → both dispose.

---

#### F4 — Input / sequence-timeout can re-enter the tree mid-frame

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 |
| **Class** | Confirmed design hole (race) |

**What happens**

`FrameDriver` tracks `inFrameRender` for error classification only. Nothing gates input dispatch on it. `InputDispatcher` sequence timeout uses a raw `Timer` that calls into plain key dispatch. `runApp` dispatches driver events and schedules frames without a “wait until not rendering” lock.

**Evidence**

- `frame_driver.dart` — `inFrameRender` usage (~187–190, 323–373).
- `input_dispatcher.dart` — sequence timeout timer (~416–431).
- `run_app.dart` — event dispatch / schedule (~843–894).

**Assumption challenged**

“Build / layout / paint is non-reentrant with respect to input and binding handlers.”

**First-principles rationale**

A 500 ms sequence timeout (or a dense event burst) can fire while build/layout/paint runs, invoking focus/key handlers that `setState`, mutate focus, or touch render objects mid-pass. That races dirty queues, focus attachment, and layout-time `LayoutBuilder` updates — classic hard-to-repro TUI corruption under real typing speed and chords.

**Recommended fix**

Queue input until frame end, or ignore / defer sequence timeouts while `inFrameRender`. Prefer a single “input epoch” per frame. Tests that force timeout during a long paint.

---

#### F10 — Ambiguous-width probe can paint the main screen in inline mode

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 |
| **Class** | Confirmed bug (missing mode gate) |

**What happens**

The ambiguous-width probe writes home cursor, a sample glyph, CPR, and erase. Probe documentation assumes the alternate screen. `_maybeProbeAmbiguousWidth` only guards TTY + raw stdin — **not** `mode.alternateScreen`. `TerminalMode.inline` keeps the main buffer.

**Evidence**

- `terminal_probe.dart` — probe sequences / alt-screen expectation.
- `posix_driver.dart` — `_maybeProbeAmbiguousWidth` guards (~311–332).
- `terminal_driver.dart` — `TerminalMode.inline` (`alternateScreen: false`).

**Assumption challenged**

“Startup probes are invisible / confined to the alternate screen.”

**First-principles rationale**

Inline / scrollback-preserving apps can flash a probe glyph or leave cursor artifacts on the user’s real buffer before the first frame. That looks like a broken app on first boot.

**Recommended fix**

Skip or confine the probe when not on the alternate screen; document the env override path.

---

#### F11 — Semantic action IDs churn for unkeyed demo widgets

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 for serve/AT demo claims |
| **Class** | Confirmed product risk + partial intentional deferral |

**What happens**

When widgets do not supply stable keys / explicit semantic ids, ids fall back to snapshot-local forms (`element-$hashCode` or positional `auto:…`). Rebuilds, filters, and list mutations renumber positional identities. Wire and agents activate by id.

**Evidence**

- `packages/fleury/lib/src/semantics/semantics.dart` — id assignment / positional helpers (~1277–1306, ~986–996).
- Demo-heavy widgets often wrap `Semantics` without keys (e.g. command palette rows in `fleury_widgets`).
- Related RFC: `rfc-stable-semantic-ids-and-setvalue.md` (direction exists; not universal in widgets).

**Assumption challenged**

“Served sessions stay stably operable through the a11y tree across frames.”

**First-principles rationale**

Serve’s differentiator is structured semantics. If filtering a palette renumbers nodes, screen readers and agents activate the wrong control or get `notFound`. Explicit keys/ids fix it; launch demos must actually provide them on interactive nodes.

**Recommended fix**

Key/id interactive demo widgets used under serve; expand conformance tests for id stability across filter/sort rebuilds. Do not claim AT/agent stability for unkeyed trees.

---

#### F13 — CR and LF each become Enter (no CRLF collapse)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 for Windows / serial / mixed PTY interop |
| **Class** | Confirmed interop bug (partially mitigated by bracketed paste) |

**What happens**

In ground state, `0x0D` **or** `0x0A` each emit a separate Enter key. Tests codify this. There is no “CR then ignore following LF” state. Bracketed paste avoids double-enter for pastes only.

**Evidence**

- `packages/fleury/lib/src/terminal/input_parser.dart` (~145–147).
- `packages/fleury/test/terminal/input_parser_test.dart` (~55–57).

**Assumption challenged**

“Enter is always a single logical key across hosts and transports.”

**First-principles rationale**

Some Windows, serial, and PTY paths still deliver `\r\n`. Double Enter → double submit / double newline in composers and forms. Launch demos that look fine on macOS Terminal can misbehave when piped or run under foreign line endings.

**Recommended fix**

CRLF collapse state machine; keep tests for lone CR, lone LF, and CRLF as single Enter.

---

#### F14 — TLS reverse-proxy same-origin check always assumes `http://`

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 for HTTPS deployments |
| **Class** | Confirmed operational footgun |

**What happens**

WebSocket origin policy builds the same-origin string as `http://${requestHost}` only. A browser on `https://host` is scheme-mismatched and rejected unless `--allow-origin=https://…` is set. Integration tests intentionally reject scheme mismatch.

**Evidence**

- `packages/fleury/bin/fleury.dart` — `_isAllowedWebSocketOrigin` (~764–771).
- Serve integration tests for scheme-mismatched origins.

**Assumption challenged**

“Same-origin works for the public URL scheme the browser uses.”

**First-principles rationale**

Production launch behind Caddy/nginx HTTPS often fails first paint/WS with opaque 403s. Operators must discover `--allow-origin`. Fail-closed is correct; silent scheme hard-coding is not.

**Recommended fix**

Infer scheme from `X-Forwarded-Proto` / config, or require explicit allow-origin with a clearer error page when same-origin fails only on scheme. Document HTTPS as a first-class path.

---

#### F15 — JIT debug surface is on by default over the serve wire (non-product builds)

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P1 for shared LAN demos |
| **Class** | Confirmed footgun (intentional local-dev default) |

**What happens**

`DebugConfig` defaults enabled when not compiled with `dart.vm.product`. When enabled, `runApp` answers debug requests over the serve wire with frames, logs, and full error stacks. Token is optional; non-loopback only **warns**.

**Evidence**

- `debug_state.dart` — default enabled when not product.
- `run_app.dart` — debug request wiring (~612–630).
- `bin/fleury.dart` — non-loopback warning without token (~452–463).

**Assumption challenged**

“Serve demos don’t export internal diagnostics unless production-hardened.”

**First-principles rationale**

Trust model already says WS owns the app UI. Debug adds log/error/stack exfiltration for typical `dart run` demos without explicit opt-in. LAN “share this URL” demos are exactly that path.

**Recommended fix**

Default-off debug over wire off-loopback; require token or explicit `--debug-wire` for remote debug. Keep local-dev convenience on loopback.

---

### P2 — Deferred-platform or lower urgency

---

#### F12 — Windows `clip` path feeds UTF-8; `clip` expects UTF-16LE

| Field | Detail |
| --- | --- |
| **Severity** | **medium** |
| **Priority** | P2 under current cut-list (fix before any Windows launch claim) |
| **Class** | Confirmed encoding bug |

**What happens**

Windows platform tool is `clip` with empty args. `_defaultRunTool` writes text via Dart stdin (UTF-8). Windows `clip` historically expects UTF-16LE on stdin. ASCII may work; CJK/emoji/non-Latin selection commonly corrupts.

**Evidence**

- `packages/fleury/lib/src/runtime/system_clipboard.dart` (~127–128, 154–169).

**Assumption challenged**

“Platform tool path preserves arbitrary Unicode on Windows.”

**First-principles rationale**

Clipboard correctness is user-visible on day one of any Windows claim. Until then this is a real defect parked under deferred Windows validation — not a free pass forever.

**Recommended fix**

Write UTF-16LE (with or without BOM as required by the tool path) or use a documented Windows API path; add encoding tests.

---

#### Related Windows lifecycle gaps (not separate F-ids; deferred platform)

| Gap | Detail |
| --- | --- |
| No SignalEvent / grace-period path on `WindowsTerminalDriver` | POSIX wires SIGINT/SIGTERM + grace force-exit; Windows relies on key hatch for Ctrl+C. External terminate can kill without full restore. |
| Quick Edit mode not cleared | Classic conhost footgun: click-drag freezes input until Enter. |
| Low unit coverage | Documented (~13% historically); real validation needs Windows CI. |

These are **incomplete platform parity**, not stubs that crash on import. Track under Windows validation plan; do not block POSIX launch.

---

### Additional medium findings from serve/input review (keep on radar)

These were validated against the tree during the audit; priority is P1–P2 depending on whether serve/agents are in the launch claim.

| ID | Severity | Title | Summary |
| --- | --- | --- | --- |
| F16 | medium | Concurrent semantic actions are fire-and-forget | `unawaited` invoke + schedule without serialization (`run_app.dart` ~578–609). Overlapping AT/agent activations can dual-submit. **Fix:** queue/mutex one action at a time. |
| F17 | medium | `SignalEvent` is a first-class wire INPUT_EVENT | Peer can synthesize terminate. Inside WS-trust model this is intentional host power, but untested on remote path and easy session kill. **Fix:** policy gate or document + test. |
| F18 | medium | Protocol skew is warn-only | Client `console.warn`s version mismatch; still interprets frames. Partial deploy → corrupt UI. **Fix:** hard-fail or force resync on major skew. |
| F19 | medium | Oversized frame length clears whole decoder buffer; browser may stay connected | Server/transport may close; browser client logs and resyncs without always closing — can look hung. **Fix:** close unrecoverable sessions. |
| F20 | medium | Inline-image cache is count-capped (512), not byte-budgeted | Hostile/buggy flood of large distinct images → browser memory pressure. **Fix:** byte budget + eviction. |
| F21 | medium | Startup probes drop keystrokes when DA never arrives | No DA terminator → no replay of probe-window input (`posix_driver.dart` ~335–348). **Fix:** safer timeout replay policy or document. |
| F22 | medium | Paste during IME composition drops composition base without cancel | `text_input.dart` paste path nulls composition base without `cancelComposing()`. Serve/browser IME + paste. **Fix:** cancel composition before bulk insert. |
| F23 | low | Word movement ignores selection-collapse semantics used by arrow movement | `moveWordLeft/Right` vs `moveLeft/Right` inconsistency in `text_editing.dart`. |
| F24 | low | `setState` during dispose soft-fails | Mutation runs; rebuild no-ops if inactive; element null only after dispose finishes. DX noise. |
| F25 | low | Process-global `GlobalKey` registry vs multi-runtime hosts | Registry is static; runtimes otherwise isolated. Document or scope per owner. |
| F26 | note | `FrameScheduler.dispose` does not cancel pending delayed Timer | Safe if callback hardened; minor teardown footgun. |
| F27 | note | OSC 52 has no tmux passthrough; images do | Env-dependent degradation; secondary to F6. |

---

## Coverage and test gaps that hide risk

| Gap | Why it matters |
| --- | --- |
| No test: LayoutBuilder replaces stateful child → assert `dispose` same frame / after idle skip | Hides F1 |
| No test: `flushBuild` throw mid-snapshot → later `setState` / reassemble still rebuilds | Hides F2 |
| No test: duplicate sibling `ValueKey` → both dispose | Hides F3 |
| No test: input during `inFrameRender` | Hides F4 |
| No test: OSC 52 lands on **driver** terminal handle under fd-capture | Hides F6 |
| Job-control PTY opt-in only (`FLEURY_PTY_JOB_CONTROL=1`) | Hides F7 in CI |
| No remote INIT timeout / spawn session-cap tests | Hides F8/F9 |
| No remote `SignalEvent` policy tests | Peer kill path untested |
| Windows driver signals / Quick Edit / clip encoding | Deferred platform, low coverage by design |
| Capability-matrix widget rendering under degraded profiles | Still a gap (see `test-quality-assessment.md` T5) |
| Heavier gates (`wire-gate`, `serve-wire-live`) not in auto `benchmark gates` | Not green-claimed by this audit |

### Stale documentation corrections (from this re-verify)

| Prior claim | Current tree |
| --- | --- |
| Asset-freshness is a “chronic red” (`tool/fleury_dev.dart` comments) | **Passed** on this tree |
| Input parser has zero fuzz (`test-quality-assessment.md`) | **Has** seeded fuzz + amplification bounds |
| No PTY integration tests (older quality plan T1) | **Exists** `test/integration/pty_run_app_test.dart` (job-control still opt-in) |

---

## Intentional deferred scope (not filed as launch blockers)

From cut-list / MVP audits — **do not treat as bugs unless the launch bar expands**:

- Full Windows real-TTY matrix and Windows validation packets (except: fix F12 before claiming Windows).
- Extended terminal matrix (iTerm2, Kitty, Ghostty, Alacritty, WezTerm, SSH matrix claims).
- `fleury_acp`, full replay/devtools, public launch collateral.
- Plugin ecosystem; broad a11y claims beyond current semantic/keyboard surface.
- Wire scroll optimizations already measured and accepted where deferred.

---

## Prioritized launch recommendations

### Must fix or re-prove before launch (POSIX TUI + example + default serve)

1. **F6** — Wire OSC 52 through the driver’s terminal stdout (or inject `stdoutWrite: usedDriver.write`). Regression under fd-capture.
2. **F1 + F5** — Finalize inactive elements after layout **and** on runtime dispose. LayoutBuilder + idle skip + dispose tests.
3. **F2** — Heal dirty-queue invariant on flush abort; recovery / reassemble tests.
4. **F7** — Single-flight SIGTSTP + write exclusivity. Re-run PTY with `FLEURY_PTY_JOB_CONTROL=1` and keep evidence.
5. **If serve is a launch surface beyond loopback demos: F8 + F9** — max concurrent sessions + INIT handshake deadline; fail closed.
6. **Ops** — document/require `bootstrap` before `check`, or auto-bootstrap git deps so clean clones do not fail for the wrong reason.

### Should fix soon (not necessarily day-0 if scope is local demo only)

- F3 duplicate-key assert + deactivate-all  
- F4 serialize input vs frame  
- F10 gate ambiguous-width probe on alternate screen  
- F11 key/id demo widgets used under serve AT  
- F13 CRLF collapse in input parser  
- F14 infer scheme or document HTTPS `--allow-origin` as mandatory with clearer errors  
- F15 disable or token-gate debug wire off-loopback  
- F16 serialize semantic actions  
- F18 hard-fail protocol skew on major mismatch  

### Can wait (tied to deferred scope)

- F12 Windows clip UTF-16 and Windows signal / Quick Edit gaps  
- Extended terminal matrix, public collateral, ACP, full replay  
- Auto-running heavy `wire-gate` / `serve-wire-live` on every audit (run before public perf claims)  
- Coverage floors in CI (process gap, not a product crash)

---

## What this audit is not

- Not a re-baselining or loosening of perf gates  
- Not a rewrite of prior May–June planning audits  
- Not an exhaustive line-by-line of every package file  
- Not Windows real-TTY validation  
- Not implementation of fixes (report only)

---

## Related docs

| Doc | Role |
| --- | --- |
| [launch-hardening-audit.md](launch-hardening-audit.md) | Planning-time scope / deferral decisions (2026-05-31) |
| [mvp-completion-audit.md](mvp-completion-audit.md) | MVP completeness and deferred list (2026-06-02) |
| [cut-list.md](cut-list.md) | Scope cut guardrails |
| [test-quality-assessment.md](test-quality-assessment.md) | Coverage methodology (partially stale; see corrections above) |
| [serve-production-readiness.md](serve-production-readiness.md) | Serve hardening narrative; this audit re-checks residual gaps |
| [perf-gates.md](perf-gates.md) | Gate inventory |
| [Claude.md](../../Claude.md) / CLAUDE.md | Dev/check/gate commands |

---

## Evidence snapshot (2026-07-08 re-run)

```
bootstrap                         OK
analyze packages/fleury           No issues (post-bootstrap)
fleury_dev check                  EXIT 0
fleury unit (-x integration)      1978 passed
fleury_widgets                    932 passed
fleury_example_console            26 passed
integration                       23 passed, 2 skipped (job control)
asset freshness                   passed
benchmark gates (fast)            all pass
  - serve-semantics-gate
  - image-bench
  - bundle-size
  - alloc-gate
wire-gate / serve-wire-live       not auto-run this pass
```
