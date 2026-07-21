# Launch-hardening architecture audit (2026-07-08)

**Status:** Findings report (analysis only)  
**Date:** 2026-07-08  
**Tree:** branch `fleury-main-sync`  
**Companions:**  
- [launch-bug-audit-2026-07-08.md](launch-bug-audit-2026-07-08.md) — correctness  
- [launch-perf-audit-2026-07-08.md](launch-perf-audit-2026-07-08.md) — performance gates & measurements  

**Primary sources:** current code under `packages/fleury/**`, `packages/fleury_widgets/**`, `packages/fleury_web/**`; architecture docs (`docs/architecture.md`, `architecture-overview.md`, RFCs 0007–0016); peer landscape as of mid-2026 scorecards; live bug/perf re-runs on this tree.

---

## Purpose

Assess Fleury’s **core architectural model** for launch: is the system shape sound for robust, performant terminal (and multi-surface) apps? How does it compare to the peer field? Where are structural strengths vs structural liabilities — as distinct from local bugs or micro-opts?

This is **not** a rewrite of `architecture.md` or a product roadmap. It is a review: validate the model, challenge it from first principles, and file comparative strengths/weaknesses with launch-priority recommendations.

---

## Executive summary

Fleury’s architecture is a deliberate, coherent bet:

> **Flutter’s retained multi-tree pipeline, rebuilt for a cell grid, with a first-class semantic graph, terminal-native I/O, and multi-surface presentation (ANSI TTY + embed DOM + served wire).**

Against the 2026 TUI field, that bet is **still the strongest available answer** for *app-scale, machine-legible, multi-surface* terminal software. No peer combines:

1. retained widget/element/render identity,  
2. a framework-owned semantic app graph with actions,  
3. damage-aware dual presenters (terminal + browser), and  
4. capability/security as framework policy —  

in one pure-Dart AOT-shippable stack.

**Architectural robustness** is high on the designed axes (incrementality, cleanup, host SPI, oracles, sanitize-by-default). Residual risk is not “wrong model” but **incomplete enforcement of the model’s own contracts** (lifecycle finalize after layout, dirty-queue recovery, serve plan ignoring damage bounds, palette/overlay scenario correctness, process gates outside CI). Those are architecture *discipline* gaps, not reasons to abandon the four trees.

**Architectural performance** is correctly positioned: compete on *app-shaped* incrementality and wire discipline, not OpenTUI/Ratatui raw buffer FPS. The retained-tree tax is real but measured and sub-millisecond for realistic rebuilds; the larger open lever is **presenter asymmetry** (ANSI can bound damage; serve plan still full-scans).

### Priority-ordered architecture findings

| P | ID | Title | Severity |
| --- | --- | --- | --- |
| P0 | A1 | Semantic graph is the flagship differentiator — must stay load-bearing | **high** (strategic) |
| P0 | A2 | Multi-surface host SPI is sound; serve path under-implements damage contract | **high** |
| P0 | A3 | Lifecycle/dirty contracts incomplete relative to Flutter-class model | **high** |
| P0 | A4 | App-kernel + overlay composition under churn is not yet architecture-proven (SB.8) | **high** |
| P1 | A5 | Four-tree retained model is correct for the product; tax is acceptable | **note** (strength) |
| P1 | A6 | Capability/security as first-class policy beats peer afterthoughts | **strength** |
| P1 | A7 | Pure Dart multi-target vs native-core peers — intentional, defendable | **strength w/ cost** |
| P1 | A8 | Verification machinery (oracles + gates) is architecture — CI still incomplete | **medium** |
| P1 | A9 | Full-screen-first product shape vs peer inline/CLI modes | **medium** (product/arch boundary) |
| P2 | A10 | Semantic incremental identity / agent surface still maturing | **medium** |
| P2 | A11 | Frame-rate policy default (uncapped) vs streaming workloads | **medium** |
| P2 | A12 | Package/host split is clean; git `stdio` dep is a distribution seam | **low** |

---

## 1. Fleury’s core architecture model (as implemented)

### 1.1 One app description, four retained trees

From `docs/architecture-overview.md` and `packages/fleury/lib/src/widgets/framework.dart` / `rendering/**` / `semantics/**`:

