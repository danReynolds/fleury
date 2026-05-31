# Fleury Engine: Context, Research Findings, and Implementation Plan

**Subtitle:** A Dart-native terminal UI framework with Flutter ergonomics and terminal-native internals
**Status:** Planning document — P0 implementation ready
**Date:** May 16, 2026
**Target repo path:** `packages/fleury/` and `docs/rfcs/0007-fleury-framework.md`

## Executive decision

Approve and begin **P0: Engine proof** for a Dart-native TUI framework. The project should be framed as:

> **Flutter ergonomics, terminal truth.**

The goal is not to clone Flutter or reuse Flutter's implementation. The goal is to bring Flutter's familiar app-authoring model — widgets, state, context, keys, constraints, inherited dependencies, and hot-reload-friendly rebuilds — to terminal UIs while implementing the runtime with terminal-native best practices: cell buffers, ANSI diffing, raw-mode lifecycle management, grapheme-aware text, capability detection, and safe input handling.

The current plan is feasible if scope remains tight. P0 should prove the hardest assumptions: state-preserving hot reload, key-based widget identity, cell-buffer rendering, Unicode-safe text handling, terminal-safe output, deterministic flex layout, and exception-safe terminal cleanup.

## Updated understanding

### What we are building

`fleury` is a standalone Dart package for terminal UIs. It should feel natural to Flutter developers, but it should not import or depend on `package:flutter`.

The package provides:

- Flutter-shaped authoring primitives: `Widget`, `StatelessWidget`, `StatefulWidget`, `State<T>`, `BuildContext`, `Key`, `setState`, `InheritedWidget`, `Row`, `Column`, `Expanded`, `Text`, focus, async builders, and theme lookup.
- A terminal-native engine: `TerminalDriver`, raw mode, event parsing, cell constraints, render objects, `CellBuffer`, grapheme-aware text, ANSI diff output, and terminal lifecycle cleanup.
- A dev-mode reload path: a root widget factory plus `reassembleApplication()` driven by Dart VM-service `reloadSources`.

### What we are not building

This is not a Flutter engine. It will not implement Skia/Impeller rendering, pixels, GPU compositing, Flutter assets, platform channels, Material/Cupertino widgets, gesture arenas, Slivers, `CustomPaint`, Hero transitions, or source compatibility with Flutter widgets.

The expected compatibility is **ergonomic and conceptual**, not binary or source compatibility.

## Design principles

1. **Familiar above, native below.** Application code should feel familiar to Flutter developers; runtime internals should be terminal-native.
2. **Terminal correctness wins.** When Flutter purity conflicts with terminal correctness, terminal correctness wins.
3. **Text is untrusted data.** Widgets never emit raw ANSI/control sequences. Only the renderer may write terminal control bytes.
4. **Layout is cell-based. Text is grapheme-width aware.** Flex divides terminal rows/columns; text inside those regions is measured by grapheme display width.
5. **Full-buffer paint plus diff first.** P0 should paint a complete cell buffer and diff it against the previous buffer. Dirty-region optimization can come later.
6. **Hot reload is root-factory plus reassemble.** Do not rerun `main()`. Preserve `State<T>` through element reconciliation.
7. **Dune gates the framework.** Nothing lands in the framework unless the Dune TUI needs it or the P0/P1 correctness gates require it.

## Relationship to Flutter

We should reuse Flutter's patterns aggressively, not Flutter's code.

| Flutter pattern | `fleury` equivalent | Why it matters |
|---|---|---|
| `Widget` | Immutable terminal UI description | Familiar declarative API |
| `Element` | Persistent mounted identity | State preservation and reconciliation |
| `State<T>` | Retained mutable local state | Stateful TUI interactions and hot reload |
| `Key` | Identity across sibling reorder/reload | Correct state retention |
| `BuildContext` | Position in terminal UI tree | Theme, focus, services, inherited lookup |
| `InheritedWidget` | Theme/capability/service propagation | Context-driven app structure |
| Constraints down, sizes up | Integer cell constraints | Natural `Row`/`Column`/`Expanded` behavior |
| `reassemble()` | Dev-mode reload hook | Flutter-like hot reload semantics |

Why not reuse Flutter code directly:

- `package:flutter` is coupled to the Flutter SDK and engine stack.
- Flutter's engine solves graphics, rasterization, text shaping, platform embedding, and accessibility concerns that are out of scope for a terminal engine.
- A clean-room terminal implementation can be much smaller and easier to reason about.
- Mirroring names is useful; pretending Flutter widgets can run here is not.

