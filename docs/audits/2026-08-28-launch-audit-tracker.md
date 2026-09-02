# Launch audit tracker — 2026-08-28

**Scope:** full framework at `danreynolds/fleury-launch-bug-audit-618d54`, covering the ~267 commits since the 2026-07-17 audit.
**Method:** 15 area auditors (one per infrastructure area / feature) → 102 findings → **14 independent verification agents that re-derived every finding from the code**, with authority to refute, re-grade in either direction, and correct the original's reasoning. Fixes were compiled or reproduced where cheap.
**Verification outcome:** 13 severities moved, 6 claims refuted or materially corrected, 4 new findings surfaced that no auditor was looking for.
**Baseline:** as in July — none of this is caught by the existing suite. Every fix should land with a pinning test, and §D explains why the suite missed them.

Full findings with issue / impact / fix reasoning: <https://claude.ai/code/artifact/7ee62f0a-afd8-44c4-b3d1-c1b2a8acd3a3>

---

## How this is triaged

| Bucket | Meaning | Count |
| --- | --- | --- |
| **[A] Do now** | Clear cause, contained fix, low regression risk. Land these in batched PRs without further discussion. | 43 |
| **[B] De-escalated** | Real, but narrow, or needs a product call not worth making pre-launch. Parked with a stated reason. | 27 |
| **[C] With you** | Genuinely hard, architecturally central, or a decision that is yours. Do not start solo. | 24 |
| **[D] Process** | Why the suite missed all of this. Not bugs; the reason they recur. | 5 |

Severity is the **verified** severity. `↓`/`↑` marks a grade the verification pass moved; `✎` marks a finding whose claim was corrected or partly refuted — read the note before acting, because in several cases the original's stated trigger does not reproduce.

---

## [A] Do now — clear and contained

### A1 · Docs that do not compile *(one PR; all fixes compile-verified)*

- [x] **1.c** `P0` README quick start passes a zero-arity closure to `onTrigger` — `packages/fleury/README.md:48`, `coming-from-flutter.md:56`
  **Fix:** `onTrigger: (_) => setState(...)`. Consider generating this block from the compiled `example/counter_quickstart.dart` so it cannot drift again.
  **Notes:** LANDED (A1, merged c1832be0). README fence now byte-mirrors example/counter_quickstart.dart, pinned by a parity test.

- [x] **1.d** `P0` `fleury_themes` teaches a `runApp` parameter that does not exist — README:9, `lib/fleury_themes.dart:9`, `registry.dart:2144`, `registry.dart:3470`
  **Fix:** `FleuryApp(title:, theme:, home:)` with both imports. Four sites move together. Strike `runApp` from the adjacent prose list.
  **Notes:** LANDED (A1). All four sites → FleuryApp form. fleury_themes dartdoc built from fleury_core (the package web-safety guard greps lib/ for the umbrella import).

- [x] **16.d** `P0` ↑ Both testing quick starts construct `KeyEvent` with named params it lacks — `README.md:124`, `testing.md:107`
  **Fix:** `const KeyEvent(KeyCode.char(' '))` / `const KeyEvent(KeyCode.enter)` — matches the mirror test verbatim.
  **Notes:** LANDED (A1).

- [x] **16.c** `P1` ✎ Theming guide's three `FleuryApp` snippets omit required `title:` — `theming.mdx:38,168,221`
  **Fix:** add `title:`. **Must update `theme_source_parity_test.dart` in the same commit** — it compares strings and currently pins the broken line, so fixing the guide alone turns it red. (Refuted side-claims: the `file=` attribute naming a nonexistent file is by design; a parity test does exist.)
  **Notes:** LANDED (A1), parity test moved in the same commit.

- [x] **11.f** `P2` Loading-data guide's error pattern raises a spurious error banner — `loading-data.mdx:44`, `registry.dart:3603`
  **Fix:** don't assign an already-failed future; defer the throw or attach a no-op handler. Terminal-only — the web demo has no guarded zone, so the banner never showed there.
  **Notes:** LANDED (A1). CORRECTION: Future.sync does NOT fix this (measured); Future.delayed does. The compiled doc_snippets mirror had the same bug.

- [x] **15.new** `P3` Hot-reload guide still teaches the superseded argv workaround — `hot-reload.md:53`
  **Fix:** replace with `runApp(args: args)`.
  **Notes:** LANDED (A1).

### A2 · Packaging

- [x] **16.f** `P2` Publish validation fails on an undeclared `collection` import — `packages/fleury/pubspec.yaml`
  **Fix:** add to `dev_dependencies`. Separately decide whether `test/`/`tool/`/`benchmarks` should ship at all (1 MB tarball).
  **Notes:** LANDED (A1): publish dry-run now 0 warnings.

- [x] **16.h** `P3` Three changelogs will publish every breaking rename under "Unreleased"
  **Fix:** rename headings to `## 0.1.0`, fold the stubs in. Also decide export-or-delete on 6 zero-reference exported symbols.
  **Notes:** LANDED (A1) + a changelog-leads-with-pubspec-version guard.

### A3 · Floats and overlays *(6.a/6.f share one barrier change)*

- [x] **6.d** `P1` ColorPicker hex popover is transparent and spans the full terminal height — `color_picker.dart:618`
  **Fix:** `Container.framed` + `mainAxisSize: MainAxisSize.min`. Pair validated on an equivalent tree (12-row transparent → 4-row opaque). Assert row count and interior opacity, not just that "Hex" appears.
  **Notes:** LANDED (A3).

- [x] **6.e** `P1` Autocomplete dropdown is transparent — `autocomplete.dart:314`
  **Fix:** `Container.framed`; pad short rows to panel width if leakage persists. **Extend `overlay_opacity_test.dart` to all 7 floats** — it covers 5, and the 2 it misses are exactly the 2 that leak.
  **Notes:** LANDED (A3); overlay_opacity_test now covers all 7 floats.

- [x] **6.a** `P1` `present()` has no pointer barrier — clicks fall through, even with `barrierColor` — `navigator.dart:829`
  **Fix:** `AbsorbPointer` over the whole route slot, mirroring `select.dart:212`. Reaches the flagship flow — a click behind an open CommandPalette fired a `DELETE ALL` button. ⚠ One decision inside an otherwise-clear fix: should the barrier carry `onTap: maybePop` when `barrierDismissible`? That changes a documented flag's meaning — flag it in the PR rather than deciding silently.
  **Notes:** LANDED (A3, merged f5d60c84): AbsorbPointer over the whole modal slot, every modal route. Barrier has NO onTap — Esc stays the only dismissal; click-outside is Q9.

- [x] **6.f** `P2` Menu has no pointer barrier and no click-outside dismiss — `menu.dart:121,376`
  **Fix:** same barrier. Land with 6.a; better, factor one shared float wrapper — only 2 places in the repo use `AbsorbPointer` at all.
  **Notes:** LANDED (A3) via a shared AnchoredFloat (exported) used by Select and Menu; submenus stay bare on purpose. Also fixed a PRE-EXISTING bug the barrier made routine: closing a menu from outside the chain stranded the submenu focus trap (keyboard on no node).

- [x] **6.b** `P2` ↓ Two adjacent `SubMenu` rows throw on selection move — `menu.dart:589`, `bounds.dart:68`
  **Fix:** per-row notifier wrapped unconditionally (also kills per-keystroke widget-type churn), or move `claimWriter` to first paint. **Assert-gated** — `dart run` is correct, only `dart test` breaks, so this is DX severity. Also null-guard `_BoundsObserverElement.unmount`, which turns one failure into two.
  **Notes:** LANDED (A3): option (a) per-row notifiers (also kills per-keystroke widget-type churn) + RenderObjectElement.maybeRenderObject null-guard in unmount. Genuine double-writer still throws, once.

- [x] **6.h** `P3` Dead `_selfBounds` observer on every menu panel — `menu.dart:274`
  **Fix:** delete — unless 6.f wants it for the click-outside barrier, in which case wire it there.
  **Notes:** LANDED (A3).

- [x] **12.d** `P2` The Popup removal dropped chrome selection semantics — `which_key.dart:128`
  **Fix:** `SelectionArea.disabled` on the which-key popup, **and on the other six floats** — they are currently saved only by accident of mounting through an overlay. Add a drag-and-copy test per float.
  **Notes:** LANDED (A3): all 7 floats state SelectionArea.disabled. CommandPalette leaked too when composed inline (not presented).

### A4 · Widgets

- [x] **9.b** `P1` DatePicker arrows stuck / off-by-one across DST — `date_picker.dart:236` (+7 sites)
  **Fix:** `DateTime(y, m, d + n)` — normalizes rollover for free and always returns local midnight. Simpler than porting the heatmap's UTC helper. Normalize `_emit` unconditionally. Regression test under a DST zone (harness exists). Up/−7 misfires too, not just Down.
  **Notes:** LANDED (A4, merged 1f0fde18): calendar-lattice stepping, 8 sites, emit normalized to midnight.

