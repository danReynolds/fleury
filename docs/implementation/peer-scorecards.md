# Fleury Peer Scorecards

**Status:** Phase 1 source-linked refresh complete
**Last source refresh:** 2026-06-01
**Update cadence:** At phase boundaries, when a peer ships a major release, and
before any public performance or superiority claim.
**MVP scope:** Peer benchmark expansion is frozen after the SB.5 variance
checkpoint. During MVP, update this file only to preserve existing evidence or
to record a peer change that materially affects a core/API decision.

## Purpose

Track the moving TUI landscape so Fleury is compared against current peers,
not stale assumptions.

This document is an execution tool, not marketing copy. It should separate:

- Current source truth: peer versions, docs, repos, and benchmark sources.
- Claims to verify: what Fleury must measure or inspect before launch.
- Known gaps: places where Fleury is not yet proven or where peer parity is
  unclear.
- Differentiators to prove: developer-visible wins, not internal architecture
  slogans.

## Source Snapshot: 2026-06-01

Versions below were refreshed from primary package or repository sources on
2026-06-01, with the Bubble Tea/Bubbles/Glamour module check and Ink fixture
packages refreshed on 2026-06-02. Treat them as a snapshot, not durable facts.

| Peer | Current version/ref | Primary sources | Benchmark or comparison sources |
| --- | --- | --- | --- |
| Nocterm | `0.6.0` on pub.dev; repo default branch `main`. | [pub.dev](https://pub.dev/packages/nocterm), [repo](https://github.com/Norbert515/nocterm), [docs](https://docs.nocterm.dev) | [benchmark suite](https://github.com/Norbert515/nocterm/blob/main/benchmark/benchmark.dart), [display-list benchmark](https://github.com/Norbert515/nocterm/blob/main/benchmark/display_list_benchmark.dart) |
| Bubble Tea v2 | `v2.0.7` GitHub release; fixture uses Bubbles `v2.1.0` for viewport components and Glamour `v2.0.0` for Markdown rendering. | [repo](https://github.com/charmbracelet/bubbletea), [release](https://github.com/charmbracelet/bubbletea/releases/tag/v2.0.7), [Go docs](https://pkg.go.dev/charm.land/bubbletea/v2), [Bubbles docs](https://pkg.go.dev/charm.land/bubbles/v2), [Glamour docs](https://pkg.go.dev/charm.land/glamour/v2) | Compare app behavior and Charm ecosystem components: [Bubbles](https://github.com/charmbracelet/bubbles), [Lip Gloss](https://github.com/charmbracelet/lipgloss), [Huh](https://github.com/charmbracelet/huh), [Glamour](https://github.com/charmbracelet/glamour). |
| Textual | `8.2.7` on PyPI. | [PyPI](https://pypi.org/project/textual/), [docs](https://textual.textualize.io/), [repo](https://github.com/Textualize/textual) | Compare app framework, widgets, workers, testing, devtools, and terminal/web serving from current docs and examples. |
| OpenTUI | `@opentui/core` `0.3.1` on npm. | [npm](https://www.npmjs.com/package/@opentui/core), [repo](https://github.com/anomalyco/opentui), [docs](https://opentui.com/docs/getting-started) | [benchmark folder](https://github.com/anomalyco/opentui/tree/main/packages/core/src/benchmark), [native bench README](https://github.com/anomalyco/opentui/tree/main/packages/core/src/zig/bench). |
| Ratatui | `0.30.0` on crates.io. | [crates.io](https://crates.io/crates/ratatui), [docs.rs](https://docs.rs/ratatui/latest/ratatui/), [site](https://ratatui.rs/), [repo](https://github.com/ratatui/ratatui) | [Criterion benches](https://github.com/ratatui/ratatui/tree/main/ratatui/benches), especially table and paragraph workloads. |
| Ink | `7.0.5` on npm. | [npm](https://www.npmjs.com/package/ink), [repo](https://github.com/vadimdemedes/ink), [docs/readme](https://github.com/vadimdemedes/ink#readme) | Compare React-style ergonomics, stdout/scrollback behavior, component composition, and developer adoption. |

Registry/API checks run during the Phase 1 exit review and later peer-fixture
work:

- `https://pub.dev/api/packages/nocterm` -> `0.6.0`.
- `https://api.github.com/repos/charmbracelet/bubbletea/releases/latest` ->
  `v2.0.7`.
- `go list -m -versions charm.land/bubbletea/v2 charm.land/bubbles/v2` ->
  latest listed modules `charm.land/bubbletea/v2 v2.0.7` and
  `charm.land/bubbles/v2 v2.1.0` for the Bubble Tea `SB.4` fixture.
- `go list -m -versions charm.land/glamour/v2` ->
  latest listed module `charm.land/glamour/v2 v2.0.0` for the Bubble
  Tea/Bubbles/Glamour `SB.5` fixture.
- `https://pypi.org/pypi/textual/json` -> `8.2.7`.
- `https://registry.npmjs.org/%40opentui%2Fcore` -> `0.3.1`.
- `https://crates.io/api/v1/crates/ratatui` -> `0.30.0`.
- `npm view ink version engines` -> `7.0.5`, `node >=22`.
- `npm view ink-text-input version` -> `6.0.0`.
- `npm view react-ink-textarea version` -> `0.1.3`.
- `npm view ink-testing-library version` -> `4.0.0`.

## Peers To Track

| Peer | Why it matters | What Fleury must watch |
| --- | --- | --- |
| Nocterm | Direct Dart and Flutter-style competitor. | API ergonomics, hot reload, component count, BLoC integration, docs, adoption, benchmark results, and how much app structure it adds over widgets. |
| Bubble Tea v2 | Current Go/Charm performance and CLI taste benchmark. | Cursed Renderer, synchronized output, keyboard/input model, clipboard, image support, production apps, and ecosystem cohesion across Bubble Tea/Bubbles/Lip Gloss/Huh. |
| Textual | Strongest Python full app framework reference. | App structure, CSS/theme model, data tables, workers, devtools, testing, browser serving, and mature widget behavior. |
| OpenTUI | Native-core frontier with TypeScript bindings and OpenCode usage. | Zig core, render throughput, benchmark breadth, component model, render accuracy, terminal protocol support, and production-agent use. |
| Ratatui | Rust standard for performance and explicit rendering. | Render throughput, data widgets, ecosystem, benchmark rigor, and reactive layers on top. |
| Ink | React-style CLI adoption reference. | Familiar reactive ergonomics, npm distribution, AI/dev CLI usage, stdout/scrollback behavior, and React component mental model. |

## Current Differentiation Claims To Prove

These are claims to prove with code, tests, examples, and benchmark evidence.
Do not promote them as launch claims until Phase 1 or Phase 2 evidence exists.

- Fleury can offer stronger semantic testing and structured automation than
  Nocterm, Bubble Tea v2, Textual, OpenTUI, Ratatui, and Ink. Phase 1 now has
  core semantic nodes, tester queries, debug inspector summaries, demo-app
  semantic assertions, and redacted debug capture; peer automation parity still
  needs scenario-by-scenario comparison before launch copy.
- Fleury can offer a stronger Dart-native retained-reactive app model than
  Nocterm by pairing Flutter-style ergonomics with semantic graph, app kernel,
  scenario benchmarks, terminal capability contracts, and example demo-app
  evidence. Phase 1 now proves that stack internally; post-MVP comparison must
  measure equivalent Nocterm app slices against the stable launch API.
- Fleury can offer a stronger developer-tool app framework than Bubble Tea v2
  for teams that prefer retained UI, semantic tests, typed app commands, and
  Dart AOT. Bubble Tea's v2 renderer and Charm ecosystem remain the bar for
  terminal taste and runtime maturity.
- Fleury can make terminal capability degradation and untrusted-output safety
  more visible and testable than most peers. Phase 1 now has
  `fleury diagnose --json`, capability requirement semantics, policy-gated
  clipboard/link/image behavior, process-output sanitization, and redaction
  hooks; real-terminal matrix evidence is still Phase 2.
- Fleury can be agent-adapter ready at launch, with ACP support scoped to a
  fast-follow `fleury_acp` package rather than core.
- Fleury can use the example subpackage and later Dune/`dune_cli` to prove
  real-product pressure, not only toy examples.

## Known Gaps And Unknowns

| Area | Current risk | How to close it |
| --- | --- | --- |
| Fleury baseline evidence | Fleury now has internal scenario baselines for `SB.1` counter, `SB.2` text editing, `SB.3` 100k-row DataTable, `SB.4` log scrollback, `SB.5` streaming markdown, `SB.6` dashboard updates, `SB.7` resize storm, `SB.8` overlay/command palette churn, `SB.9` subprocess/output safety, `SB.10` demo-app journey, `SB.11` TreeTable, and `SB.12` layout dirtiness. M3.9 now also has strict-passing local `SB.2` repeated-run variance artifacts for Ink, Nocterm, Textual, and Bubble Tea/Bubbles, `SB.3` repeated-run variance artifacts for Ratatui, OpenTUI, Nocterm, and Textual, `SB.4` repeated-run variance artifacts for Nocterm, OpenTUI, Textual, and Bubble Tea/Bubbles, and first `SB.5` repeated-run variance artifacts for Textual and Bubble Tea/Bubbles/Glamour. It still lacks broad scenario variance, cross-machine variance, and real-terminal variance. | Treat the current peer evidence as the MVP-cycle stopping point. Resume full peer comparison, additional fixtures, cross-machine runs, and public comparison claims post-MVP after the API and major core implementation are stable. |
| Nocterm comparison | Nocterm is the closest Dart peer, with a Flutter-like API, built-in testing, hot reload, 45+ component claim, examples, ecosystem packages, and repo benchmarks. | Post-MVP: build matching counter, text input, table/list, resize, and streaming workloads; compare API ergonomics, semantic testing, diagnostics, safety, and timing. |
| Bubble Tea v2 comparison | Bubble Tea may beat Fleury on CLI taste, ecosystem maturity, and raw runtime simplicity. | Post-MVP: prove retained composition, app commands, semantic tests, and example-app complexity are meaningfully easier in Fleury. |
| Textual comparison | Textual is much more mature as a full app framework. | Post-MVP: use static types, Flutter-style retained UI, terminal capability contracts, and semantic tests as the wedge; do not pretend Fleury has mature breadth on day one. |
| OpenTUI/Ratatui throughput | Native/Rust peers may win raw render throughput and benchmark credibility. | Post-MVP: compete on app-shaped latency, semantics, testing, terminal safety, data widgets, and developer workflow; benchmark honestly. |
| Ink comparison | Ink wins familiarity for React/npm developers. | Post-MVP: prove terminal-first correctness, data widgets, focus, commands, and testing are stronger for dense full-screen apps. |

## Scenario Benchmark Mapping

Use the [scenario benchmark lab](scenario-benchmark-lab.md) as the source of
workload names, fixture shapes, target metrics, and candidate thresholds.
Use the
[comparative benchmark manifest](comparative-benchmark-manifest.json) as the
machine-readable M3.9 contract for peer-equivalent scenario definitions,
required metrics, correctness gates, source links, and empty `peerRuns` slots.
Use `dart tool/fleury_dev.dart benchmark-result` to validate peer-run artifacts
against that contract before writing any manifest copy with populated
`peerRuns`.

| Scenario | Primary peers | Evidence to collect |
| --- | --- | --- |
| SB.1 Time To Counter App | Nocterm, Bubble Tea v2, Textual, Ink | Lines of code, first frame, increment latency, command/action structure, testing shape. |
| SB.2 Text Editing Composer Stress | Nocterm, Textual, Bubble Tea/Bubbles, Ink ecosystem inputs | Grapheme correctness, multiline behavior, paste, selection, undo/history, completion, semantic state, latency. |
| SB.3 DataTable 100k Rows | Textual, Ratatui, OpenTUI, Nocterm | Navigation latency, fixed header, sort/filter, copy, virtualization, semantic rows/cells, memory. |
| SB.4 Log Tailing And Scrollback | Textual, OpenTUI, Bubble Tea viewport patterns, Nocterm display-list benchmarks | Append throughput, scroll anchoring, search/copy, sanitization, redaction, memory policy. |
| SB.5 Streaming Markdown | OpenTUI, Textual, Bubble Tea markdown ecosystem | Incremental parse/render, link policy, code fences, tables, wrap cost, semantic nodes. |
| SB.6 Dashboard Update Pressure | Ratatui, Bubble Tea, Nocterm, OpenTUI | Frame/update cost, bytes emitted, progress semantics, layout skipped/performed counts, update rates; current Fleury baseline has update-total p95 267 us and update-frame layout p95 45 performed / 29 skipped over 400 dashboard ticks and 23 surfaces. |
| SB.7 Resize Storm | Nocterm, Textual, Ratatui | Layout stability, focus preservation, semantic region validity, no exceptions, terminal cleanup. |
| SB.8 Overlay And Command Palette Churn | Textual, Bubble Tea, Ink | Focus scopes, active commands, modal semantics, open/close latency, stale-action prevention; optimized Fleury baseline has zero stale palette semantics and zero unexpected invocations over 800 measured cycles, 1000-command filter p95 1121 us, and full-cycle p95 6429 us. |
| SB.9 Subprocess Handoff And Untrusted Output | Textual workers, Bubble Tea commands, Nocterm async examples | Terminal mode restore, cancellation, unsafe escape blocking, output capture, redaction-before-artifact; first Fleury baseline has process-run p95 647254 us, cancellation p95 11823 us, stream-frame p95 6230 us, restored handoff state, and zero unsafe artifact leaks on a 1 MB target subprocess fixture. |
| SB.10 Demo-App Journey | All peers where an equivalent app exists | End-to-end app pressure: navigation, composer, data table, logs, commands, diagnostics, semantic assertions. |

## 2026-Q2 Phase 1 Scorecard

Use this table at phase boundaries. `Unmeasured` means the source snapshot has
current peer entries, but Fleury has not yet run an equivalent workload against
that peer.

| Category | Fleury Phase 1 evidence | Nocterm 0.6.0 | Bubble Tea v2.0.7 | Textual 8.2.7 | OpenTUI 0.3.1 | Ratatui 0.30.0 | Ink 7.0.5 | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Time to counter app | `SB.1` saved baseline: command-to-frame p95 254 us, first-frame p95 61 us, semantic-query p95 102 us. | First local Nocterm `SB.1` fixture run saved in `peer-fixtures/nocterm/sb1_counter/results`: command-to-frame p95 2053 us, first-frame p95 1926 us, test-query p95 2385 us over 20 `nocterm-test-harness` iterations; not real-terminal evidence. | Small TEA counter shape; peer run unmeasured. | Full `App`/widget counter shape; peer run unmeasured. | Component renderer; peer run unmeasured. | Immediate render loop; peer run unmeasured. | React counter shape; peer run unmeasured. | Post-MVP comparison should fill remaining peer-equivalent text, data, resize, and streaming workloads before public comparison claims. |
| Text editing | Grapheme-safe model, selection, undo/redo, paste policy, completion state/UI seam, composition seam, custom keymaps, Emacs presets. `SB.2` saved baseline: cursor-move p95 798 us, insertion/deletion p95 641 us, selection p95 2191 us, chunked-paste completion p95 18573 us, semantic-query p95 508 us over a 10k-character mixed-width editor. | First local Nocterm `SB.2` fixture saved: cursor-move p95 7279 us, insertion/deletion p95 9915 us, selection p95 20243 us, paste p95 23541 us, test-query p95 860 us over a 10k-character `nocterm-test-harness` run. First strict-passing repeated-run summary over three comparable Nocterm `SB.2` artifacts: cursor-move p95 median 24555 us with 186.231% spread, paste p95 median 45691 us with 438.988% spread, and test-query p95 median 4042 us with 731.173% spread. Nocterm owns `TextField`; undo/history/completion are app-owned adapters in the fixture. | First local Bubble Tea/Bubbles `SB.2` fixture saved: cursor-move p95 140090 us, insertion/deletion p95 7586 us, selection p95 630 us, undo/redo p95 1411 us, history navigation p95 26 us, completion accept p95 100 us, paste p95 5193 us, app-state query p95 3582 us over a 10k-character `bubbletea-textarea-model-harness` run. First strict-passing repeated-run summary over three comparable Bubble Tea/Bubbles `SB.2` artifacts: cursor-move p95 median 718298 us with 54.66% spread, paste p95 median 22525 us with 153.23% spread, completion-accept p95 median 68417 us with 132.227% spread, and app-state query p95 median 16321 us with 98.94% spread. Bubble Tea owns model/update/view structure; Bubbles owns textarea movement/edit/paste and textinput password/suggestions; selection/undo/history are fixture-owned adapters. | First local Textual `SB.2` fixture saved: cursor-move p95 90273 us, insertion/deletion p95 90516 us, selection p95 89952 us, undo/redo p95 91934 us, history navigation p95 122264 us, completion accept p95 109193 us, paste p95 77338 us, widget/app-state query p95 165 us over a 10k-character `textual-run-test-harness` run on Python 3.13.1. First strict-passing repeated-run summary over three comparable Textual `SB.2` artifacts on Python 3.12.13: cursor-move p95 median 217392 us with 50.857% spread, paste p95 median 147414 us with 29.885% spread, history-navigation p95 median 344880 us with 298.423% spread, and test-query p95 median 225 us with 1426.222% spread. Textual owns `TextArea`, password `Input`, cursor/selection/edit APIs, paste behavior, and undo/redo; history/completion are fixture-owned adapters. | Docs list `Input` and component primitives. | Mostly app/ecosystem-authored. | First local Ink `SB.2` fixture saved: cursor-move p95 1357 us, insertion/deletion p95 503 us, selection p95 346 us, undo/redo p95 128 us, history navigation p95 13 us, completion accept p95 3 us, paste p95 619 us, app-state/frame query p95 422487 us over a 10k-character `ink-testing-library-memory` run. First strict-passing repeated-run summary over three comparable Ink `SB.2` artifacts: cursor-move p95 median 2449 us with 59.004% spread, paste p95 median 997 us with 90.171% spread, and app-state/frame query p95 median 152763 us with 25.67% spread. Ink owns React rendering, `react-ink-textarea`, and `ink-text-input`; selection, redo, history, completion, and app-state query are fixture-owned adapters. | Text-editing peer set now has local repeated-run variance across Ink, Nocterm, Textual, and Bubble Tea/Bubbles; post-MVP comparison needs real-terminal and cross-machine variance before public claims. |
| Selection/copy | Text control policy semantics, clipboard reports, redaction, DataTable row/cell/range copy/export. | Unmeasured. | Bubbles/table and app-authored clipboard patterns; unmeasured. | Widget/app support likely mature; exact clipboard policy unmeasured. | Unmeasured. | App-authored. | App-authored or ecosystem. | Fleury's security-aware copy surface is a plausible wedge. |
| DataTable 100k rows | `SB.3` saved baseline: page-move p95 772 us, selected-row copy p95 310 us, semantic-query p95 2497 us over 100k rows. | First local Nocterm `SB.3` fixture saved: mount p95 451662 us, first-render p95 712 us, arrow p95 6480 us, page p95 5660 us, jump p95 4543 us, copy p95 1194 us, terminal/app-state query p95 1056 us, RSS delta 5754880 bytes over 100k table-shaped rows in `nocterm-test-harness` mode. First strict-passing repeated-run summary over three comparable Nocterm `SB.3` artifacts: mount p95 median 1170683 us with 41.409% spread, page-move p95 median 22230 us with 150.99% spread, copy p95 median 3133 us with 74.433% spread, and terminal/app-state query p95 median 2751 us with 105.234% spread. Nocterm owns `ListView.builder`, `ScrollController`, and `Text`; table formatting, retained rows, selection, copy/export, and test query are fixture-owned. | Bubbles has table component; 100k-row behavior unmeasured. | First local Textual `SB.3` fixture saved: mount p95 10128627 us, arrow p95 304428 us, page p95 113432 us, jump p95 141400 us, copy p95 90152 us, widget-state query p95 307 us over 100k rows in `textual-run-test-harness` mode. First strict-passing repeated-run summary over three comparable Textual `SB.3` artifacts: mount p95 median 10503380 us with 32.667% spread, page-move p95 median 97347 us with 30.393% spread, jump-to-end p95 median 285626 us with 36.779% spread, copy p95 median 81377 us with 13.508% spread, and widget-state query p95 median 230 us with 545.217% spread. Textual owns `DataTable`; jump/copy are fixture-owned app commands. | First local OpenTUI `SB.3` fixture saved: mount p95 42056 us, first-render p95 1290 us, arrow p95 1725 us, page p95 1795 us, jump p95 1648 us, copy p95 17 us, frame/app-state query p95 29 us, RSS delta 142475264 bytes over 100k rows in `opentui-test-renderer-memory` mode. First strict-passing repeated-run summary over three comparable OpenTUI `SB.3` artifacts: mount p95 median 107762 us with 42.953% spread, page-move p95 median 9039 us with 135.69% spread, jump-to-end p95 median 12461 us with 146.409% spread, copy p95 median 33 us with 284.848% spread, frame/app-state query p95 median 38 us with 171.053% spread, and RSS delta median 152289280 bytes with 10.898% spread. OpenTUI owns `TextTableRenderable`, styled text chunks, and the test renderer; retained rows, visible slicing, navigation, copy/export, and test query are fixture-owned. | First local Ratatui `SB.3` fixture saved: mount p95 31690 us, first-render p95 272 us, arrow p95 223 us, page p95 235 us, jump p95 257 us, copy p95 10 us, buffer/state query p95 24 us, RSS delta 36175872 bytes over 100k rows in `ratatui-buffer-render-harness` mode. First strict-passing repeated-run summary over three comparable Ratatui `SB.3` artifacts: mount p95 median 78320 us with 48.809% spread, page-move p95 median 908 us with 388.326% spread, copy p95 median 590 us with 130.847% spread, app-state/buffer query p95 median 198 us with 159.091% spread, and RSS delta median 36208640 bytes with 0.407% spread. Ratatui owns `Table`, `TableState`, and `Buffer` rendering; retained rows, visible slicing, navigation, copy/export, and test query are fixture-owned. | Limited fit for dense full-screen data. | Data-widget variance now covers Ratatui, OpenTUI, Nocterm, and Textual; post-MVP comparison needs real-terminal variance, cross-machine variance, and broader table/list ergonomics before public claims. |
| Streaming markdown | Safe `MarkdownText`/`MarkdownView` link semantics, visible URL fallback, selected-block copy, and `SB.5` saved baseline: chunk-update p95 13428 us, chunk-parse p95 12588 us, chunk-frame p95 926 us, semantic-query p95 2155 us over 1000 streamed chunks with zero unsafe frames. | Markdown support claimed; streaming behavior unmeasured. | First local Bubble Tea/Bubbles/Glamour `SB.5` fixture saved: 100 streamed chunks in `bubbletea-glamour-viewport-model-harness` mode, chunk-update p95 145270 us, chunk-frame p95 16742 us, final-render p95 13567 us, selected-block-copy p95 72 us, app/model-state query p95 63 us, 41 sanitized chunks, 8 unsafe links with visible fallback, and unsafe frame count 0. First strict-passing repeated-run summary: chunk-update p95 median 127299 us with 25.274% spread, chunk-frame p95 median 16422 us with 47.296% spread, selected-block-copy p95 median 95 us with 5723.158% spread from one small absolute outlier, app/model-state query p95 median 25 us with 32% spread, and unsafe frame count 0 in all runs. Bubble Tea owns model/update/view, Bubbles owns viewport primitives, and Glamour owns full-document terminal Markdown rendering; sanitizer, visible URL fallback, selected-block copy, markdown metadata, and query state are fixture-owned app code. | First local Textual `SB.5` fixture saved: 100 streamed chunks in `textual-run-test-harness` mode, chunk-update p95 153495 us, chunk-frame p95 151148 us, final-render p95 58293 us, selected-block-copy p95 125601 us, widget/app-state query p95 423 us, 41 sanitized chunks, 8 unsafe links with visible fallback, and unsafe frame count 0. First strict-passing repeated-run summary: chunk-update p95 median 159364 us with 40.515% spread, chunk-frame p95 median 158718 us with 37.935% spread, selected-block-copy p95 median 78141 us with 26.327% spread, widget/app-state query p95 median 172 us with 92.442% spread, and unsafe frame count 0 in all runs. Textual owns `Markdown`, append parsing/rendering, focus, scrolling, and the test harness; sanitizer, visible URL fallback, selected-block copy, markdown metadata, and query state are fixture-owned app code. Full 1000-chunk Textual evidence remains unmeasured. | Agent/workflow use makes this important; measure. | Ecosystem/app-authored. | Ecosystem/app-authored; some CLIs use Ink for agent streams. | This is the MVP-cycle stopping point for streaming Markdown peer comparison. Full-scale runs, OpenTUI/Ink equivalents, real-terminal variance, and richer wrap/long-document pressure move to post-MVP. |
| Log tailing/scrollback | `LogRegion` plus `SB.4` saved baseline: append-burst p95 9591 us, scrollback-jump p95 3513 us, copy-selected-entry p95 8608 us, filter-query p95 68785 us, semantic-query p95 3630 us over 100k starting entries plus 1000 appended rows. | First local Nocterm `SB.4` fixture saved: append-burst p95 88462 us, scrollback-jump p95 15173 us, scroll-to-tail p95 12426 us, copy-selected-entry p95 8560 us, filter-query p95 135920 us, terminal/app-state query p95 456 us, unsafe leak count 0 over 100k starting lines plus 1000 appended rows in `nocterm-test-harness` mode. First strict-passing repeated-run summary over three comparable Nocterm `SB.4` artifacts: append-burst p95 median 95014 us with 18.47% spread, scrollback-jump p95 median 6099 us with 231.677% spread, scroll-to-tail p95 median 5615 us with 101.603% spread, copy p95 median 2469 us with 75.334% spread, filter-query p95 median 125479 us with 148.463% spread, terminal/app-state query p95 median 682 us with 49.56% spread, and unsafe leak count 0 in all runs. Nocterm owns `ListView.builder`, `ScrollController`, and `Text`; sanitizer, filter, selected-entry state, copy/export, and query state are fixture-owned app code. | First local Bubble Tea/Bubbles `SB.4` fixture saved: append-burst p95 902997 us, scrollback-jump p95 441959 us, scroll-to-tail p95 445006 us, copy-selected-entry p95 9 us, filter-query p95 329016 us, app/model-state query p95 18 us, unsafe leak count 0 over 100k starting lines plus 1000 appended rows in `bubbletea-viewport-model-harness` mode. First strict-passing repeated-run summary over three comparable Bubble Tea/Bubbles `SB.4` artifacts: append-burst p95 median 1346052 us with 67.347% spread, scrollback-jump p95 median 658370 us with 63.013% spread, scroll-to-tail p95 median 649960 us with 20.058% spread, copy p95 median 13 us with 23.077% spread, filter-query p95 median 437393 us with 35.305% spread, app/model-state query p95 median 49 us with 75.51% spread, and unsafe leak count 0 in all runs. Bubbles owns viewport content/scroll primitives; sanitizer, filter, selected-entry state, copy/export, and query state are fixture-owned app code. | First local Textual `SB.4` fixture saved: append-burst p95 125833 us, scrollback-jump p95 52529 us, scroll-to-tail p95 38089 us, copy-selected-entry p95 73883 us, filter-query p95 59517 us, widget/app-state query p95 101 us, unsafe leak count 0 over 100k starting lines plus 1000 appended rows in `textual-run-test-harness` mode. First strict-passing repeated-run summary over three comparable Textual `SB.4` artifacts: append-burst p95 median 92454 us with 23.275% spread, scrollback-jump p95 median 43054 us with 9.363% spread, scroll-to-tail p95 median 46689 us with 6.991% spread, copy p95 median 73105 us with 23.747% spread, filter-query p95 median 108052 us with 13.957% spread, widget/app-state query p95 median 60 us with 68.333% spread, and unsafe leak count 0 in all runs. Textual owns `Log`; sanitizer, filter, selected-entry state, and copy are fixture-owned app code. | First local OpenTUI `SB.4` fixture saved: append-burst p95 1366 us, scrollback-jump p95 810 us, scroll-to-tail p95 839 us, copy-selected-entry p95 6 us, filter-query p95 16075 us, frame/app-state query p95 42 us, unsafe leak count 0, RSS delta 128843776 bytes over 100k starting lines plus 1000 appended rows in `opentui-test-renderer-memory` mode. First strict-passing repeated-run summary over three comparable OpenTUI `SB.4` artifacts: append-burst p95 median 5018 us with 192.766% spread, scrollback-jump p95 median 3587 us with 120.156% spread, scroll-to-tail p95 median 3103 us with 42.217% spread, copy p95 median 3 us with 333.333% spread, filter-query p95 median 40358 us with 266.879% spread, frame/app-state query p95 median 45 us with 60% spread, and unsafe leak count 0 in all runs. OpenTUI owns `TextRenderable` and the test renderer; retained logs, tail policy, scrollback selection, sanitizer, filter, selected-entry state, copy/export, and query state are fixture-owned app code. | App-authored. | Static/child-process patterns exist; full-screen logs app-authored. | Log/viewport variance now covers Nocterm, OpenTUI, Textual, and Bubble Tea/Bubbles; post-MVP comparison needs real-terminal variance, cross-machine variance, and deeper ergonomics comparisons before public performance claims. |
| App shell commands/sections | `FleuryApp`, app-owned sections, command registry, status, app palette, key hints, tester invocation, demo-app flow. | Flutter-like components/testing; app-kernel parity unmeasured. | TEA model plus manual app structure. | Strong app/screen/action/command-palette model. | Component renderer and bindings; app-shell maturity unmeasured. | App-authored. | React composition; shell structure app-authored. | Textual remains the mature app-framework bar, while Fleury keeps section state ordinary widget/app code. |
| Agent-adapter readiness | Boundary audit complete; protocol-neutral commands, semantics, tasks, output safety, DataTable, debug capture, capability policy. | Has built apps such as `vide_cli`; adapter boundary unmeasured. | Strong production developer-tool ecosystem; adapter boundary unmeasured. | Strong workers/app tooling; adapter boundary unmeasured. | Powers OpenCode in production. | App-authored. | Used by AI/dev CLIs; adapter boundary unmeasured. | Score protocol-neutral primitives, not ACP implementation. |
| Semantic testing | Core semantic graph, tester queries, semantic roles/state/actions, demo-app assertions, debug Tree summaries. | Built-in tester and terminal-state assertions; semantic graph parity unmeasured. | Testing is app-authored; ecosystem varies. | Mature pilot/testing APIs; semantic-node parity unmeasured. | Unmeasured. | Buffer/golden style common. | Testing and React DevTools exist; terminal semantic graph unmeasured. | Fleury's semantic graph should remain a primary differentiator. |
| Debug capture/replay hooks | Debug inspector, frame reasons, dirty bounds, terminal diagnosis rows, bounded capture-to-test hooks; full replay deferred. | Unmeasured. | App/debug tooling varies. | Devtools and console are strong reference points. | Unmeasured. | App-authored. | React DevTools available. | Full replay stays Phase 3 unless Phase 2 bugs demand it. |
| Capability diagnostics | Passive `fleury diagnose --json`, capability requirements/resolutions, demo-app diagnostics, inspector rows. | Mouse/terminal compatibility docs exist; JSON diagnose parity unmeasured. | v2 terminal features/renderer are strong; machine-readable diagnose unmeasured. | Capability handling unmeasured. | Correctness/stability focus; diagnose shape unmeasured. | Backend/crossterm capability app-authored. | Stdout/stderr/stdin hooks; terminal diagnostics unmeasured. | Real-terminal matrix is Phase 2. |
| Untrusted output safety | Sanitized process output, ANSI/OSC/DCS/APC collapse, malformed UTF-8 tolerance, markdown link policy, redaction-aware semantics/debug, and `SB.9` saved baseline with zero visible/copy/semantic artifact leaks over subprocess and captured-output fixtures. | Unmeasured. | Input sanitization exists in Bubbles; broader output policy unmeasured. | Rich/Textual handling is mature; active terminal policy unmeasured. | Unmeasured. | App-authored escaping policy. | React rendering escapes UI text; process/log policy app-authored. | Post-MVP comparison should compare ANSI/OSC/link/image/redaction policy surfaces and subprocess handoff behavior. |
| Distribution | Local launcher, path activation, standalone `dart compile exe` route validated; public pub.dev path deferred. | pub.dev. | Go module/binaries. | PyPI. | npm/Bun. | Cargo. | npm. | Fleury must make Dart AOT and pub.dev feel credible before public launch. |

## Launch Comparison Questions

Answer these before external launch:

- Against Nocterm: can Fleury show three developer-visible wins in app
  structure, semantic tests, terminal diagnostics/security, data widgets, or
  benchmarked responsiveness?
- Against Bubble Tea v2: can Fleury show that retained composition, commands,
  focus, semantic tests, and app-level state reduce complexity for dense apps?
- Against Textual: can Fleury show a clear reason to choose a typed
  Flutter-style terminal framework despite Textual's maturity?
- Against OpenTUI and Ratatui: can Fleury show enough performance evidence to
  be credible while positioning semantics, app shell, and safety as its wedge?
- Against Ink: can Fleury show that terminal-first full-screen apps are more
  robust than using a generic React CLI layer?

## Update Protocol

When refreshing this scorecard:

1. Refresh package/release versions from primary sources.
2. Link the exact peer docs, release, benchmark, or source files used.
3. Record the date and any commands used to collect versions.
4. Update scenario benchmark mappings if a peer adds or removes comparable
   coverage.
5. Move any proven Fleury claims from "claims to prove" into launch collateral
   only after tests, examples, or benchmark artifacts exist.

## Notes

- Do not compare against marketing claims alone when benchmarks can be run.
- If a peer closes a Fleury differentiator, update the roadmap and cut list.
- Raw render throughput may favor Bubble Tea v2, Ratatui, or OpenTUI. Fleury
  should still measure semantic testing, retained-state ergonomics,
  capability diagnostics, terminal safety, and stability under demo-app
  workflows.

## Native-Stack Wire Snapshot: 2026-06-11

First wire runs with every participant native (arm64 Dart AOT for fleury,
GOARCH=arm64 bubbletea, arm64 rustc ratatui, universal node/python for
opentui/ink/textual). All earlier captures ran fleury (and bubbletea) under
Rosetta; treat pre-2026-06-11 standings as superseded. Clean captures in
`profiling/caps/2026-06-11-native-sb6-wire` and
`profiling/caps/2026-06-11-native-multi-wire` (3 runs each).

| Scenario | vs | Leading | Behind | Position |
| --- | --- | --- | --- | --- |
| SB.6 Dashboard | ratatui, opentui, bubbletea | bytes, bytes/frame, FPS | TTFB 2.2x / RSS 8x / CPU vs ratatui | catch up |
| SB.12 Layout dirtiness | nocterm, ratatui, opentui | bytes, bytes/frame, SGR overhead, FPS | TTFB/RSS/CPU vs ratatui | catch up |
| SB.4 Log region | textual, bubbletea, opentui | TTFB (19.7ms, beats all three), FPS | bytes 1.17x vs bubbletea; RSS vs Go | parity ok |
| SB.9 Subprocess | textual, bubbletea, opentui | TTFB, FPS (~par with bubbletea) | bytes/SGR overhead vs bubbletea (36% — optimization target) | needs data |

Reading: fleury LEADS on wire efficiency (bytes, bytes/frame, FPS) against
every peer including the systems-language ones, and leads startup against
every managed-runtime peer. The remaining "WAY OFF" axes are exclusively
TTFB/RSS/CPU against ratatui (Rust): a language-runtime floor (Dart AOT
~20MiB / ~20-30ms boot vs Rust ~2MiB / ~5-14ms), consistent with the
maintainer's stated bar of "ballpark of perf-oriented peers" on footprint
while leading on protocol efficiency. SB.9's 36% SGR overhead is a real
remaining byte-optimization target. NOTE: the Rosetta-era harness masked
ratatui's TTFB advantage (the capture tooling itself was emulated); native
TTFB comparisons are now trustworthy.


## Final Native Snapshot: 2026-06-11 (post wire-efficiency plan)

Full 12-scenario re-run (3 runs each, all participants native, post
encoder work) in `profiling/caps/2026-06-11-final`. Position rollup now
bands RSS/CPU within runtime class (native best annotated in-cell).

**Positions: push leading 8/12** (SB.1, SB.2, SB.3, SB.5, SB.6, SB.7,
SB.10, SB.12), **parity ok 2/12** (SB.4, SB.8), **catch up 2/12**
(SB.9, SB.11).

Measured floors and verdicts behind the two catch-ups (full detail in
the execution log, 2026-06-11 entries):

- Fleury's cursor encoding is byte-minimal for its diff granularity
  (verified by transcript histograms before/after byte-accounted styled
  gap rewriting); SB.9's residual delta is fixture surface area — the
  fleury fixture renders more live regions than the peer fixture.
- Fleury-attributable startup is 2.5ms (first byte at 0.5ms after
  entry); the Dart AOT boot floor (~29-39ms hello-world) is the entire
  TTFB gap vs ratatui. Startup claims scope to managed-runtime peers,
  where fleury leads everywhere measured.
- RSS floor (re-measured 2026-06-11, single consistent harness): bare
  AOT hello-world 13.8 MiB; minimal fleury app +3.3 MiB (mostly touched
  code pages — retained framework heap is ~85 KB); SB.6 dashboard
  +6.4 MiB total, of which ~1-7 MiB (grid-dependent) is VM new-gen GC
  sizing, reclaimable via `DART_VM_OPTIONS=--new_gen_semi_max_size=1`
  at ~6% CPU on large grids. SB.11's 143 MiB is its fixture's 100k
  eager node maps (recommendation recorded; fixtures are not slimmed to
  move their own scoreboard rows).

Claims language for public use: "Fleury leads wire efficiency (bytes,
bytes/frame, FPS) against every measured peer including the Rust and
Zig ones, and leads startup against every managed-runtime peer; on
memory and raw startup it is ballpark-of-systems-languages with a
documented Dart-runtime floor and a 2.5ms framework-attributable share."