## Relationship to existing TUI practice

The framework should take terminal mechanics from mature TUI ecosystems:

| TUI pattern | Source of inspiration | `fleury` use |
|---|---|---|
| Cell buffer | Ratatui, Notcurses-style renderers | Off-screen terminal frame |
| Double-buffer diff | Ratatui | Efficient repaint with low flicker |
| Event/update/render discipline | Bubble Tea | Coalesced event-driven scheduling |
| Component-style TUI | Ink, Gemini CLI-like UIs | Validation for reactive terminal apps |
| Flex layout | Ink/Yoga, Ratatui layouts | Familiar split panes and responsive layouts |
| Terminal protocol care | Xterm, Kitty | Paste, mouse, modifiers, resize, cleanup |

The guiding phrase is:

> **Flutter app model + TUI rendering discipline + Dart hot reload.**

## Engine architecture

```text
Application widgets
  -> Widget tree             immutable declarations
  -> Element tree            persistent identity and State<T>
  -> Render tree             layout and paint objects
  -> CellBuffer              rows x columns of styled terminal cells
  -> ANSI diff renderer      batched cursor/style/text updates
  -> Terminal emulator       stdout/stderr under managed modes

Terminal input
  -> TerminalDriver
  -> TuiEvent stream
  -> Scheduler / Focus / handlers
  -> setState / stream updates
  -> next frame

Dev reload
  -> Dev runner / VM service
  -> reloadSources
  -> reassembleApplication
  -> reconcile root widget
  -> preserve compatible State<T>
```

### Core runtime layers

| Layer | Responsibilities |
|---|---|
| Foundation | keys, geometry, diagnostics, equality, utility types |
| Widgets | widget classes, elements, state, build context, inherited dependencies |
| Rendering | constraints, render objects, flex, text layout, cell buffer, ANSI renderer |
| Terminal | driver abstraction, modes, capabilities, input parser, events, cleanup |
| Dev | root factory, reassemble hook, experimental hot reload runner |
| Dune integration | `QueryBuilder`, chat widgets, status panes, daemon/network streams |

## Rendering model

Flutter draws into pixels. A TUI draws into **terminal cells**. A normal terminal may be `120 x 40`, meaning 120 columns and 40 rows. Widgets can draw anywhere in that grid, but only at row/column granularity.

A simplified terminal cell model:

```dart
enum CellRole { empty, leading, continuation }

final class Cell {
  final String? grapheme;   // set only on leading cells
  final CellRole role;      // wide grapheme continuation support
  final CellStyle style;    // fg, bg, bold, dim, underline, inverse, etc.
}
```

A wide emoji or CJK character may occupy two terminal columns:

```text
[🙂 leading][continuation]
```

The frame pipeline:

```text
1. Rebuild dirty widgets.
2. Layout render objects using integer cell constraints.
3. Paint the render tree into a new CellBuffer.
4. Diff the new CellBuffer against the previous CellBuffer.
5. Emit batched ANSI cursor moves, style changes, and text writes.
6. Store the new buffer as the previous buffer.
```

Only step 5 writes to the terminal. Widgets never write raw terminal bytes.

## Layout model

Layout uses the Flutter mental model, but in integer terminal cells.

```dart
final class CellConstraints {
  final int minCols;
  final int? maxCols; // null means unbounded
  final int minRows;
  final int? maxRows; // null means unbounded
}
```

Flex divides available terminal columns/rows, not grapheme counts.

Example:

```dart
Row(children: [
  Expanded(flex: 1, child: Sidebar()),
  Expanded(flex: 4, child: ChatPane()),
])
```

In a 120-column terminal:

```text
total flex = 1 + 4 = 5
left pane  = 120 * 1 / 5 = 24 columns
right pane = 120 * 4 / 5 = 96 columns
```

With a fixed-width divider:

```dart
Row(children: [
  Expanded(flex: 1, child: Sidebar()),
  VerticalDivider(), // 1 col
  Expanded(flex: 4, child: ChatPane()),
])
```

The divider is subtracted first. The remaining 119 columns are divided deterministically. P0 should define a fixed integer rounding rule: floor each allocation, then distribute leftovers in child order.

## Text, Unicode, and terminal safety

Text rendering is one of the most important engine areas. The renderer must handle:

- Unicode extended grapheme clusters.
- Combining marks.
- CJK wide characters.
- Emoji and ZWJ sequences.
- Ambiguous-width characters.
- Clipping and wrapping at cell boundaries.
- Overwriting wide graphemes safely.
- Sanitizing ESC and control characters.