- [x] **9.d** `P2` LineChart throws on a degenerate range ≥ 2^53 — `line_chart.dart:886`
  **Fix:** widen degenerate ranges multiplicatively; add a non-finite guard before `.round()` to close the class. Guard belongs on the resolved range — three consumers share the division. Contained by the error boundary today, so not a crash.
  **Notes:** LANDED (A4): multiplicative pad + non-finite guard. Kept the x-axis asymmetry (a lone point sits at the left edge); centring x is a visible change → decide.

- [x] **10.b** `P2` ✎ Completion popups sized by code-unit length; options vanish — `completion_text_input.dart:330`, `autocomplete.dart:276`
  **Fix:** measure with `widthOfText` under the ambient policy (3 in-tree precedents). Trigger is **BMP wide chars only** — astral emoji size correctly, so this is CJK/Kana/Hangul/fullwidth, not "emoji in branch names".
  **Notes:** LANDED (A4): widthOfText + clamp to surface width + one-row ellipsis.

- [x] **8.f** `P2` `CodeView`/`JsonView` throw under unbounded height — `code_view.dart:514`, `json_view.dart:640`
  **Fix:** `maxVisible` + `SizedBox` wrap, matching `TreeTable`/`FileBrowser`. Document the bound. Separately, make the diagnostic name the enclosing widget rather than the internal `ListView`.
  **Notes:** LANDED (A4): maxVisible default 12 (matches TreeTable/FileBrowser).

- [x] **8.d** `P2` ✎ Scrollbar records buffer-local geometry; drag mapping wrong in a repaint boundary — `scrollbar.dart:282`
  **Fix:** one line — `(screenOffset ?? offset).row`. Lone outlier among 3 correct siblings; its own doc comment cites the idiom it doesn't follow. ScrollView case is conditional (only breaks off-origin). Test all 3 composition shapes.
  **Notes:** LANDED (A4).

- [x] **8.e** `P3` ↓ Activating the newest message re-arms follow-tail — `message_list.dart:403`
  **Fix:** delete the unreachable `followTail = false`. Behaviour matches the documented coupling contract — the dead line is the defect, not the outcome.
  **Notes:** LANDED (A4): dead lines deleted; pinned via the notification flap. NOTE: MessageListController.jumpToIndex has the same dead pattern (message_list.dart:155-166).

### A5 · Input, runtime, rendering