| Tree | Responsibility | Durable across rebuilds? |
| --- | --- | --- |
| **Widget** | Immutable configuration | No (throwaway) |
| **Element** | Identity, `State`, dependency edges, dirty scheduling | Yes |
| **RenderObject** | Cell constraints, layout, paint into `CellBuffer` | Yes (when type/key match) |
| **Semantics** | Roles, state, actions, geometry for tests/AT/agents/wire | Snapshot + dirty tracking; wire can patch |

Pipeline (event-driven, not continuous spin):

```
input / setState / ticker
  → schedule frame (microtask coalesce; optional rate cap)
  → flushBuild (dirty elements, shallow-first)
  → layout (constraints down, sizes up)
  → paint → damage-tracked CellBuffer
  → presentation plan (full / paint bounds / rows)
  → presenter: ANSI diff | remote plan | DOM apply
  → (deferred) semantic flush
```

Idle contract: no dirty work → **no paint, no bytes** (measured in expert assessment: 0 B / 0 CPU idle PTY).

### 1.2 Host SPI and multi-surface targets

```
App widgets
    │
    ▼
TuiRuntime  (BuildOwner, FocusManager, Binding, PointerRouter)
    │
    ▼
TuiFrameLoop + FrameDriver  (double buffer, damage, backpressure hook)
    │
    ├── AnsiFramePresenter     → Posix/Windows TerminalDriver
    ├── WireFramePresenter     → RemoteTerminalDriver / serve
    └── Browser host           → DOM grid + semantics (fleury_web)
```

Critical property: **core is presenter-agnostic and `dart:io`-free** for the web-safe barrels; native `runApp` and drivers hang off `fleury.dart` / host IO. That is the structural enabler for “same tree, terminal or browser.”

### 1.3 App kernel and toolkit layers

Above the engine (not optional glue for dense apps):

- **`FleuryApp` / commands / status** — typed command registry, palette integration, key hints.  
- **Focus / overlay / navigator** — scopes, routes, modal presentation.  
- **Editing engine** — grapheme-correct buffer, selection, history, paste policy, completion seams.  
- **Effects / tasks** — process tasks, cancellation, output capture, external editor handoff.  
- **Capability contract** — detect / require / degrade (color, mouse, images, clipboard…).  
- **`fleury_widgets`** — data-heavy and workflow widgets sharing semantics/copy conventions.

### 1.4 Safety and verification as architectural layers

| Layer | Role |
| --- | --- |
| Sanitize-by-default paint path | Untrusted subprocess/LLM text does not inject escapes |
| Terminal lifecycle | enter/restore, signals, handoff, zone-guarded cleanup |
| Diff oracles | Byte-equivalence (diff vs full repaint); semantics retained vs rebuild |
| Perf gates | Wire bytes, alloc/frame, image invariants, serve semantics anti-cliff |
| Semantic tester | Query/invoke by meaning, not cell scrape |

These are not accessories; they encode the product’s claim that dense, hostile, multi-surface apps are *framework-owned* concerns.

---

## 2. Peer architectural models (comparative map)

| Peer | Core model | Update discipline | Structure / meaning | Surfaces | Strength archetype |
| --- | --- | --- | --- | --- | --- |
| **Ratatui** | Immediate: rebuild view → buffer every frame | App owns loop; library diffs buffers | No framework semantic graph | Terminal (backends) | Minimal, explicit, max control, max perf headroom |
| **Bubble Tea v2** | TEA: `Model` / `Update` / `View → string` | Message pump; Cursed Renderer, sync output | Meaning lives in model + app tests | Terminal (+ Charm ecosystem) | Cleanest mental model; ecosystem taste |
| **Textual** | Widget DOM + CSS-like styles + compositor | Reactive messages/workers; full app shell | Strong widgets/devtools; not Flutter semantics tree | Terminal + **textual-web** | Mature full-app framework |
| **Ink** | React reconcile → stdout lines | React scheduler; often inline/scrollback | React DevTools; no terminal a11y graph | Stdout / CLI-shaped | Familiarity; streaming CLI |
| **OpenTUI** | Components over **native (Zig) buffer** | TS API over native core | Product-proven in OpenCode | Terminal (+ native throughput) | Native-core render ambition |
| **Nocterm** | Flutter-like widgets in Dart | Retained components, hot reload, tester | Widget/test harness; semantic graph parity weaker | Terminal | Closest Dart peer surface |
| **Fleury** | Flutter **four-tree** on cells + **semantics** + multi-host | Incremental dirty pipeline + presenters | Framework semantic graph + actions | Terminal + embed DOM + **serve wire** | App-scale retained + machine-legible + multi-surface |