The engine should expose:

```dart
abstract interface class WidthResolver {
  int widthOfGrapheme(String grapheme, TerminalProfile profile);
}
```

`Text(message.body)` must mean "render this as safe visible text," not "write this string to stdout." This is mandatory for Dune because chat content is remote and untrusted.

### Trusted ANSI passthrough (deferred extension point)

A small number of consumers will legitimately want to display pre-styled
ANSI output: log tails, `git diff`, CI logs, terminal-color program output.
The default safety rule above forbids this through `Text`. The framework
should reserve a separate opt-in path — working name `RawText` or
`AnsiPassthrough` — whose contract is:

- Accepts arbitrary bytes including ESC sequences.
- Parses them into `CellStyle` runs at the buffer level.
- Never passes raw bytes through to the renderer.
- Drops unknown / dangerous sequences (cursor motion, screen clears,
  OSC) rather than honoring them.

This is **deferred past P1**. P0/P1 must not invent a generic "let widgets
emit ANSI" surface; the contract above is the only safe shape and it
should be designed when there is a real consumer driving it.

## stdout ownership

An interactive TUI owns stdout. Any `print()`, `stdout.writeln`, or stray
write from anywhere in user code, framework code, or third-party packages
will corrupt the frame mid-render. This is a framework-level invariant,
not advice:

- **Only the diff renderer writes to stdout.** Every other layer routes
  output elsewhere.
- **`Logger` defaults to stderr** (or a configurable file sink). Widgets
  and `State` may log freely; the bytes never touch the TUI surface.
- **Dev-mode reload status renders inside the frame**, never as a stdout
  message. A small built-in status overlay widget surfaces "reloading",
  "reload failed", and reload errors without leaving stdout.
- **`assert` failures and framework warnings** surface through the
  logger and through a dev overlay; they do not `print`.
- **Third-party package output** that bypasses the framework is the
  consumer's responsibility, but the framework should provide a
  guarded zone (e.g. an alternate-screen mode) that contains damage to
  one frame on the way out.

Operationally this means the `TerminalDriver` is the single owner of the
stdout sink and exposes it only to the renderer. A `runTui()` host that
detects writes from the dev/debug overlay coalesces them onto stderr.

## Input and terminal lifecycle

Input is a subsystem, not a helper. A serious TUI input layer handles
escape buffering (Alt vs ESC ambiguity within a few-ms window), paste
state machines (bracketed paste start/end markers), Kitty/CSI-u
disambiguated keys, SGR/X11 mouse encoding, focus-in/focus-out events,
and priority-based subscribers so that modals and dialogs can claim keys
without being a tree ancestor of the focused widget. Gemini CLI's
`KeypressContext` is the most production-real reference. [R12]

### Phased input scope

- **P0:** raw mode entry/exit with exception-safe cleanup, basic keys
  (printable + arrows + function keys + common modifiers), resize, text
  input events. Enough to validate the substrate.
- **P1:** bracketed paste, focus dispatch with priority subscribers,
  scroll keys, single-line composer support, mouse wheel where it is
  straightforward.
- **P2:** Kitty/CSI-u progressive enhancement, richer shortcut
  disambiguation, key release / key repeat where the protocol provides
  it.

### TerminalDriver

The terminal layer is abstracted immediately:

```dart
abstract interface class TerminalDriver {
  CellSize get size;
  TerminalCapabilities get capabilities;
  Stream<TuiEvent> get events;

  Future<void> enter(TerminalMode mode);
  Future<void> restore();

  void write(String data);
}
```

Typed events:

```dart
sealed class TuiEvent {}
final class KeyEvent extends TuiEvent { /* key + modifiers */ }
final class TextInputEvent extends TuiEvent { /* safe typed text */ }
final class PasteEvent extends TuiEvent { /* bracketed paste text */ }
final class MouseEvent extends TuiEvent { /* button, wheel, position */ }
final class FocusEvent extends TuiEvent { /* terminal focus gained/lost */ }
final class ResizeEvent extends TuiEvent { /* new CellSize */ }
```

### Routing and priority

`FocusManager` maintains the focused `FocusNode`. `KeyEvent`s reach the
focused node first and bubble up its ancestor chain. **Priority
subscribers** — registered through an `Actions` / `Intents`-style API —
intercept *before* the focus chain, in registration order. A modal
registers a priority subscriber that swallows `Escape`; the same
`Escape` keypress, with no active modal, bubbles normally to whoever
claims it. Priority subscribers are how shortcuts that cross-cut the
widget tree (global help, command palette, modal dismissal) work
without forcing a particular tree shape.

