# Bounded inline terminal viewport

Status: in progress, 2026-09-24. The renderer foundation is implemented;
`runApp` does not yet offer a usable inline session.

RK's `use` and `init` matrices are the first consumer. They should occupy a
small region below the command while earlier shell output remains visible.
This activates the adopter-demand trigger in [RFC 0016](../rfcs/0016-inline-mode.md).

## Scope

One full-width region with an explicit, changeable row count, clamped to the
terminal height. Existing widgets receive that region's logical size and keep
their ordinary layout, scrolling, focus, and keyboard behavior. Exit clears
the live region; the command can then print its final result.

Initial qualification covers native macOS and Linux. Natural content-height
measurement, continuously inserting logs above a running UI, persistent final
frames, Windows, and native graphics protocols are follow-ups. Images use
the existing glyph fallback in the first inline implementation.

## Implementation slices

### 1. Rendering foundation — implemented

`AnsiRenderTarget` describes the host's current full-screen or inline target.
It is a presentation detail, not the app-facing height configuration. The
host must reserve the rows, provide a valid origin, and release old rows when
changing the allocation.

- `AnsiRenderer` offsets absolute row addressing. Same-row cursor movement
  stays relative and local buffers remain unchanged.
- Inline targets disable both explicit and detected whole-terminal scroll
  optimizations. A region starting at row zero is still bounded.
- `AnsiFramePresenter` clears only the current region's rows, offsets the
  caret and paint-flash overlays, and repaints when the target moves.
- Coordinate conversion preserves out-of-bounds positions, so native input
  integration can deliver captured drags and releases without clamping them
  into an edge widget.
- Unsupported native image placement fails before emitting frame bytes.

The target is intentionally not exported from the public barrels yet. The
runtime continues to select the existing full-screen path. No application
should try to enable this with `TerminalMode(alternateScreen: false)`.

Evidence: 595 rendering/presentation/runtime regression tests pass, including
300 randomized inline diffs that preserve surrounding simulated shell rows,
explicit and detected scroll cases, region relocation, caret and debug
coordinates, and the existing full-screen ANSI byte golden. These are model
and unit tests, not native inline terminal qualification.

### 2. Native region ownership and runtime integration — next

- Settle the app-facing viewport configuration and mechanism for changing
  its requested row count. Keep terminal row origins out of application code.
- Use `TerminalQueryRunner` to obtain the cursor anchor without stealing
  keystrokes. Define a safe, tested failure path when cursor reports are
  unavailable; never assume row zero and paint over the shell.
- Reserve rows with controlled newlines, accounting for bottom-of-screen
  scrolling. Own and restore autowrap separately from alternate-screen mode.
- Supply the same logical size to root layout and `FrameDriver`, and a
  matching render target to the ANSI presenter. Schedule a full repaint
  after any allocation change, even when the logical size is unchanged.
- Translate native mouse reports into local coordinates. Preserve captured
  releases outside the region and clear hover when the pointer leaves it.
- Clear/release the old allocation before handoff or suspend; reacquire an
  anchor after foreign output before resuming painting. Serialize allocation
  changes and suppress frame output while the anchor is uncertain.
- Integrate ordinary exit, startup failure, signals, and the development
  supervisor's restart/crash cleanup. Avoid painting probes outside owned
  rows and advertise the glyph image fallback for inline sessions.

Absolute row addressing is safe for the bounded region only while the host
knows its current anchor and prevents uncoordinated scrolling. The original
RFC's relative-addressing discussion describes a broader, continuously
growing transcript. Do not treat this renderer work alone as that feature.

### 3. Native qualification and RK adoption — pending

Retain PTY scenarios for entry near the screen bottom, shell output above
the region, clicks, drags outside the region, focus loss, growing/shrinking,
width reflow, rapid resize, Ctrl+C, startup failure, suspend/resume,
subprocess output, and development restart. Verify prompt position and
restored modes, in addition to emitted bytes. Run on macOS and Linux, then
visually dogfood at least a narrow and an ordinary terminal.

Only after that should RK select inline viewports for its command matrices.
Keep existing full-screen Fleury applications and browser embeds unchanged.