### 2.1 Model families

```
Immediate buffer          Elm/TEA              React-reconcile         Flutter retained
(Ratatui)                 (Bubble Tea)         (Ink)                   (Nocterm ≈ surface;
                                                                        Fleury = full stack)
         \                   |                    |                              |
          \__________________|____________________|______________________________|
                                     Textual sits between React-DOM and full app framework
                                     OpenTUI sits at native buffer + component API
```

**Fleury’s family membership is Flutter retained**, not TEA and not immediate mode. Choosing that family implies:

- **Wins:** local state, keys, hot reload, incremental rebuild, layout caching, multi-surface abstract buffer.  
- **Costs:** element/render bookkeeping; harder mental model than TEA for tiny apps; must earn complexity with tools and widgets.

### 2.2 Where peers still win by architecture (not just polish)

| Peer win | Why architecture favors them |
| --- | --- |
| **Ratatui / OpenTUI raw throughput** | Fewer layers between app and buffer; no element tree; native core (OpenTUI) |
| **Bubble Tea conceptual simplicity** | One update function; no three-tree debugging |
| **Textual product maturity** | Years of app-shell, CSS, workers, docs, web serve as a *product* |
| **Ink inline/scrollback CLI** | Architecture assumes stdout region, not alt-screen app |
| **Nocterm “good enough Flutter-like”** | Smaller surface; may ship simpler apps faster if kernel/semantics not needed |

Fleury should **not** claim universal architectural superiority. It should claim superiority for a **category**: dense, long-lived, testable, agent-touchable, multi-surface terminal applications written in Dart.

---

## 3. Comparative strengths (architectural)

### S1 — Retained multi-tree incrementality is the right scale model

**Claim:** For app-scale screens with continuous partial updates, work must scale with *what changed*, not screen size.

**Fleury:** Dirty element queue, layout skip for clean same-constraint subtrees, paint damage tracking, repaint boundaries, scroll-up detection, frame skip when no visual work.

**Peers:**  
- Ratatui: full view rebuild; relies on buffer diff (cheap in Rust, still full app recompute).  
- Bubble Tea: view often rebuilds string representation of whole UI.  
- Ink: React reconciliation helps, but terminal mapping is line/stdout oriented.  
- Nocterm: retained, but without Fleury’s full damage→presenter stack and semantic shadow.

**Launch implication:** Strength is real and measured (SB.6/SB.12 sub-ms bands; idle zero work). Defend with gates, not slogans.

---

### S2 — Semantic app graph as a first-class tree (unowned peer position)

**Claim:** Machines (tests, agents, AT) need structure, not ANSI scrape.

**Fleury:** Roles, labels, values, actions, focus/selection state, redaction-aware inspection, wire semantics patches, MCP path, conformance tests over the widget catalog.

**Peers:**  
- Bubble Tea: model tests; no standard render-tree a11y (open a11y issues historically).  
- Textual: strong pilot testing; not the same “semantic action graph as product.”  
- Ink/React: DevTools, not terminal a11y tree.  
- Ratatui: buffer/golden.  
- **No peer ships a queryable render/semantic tree of the TUI as a primary feature.** Architecture priorities (2026-06-04) still correctly call this the flagship.

**Launch implication:** This is the **only durable architectural moat**. Everything else (Flutter-like API, benchmarks, widgets) is copyable or already peer-shared. Do not ship a launch story that demotes semantics to “nice testing helper.”

---

### S3 — Multi-surface host SPI (terminal / embed / serve)

**Claim:** One app definition; multiple presenters; parity oracle.

**Fleury:** Shared `TuiRuntime` + `TuiFrameLoop` + presentation plan; ANSI, remote plan codec, DOM host; `fleury serve` streams structured intent (not xterm.js ANSI relay).