### Terminal mode cleanup

Every terminal mode must be restored on normal exit, exception, and
interrupt where possible:

- raw mode
- alternate screen
- cursor visibility
- bracketed paste
- mouse mode
- enhanced keyboard mode
- style reset

The driver registers signal handlers (`SIGINT`, `SIGTERM`) and runs
cleanup before the process exits. `runTui()` wraps the app in
`try / finally` so an uncaught exception still flushes the cleanup
sequence.

## Reactivity and Dune integration

The framework should support the familiar reactivity stack:

- `setState` for local state.
- `ListenableBuilder` and `ValueListenableBuilder` for synchronous notifiers.
- `FutureBuilder` and `StreamBuilder` for async state.
- A Dune-specific or generic `QueryBuilder<T>` for stable query lifecycle management.

Important lifecycle rule: streams should not be recreated casually inside `build`. For Dune APIs, prefer:

```dart
QueryBuilder<List<MessageModel>>(
  query: Dune.messages.conversation(key).latest(limit: 200),
  builder: (context, snap) {
    return MessageList(messages: snap.data ?? const []);
  },
)
```

This avoids restarting subscriptions on parent rebuilds.

## Hot reload plan

The Dart VM gives us the primitive through VM-service `reloadSources`. The framework must provide the Flutter-like behavior by preserving the element/state tree.

Correct shape:

```dart
void main() {
  runTui(() => const DuneTuiApp());
}
```

On reload:

```text
1. Dev runner calls reloadSources through the VM service.
2. Framework receives reload success or the runner asks it to reassemble.
3. Framework calls the stored root widget factory.
4. Reconciler walks new widgets against existing elements.
5. Matching runtimeType + key preserves Element and State<T>.
6. The next frame layouts/paints/diffs with preserved state.
```

Do not promise more than Flutter does. Changes to `main`, initialization flow, static/global initializers, some type-shape changes, and incompatible edits may require restart.

P0 proof:

```text
Run a counter/status TUI.
Increment counter to 5.
Edit display text.
Trigger VM reload + reassemble.
Screen updates.
Counter remains 5.
Terminal restores cleanly on exit.
```

## Implementation roadmap

### P0 — Engine proof

**Goal:** prove the architecture works.

Deliver:

- `Widget`, `Element`, `BuildContext`, `StatelessWidget`, `StatefulWidget`, `State<T>`.
- `Key` and key-based reconciliation.
- `setState` and dirty build scheduling.
- Root factory and `reassembleApplication()`.
- `Text`, `Row`, `Column`, `Expanded`, `Flexible`, `SizedBox`, `Padding`, `Container`, `Stack` / `Positioned`.
- `CellConstraints`, `CellSize`, `CellOffset`, `CellRect`.
- `CellBuffer` with leading/continuation cells.
- Safe text sanitization.
- ANSI diff renderer.
- `TerminalDriver` abstraction with basic input (raw mode, keys, resize, text input) per the phased input scope above.
- Prototype `dart_console` driver or fake/test driver.
- `Logger` that defaults to stderr so dev-mode logging never reaches the TUI surface.
- Minimal hot reload proof.

P0 gates:

1. State survives rebuild when `runtimeType + key` match.
2. State is replaced when key changes.
3. Row flex divides 120 columns deterministically.
4. `Text` cannot emit raw ESC/control sequences.
5. Wide graphemes occupy leading + continuation cells.
6. Overwriting a wide grapheme clears continuation cells.
7. Renderer emits only changed cells/runs between frames.
8. `Stack` overlays paint correctly: a later sibling overwrites earlier
   cells, including evicting any wide-grapheme continuations it crosses.
9. `reassembleApplication()` rebuilds root while preserving compatible `State<T>`.
10. Terminal modes restore after normal exit and thrown exception.
11. No framework code path (including the dev overlay and logger) emits
    bytes to stdout outside the diff renderer.

Estimate: **2–4 weeks**, about **4k–8k implementation LOC plus tests**.

### P1 — Dune chat MVP

**Goal:** make the framework useful for the first real Dune client.

Deliver:

