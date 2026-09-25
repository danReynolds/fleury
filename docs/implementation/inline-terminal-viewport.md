# Bounded inline terminal viewport

Status: implemented in `codex/inline-viewport`, 2026-09-24. Native macOS/Linux
PTY qualification and a temporary RK consumer build pass. Ready for code review
and terminal-app dogfooding; not yet merged or published.

RK's `use` and `init` matrices are the first consumer. They should occupy a
small region below the command while earlier shell output remains available.
This activates the adopter-demand trigger in [RFC 0016](../rfcs/0016-inline-mode.md).

## Public contract

```dart
await runApp(app, mode: const TerminalMode.inline(rows: 14, mouse: true));
print('Done.');
```

One full-width region with an explicit, changeable row count, clamped to the
terminal height. Existing widgets see the region's logical size and keep
ordinary layout, scrolling, focus, and keyboard behavior. Exit clears the live
region; the caller prints the result. From an interaction/lifecycle callback,
`TerminalSession.of(context).resizeInline(20)` requests another height. Requests
during handoff or suspend apply on return. `isInline` distinguishes this native
operation from full-screen and remote sessions.

See the [consumer guide](../../packages/fleury/doc/inline_terminal.md) and
[runnable picker](../../packages/fleury/example/inline_picker.dart).

## Ownership and rendering

`InlineTerminalRegion` tracks the allocation and last local hardware cursor;
`PosixTerminalDriver` serializes geometry changes and owns all terminal I/O.

- Entry requires stdin/stdout TTYs and a real cursor report through
  `TerminalQueryRunner`. Missing reports fail after mode restoration; no
  fallback origin is guessed. Partial shell lines survive entry.
- Newlines reserve rows and move earlier output into normal scrollback as
  needed. The driver owns autowrap separately from alternate-screen mode.
- The same logical size reaches layout and frame buffers. `AnsiRenderTarget`
  offsets ANSI rows and caret/debug output; only owned rows are cleared.
  Explicit and detected whole-terminal scroll optimizations are disabled.
- Native image protocols and painting width probes are bypassed. Inline
  images use glyph rendering; native image placement is rejected by the
  presenter before emitting bytes if a host incorrectly supplies an encoder.
- Mouse input is translated to local coordinates. Out-of-bounds releases are
  preserved for capture; relocation cancels the old pointer interaction.
- The presenter reports the final local caret, or a stable bottom-left
  resting cursor. Resize obtains the actual terminal cursor, recovers the
  origin, and repaints. Geometry changing during a query causes a retry with
  painting still gated; each query is bounded and teardown cancels the wait.
- Frame writes and mouse delivery are gated while allocation is uncertain,
  suspended, or handed off. A lifecycle generation prevents pending queries
  from reactivating a restored session. Coalesced height requests emit a final
  repaint even when an earlier queued request did the actual allocation.
- Handoff and suspend clear the allocation before giving the terminal away;
  return obtains a fresh anchor after shell/child output. Normal exit, signals,
  and startup failure share the existing restoration path.

The private supervisor lease stores typed mode and geometry metadata in its
existing temporary directory. It records actual keyboard/pointer-stack
ownership and becomes inactive after normal release. Crash cleanup uses the
committed region only when physical dimensions still match. Stale dimensions
cause a newline and mode restoration, leaving uncertain content alone. Metadata
never supplies raw executable escape bytes.

The retained renderer continues to use absolute addressing within a known,
owned region. The original RFC's relative-addressing and transcript proposals
remain a broader future feature. The old `alternateScreen` switch is removed;
use `TerminalMode.fullScreen()` or `TerminalMode.inline(rows: ...)`.

## Validation and evidence boundary

- Core regression suite: 3,718 tests passed, one existing ambient probe skipped;
  the final focused rerun passes 32 tests, including resize-during-query,
  unreportable terminal dimensions, and pointer crash recovery.
  Existing full-screen ANSI byte golden remains unchanged.
- Existing native full-screen and development-supervisor PTY suites: 19 passed.
- `tool/check_inline_tui.py`: eight scenarios pass on macOS (Dart 3.12.2) and
  Linux aarch64 Docker (Dart 3.13.3). Covers 80x18 and 40x12 layouts, shell
  scrollback preservation, text, offset mouse clicks, height changes, width/
  height resize, subprocess output, Ctrl+Z/resume, Ctrl+C, SIGINT/SIGTERM,
  supervised restart, SIGKILL, and abrupt positive-code exit. A separate session
  guardian checks actual termios after Dart exits and never restores it itself.
- New unit tests cover unavailable cursor reports, stale geometry on release,
  outside mouse release, pending-resize shutdown, handoff height requests,
  invalid/oversized recovery metadata, and owned-only clearing. Rendering tests
  include 300 randomized diffs preserving surrounding simulated shell rows.
- Temporary RK build with `TerminalMode.inline(rows: 20)`: real `use` selects
  and executes a disposable Local installation; `init` reviews before creating
  configuration. Both restore terminal modes without alternate-screen entry.
  RK's checked-in dependency and the user's installations are unchanged.
- CI now runs the inline PTY harness on macOS and Linux with Dart 3.12.2.
  These workflow changes have not yet run in hosted CI.

The automated harness uses a real PTY and a Python terminal emulator. It is not
Apple Terminal/tmux visual acceptance: the emulator models resize by retaining
cursor-relative rows, and physical terminal reflow can differ. Native Terminal
UI automation was unavailable in this environment. Manual terminal dogfooding
remains before release qualification.

## Intentional limits

Natural content-height measurement, permanent log insertion above a live UI,
persistent final frames, Windows inline support, and native image protocols
are deferred. Stray output retains Fleury's existing capture/replay behavior.
During supervised development the VM-service banner can remain above the UI.
If resize is unprocessed when the process exits, uncertain rows may remain;
preserving shell content takes precedence over speculative clearing.