**Peers:**  
- Textual-web / ttyd-class tools: usually **ANSI to emulator**.  
- Bubble Tea/Ink: terminal-primary.  
- OpenTUI: terminal/native.  

**Launch implication:** Structurally unique among TUI frameworks. Performance architecture must keep **damage contracts identical** across presenters (see W2) or the multi-surface claim becomes two half-products.

---

### S4 — Terminal truth as architecture (lifecycle, input, unicode, safety)

**Claim:** Terminal correctness beats Flutter purity when they conflict.

**Fleury evidence (expert assessment + code):** raw-mode lifecycle, signal/grace/handoff, Kitty keyboard, bracketed paste, grapheme/width (incl. VS16), sanitize-on-paint, capability detection, synchronized output, fd-level stray-output capture.

**Peers:** Individual peers match pieces (BT v2 renderer features, Textual maturity, Ratatui backends). Few stack **all** of them with a retained app model.

**Launch implication:** Engine room is a strength. Remaining “citizenship” gaps (hardware caret/IME, inline mode honesty, OSC title/links) are **finish-or-remove** at the product boundary, not model flaws.

---

### S5 — App kernel + data/workflow toolkit as framework, not sample code

**Claim:** Dense tools need commands, status, tasks, tables, logs, forms — not only `Text` and `Row`.

**Fleury:** `FleuryApp`, command registry, process tasks, DataTable/TreeTable/LogRegion/Markdown/… with shared semantics.

**Peers:** Textual is the maturity bar; Charm ecosystem is composition of libraries; Ratatui/Ink leave app structure to authors; Nocterm is closer but thinner on kernel/semantics.

**Launch implication:** Architectural *completeness* for the target category. Must not regress into “widget kit without app law” (commands/focus/overlay invariants — see W3).

---

### S6 — Verification and gates as part of the architecture

**Claim:** Incremental systems require oracles or they rot.

**Fleury:** Diff oracles, semantics divergence oracles, DOM parity, wire/alloc/image/semantics gates, scenario lab.

**Peers:** Ratatui Criterion, OpenTUI native benches, Textual tests — strong in places; few couple **semantic retained/rebuild oracles** with **wire byte gates** and **multi-surface parity**.

**Launch implication:** Strength only if gates actually run (CI/process). Architecture without enforcement is aspirational.

---

## 4. Comparative weaknesses (architectural)

### W1 — Complexity tax of the Flutter model

**Nature:** Structural cost of the family.

| Cost | Manifestation |
| --- | --- |
| Learning curve | Three trees + semantics vs TEA’s one loop |
| Bug classes | Dirty/inactive lifecycle, key collisions, reentrancy (see bug audit F1–F4) |
| Debug surface | Need inspector + semantics; “just print the view” is harder |
| Tiny-app overhead | Counter app heavier than Bubble Tea/Ink for trivial CLIs |

**Vs peers:** Bubble Tea and Ratatui win “hello world” and teaching simplicity by design. Fleury should **own** dense apps and **not** market itself as the smallest CLI toolkit.

**Mitigation already present:** Error boundaries, debug shell, semantic tester, goldens.  
**Still weak:** Incomplete lifecycle finalize (bug F1/F5); dirty-queue recovery (F2).

---

### W2 — Presenter asymmetry breaks the multi-surface contract

**Nature:** Architecture says “one damage plan, many presenters.” Implementation favors ANSI.

| Path | Damage-aware? | Evidence |
| --- | --- | --- |
| ANSI `renderDiff` | Yes (`dirtyBounds`) | ~180× faster sparse 160×50 in perf audit |
| Serve `buildRemotePlan` | **No** — full grid stats + patches | ~589 µs sparse for 24 B encoded |
| Semantics wire | Diff/patch + DEFLATE | Gate green; rebuild cost separate |

**Vs peers:** Single-surface peers do not have this consistency obligation. Fleury **created** the obligation by choosing multi-surface.

**Launch implication:** Highest architectural performance liability. Until serve honors the same damage model, “one pipeline” is only half true.

---

### W3 — App-shell composition under churn not yet architecture-proven

**Nature:** Kernel + navigator + overlay + palette is the hard part of “app framework.”