- `InheritedWidget` and `TerminalTheme`.
- `Focus`, `FocusNode`, `FocusScope`.
- Keyboard dispatch with priority-based subscribers (modals/dialogs) and shortcut bubbling along the focus chain.
- Lifecycle-safe `StreamBuilder` and `QueryBuilder<T>`.
- `Viewport`, `ScrollController`, basic `ListView`.
- Single-line text input/composer.
- Status bar, conversation sidebar, message pane.
- Bracketed paste support and `PasteEvent`.
- Mouse wheel where the protocol path is straightforward.

P1 gate:

```text
Dune chat can show a sidebar, select a conversation, stream messages,
preserve selected conversation and draft input across rebuilds, compose/send,
scroll history, and restore terminal state after Ctrl-C or exception.
```

Estimate: **6–10 additional weeks**, about **10k–18k implementation LOC plus tests**.

### P2 — Robust internal v1

**Goal:** make it reliable enough to use daily.

Deliver:

- Virtualized `ListView.builder`.
- Better ANSI style diffing and repaint performance.
- Mouse wheel / SGR mouse where useful.
- Capability detection.
- Truecolor / 256-color / 16-color fallback.
- tmux and SSH validation.
- Windows Terminal smoke test.
- Golden render tests, input parser tests, terminal lifecycle tests.
- Improved dev-runner UX.

P2 gate:

```text
Dune TUI works locally, in tmux, over SSH, and in Windows Terminal without
corrupting terminal state, dropping normal keys, or repainting excessively.
```

Estimate: **3–4 months from start** for robust internal v1.

### P3 — Community beta

**Goal:** make it publishable, not just useful inside Dune.

Deliver:

- Public API review.
- Package docs.
- Examples.
- Theming docs.
- Terminal safety docs.
- Hot reload dev-runner docs.
- `dart pub publish --dry-run`.
- No Dune imports in framework package.
- Dune consumes through a normal package boundary.

P3 gate:

```text
A second non-Dune sample app can be built without framework changes.
```

Estimate: **4–6 months from start** for community-grade beta.

## Proposed repository structure

```text
docs/
  rfcs/
    0007-fleury-framework.md

packages/
  fleury/
    pubspec.yaml
    README.md
    lib/
      fleury.dart
      src/
        foundation/
          diagnostics.dart
          geometry.dart
          key.dart
        widgets/
          async.dart
          basic.dart
          build_context.dart
          element.dart
          framework.dart
          inherited.dart
          state.dart
          widget.dart
        rendering/
          ansi_renderer.dart
          cell.dart
          cell_buffer.dart
          flex.dart
          layout.dart
          render_object.dart
          text.dart
          width_resolver.dart
        terminal/
          capabilities.dart
          events.dart
          input_parser.dart
          terminal_driver.dart
          terminal_modes.dart
        dev/
          hot_reload_runner.dart
          reassemble.dart
    example/
      counter_status.dart
    test/
      reconciliation_test.dart
      flex_layout_test.dart
      cell_buffer_test.dart
      ansi_renderer_test.dart
      text_safety_test.dart
      reassemble_test.dart
```

Working branch:

```text
feature/fleury-p0
```

Package path:

```text
packages/fleury/
```

Use `fleury` as the package name even if `fleury` remains the working brand. It avoids package-name collision and makes the terminal scope explicit.

## Testing strategy

### Widget/runtime tests

- Same `runtimeType + key` preserves `State<T>`.
- Key mismatch remounts.
- Child reorder preserves keyed state.
- `setState` marks only expected subtree dirty.
- `reassembleApplication()` rebuilds and preserves compatible state.

### Layout tests

- Flex allocation with fixed and flexible children.
- Remainder distribution.
- Padding and alignment edge cases.
- Resize behavior.
- Overflow/clipping behavior.

### Text/cell tests

- ASCII text.
- Combining marks.
- CJK wide characters.
- Emoji and ZWJ sequences.
- Ambiguous-width policy.
- Wide-character overwrite.
- Edge clipping.
- Control-character sanitization.

### Renderer tests

- Dirty run detection.
- Style diffing.
- Cursor movement batching.
- No ANSI leakage from `Text`.
- Full-buffer repaint after resize.

### Input tests

- Normal text input.
- Arrows/function keys.
- Escape ambiguity.
- Bracketed paste.
- Resize event.
- Mouse events once implemented.
- Kitty/CSI-u progressive enhancement later.

### Terminal lifecycle tests

- Raw mode restored after exception.
- Cursor visibility restored.
- Alternate screen restored.
- Paste/mouse/keyboard modes disabled on exit.
- Final style reset emitted.

### Dune integration tests

- Message stream updates a pane.
- Conversation selection persists.
- Composer draft persists across rebuild/reload.
- Scrolling remains stable as new messages arrive.

## Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Unicode width correctness | High | `WidthResolver`, grapheme tests, conservative policy, explicit terminal profile |
| Raw ANSI/control injection | High | Only renderer emits ANSI; sanitize `Text`; tests for ESC/control chars |
| Terminal mode not restored | High | `try/finally`, signal handling where possible, lifecycle tests |
| Hot reload overpromised | Medium-high | Root factory + reassemble; document Flutter-like limitations; P0 proof |
| Input parser complexity | Medium-high | Phase protocols; legacy first, bracketed paste P1, Kitty/CSI-u P2 |
| Scope creep | High | Dune gates framework APIs; no full Flutter parity; no widget catalog before core |
| Windows compatibility | Medium | Smoke test before P1 complete; use substrate package initially |
| SSH/tmux repaint performance | Medium | Double-buffer diff in P0; benchmark and dirty regions later |
| Package naming collision | Low-medium | Use `fleury` for package path/name; treat `fleury` as working brand |
| Team ownership | Medium | Small public surface, internal docs, tests from day one |

## Immediate next steps

### Day 0–1

- Commit RFC and scaffold under `docs/rfcs/` and `packages/fleury/`.
- Add package README with design principles and P0 gates.
- Add minimal `pubspec.yaml` with `characters`, `meta`, `test`, and possibly `dart_console`.

### Week 1

- Implement core `Widget`/`Element`/`State<T>` runtime.
- Implement key reconciliation tests.
- Implement fake terminal driver for deterministic tests.
- Implement `CellConstraints` and geometry types.

### Week 2

- Implement `Text`, `CellBuffer`, safe sanitization, and width resolver.
- Implement `Row`, `Column`, `Expanded`, `SizedBox`, `Padding`, `Container`.
- Implement ANSI diff renderer with tests.

### Week 3

- Implement root factory and `reassembleApplication()`.
- Build hot reload POC with VM service.
- Build counter/status demo.
- Validate terminal cleanup behavior.

### Week 4

- Review P0 gates.
- Decide whether to continue directly into P1 or harden P0.
- Start Dune chat MVP widgets only after P0 gates pass.

## Final recommendation

Proceed with P0 now.

The architecture is credible because Flutter gives the right application model, mature TUI frameworks give the right terminal rendering discipline, and Dart gives a plausible hot-reload differentiator. The main engineering work is not inventing the concept; it is implementing the seam carefully:

```text
Flutter-shaped identity and layout
  + terminal-native rendering and input
  + Dart VM reload integration
  + Dune as the first real consumer
```

P0 should remain narrow and test-heavy. If P0 proves state-preserving reload, safe grapheme-aware rendering, deterministic cell layout, and terminal cleanup, the project is worth continuing into the Dune chat MVP.

## References

1. Flutter Widget class and element identity: https://api.flutter.dev/flutter/widgets/Widget-class.html
2. Flutter Element class: https://api.flutter.dev/flutter/widgets/Element-class.html
3. Flutter architectural overview: https://docs.flutter.dev/resources/architectural-overview
4. Flutter layout constraints: https://docs.flutter.dev/ui/layout/constraints
5. Flutter hot reload: https://docs.flutter.dev/tools/hot-reload
6. Flutter State.reassemble: https://api.flutter.dev/flutter/widgets/State/reassemble.html
7. Dart VM service protocol reloadSources: https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md
8. Ratatui rendering under the hood: https://ratatui.rs/concepts/rendering/under-the-hood/
9. Ink: React for CLIs: https://github.com/vadimdemedes/ink
10. Bubble Tea: https://github.com/charmbracelet/bubbletea
11. dart_console package: https://pub.dev/packages/dart_console
12. characters package: https://pub.dev/packages/characters
13. Unicode UAX #29: Text Segmentation: https://www.unicode.org/reports/tr29/
14. Unicode UAX #11: East Asian Width: https://www.unicode.org/reports/tr11/
15. Xterm control sequences: bracketed paste and terminal modes: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
16. Kitty keyboard protocol: https://sw.kovidgoyal.net/kitty/keyboard-protocol/
17. Windows console virtual terminal sequences: https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
18. Windows pseudoconsole sessions: https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session
19. [R12] Gemini CLI `KeypressContext` — escape buffering, paste state machine, Kitty/CSI-u handling, SGR/X11 mouse parsing, priority-based subscribers: https://github.com/google-gemini/gemini-cli/blob/main/packages/cli/src/ui/contexts/KeypressContext.tsx