- [x] **2.b** `P1` Auto-repeat both advances and cancels sequences — `input_dispatcher.dart:1339,1368`
  **Fix:** treat a repeat on the pending path as a no-op that neither advances, completes, nor cancels. **Both** halves of the RFC rule fail; the cancel half is the one users hit (which-key's "press and pause"). Open: should a repeat extend the timeout? Leaving it is the literal reading and the smaller change.
  **Notes:** LANDED (A5, merged 3fa7dbb9). includeRepeats on a multi-step binding now asserts at construction (it was a silent no-op). Also covered the InputBatch call site.

- [x] **11.c** `P1` `Animation.dispose` never unregisters its reassemble callback — `animation.dart:261,394`
  **Fix:** cache the tear-off in a field (the pattern `frame_ticker.dart:54` already uses). Measured 200/200 retained vs 0/200 for FrameTicker. Slow leak — a few hundred bytes each, no per-frame cost. Add a structural count so this class can't recur a third time.
  **Notes:** LANDED (A5) + TickerScheduler.reassembleCallbackCount + Animation.debugDependentCount.

- [x] **12.b** `P2` `ConstrainedBox` bound changes after mount are ignored — `basic.dart:1046`
  **Fix:** private fields + `markNeedsLayout()` setters. **Land before 12.c** — the central fix cannot work without these setters existing. Only render object in the package with bare mutable layout config.
  **Notes:** LANDED (A5).

- [x] **12.e** `P3` Debug-invalidation labels allocated eagerly on every invalidation — `framework.dart:854`, `render_object.dart:932,957,970`
  **Fix:** pass a thunk / check `hasListeners` at the call site, as the doc already promises. Measured 20–50×. Should *improve* `alloc-gate` — and see D3 for why the gate didn't catch it.
  **Notes:** LANDED (A5): call-site guard (DebugInvalidations.isRecording). alloc-gate did NOT move — it only sums package:fleury classes, so dart:core Strings are invisible to it (see D3). Measured 520 ns → 1.6 ns.

- [x] **7.c** `P3` Dead `styleResetRequired` gates three unreachable branches — `ansi_renderer.dart:263`
  **Fix:** delete, or set it where intended and add the test that would have caught it dead.
  **Notes:** LANDED (A5): variable, 3 branches, resetFirst param and the leading-0 param all deleted; 400-pair diff corpus byte-identical.

- [x] **5.g** `P3` ✎ Default selection wrap rebuilds the full string per mouse event — `selection_area.dart:244`
  **Fix:** early-return when no callback. Note: `selection-gate` never constructs a `SelectionArea`, so this **cannot** move the gate (see D3).
  **Notes:** LANDED (A5).

- [ ] **4.e** `P2` `FLEURY_AMBIGUOUS_WIDTH` disables the entire probe battery — `posix_driver.dart:624`
  **Fix:** narrow the guard to its own axis. ⚠ **Sequence with 4.a** — this env var is the accidental workaround for 4.a, so fixing it alone exposes 4.a to operators who had escaped it.
  **Notes:** HELD — do not land before 4.a (this env var is 4.a's accidental workaround; alone it exposes the P1).

- [x] **4.g** `P3` ✎ `OutputCaptureView` pads/truncates by UTF-16 code unit — `output_capture_view.dart:231`
  **Fix:** measure in cells — or drop string padding and get opacity from a real background fill, which removes the problem rather than fixing it. (Surrogate-split concern refuted: the resolver drops lone surrogates.)
  **Notes:** LANDED (A5): cell-measured helpers through the display projection (a background fill was not viable — the header is a CellStyle, the fill takes a Color).

- [x] **3.d** `P3` ↓ ✎ "Restored while negotiating" guard is dead — a null-check throws first — `posix_driver.dart:417`
  **Fix:** hoist the guard above the probe block; add the scripted test RFC 0021 §12 already names. (Secondary stray-byte claim did **not** reproduce.)
  **Notes:** LANDED (A5): _checkStillEntering between every probe await; _negotiateKeyboard/_restoreLegacyKeyboard made null-safe.

### A6 · Serve and web

- [x] **14.a** `P2` ✎ Meta regime leaves a key permanently held after auto-repeat — `dom_input_source.dart:292`
  **Fix:** synthesize the release after a repeat too (`!= KeyEventType.up`) — 2 lines, replayed clean. Worse than reported: the key's bindings then stop firing for the session, and two occurrences permanently demote the whole session to press-only. Open: narrow the branch to macOS?
  **Notes:** LANDED via A6 merge (fbd46015): Meta-regime repeat also synthesizes its release. Not narrowed to macOS UAs (small payoff, off-macOS Super+key is WM-swallowed anyway).

- [x] **14.b** `P2` Ctrl/⌘+wheel and pinch-zoom swallowed over the whole page — `dom_input_source.dart:665`
  **Fix:** early-return before `preventDefault()` when `ctrlKey`/`metaKey`. Non-passive listener confirmed by measurement in Chrome.
  **Notes:** LANDED via A6 merge (7d12b957): ctrl/meta + wheel returns before preventDefault and the accumulator.

- [x] **14.e** `P2` ↑ Clicking outside the grid silently kills all keyboard input — `serve_index_html.dart:35`, `dom_input_source.dart:81`
  **Fix:** host-level (served page: document-level) listener that only re-establishes capture; drop the host's now-pointless `tabindex="0"`, which just makes it a focus sink. All three blur routes verified with real clicks.
  **Notes:** LANDED via A6 merge (83e58a0f): host-level pointerdown recapture + document-level under captureKeyboardFromDocument (serve only); host loses tabindex. 4 tests incl. end-to-end in remote_client_runner_test.

- [x] **14.d** `P2` ✎ Every `pointermove` becomes an app mouse event — `dom_input_source.dart:583`
  **Fix:** dedupe against the last emitted tuple (include modifiers); clear on button/metrics change. ✎ Cost claim corrected: semantics flush is coalesced to **frame** rate, not pointer rate — the real cost is wire traffic and dispatch. Honouring a motion opt-in is a separate, larger question.
  **Notes:** LANDED via A6 merge (6d153ca5): same-cell pointermove dedup keyed on kind/cell/buttons/modifiers/MeasuredCellBox identity; cleared on press/release/cancel.

- [x] **14.g** `P3` `FrameSurface.capabilities` has a test but no reader — and already lies — `frame_presentation.dart:25`
  **Fix:** delete the member, its class and the defaults test. Not public API. It already reports `supportsSemanticLinks: false` while rendering real anchors — the standard argument that an unread field lies.
  **Notes:** LANDED via A6 merge (2141e422): WebSurfaceCapabilities deleted; boundary test scans lib/ for the identifier.

- [x] **14.f** `P3` DPR change with no CSS resize never invalidates cell metrics — `dom_cell_metrics.dart:78`
  **Fix:** resolution media-query listener (re-armed) or device-pixel content box, routed into the existing dirty signal.
  **Notes:** LANDED via A6 merge (7abb76e3): matchMedia(resolution) listener re-armed at each new ratio → metrics dirty; torn down on dispose.

- [x] **13.g** `P3` Transport `close()` not await-idempotent on the graceful path — `unix_socket_transport.dart:269`
  **Fix:** cache the graceful teardown future like the abort paths do. Reachable via the handshake-fuse path.
  **Notes:** LANDED via A6 merge (00315b50): close() => _closeFuture ??= _close(), so every concurrent caller shares one teardown; real unix-socket test, red before.

- [x] **13.h** `P3` Semantics encoder's documented reconnect contract has no caller — `remote_semantics.dart:484`
  **Fix:** call it where a driver begins a session (idempotent-cheap), or narrow the doc and assert reuse is unsupported.
  **Notes:** LANDED via A6 merge (edba38a7): encoder reset at enter(); injectable encoder makes the contract observable (stale encoder → NO frame at all for a new peer). Adjacent: RemoteTerminalDriver cannot truly re-enter (_handshakeReceived never reset).

- [x] **13.new** `P2` Hitting the session cap gives a blank page with no message — `bin/fleury.dart:1250`
  **Fix:** reject after the upgrade with a close reason the client can display. Same family as 13.d — fix in that pass.
  **Notes:** LANDED via A6 merge (7d53ed57): over-cap connection is upgraded then closed with 4001 + reason naming --max-sessions (1013 is reserved by dart:io); client shows the server reason. 13.d can reuse the code + banner.

### A7 · Dead API removal *(one sweep, pre-freeze)*

- [x] **2.g** `P3` `FocusManager.dispatchKey` — public, tested, no caller, diverges from real routing — `focus.dart:993`
  **Fix:** delete + re-point 9 tests at `InputDispatcher.dispatch`.
  **Notes:** LANDED (A7, merged 338909b7): all 9 re-pointed assertions pass under the real dispatcher — no hidden finding.

- [x] **10.h** `P3` `TextHistoryController.canNavigatePrevious/Next` — no caller, no test — `text_history.dart:42`
  **Fix:** delete, or wire into the input's semantic state. Semantics already mismatch at index 0.
  **Notes:** LANDED (A7): deleted.

- [x] **10.g** `P3` `FormField.builder` without a focus node silently drops first-invalid focus — `form.dart:388`
  **Fix:** debug assert (mirroring the existing claim check), or make the parameter required on that constructor.
  **Notes:** LANDED (A7): debug StateError from a microtask (mirrors _scheduleClaimCheck; throwing synchronously would hang validate()). Required focusNode rejected — an unattached node is exactly this bug.

- [x] **4.f** `P3` Three RFC-mandated APIs have tests but no production caller — `width_policy.dart:158`, `text_projection.dart:81,101`
  **Fix:** route the pin through the resolved policy and delete the duplicated agreement rule, or delete the unused pair. Behaviour-neutral — re-run `wire-gate` to prove byte-identical output.
  **Notes:** LANDED (A7) — REWIRED, not just deleted: ResolvedTextPresentationPolicy.pinsAmbiguousWidth is now the one authority; ambiguousWidthFromMeasurements and the driver override deleted; projection pair deleted. ONE intentional behaviour change: fleury diagnose now honours FLEURY_AMBIGUOUS_WIDTH (RFC 0019 §6.2). Profiling harnesses declare the width via env. wire-gate sb1/sb9 byte-identical.

---

## [B] De-escalated — real, but parked

Each carries the reason it was parked. Anything here can be pulled up if you disagree with the reasoning; several are one-liners held back only because the *decision* around them isn't worth making pre-launch.

### B1 · Narrow trigger, conservative failure

- [x] **3.b** `P2` ↓ Negotiation collapses at RTT ≥ 150 ms — `posix_driver.dart:144`
  **Parked because:** degrades conservatively — no corruption, no lockout — and two of four axes are recoverable via existing env vars. Population is SSH beyond ~130 ms. The real defect is a **broken written contract** (the probe doc and RFC both claim RTT-independence), so the honest cheap move pre-launch is to correct the doc and add the missing knobs; the adaptive-deadline redesign is post-launch.
  **Notes:** LANDED: the adaptive-deadline redesign was taken instead of the doc-only patch. `TerminalQueryRunner` now reports the round trip the first ANSWERED exchange measured; the first probe keeps a fixed deadline (150 → 400 ms, free because the 500 ms aggregate budget — not the per-probe timeout — is what bounds a silent terminal), and every later probe gets max(150 ms, 3× RTT) capped at 1.5 s with the aggregate budget growing to 8× RTT capped at 2 s. A terminal that answers nothing measures nothing, so its startup cost is unchanged at 500 ms. Written contract corrected in the same change (RFC 0020 §8.2, RFC 0021 §7, compatibility matrix, `probeKeyboardFlags` dartdoc): the *verdict* is read off the reply, the *deadline* is not RTT-independent. Links past ~400 ms RTT still degrade — that is now the documented limit rather than an unstated one.

- [ ] **3.e** `P3` ✎ Force-exit skips capture teardown, discarding session output — `posix_driver.dart:211`
  **Parked because:** diagnostic-only on an already-hung process. ✎ The stated "Ctrl+C twice" trigger does **not** reach this path (`cfmakeraw` clears ISIG); real trigger is an external SIGTERM past the grace.
  **Notes:**

- [ ] **4.c** `P2` ✎ Ellipsis written without being measured — `render_objects.dart:444`, `rich_text.dart:656`
  **Parked because:** needs an ambiguous-wide policy, so not the default cohort — and the fix needs a **decision** on what a one-column box should degrade to. ✎ Stated symptom is backwards: in normal L-to-R order the *ellipsis itself* vanishes, so truncated text stops looking truncated.
  **Notes:**

- [ ] **4.b** `P2` RichText tears a lowered emoji cluster across lines — `rich_text.dart:565`
  **Parked because:** the two wrap implementations differ enough that a shared helper is awkward; likely wants a property test asserting both agree, which is a bigger piece than the bug. Broader than "emoji" though — the wrapper splits only on spaces, so all CJK is one token.
  **Notes:**

- [ ] **10.f** `P3` Composing range survives a programmatic write; IME commit clobbers — `text_input.dart:136`
  **Parked because:** browser-only, and needs an async write inside an open preedit. Real corruption, very narrow window.
  **Notes:**

- [ ] **13.f** `P3` ↓ Transport tears down the session on a *recoverable* decode error — `unix_socket_transport.dart:25`
  **Parked because:** **no reachable non-hostile trigger** — the input buffer closes rather than truncating, so no legitimate input corrupts framing. Buggy/hostile peer only, and such a peer already owns the app. Worth a doc correction so third-party implementers aren't misled.
  **Notes:**

- [ ] **8.h** `P2` ✎ Jump stashed across a zero-row layout strands the selection — `list_view.dart:1730,1133`
  **Parked because:** small fix, but ✎ the claimed trigger is **refuted** — an empty-list jump is clamped and harmless. Real triggers (collapsed pane, filter with no matches) are narrower. Open: drop the stale jump vs defer it until re-expand.
  **Notes:**

- [ ] **8.g** `P2` ✎ Focus drops to null when a focused row is virtualized away — `list_view.dart:1543`
  **Parked because:** the *right* fix is a scope-level fallback in `FocusManager` that would fix every virtualizing widget at once — a design question, not a list patch. ✎ Recovery is better than reported: Tab restores (the app shell installs a traversal group), the user just loses position. Lazy-only.
  **Notes:**

### B2 · Needs a product call, not a bug fix

- [ ] **10.d** `P2` A whole typing run collapses into one undo step — `text_input.dart:459`
  **Parked because:** **documented as designed**, and redo restores it. This is a design objection, not a defect against spec. Worth doing (every editor breaks at word boundaries) but it's your call on the rule: whitespace boundary, length cap, or a clock the model doesn't currently have.
  **Notes:**

- [ ] **10.c** `P2` Up-into-history then typing destroys the draft — `text_input.dart:1232`
  **Parked because:** the controller's behaviour is **pinned by a test**, so it's behaving as specified — the policy to change is the widget's. Also surfaces a broader undocumented fact worth deciding on: *any* `controller.text =` clears undo **and** redo. Opt-in controller, and pressing Up mid-draft often does mean abandoning it.
  **Notes:**

- [ ] **10.e** `P2` Form submit failures become unhandled async errors — `form.dart:37`, `forms.mdx:38`
  **Parked because:** one-line workaround, and the fix is a fork: add an `onSubmitError` hook, or keep the contract and document it in the dartdoc + canonical example. Pick one. (Verified only *routing* is wrong — state resets correctly.)
  **Notes:**

- [ ] **5.e** `P2` Cross-widget copy joins in widget order, not visual-row order — `selection_container_delegate.dart:224`
  **Parked because:** the fix needs the `Selectable` interface to grow a row-wise accessor, plus a **product decision** on the same-row separator (space vs tab vs real column gap). Nothing is lost — the text is all there, just badly joined.
  **Notes:**

- [ ] **9.c** `P2` ✎ Diff hunk with understated counts demotes the rest to metadata — `diff_view.dart:219`
  **Parked because:** malformed input, and the fix needs care not to regress the `--`/`++` misparse the counts were added for. ✎ Numbers overstated (counts undercount, not zero) — but the blank-line trigger is **broader**: it orphans the entire rest of the hunk.
  **Notes:**

- [x] **13.d** `P2` ✎ A second browser tab shows a wrong error and reload-loops — `bin/fleury.dart:801`
  **Parked because:** small, but bundle it with 13.new and the 13.b/13.c work — all three are "a rejection path the structured client can't surface". ✎ Loop is user-driven, not automatic.
  **Notes:** LANDED with 13.b: a second tab is closed with 4002 + a reason the client shows (was a raw OUTPUT frame + codeless close). Reason kept under the 123-byte cap.

- [x] **13.e** `P2` Debug wire on by default in bridge mode, no way off — `run_app.dart:1176`
  **Parked because:** needs a decision on **which side owns the default** — flipping the app side is more honest but changes behaviour for `fleury shell` and MCP, so check those first. Meanwhile `--debug` is warned-as-ignored while the surface it controls is live, which is the actively misleading part and is cheap to fix alone.
  **Notes:** LANDED with 13.b: the supervisor owns the default — the greeting carries --debug; runtime honours it when a supervisor spoke first, keeps FLEURY_DEBUG_WIRE for self-handshaking peers (shell, MCP). --debug is no longer "ignored in bridge mode".

- [ ] **11.d** `P3` ↓ `AnimationPolicy` unreachable in production; snap path forgets to notify — `run_app.dart:482`, `animation.dart:522`
  **Parked because:** ↓ neither half is reachable by a shipped app. **Decision:** ship the policy (plumb it + add the missing notify, which becomes a live P2 the moment you do) or cut it (stop exporting, delete the two guide lines promising accessibility behaviour that doesn't exist). Today's only real defect is those two guide lines.
  **Notes:**

- [ ] **2.c** `P2` ↓ Multi-step sequences can't arm under a modal scope — `input_dispatcher.dart:1046`
  **Parked because:** ↓ real scope is much smaller than it looked — `Menu`/`Select` carry no bindings of their own, so this is an app declaring its own sequence inside `present()`, with a workaround (`push`). Pull it up if "sequences work everywhere bindings work" is a shipped guarantee.
  **Notes:**

- [ ] **2.e** `P2` ↓ Alt dropped from ESC-prefixed non-printable chords — `input_parser.dart:485`
  **Parked because:** ↓ the P1 framing assumed the chat keymap was reachable by default; **nothing shipped uses it**. The parser bug is real byte-for-byte, but the fix reopens a genuine ambiguity (Esc-then-key on a slow link) that needs a timing window or a restricted byte set. **Do now regardless:** correct the dartdoc's false "reliably-detectable" claim.
  **Notes:** Dartdoc LANDED (A1): the chat preset states the legacy-terminal limitation, pinned by a parser test. Parser unchanged.

- [ ] **2.f** `P2` ✎ Demotion doesn't stop the next press re-latching a hold — `key_bindings.dart:553`
  **Parked because:** needs Warp-class terminal *and* `KeyBinding.hold`; escape depends on incidental tree shape. ✎ Framing corrected — it was never inert beforehand; the demotion correctly closes the in-flight hold, it just doesn't stop the next one. Fix must add a listener without making bindings a *build* dependent of the notifier.
  **Notes:**

- [ ] **6.g** `P3` ↓ ✎ `Anchored` has no test and no production caller — `anchored.dart:95`
  **Parked because:** ✎ the behavioural claim is **refuted** — it works fine; the microtask deferral is deliberate and a real event loop drains it. Only sync test bodies see nothing. What remains is coverage + three widget docs falsely claiming they're "built on Anchored".
  **Notes:**

- [ ] **9.e** `P2` DataTable `IntrinsicColumnWidth` sizes to the header only — `data_table.dart:1685`
  **Parked because:** **this is a design question, not a patch.** The table is virtualized, so "widest cell" is O(rowCount) by definition. Three options, none obvious: visible-window (jitters on scroll — probably disqualifying), bounded prefix, or fix the *contract* (table-specific width type, or document header-sizing). Pre-launch stance permits the clean break. Off the default path — nothing in samples or storybook uses it.
  **Notes:**

- [ ] **15.d** `P2` ✎ VM service banner is the first line users see — `dev_bootstrap.dart:93`
  **Parked because:** capture-vs-banner is a genuine race, so the fix needs both halves (early capture + scrub fallback). Verified **no suppression flag exists** on Dart 3.12.2. ✎ Supervised operation *is* PTY-covered — against a fixture, not the generated scaffold; add that case.
  **Notes:**

- [ ] **15.g** `P2` ✎ In-app reload has no docs and no reachable recipe — `dev_bootstrap.dart:764`
  **Do now (docs half):** the **documented** browser command — in the serving guide *and* the generated project's README — produces no service and therefore no reload. Correct it.
  **Parked (code half):** having `serve --spawn` inject the flag needs a call on whether injecting into a user-supplied command is acceptable, plus the cost of a service per concurrent session.
  **Notes:** Docs half LANDED (A1): serve guide, hot-reload guide, scaffold README teach the --enable-vm-service=0 recipe. Code half (serve injects the flag) still open. NOTE: getting-started.mdx:273, deployment.md:89, coming-from-flutter.md:90 also teach the reload-less command — not yet swept.

- [ ] **15.h** `P2` ✎ Watch roots resolve from CWD, not the entrypoint — `source_watcher.dart:38`
  **Parked because:** running from the project root is the documented flow, so most users are fine. ✎ Worse than reported though: the supervisor starts **either way**, so an unsupervisable session pays every cost (double `main()`, banner, signal window, second VM) for zero benefit. The "fall through when there's nothing to watch" half is cheap and worth doing alone.
  **Notes:**

- [ ] **15.f** `P2` Stale `.fleury/handle` silently disables hot reload project-wide — `handle_discovery.dart:14`
  **Parked because:** needs SIGKILL to occur; app keeps working. Fix is well-shaped though — the liveness proof already exists CLI-side and is **synchronous** (non-blocking `lockSync`), which is exactly what the pre-gate requires. Pull up if you've hit it.
  **Notes:**

- [ ] **14.c** `P2` ✎ Alt-modified printables dropped entirely — `dom_input_source.dart:835`
  **Parked because:** the removal is easy; the **identity work** isn't — matching `KeySequence.alt.char('1')` needs the physical code's base-layout twin, the same fallback the RFC defines for kitty. ✎ Two corrections: the "pinned by a test" claim is wrong (a code-conditioned fix leaves it green), and a **concrete victim exists** — `tabs.dart:296` ships alt+1..9 as a documented first-party shortcut, dead on browser, and on macOS it types junk into whatever has focus. Pull up if the tabs shortcut matters for launch.
  **Notes:**

- [x] **11.e** `P2` Harness latches the frame from a seam `runApp` removed — `fleury_tester.dart:107`
  **Parked because:** tied to 11.b — fix them together or the harness still can't see it. See D2.
  **Notes:** LANDED with 11.b. The harness no longer owns a latch seam at all: it calls the one `installKeyboardLatch` every host calls, and publishes the frame clock from `render()` — the analog of `FrameDriver.onLatchInput`, at the same point in the frame. Red before: "with no ticker running, renders expire edges" and "the live clock follows ticker registration" both failed, because renders under the tester never latched. The comment asserting the opposite is gone.

---

## [C] With you — hard, central, or your call

Ordered by what I'd take first. Each names **what makes it hard**, so we can decide together rather than me guessing at a design.

### C1 · The two freezes *(take first — both are "app is dead" on a default path)*

- [x] **1.a** `P0` Frame-from-inside-frame is a microtask → uninterruptible isolate freeze — `frame_scheduler.dart:23`
  **Hard because:** the ~6-line fix (`_inFrame` flag → `Timer.run`) is easy; deciding it's *safe* is not. It changes frame-ordering semantics — anything relying on "post-frame lands before the next I/O event" now interleaves with input — and it sits on the hot path under `alloc-gate`/`paint-gate` plus the serve timing gates. **And it is only half the problem:** the paste chunker is quadratic independently (controller-only edits, no rendering: 4/12/62 ms for 128/256/512 KiB), so the scheduler fix converts a freeze into a long janky paste. Second decision: cap chunk work by time, bulk-apply above a threshold, or lower the max paste size.
  **Measured:** 64 KiB → 254 ms, 128 KiB → 814 ms, 256 KiB → 3.1 s, 512 KiB → 12.4 s (~4× per doubling); 1 MiB segment ≈ 50 s. Starved isolate ignores **SIGINT, SIGTERM and SIGQUIT** — only SIGKILL, and nothing restores the terminal after it. Browser immune (rAF); **serve is affected**.
  **Notes:** Scheduler half LANDED on this branch (30dc8b00): re-entrant zero-delay flush → Timer (macrotask); idle path unchanged. Pinned in frame_scheduler_test (+2) and integration/frame_chain_yields_test (+2), all red without the fix. Fast gates + wire-gate pass. serve-wire-live fails identically WITHOUT the fix at load avg 117 (parallel batch runs) — re-run quiet before PR. Chunker half LANDED (fb25c811, with **N2** and **Q10**): each step applies at least the current document length as ONE coalesced edit, so the document grows geometrically — O(log n) edits and frames, linear total work. 512 KiB rendered: 8221 ms / 256 edits / 255 frames / 64.3 MiB copied → 53 ms / 9 / 8 / 1.0 MiB (~6.6 ms of work per frame). The duplicated state machine moved to `TextPasteDriver` in `editing/text_paste.dart`. text_area_test:316-349 did NOT have to change — its 8-char payload still takes 3 steps — but one-chunk-per-pump is no longer the contract; the real requirement (key observed mid-paste + bounded edits/frames/copying) is pinned by 3 new tests. Fast gates pass.

- [x] **1.b** `P0` ✎ Stale selection offsets throw on Ctrl+C and disable the exit chord — `selectable_text_mixin.dart:465`
  **Hard because:** the one-line clamp stops the throw but leaves the *silent* sibling — when text **grows**, the wrong characters are copied with no error at all, which is quieter and arguably worse. The real fix is to stop caching flat offsets and re-resolve from the delegate's screen coordinates on content/geometry change — which must happen **once at invalidation, never inside the per-grapheme query**, or it lands on `paint-gate`. Shares its machinery with **5.f**; design once.
  **Also decide:** whether `run_app`'s exit guard should survive *any* throwing handler (run it in a `finally`). That converts a whole future class from "unquittable" to "banner, still quits" and is worth doing independently.
  **✎ Corrections:** not permanently unquittable — a click that reaches the root selection area recovers it (but **5.b** removes that escape over most of an app). Two triggers the first pass missed: **terminal resize alone**, and `RichText`.
  **Notes:** LANDED on this branch (07a51e55): mixin keeps the screen points per edge and re-resolves them lazily when `selectionLines` identity changes (text set, resize re-wrap, policy change); offset-based edges clamp at the same choke point. Also landed the run_app exit-guard hardening (a throwing dispatch is reported and treated as `ignored`, so Ctrl+C still quits). Pinned: 5 selection tests + 1 runtime test, all red without the fix. Gates green. 5.f can build on `_relatedLines`.

- [x] **5.f** `P2` ↑ A selectable mounting mid-selection can never join it — `selection_container_delegate.dart:190`
  **Pairs with 1.b** — same invalidation machinery. ↑ Raised: not a one-frame lag; scrolling a `ListView.builder` mid-drag evaporates the whole selection. The unmount half is genuinely harder (Flutter has the same limitation) — reasonable to stop there, but **say so** rather than leaving it looking fixed. Its pinning test cannot fail as written (see D1).
  **Notes:** Partly unblocked by 1.b (07a51e55): the mixin now re-relates cached screen points whenever its lines change; the remaining gap is the delegate replaying edges to a selectable that had NO points yet (first paint after mount). VERIFIED on this branch (127e3c3b): a real lazy-list test — drag 4 rows, scroll by one, release, copy — shows the newly mounted item joins and the unmounted one leaves. Already green (1.b re-relate + delegate edge replay); kept as the regression pin, not a red→green fix.

### C2 · Default-path correctness with a design fork

- [x] **5.b** `P1` ✎ Text inside any tap-handling widget is unselectable — `pointer.dart:246`
  **Hard because:** the 10-line fix (fire the drag target's tap-down too) only works while the root selection area happens to be the topmost *drag* region — interpose a scrollbar, slider or nested area and the anchor is still never set. The durable fix is a **real hit-test path**: collect every region under the point and propagate tap-down up it, with `AbsorbPointer` as the stop. That's a per-frame input change → `input-alloc-gate`.
  **✎ Worse than reported:** Fleury's own core `ListView` wraps every item in a `GestureDetector`, so list content — logs, transcripts, file lists — is entirely unselectable. And the phantom-extension half hands users content they never dragged over.
  **Notes:** LANDED (targeted fix, not the hit-test path): the armed drag target also receives the press when it is not the tap target, so a SelectionArea under a tap-only widget gets its anchor. Tap semantics unchanged. 3 tests (GestureDetector text copies; plain click still taps; ListView rows select). Interposed sliders/scrollbars correctly keep the drag — a hit-test path is not needed for launch.

- [ ] **4.a** `P1` Scratch-buffer replay loops re-measure under the spec policy — `cell_buffer.dart:390` + 5 call sites
  **Hard because:** making `policy` required is the right move but it **surfaces decisions**, not just call sites — border glyphs and scrollbar glyphs are ambiguous-width and currently write at spec, which matches reserved geometry but not what an ambiguous-wide terminal draws. That needs an answer, not a mechanical `spec`. The structural blit also has transparency semantics to preserve (these loops deliberately skip empty cells) → likely a per-cell structural write, not a rect copy. Hot path: `alloc-gate` + `paint-gate`.
  **Why it's high:** the probe runs **unconditionally**, so non-spec policy is the *default* state on ~19 of ~30 terminals including macOS/GNOME/VS Code defaults. ⚠ Sequence with **4.e**.
  **Notes:**

- [x] **10.a** `P1` ✎ Caret, selection and scroll paint in the wrong cells after pasting ANSI text — `text_input.dart:1792`, `text_area.dart:1027`
  **Your call — three fix directions, none obviously right:** (a) sanitize at the **model** boundary so index spaces match by construction — cleanest, but changes what the app reads back and silently drops pasted bytes; (b) keep render-boundary sanitizing and carry a raw→display offset map — needs an identity fast path for the common equal-length case or it hits `alloc-gate`/`paint-gate`; (c) a length-preserving sanitizer emitting one replacement per code unit — indices align free, at the cost of ~40 cells of `U+FFFD` for one pasted hyperlink.
  **✎ Worse than reported:** the **selection highlight covers different characters than the selection**, so shift-select + Delete removes the wrong span. In `TextArea` the caret drifts across *rows*. Terminal is partly shielded (xterm/kitty strip C0 from paste); **serve and every programmatic write are not**.
  **Notes:** LANDED, direction (a). New `sanitizeMultiline` (`sanitizeForDisplay` per line, `\n` kept) canonicalizes in the `TextEditingValue` constructor, so every write — typed, paste, IME, `text =`, `value =`, initial value — is canonical by construction; `TextEditingModel.prepareInput` applies it to the inserted string *before* the offset math, so `start + input.length` measures painted text. Both render boundaries became identity + a debug assert (`TextInput` still maps a stray `\n` 1:1 to `U+FFFD`; placeholders are widget-supplied and still sanitized there). Allocation-free when clean: a code-unit scan replaces the old `runes` fast path. Documented on `TextEditingController` (what is rewritten, what an app reads back) and both widgets. 11 tests, red first: caret column after an ESC paste, highlight == `selectedText`, shift-select + Delete removes exactly the highlight, `TextArea` caret row (was row 2 col 0, is row 1 col 1), programmatic writes, and 6 model-level. alloc/paint/input-alloc gates green.

- [x] **7.a** `P1` Cached repaint-boundary blits sever wide-glyph pairs — `cell_buffer.dart:207`
  **Hard because:** the fix mirrors an existing precedent (evict wide neighbours + widen damage ±1, as the image-placement path already does), but it's on the blit hot path and the damage-widening interacts with the derived-damage model — get it wrong and you either leave the garble or over-damage every frame. Also check the destination-clip sub-case, where clamping can slice the *source* mid-pair.
  **Scope narrowing worth knowing:** ambiguous-wide pins contain the damage and emoji always pin, so cascading drift is **CJK on probe-cleared-narrow terminals** specifically. The full-row fast path can't sever anything. **No test can reach the production overlay path** (see D2).
  **Notes:** LANDED on this branch (f80db6d5): edge evictions before each row copy + ±1 damage (the image-placement precedent) + source-side orphan clearing for clipped slices; fast path untouched. Pinned: 4 buffer tests + a real-widget ListView-over-CJK test, all red without the fix. wire/alloc/paint gates green.

- [x] **8.c** `P1` DataTable paints past its own box and corrupts siblings — `data_table.dart:1894`
  **Arguably P0** — writing outside your own rect breaks a framework invariant that damage tracking, repaint caches and the serve wire's damage bounds all rely on, so corruption can persist across frames. Held at P1 only because the author must under-size the table.
  **Your call inside it:** clamp and truncate (minimal, symmetric with `_writeRule`/`_fillRow` two methods up), or shrink fixed columns proportionally (changes existing layouts)? And should truncated cells get an ellipsis? ✎ Default flex sizing is safe; the hit-test overhang is inert. Repo's own dashboard/finance samples declare overflowing widths.
  **Notes:** LANDED (2394ec38): each column gets a painted width cut at the table's right edge (fully clipped columns skipped, builder included) — the rule/fill clamp, applied to header and body cells. No ellipsis (separate visual call). Red at 17 cols before; samples (finance/dashboard) green.

### C3 · List and framework centre

- [x] **8.a** `P1` ✎ List anchor never clamped to the last full page — `list_view.dart:1153,1745`
  **Hard because:** variable-height rows — the backwards-walk helper **mounts items** in the lazy path, so calling it every layout adds hot-path work. Wants a cheap post-check ("did we under-fill?") then a re-walk, not a pre-pass. ✎ Wheel trigger refuted, but a worse one found: a **scroll-only list with `pinToBottom`** — a tailing log, a documented config — renders exactly one item per frame forever.
  **Notes:** LANDED: post-check after the forward walk (ran out of items with rows to spare, anchor > 0) → re-anchor via the existing backwards helper + re-walk, both paths; lazy re-walk reuses the leftover sweep. 4 tests red before (scroll-only tail follow showed (19,19)). jumpToIndex doc: clamped to the last full page.

- [x] **8.b** `P1` Capped transcript permanently loses follow-tail — `list_view.dart:688`
  **Hard because:** the fix changes *classification* (old-first-key gone + old-last-key resolves ⇒ trailing growth), and must keep the existing keyed-reorder test green — that test is the contract. Mixed reorder-plus-eviction stays ambiguous, which the docs already disclaim.
  **The inversion is the sting:** the same rolling window follows correctly **without** keys and breaks **with** them — supplying identity, the documented best practice, is what triggers it. Out-of-box config; the example console does exactly this.
  **Notes:** LANDED on this branch (6a7c9f31): classifier recognises head-eviction (old first key gone, old last key resolves → everything after it is the append); pure reorders untouched, contract test green. Pinned: 2 ListView tests + 1 real MessageList test, all red without the fix.

- [x] **12.a** `P1` `IntrinsicWidth`/`IntrinsicHeight` blank their subtree for almost any real child — `intrinsic.dart:38,113`
  **Hard because:** the general fix is delegating intrinsics from the single-child default — broad, touching most render objects, and genuinely ambiguous for `Stack`/`Wrap` where "natural width" has no single answer. Cheap interim: **assert** when a child reports 0 but would lay out non-empty under loose constraints, turning a silent blank into a diagnostic without changing layout.
  **Honest scope:** opt-in, zero non-test callers — a documented primitive that doesn't work, not a default-path failure. But the blank set includes the two wrappers the framework inserts *unasked* (list items, route content), and Flutter **asserts** where this returns 0.
  **Notes:** LANDED (general fix, not the assert): base default delegates intrinsics for every single-child wrapper; RenderBorder adds its frame; Stack/IndexedStack report the largest child. 5 tests red at 0 before. Fast gates pass (intrinsics are not per-frame).

- [x] **12.c** `P2` ✎ Render config never refreshed on a dependency-only rebuild — `framework.dart:1736`
  **Hard because:** the central fix (call `updateRenderObject` from `performRebuild`) is the one change here with **real gate exposure** — an extra call per dirty render-object element per frame. Setters no-op on unchanged values, so the cost is getters plus inherited lookups; if those show up, the fallback is a narrower opt-in mixin, which leaves the trap open for third-party widgets. **Land 12.b first** — the setters this needs don't exist yet.
  **✎ Framing corrected:** "no user-facing trigger today" is **false** for the contract, even though it's true of the four in-repo instances. A live trigger was reproduced: a user-written render-object widget reading `Theme.of(context)` in `createRenderObject`, hoisted `const`, theme swapped — keeps painting the old colour.
  **Notes:** LANDED (d91335af): inherited notify flags RenderObjectElements too; rebuild re-runs updateRenderObject once when flagged (setters no-op on unchanged values). Theme-swap-under-const test red before. alloc/paint gates unchanged.

### C4 · Input authority and terminal policy

- [x] **2.a** `P1` ✎ Any rebuild between sequence steps silently drops it — `input_dispatcher.dart:728` — LANDED (ace82485): pending re-resolves candidates from the captured KeyBindingSource scopes each step; fires the live handler; which-key refreshes; 5 tests (3 red before); input-alloc +0.2%
  **Hard because:** positional re-resolution has a failure mode worse than the bug — if a rebuild **reorders or shortens** the binding list, an index re-read can fire the *wrong handler*. Needs a structural key (source node + sequence) rather than a raw index, validated against the already-consumed prefix. `input-alloc-gate` covers it, and storing a record per candidate adds allocation.
  ✎ Trigger narrower than reported (a sibling rebuild is harmless — it's a rebuild of the widget that *constructs* the bindings), but that's still the common case under streaming output.
  **Notes:**

- [ ] **2.d** `P1` Held keys never recovered across Ctrl+Z or handoff — `run_app.dart:672` vs `posix_driver.dart:739,829`
  **Hard because:** needs a new authority-loss signal from driver → dispatcher (new event type, or reuse the focus event), fired from suspend and handoff, with the re-acquisition side considered. Double-firing is safe; the reverse ordering (handoff returns while re-entering) needs checking.
  **Perverse second arm:** two stuck keys re-pressed trip the phase-violation counter and **permanently demote an honest kitty/ghostty to press-only** — on evidence Fleury manufactured itself.
  **Notes:**

- [ ] **3.a** `P1` Ctrl+Z swallowed as job control; `TextInput` undo unreachable — `posix_driver.dart:679`
  **Your call:** it's a **policy collision**, not a code bug — suspend was deliberate, undo-on-Ctrl+Z is in both shipped default keymaps, and nothing reconciles them. The Ctrl+C path already models the answer (dispatch first, self-stop only if unhandled). Deciding to move suspend behind an unhandled-chord fallback is yours; the wiring after that is small.
  **Sharpens it:** the Sprite Studio sample renders a hint bar advertising `^Z undo`, and the showcase page tells the reader to press it. Works on serve, not terminal — the two surfaces disagree.
  **Notes:**

- [ ] **3.c** `P1` ✎ Terminal handoff unreachable from a default `runApp` — `external_editor.dart:200`
  **Hard because:** needs an **API decision** — publish the session driver via an inherited scope, or a runtime-owned reference plus a top-level helper? A global is friendlier but is a second source of truth about who owns the terminal.
  **✎ Worse than reported:** `runApp` has `dup2`'d fds into capture pipes, and pause/resume is wired *only* into the handoff path — so an `inheritStdio` child inherits the **pipe, not the terminal**. `$EDITOR` draws into the log buffer while eating raw keystrokes: the app just looks frozen. The only workaround costs stray-output capture, remote-handle resolution, and the supervisor.
  **Notes:**

- [x] **11.b** `P1` Sampled input edges destroyed by any unrelated render — `keyboard_state.dart:538`
  **Hard because:** the fix (expire on the ticker clock, not the render clock) needs a **fallback for apps with no tickers** — that hook never runs, so the sampled API would report stale taps forever. And do **not** re-add a second publisher; that was the earlier regression. Pairs with **11.e** or no test can see it.
  **Honest scope:** sampled lane only, and Asteroids is accidentally immune (its fire is also a regular binding) — so nothing shipped visibly breaks. What breaks is a frozen documented API for anyone following the RFC.
  **Notes:** LANDED. `publishLatch` now takes a `KeyboardLatchClock` and the session arbitrates: whichever clock is not live returns the standing snapshot untouched, so there is never a second publisher — only a different one. The live clock is read off `TickerScheduler.isActive` (a live query, not a mirrored flag), so the ticker owns expiry while any ticker is registered and the frame clock takes back over the instant the last one unregisters — that IS the ticker-free fallback, and it is tested in both directions. Both clocks are wired in one place (`installKeyboardLatch`), used by `runApp`, `runTuiSurface` and the harness alike. Red before: "a tap survives an unrelated render before the tick" — Expected true, Actual false. RFC 0020 §7 carries an amendment note; guide + `Keyboard` dartdoc say "tick", not "frame".

- [x] **6.c** `P1` ✎ A float outlives its anchor when the anchor stops painting — `bounds.dart:169`
  **Hard because:** the frame-epoch fix needs two things measured first — the epoch must be correct under **retained-paint replay** (a cached boundary republishes for a subtree that didn't run), and the staleness threshold must be **one frame, not zero**, since an anchor painting before its observer legitimately reads last frame's bounds. Get either wrong and every float flickers.
  **✎ Far broader than route-push:** `IndexedStack`/`Tabs` means "open a dropdown, switch tabs" strands the panel over the new tab. Affects every anchor consumer. Cheap complement worth doing regardless: close stock floats on route change.
  **Notes:** LANDED (a59f9ad6, registry made per-owner in 521b9124): the damage tracker numbers each root paint pass and sweeps its PaintPassParticipants; observers stamp paint/replay and register on first publish; unrefreshed ones publish null at pass end → anchored float hides next frame (hasFrameWork schedules it). IndexedStack-switch test red before; cached-boundary stability test. No route-change close needed for the stock floats now.

### C5 · Serve

- [x] **13.b + 13.c** `P1` Bridge mode wedges, and the app-first flow self-destructs at the 10 s fuse — `bin/fleury.dart:752`, `remote_driver.dart:208`
  **One bug in practice — must land together.** 13.c fires 13.b automatically: fix only 13.c and a Ctrl+C'd app still wedges serve; fix only 13.b and app-first still dies at ten seconds, just recoverably.
  **Your call on 13.c:** the fuse was added against a real silent-peer process-leak attack, so reverting is not an option. Either treat bridge mode as the supervised peer it genuinely is (protocol addition, the proper fix) or have serve send its handshake at accept like `fleury shell` does (cheap, no protocol change, but needs care that a placeholder first paint isn't visible).
  **Zero test coverage on the whole app-first axis** — no app-first case, no second-browser case, no duplicate-header case.
  **Notes:** LANDED: serve greets the app at accept with a provisional INIT (a supervisor statement, not a handshake — nothing adopted, the fuse becomes an unbounded wait like a spawn standby); BridgeAppLink reads the pending socket from accept (dead app noticed, output drained). Real app attached 12 s after connecting paints; red before. The "supervised peer" route, no version flip.

- [x] **13.a** `P1` ✎ One duplicate-header request kills serve, pre-auth — `bin/fleury.dart:993`
  **Hard because:** ✎ **two layers are required** — reading headers as a list fixes three vectors, but the fifth (missed by the original) throws *inside* the platform library's upgrade check, which is the first statement in the socket branch. So you also need handler try/catch + a zone guard, and in spawn mode the catch must release the admission slot.
  **Judgement:** held at **P1, not P0** — drive-by unreachability was **proven in a real browser** across six vectors. But there's a **non-hostile trigger**: the docs recommend a reverse proxy, and one that *adds* rather than sets the forwarded-proto header kills serve on the first connection. Spawn-mode death leaks the spawn dir permanently; bridge-mode leak is benign.
  **Also decide:** reject an ambiguous multi-valued `Origin` outright rather than taking `.first`? (Two Origin headers is never a real browser.)
  **Notes:** LANDED on this branch (c3abbebf): headers read as lines (If-None-Match any-match, X-Forwarded-Proto first line, duplicate Origin fails closed), dart:io upgrade check wrapped, both handlers guarded + stream onError. Pinned by 4 raw-socket tests against a real serve process, all red without the fix.

- [ ] **16.g** `P2` Satellite packages exact-pin the core version
  **Your decision, and it's hard to reverse after publish.** Ratify lockstep (and write "republish both satellites with every core release" into the launch checklist), or widen the constraint. **Open question the audit couldn't answer from that area:** does the INIT wire-version check key on the full version or only major/minor? That determines whether patch-level slack is safe.
  **Notes:**

### C6 · Dev loop

- [ ] **15.a** `P1` ✎ Supervisor's 300 ms signal forward collapses the documented 5 s grace — `dev_bootstrap.dart:313`
  **Hard because:** the supervisor is guessing signal provenance from a timer because POSIX provenance isn't reachable from Dart. Proper fix: the child posts a signal **ack** over the VM service connection the supervisor already holds, and the forward is cancelled positively — timer stays only as a backstop for a wedged child. Open: can the ack be posted early enough for a signal during startup, and is it safe mid-respawn?
  **✎ Both directions:** narrower than claimed (sub-300 ms teardowns are fine) but the mechanism is worse — restore cancels the signal subscriptions, and **cancelling the last one restores the OS default disposition**, so a forwarded signal kills the process outright mid-restore, skipping capture teardown and any code after `await runApp`. The emergency tty restore then makes it **look like a clean quit**.
  **Notes:** PARTIAL (1fe211ce): the worse mechanism is fixed — restore() now holds a no-op SIGINT/SIGTERM shield until cooked mode + final flush are done, so a forwarded signal can no longer kill the process raw mid-restore (test via a signal-watcher seam, red without the shield). The 300 ms provenance guess itself (positive ack over the VM service) is a design call — open.

- [x] **15.c** `P1` `main()` executes twice — once in the parked supervisor, once in the child — `dev_bootstrap.dart:219`
  **Your call — there is no clean fix.** You cannot un-run code that already ran. Pre-launch this is (a) documenting prominently that everything before `runApp` runs in both processes, and (b) a diagnostic when a first child exits non-zero within a second or two of spawn. The structural fix — a `fleuryMain` wrapper or `dart run fleury:dev` — **trades away the "plain `dart run`, no wrapper" property that is the feature's entire pitch**, so it's an RFC, not a patch.
  **Timing:** the generated scaffold is safe today (`main` is just the run call), so launch day is fine. It breaks the first day a user adds startup work — bind a port, take a lock, subscribe to stdin — which is also the day they're least likely to suspect the framework.
  **Notes:** LANDED (9599f8cc): hot-reload guide states main() runs twice (+ opt-outs, + Troubleshooting symptom); supervisor prints a stderr hint when the FIRST child exits non-zero within 2 s (pure helper devEarlyExitHint, 4 tests). Structural fix (wrapper) remains an RFC — your call.

- [x] **15.b** `P1` VM options silently dropped on the supervised respawn — `dev_bootstrap.dart:84`
  **Nearly mechanical — flagged only for the deny-list call:** replay `Platform.executableArguments`, but drop the tooling's injected internals and anything colliding with the service setup. Open: are those internal flag names stable enough across SDKs to deny-list, or should it be an allow-list? `--define` and `--enable-asserts` both verified lost. Worth documenting that `DART_VM_OPTIONS` survives as an escape hatch.
  **Notes:** LANDED on this branch (a55d068c): replayableVmOptions filter (drops dart run bookkeeping + service-owned flags), replayed ahead of the supervisor flags; 4 new gate tests. Open: DART_VM_OPTIONS already survived via env — worth a doc line.

---

## [D] Process — why the suite missed all of this

Not bugs. These are the structural reasons nearly every P0/P1 above was invisible to a fully green `check` plus seven passing gates. Worth closing regardless of which findings ship.

- [ ] **D1** Four tests that **cannot fail** — `selection_delegate_test.dart:394`, `animation_test.dart:157`, `data_table_test.dart:344`, `fleury_tester_test.dart:429`
  Each asserts a state its subject can never be in: a selection stub taking bounds in its constructor (5.f), a value assertion where the bug is a missing notification (11.d), a header wider than its cell (9.e), a stateless observer on a render-object path (12.c). Worse than absent coverage — they read as proof.
  **Fix:** rewrite each so it can fail.
  **Notes:**

- [ ] **D2** The harness diverges from production in three ways, each hiding a specific P1 — `fleury_tester.dart:107, 960, 985`
  Latches the frame on a seam production removed (hides **11.b**); builds surface capabilities with no text-policy knob, so every widget test runs on spec (hides **4.a**); opts its overlay out of entry repaint boundaries, so the production blit path is unreachable (hides **7.a**). In two cases the harness carries a comment asserting the opposite. ✎ Narrowing: tests *can* reach a non-spec surface by wrapping their own scope — the gap is coverage, not capability.
  **Fix:** match the latch cadence (or document the divergence honestly), expose a `textPolicy` knob, and force entry boundaries on in any 7.a test.
  **Notes:** PARTIAL — the latch divergence is closed (see **11.e**); the `textPolicy` knob (4.a) and the entry-boundary opt-out (7.a) are untouched. The general lesson the fix encodes: the harness now shares the host wiring function rather than reimplementing it, so this class of divergence cannot be introduced by editing only one side.

- [ ] **D3** Two gates don't cover what their names imply — `profiling/bin/selection_gate.dart:82`; `alloc-gate` vs `framework.dart:854`
  `selection-gate` never constructs a `SelectionArea` — it drives a bare scope and delegate — so it catches registration regressions and **none** of the behavioural defects in §05, and 5.g's fix cannot move it. Separately `alloc-gate` did not flag a 20–50× per-invalidation allocation on every `setState`.
  **Fix:** extend the selection gate through a real `SelectionArea`; work out why the invalidation allocation is invisible before trusting the gate on §12 fixes. **Do not read a green `selection-gate` as verification for §05.**
  **Notes:** CONFIRMED WORSE while fixing 12.e: alloc-gate sums only classes whose library uri starts with package:fleury, so dart:core String/List churn is structurally invisible — anyone reading it as a general allocation gate is misled. Also: wire-gate's sb6 scenario is nondeterministic (~4% spread on identical code; sb1/sb9 are byte-stable).

- [ ] **D4** Fuzzers and regression tests that stop one argument short — `cell_buffer_diff_fuzz_test.dart`, `storybook/test/terminal_scroll_diff_test.dart`
  The diff fuzzer never applies its bytes to a terminal model, so nothing property-tests the diff→present contract where the historical garble class lives; it also never fuzzes severed wide pairs, resize, scroll, emoji or non-spec policies. The scroll regression test calls the renderer **without** `scrollUpRows`, so the scroll path could regress green.
  **Fix:** apply fuzzer output to a terminal model and widen the dimensions; pass the scroll argument (a working version was written during the audit).
  **Notes:**

- [ ] **D5** Invariants enforced by enumeration rather than by construction
  `overlay_opacity_test.dart` covers 5 of 7 floats and misses exactly the 2 that leak (6.d, 6.e). Chrome-selection is satisfied by six floats **by accident of mount point**, not design (12.d). And an entire class — 6.b — is assert-gated, invisible under `dart run` and breaking only user tests.
  **Fix:** extend the opacity test to the full float set; state the chrome-selection property per float; adopt a standing rule that **assert-gated findings are dev/test severity by default** — this trap has now been hit twice, including in the July audit.
  **Notes:**

---

## Suggested landing order

1. **A1 + A2** — docs and packaging. Zero risk, and they're the P0s a first-time user hits. One PR each.
2. **A7** — dead-API removal, before the surface freezes.
3. **A3–A6** — batched by area. `12.b` must precede any `12.c` work.
4. **C1** — the two freezes. Start with 1.a's scheduler half, decide the chunker separately.
5. **D1–D5** alongside, so each fix lands with a test that could have caught it.
6. **C2–C6** — paced, with the design questions settled before code.

## Open questions for you

These block or shape work above and are not mine to answer:

1. **9.e** — virtualized intrinsic width: visible-window, bounded prefix, or change the contract?
2. **16.g** — lockstep releases: ratify or widen? (Needs: does the INIT check key on full version or major/minor?)
3. **10.a** — sanitizer: model boundary, offset map, or length-preserving?
4. **13.c** — bridge handshake: protocol addition, or serve sends INIT at accept?
5. **15.c** — `main()` twice: document + diagnose, or RFC a launcher and lose "plain `dart run`"?
6. **3.a** — Ctrl+Z: move suspend behind an unhandled-chord fallback?
7. **11.d** — `AnimationPolicy`: ship it or cut it?
8. **10.e / 10.d / 10.c** — forms and editing policy: hook vs document; undo granularity; draft retention.
9. **6.a** — should `barrierDismissible` also mean click-outside?
 10. ~~**1.a (chunker)** — coalesce paste chunks per frame by a time budget?~~ ANSWERED and landed (fb25c811): coalesced by a *growing size* budget rather than a wall clock — the step is the current document length, which is deterministic, keeps total work linear (a wall-clock budget does not), and needs no machine calibration. `text_area_test:316-349` still passes unchanged.

---

## Surfaced while fixing — not in the original index

Found by the batch agents in passing. Verified only to the extent stated; triage as new entries.

- [x] **N1** `P1` `WhichKey` remounts its entire subtree on every popup reveal — `which_key.dart:91` vs `:126` (returns `child` hidden, a `Stack` revealed → different runtimeType in the same slot → every `State` below is destroyed on every leader press that outlives `showDelay`). Measured `initState` ×2. Also the mechanism that makes 2.a deterministic in the shape the keyboard guide recommends. **Fix:** stable `Stack` with a conditionally-empty layer, or route the popup through the overlay.
  **Notes:** LANDED (WhichKey fix on this branch, on top of a new Stack.fit — loose/expand/passthrough): constant shape = passthrough Stack [expanding filler, app, Positioned popup]; app keeps its slot and its bare constraints, popup box = whole wrapped surface. Probe logged init,init,dispose on reveal before; init only after.
- [x] **N2** `P2` The paste chunker is quadratic independent of 1.a — controller-only edits (no render) measure 4/12/62 ms at 128/256/512 KiB, because every 2 KiB chunk re-copies the whole string (`replaceRange`) and `FrameDriver` forces a full frame per post-frame registration. Q10 covers the per-frame coalescing; the string copy is a separate (smaller) fix.
  **Notes:** LANDED with 1.a's chunker half (fb25c811) — one fix covers both: batching chunks into one growing edit per frame removes the per-chunk string copy AND the per-chunk frame. Controller-only 512 KiB: 256 edits / 64.3 MiB copied → 9 edits / 1.0 MiB.
- [x] **N3** `P2` `MessageListController.jumpToIndex` has 8.e's dead `followTail = false` pattern — `message_list.dart:155-166`; a tail index re-engages follow through the coupling.
  **Notes:** LANDED (4a11c50a): dead `followTail = false` deleted; pinned by the false→true flap seen through the controller notifications.
- [x] **N4** `P2` Three more surfaces teach the reload-less browser command — `getting-started.mdx:273`, `guides/deployment.md:89`, `coming-from-flutter.md:90`. Same fix as 15.g's docs half.
  **Notes:** LANDED: getting-started, deployment, coming-from-flutter now teach `dart --enable-vm-service=0 run …` with a one-line reason.
- [x] **N5** `P2` Spawn mode's `--max-sessions` rejection is a 503 before the upgrade, so the client shows a blank page with no message (13.new in the register; same family as 13.d).
  **Notes:** Same bug as 13.new — LANDED via A6 merge (7d53ed57), see 13.new.
- [x] **N6** `P3` `probeAmbiguousWidth` (`terminal_probe.dart:251`) — public, tested, no production caller (the driver calls `probeGlyphWidths`). `AmbiguousCharWidth`'s doc still attributes detection to it.
  **Notes:** LANDED (577a99c2): probeAmbiguousWidth + its tests removed; the driver path (probeGlyphWidths) is the only one.
- [x] **N7** `P3` `TextProjection.logicalText` — zero production readers after 4.f; its doc ("what copy and semantics answer with") is false.
  **Notes:** LANDED (6c18cdd1): TextProjection.logicalText removed; PreparedCluster doc reworded.
- [ ] **N8** `P3` Seven zero-arity `onTrigger: () =>` in `docs/rfcs/0008` and `0018` — as-proposed design records, not swept by the docs guard. Decide whether RFCs are pinned to current API.
  **Notes:**
- [x] **N9** `P3` `RenderObjectElement.renderObject` throws during teardown; any `deactivate`/`unmount` override reaching it compounds one error into two. `maybeRenderObject` now exists (A3); the other overrides were not audited.
  **Notes:** LANDED (27968f9d): raw Text unmount, BoundsAnchor unmount, pointer listener deactivate all go through maybeRenderObject. Pinned: a BoundsAnchor whose createRenderObject throws surfaces one error, not a compound.
- [ ] **N10** `P3` `LineChart`'s degenerate x padding is asymmetric (lone point at the left edge) while y is symmetric — centring x is a two-character change now, but a visible one.
  **Notes:**
- [x] **N11** `P3` `test/runtime/dead_control_warning_test.dart` is unformatted on main (`dart format` violation).
  **Notes:** LANDED: formatted.

## Recommended remaining work (2026-09-01, after the C pass)

Everything above the line is either landed or parked by design. What is
left splits by launch impact. Each item keeps its own entry; this is the
order I would take them in.

### Before launch

1. **13.b + 13.c + 13.d** — serve is a pillar and the app-first axis has zero coverage. Send the handshake at accept (no protocol change); 13.d reuses the 4001 close + reason the client now shows.
2. **3.c** — an app that opens `$EDITOR` looks frozen under the default `runApp` (the child inherits the capture pipe). Agent TUIs open editors. Needs the session-driver API decision.
3. **3.a** (then **2.d**) — dispatch Ctrl+Z first, suspend only if unhandled, like Ctrl+C. Both keymaps and the samples advertise `^Z undo`.
4. ~~**11.b + 11.e**~~ **LANDED** — edges now expire on the consumer's clock (the ticker), with the frame clock as the ticker-free fallback; one live publisher, arbitrated by the session. The harness shares the host wiring and latches at `render()`, so a widget test sees it.
5. **10.a** — serve and programmatic writes are unshielded; shift-select + Delete removes the wrong span. Direction (a): sanitize at the model boundary, document dropped bytes.
6. **15.a** (ack) — under the default dev supervisor a Ctrl+C on an app with a >300 ms teardown takes the force path. The raw-death half is fixed.
7. **16.g** — irreversible after publish. Ratify lockstep and add "republish both satellites" to the launch checklist.
8. ~~**1.a chunker (Q10) + N2**~~ — DONE (fb25c811): 512 KiB paste is 53 ms, 9 edits, 8 frames.
9. **4.a + 4.e** — the default state on ~19 of ~30 terminals; 4.e (an env var disabling the whole probe battery) is a plain bug.
10. **2.e** — the note already says "do now regardless"; needs the timing window.
11. **15.f, 15.h** — dev-loop correctness with well-shaped fixes (stale handle silently disables reload; supervisor starts even when it cannot supervise, paying double `main()` for nothing).
12. **13.e** — `--debug` is warned-as-ignored while the surface it controls is live. Decide which side owns the default.
13. **11.d** — cut or plumb `AnimationPolicy` before the surface freezes; it is exported API promising behaviour that does not exist.
14. **D1 + D3** — four tests that cannot fail, and a selection gate that never builds a SelectionArea. Cheap, and they restore trust in green.
15. **10.e, 6.g** — pick hook-vs-docs for form submit errors; fix the three docs claiming "built on Anchored" and add its test.

### After launch

8.g (scope-level focus fallback), 15.d (banner race), 5.e (row-wise join + separator decision), 10.d / 10.c (undo policy), 8.h, 4.b / 4.c (wrap and ellipsis under ambiguous-wide), 9.c, 3.b (contract doc), 14.c (Alt identity work), 2.c, 2.f, 9.e, D2 / D4 / D5, N8, N10, 3.e, 10.f, 13.f (doc), 15.c structural (RFC).

### Not tracker items

- A manual pass on a real terminal: editor sample `gg` / `dd`, Space leader with which-key, a dropdown then a tab switch, drag-select across a list. Every real catch in this project came from that kind of look.
- Push, PR, and let CI run the full `check` (this branch was verified per package because of disk pressure; the project-scaffold integration test did not run here).
- The alloc gate reads +1.3% over baseline on `main` itself (merge-base 847306f5), not on this branch. Find what moved between the 07-12 baseline and 08-28, or re-baseline deliberately with a note.