**Evidence:** SB.8 fails correctness consistently (stale palette after close, route depth mismatches, zero screen-command invokes) — perf audit P1. Latency is fine; **invariants are not**.

**Vs peers:** Textual’s age shows here; Bubble Tea apps invent structure per app (sometimes simpler because less framework magic).

**Launch implication:** The architecture *includes* app kernel; a red SB.8 means that layer is not yet launch-grade, regardless of engine excellence.

---

### W4 — Semantic identity and incremental graph still dual-mode

**Nature:** Flagship feature still has snapshot-local ids for unkeyed nodes; full live incremental graph is a trajectory (RFC 0011, architecture priorities P1).

**Vs peers:** Still ahead of zero; but agent-drive stability under list churn needs keys/ids (bug audit F11). Architecture risk: **promising a live graph while shipping mostly rebuilt snapshots + wire patches**.

**Launch implication:** Ship honest claims: “semantic testing + wire inspection today; stable ids require author keys; live incremental backend without breaking API.” Don’t claim universal AT/agent stability for unkeyed demos.

---

### W5 — Full-screen product architecture vs peer inline/CLI architecture

**Nature:** Peers (Ink especially, BT/Ratatui inline patterns, Textual) cover “live region in scrollback.” Fleury’s public `TerminalMode.inline` is incomplete (expert assessment; RFC 0016). Architecture is **alt-screen application**-first.

**Vs peers:** Not a bug if the product is Crush/OpenCode-class apps; it **is** a market-coverage hole for installers, build tools, wizards.

**Launch implication:** Architecture decision: either implement real inline or remove the public lie before freeze. Exit-persistence for alt-screen is a cheaper adjacent design.

---

### W6 — Pure Dart vs native-core performance architecture

**Nature:** Explicit decision: no Zig/Rust core; preserve web + hot reload + AOT single binary.

**Vs peers:** OpenTUI/Ratatui can win raw cell paint throughput. Fleury’s measured position is often **wire-competitive / CPU ballpark**, not “always fastest.”

**Launch implication:** Correct strategic trade if messaging is honest. Do not re-open native core pre-launch; invest in damage-bound presenters and gates instead.

---

### W7 — Process architecture: gates outside CI, silent local fails

**Nature:** Verification-as-architecture requires continuous enforcement.

**Evidence:** No CI perf gates; `benchmark local` exit 0 on SB.8 fail; wire-gate `--gate` CLI mismatch (perf audit P4).

**Vs peers:** Mature projects encode benches in CI more often (Ratatui Criterion, etc.).

**Launch implication:** Without CI, the architecture’s self-honesty erodes under time pressure.

---

## 5. Robustness assessment

### 5.1 What the model makes robust

| Concern | Architectural answer | Peer comparison |
| --- | --- | --- |
| Partial UI updates | Dirty rebuild + layout skip + damage | Stronger than TEA/immediate for large trees |
| Terminal leave-broken | Layered restore + signals + handoff | Peer-competitive / better than many |
| Untrusted output | Sanitize at paint boundary | Ahead of “escape in the app” peers |
| Testing without flaky goldens | Semantic graph + tester | Differentiator |
| Multi-session serve isolation | Host SPI + spawn sessions | Unique class of problem; hardening incomplete (bug F8/F9) |
| Hot reload | Element-preserving reassemble | Nocterm/Flutter-class; TEA harder |

### 5.2 Where robustness is not yet equal to the model

| Gap | Why architectural | Severity |
| --- | --- | --- |
| Layout-time deactivate without finalize (bug F1) | Flutter model **requires** post-layout or end-of-frame finalize of inactive elements | high |
| Dirty bit / queue desync on flush abort (bug F2) | Scheduler invariant is load-bearing for “always recoverable UI” | high |
| Input reentrancy mid-frame (bug F4) | Frame is a critical section in retained systems | medium |
| OSC 52 vs fd-capture (bug F6) | Host services must use the same output ownership model as frames | high |
| SIGTSTP write exclusivity (bug F7) | Lifecycle modes must be exclusive like handoff | high |
| SB.8 overlay invariants | App-kernel architecture unproven under churn | high |
| Serve session/INIT unbounded (bug F8/F9) | Multi-process surface needs admission control in the arch | high if serve shared |

**Verdict:** The architecture is **robust by design** and **not yet fully self-enforcing**. Launch hardening is closing the gap between design and invariant enforcement — exactly the right work.

---

## 6. Performance architecture assessment

### 6.1 Where the model is strong

| Mechanism | Role | Evidence |
| --- | --- | --- |
| Event-driven frames | Zero idle cost | Expert assessment PTY idle |
| Microtask coalescing | N setStates → 1 frame / turn | Scheduler tests |
| Layout dirtiness cache | Paint-only / idle skip layout | SB.12 |
| Damage-bounded ANSI | Sparse updates cheap | Perf audit experiments |
| Wire byte discipline | Cursor/SGR budgets, sync skip, image fast path | wire-gate, image-bench |
| Semantics off hot path + wire patch | Avoid DEFLATE cliff | serve-semantics-gate |
| Alloc-gate | Floor against silent per-frame churn | flat baseline |

### 6.2 Structural performance liabilities

| Liability | Model source | Severity |
| --- | --- | --- |
| Retained-tree bookkeeping | Element/render identity | Acceptable (measured sublinear; not launch blocker) |
| Immutable `Cell` write churn | Pure paint model | Medium ceiling (~6 KiB/frame gated) |
| Full back-buffer clear | Simple correctness | Low; intentional |
| Serve full-grid plan | Presenter incomplete | **High** — arch inconsistency |
| Uncapped default frame rate | Streaming producers | Medium for log/agent UIs |
| Full semantic rebuild before patch | Snapshot-oriented semantics | Medium; mitigated by wire |

### 6.3 Comparative performance posture (honest)

| Axis | Fleury posture | Prefer peer if… |
| --- | --- | --- |
| Bytes/frame (sparse TUI) | Competitive / leading on several SB wire scenarios | Absolute minimal CLI |
| CPU per full repaint | Trails native/immediate | Shader-like full-screen art |
| App-shaped update latency | Strong (sub-ms dashboard) | N/A |
| 100k-row navigation | Strong with virtualization | Pure Rust table microbench with fixture parity caveats |
| Multi-surface cost | Unique; serve CPU must catch ANSI | Single-surface only apps |

**Strategic architecture stance (reaffirmed):** do not race OpenTUI/Ratatui on raw paint; race on **deterministic incrementality + wire + semantics + multi-surface honesty**.

---

## 7. Architecture decision scorecard (launch)

| Decision | Keep / change | Rationale |
| --- | --- | --- |
| Four trees (W/E/R/S) | **Keep** | Required for semantics + multi-surface + incrementality |
| Pure Dart, no native core | **Keep** | Web + hot reload + AOT; perf ballpark proven |
| CellBuffer abstract intermediate | **Keep** | Presenter seam |
| Semantic graph flagship | **Keep & invest** | Only unowned moat |
| App kernel in core | **Keep; prove with SB.8** | Category definition |
| Serve structured plan (not ANSI relay) | **Keep; finish damage path** | Differentiator requires parity |
| Capability/security policy | **Keep** | Category safety |
| Full-screen default | **Keep product; fix or remove inline API** | Honesty at freeze |
| Opt-in frame interval | **Keep API; recommend caps in demos/serve** | Streaming realism |
| Gates local-only | **Change process** | Arch integrity requires CI |

---

## 8. Interaction with bug & perf audits

Architecture is validated when companion audits find **enforcement gaps**, not **model failures**:

| Companion finding | Architectural reading |
| --- | --- |
| F1 layout dispose | Element lifecycle contract incomplete |
| F2 dirty stranding | BuildOwner invariant incomplete |
| F6 OSC 52 | Host service not on presenter output path |
| F8/F9 serve DoS | Multi-process surface needs admission architecture |
| P1 SB.8 fail | App-kernel architecture unproven |
| P2 serve plan full scan | Multi-surface damage contract incomplete |
| P4 gates/CI | Verification architecture not operationalized |

None of these recommend switching to TEA or immediate mode. They recommend **finishing the contracts the Flutter-class model already assumes**.

---

## 9. Prioritized recommendations

### P0 — Before architecture-level launch claims

1. **Treat the semantic graph as non-negotiable launch surface** (docs, demos, tests, serve). Do not demote it in positioning.  
2. **Unify damage across presenters** — `buildRemotePlan` must consume the same presentation damage ANSI uses (perf P2).  
3. **Close Flutter-class lifecycle gaps** — post-layout/inactive finalize; dirty-queue recovery (bug F1/F2/F5).  
4. **Make SB.8 green** — app-kernel/overlay invariants are architectural for “full app framework.”  
5. **Operationalize verification** — CI fast gates; non-zero exit on failed scenarios; serve admission/INIT deadlines if serve is public.

### P1 — Strengthen the moat

6. Stable semantic ids on interactive demo widgets; honest agent claims.  
7. Hardware caret / IME on terminal path (citizenship; expert #1).  
8. Decide inline: implement (RFC 0016) or remove public stub; consider exit persistence.  
9. Streaming defaults: frame interval guidance for serve/log demos.  
10. Finish-or-remove half APIs (OSC title, hyperlinks capability).

### P2 — Non-goals / do not thrash

11. Native render core — out of strategy.  
12. Broad Cell pooling / zero-alloc paint — only with baselines after P0.  
13. Public peer “we’re fastest” claims without fixture-parity scoreboard.  
14. Expanding TEA-like dual APIs — confuses the model.

---

## 10. Comparative “when to choose whom” (architecture lens)

| If you need… | Prefer |
| --- | --- |
| Smallest mental model, Go ecosystem taste | Bubble Tea |
| Absolute control / max raw throughput / Rust | Ratatui |
| Mature Python app framework + CSS + docs | Textual |
| React/npm CLI, inline streaming | Ink |
| Native-core TS agent product | OpenTUI |
| Flutter-like Dart without Fleury’s kernel/semantics | Nocterm (lighter) |
| **Dense Dart apps, semantic tests/agents, multi-surface, capability safety** | **Fleury** |

---

## 11. Bottom line

Fleury’s architecture is **coherent, category-correct, and competitively distinctive**. The Flutter four-tree model plus a semantic graph plus multi-surface presenters is a stronger fit for 2026 terminal *applications* than TEA, pure immediate mode, or React-CLI alone — provided the team finishes enforcing the contracts that model implies.

**Architectural robustness:** high design quality; medium-high if lifecycle, serve admission, and app-kernel invariants land.  
**Architectural performance:** sound strategy (incrementality + wire); primary structural fix is **presenter damage parity**, not abandoning retained mode.  
**Comparative position:** lead on semantics + multi-surface + Dart retained app stack; concede raw throughput and “tiny CLI simplicity” to specialists; respect Textual’s maturity while offering a typed Flutter-shaped alternative.

Launch is an **enforcement and honesty** problem more than a **redesign** problem.

---

## Related documents

| Doc | Use |
| --- | --- |
| [../architecture.md](../architecture.md) | Narrative architecture |
| [../architecture-overview.md](../architecture-overview.md) | Four trees + targets map |
| [architecture-priorities.md](architecture-priorities.md) | Living arch priorities / semantic flagship |
| [peer-scorecards.md](peer-scorecards.md) | Scenario/peer evidence |
| [perf-architecture-recommendations.md](perf-architecture-recommendations.md) | Prior perf-arch conclusions |
| [expert-assessment-2026-07-05.md](expert-assessment-2026-07-05.md) | Engine-room validation |
| [launch-bug-audit-2026-07-08.md](launch-bug-audit-2026-07-08.md) | Correctness findings |
| [launch-perf-audit-2026-07-08.md](launch-perf-audit-2026-07-08.md) | Perf findings |
| RFCs 0007, 0011, 0012, 0013, 0016 | Framework, semantics, app kernel, capability, inline |

---

## Method note

This audit synthesizes:

1. **Code structure** (framework, runtime, remote, semantics, host SPI).  
2. **First-party architecture docs and RFCs** (model as intended).  
3. **Peer model comparison** from primary frameworks’ public models (TEA, immediate, React, Flutter-like, native-core).  
4. **Empirical companions** (bug + perf audits on this tree) as enforcement checks on architectural claims.

It does not re-run peer binaries in this pass; peer performance claims remain as previously scorecarded and should not be restated as new absolute rankings without fresh comparable captures.
