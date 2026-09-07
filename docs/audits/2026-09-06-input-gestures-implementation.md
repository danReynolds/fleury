# Input and gestures implementation

Implemented 2026-09-06 on `codex/input-gestures-dx`, based on main `bb2e10b8`.
This closes the framework changes and guide rewrite proposed in the
[DX audit](2026-09-06-input-gestures-dx.md). The original audit and its probes
are historical evidence; the regression tests under each package are current.

## Framework contract

- Pointer callbacks receive `PointerDetails`, with local and global cell
  positions, button, and modifiers. Drag details add movement delta and the
  original global press position. Existing no-argument `onTap` stays simple.
- The tap family is primary-button input; `onSecondaryTap` handles right clicks
  and `onPointerDown` reports raw button presses. Tap down finishes with up or
  cancel. Drag update receives the first changed-cell movement and continues
  outside the handle until release or cancellation.
- Cancellation propagates from browser cancellation/lost capture, focus loss,
  and terminal handoff. A hidden mounted control receives cancellation; a
  removed, error-excluded, or disposed tree is never called during cleanup.
  Selection cancellation stops auto-scroll without triggering copy-on-release.
- Click focus uses the same presented, clipped render hit order as pointer
  routing. Foreground controls block focus behind them. `AbsorbPointer` also
  blocks ancestor focus while preserving its descendant controls.
- TextInput and TextArea own caret placement, drag selection, Shift-click,
  word and line selection. Mapping follows rendered scroll offsets and
  grapheme widths. Read-only fields allow selection; disabled fields do not
  acquire focus. Obscured text selection does not expose word boundaries.
  TextInput fills bounded width and remains intrinsic when width is unbounded.
- Hover follows the ancestor chain, so child controls do not interrupt a
  hovered row. Wheel events bubble along ancestors when unhandled, never to a
  covered sibling. ScrollView and ListView honor their existing edge policy.

Migrated core controls, fleury_widgets, samples, and tests together. Removed
the legacy positional callback variants, `onTapDownWithModifiers`,
`PointerDownDetails`, and `PointerScrollListener`. Down/up/hover handlers use
`details.localPosition` or `details.globalPosition`; drag handlers use
`PointerDragDetails`; custom wheel handlers use `MouseRegion.onScroll` and
return whether they handled the step. `MouseEventKind.cancel` and `leave` were
appended, preserving existing wire enum indices. The served browser asset was
regenerated from the updated source.

## Guide

The guide uses five small source-paired live examples: ContactFields,
PressTile, SplitPane, SelectableNote, and HoverNotes. Each source and test tab
shows its actual Dart file under `website/examples/{lib,test}/input/`. The tests drive physical pointer input; logical target actions
remain linked from the testing guide. Both the repository check and website
documentation check run the new example suite.

## Validation

The later browser-feedback pass added `MouseRegion.cursor`, real source/test
filenames, press cancellation and secondary-click examples, and a selectable
note. Mouse remains opt-in in terminals; the guide now explains why. Cursor
hints use the existing semantic state transport and clipped region geometry,
without introducing a role for each cursor. Optional contributors preserve
mounted child state when a cursor is added, changed, or removed. Browser
capture retains the press owner's cursor; release, cancellation, surface exit,
and changed geometry refresh or restore it.

Validation for that pass: 3,248 core unit tests and 1,199 widget tests passed
(one existing skip in each suite), 60 focused Chrome tests passed, eight host
checks passed, all five guide tests passed, and all eight fast performance gates
passed. Chrome coverage includes a cursor hint roundtrip through the served
wire decoder and a child control overriding its cursor region. The rebuilt
144-page site was reviewed in the browser for cursor shape, drag completion,
tile cancellation and secondary clicks, cross-widget selection, real tab
filenames, and panel fit.

The following broader integration receipts are from the preceding framework
implementation pass; terminal and subprocess behavior did not change in the
browser-feedback pass.

- `dart tool/fleury_dev.dart check` completed successfully: all package
  analyses, 5,488 tests across its batches, two existing skips, and the example
  JavaScript compilation. The final focus-boundary adjustment landed after
  the core unit batch and was separately verified by the focused pass below.
- Focused core pointer, field, focus, and debug-overlay regression pass: 93
  tests after the final absorbing-boundary fix. That new regression failed
  before the fix and passed afterward.
- RangeSlider: 19 tests, including secondary input and a one-move drag inside
  padding. The broader fleury_widgets suite passed with 1,198 tests and one
  existing skip before that additional regression.
- Chrome input, coordinate, trace, and assembled-host checks: 65 tests. The
  assembled mountApp test clicks the second field and verifies `abXcdef`.
- Real PTY: click-to-caret and typing, one-movement drag, terminal focus-loss
  cancellation, and terminal restoration passed with the existing PTY suite.
- Performance: all eight fast gates passed on the final pointer source:
  serve-semantics, image, bundle, allocation, input allocation, paint,
  selection, and runtime. This is not a claim about the optional heavier
  wire-performance gates.
- Final changed input files have no analyzer findings.
- `npm run build` passed, including documentation checks, example compilation,
  and the 144-page production site. The final preview's source/test tabs and
  expanded playground were also checked in the browser.
- Manual guide review in the in-app browser covered click-to-caret, typing,
  Tab, drag selection, divider capture outside its handle, keyboard resize,
  child-button interaction within a hovered row, and nested wheel handoff.
- Manual `fleury serve --spawn` review used the same guide widgets through the
  embedded WebSocket client: a click inserted `X` at `Meet| on Tuesday`, a drag
  plus Left changed width 14 to 19, Pin activated, and the outer scroller showed
  the older notes after the inner scroller reached its end.

The native evidence is a macOS PTY run; Windows handoff was updated and analyzed
but was not exercised on a Windows device.

## Selection focus and guide refinement

Explicit `SelectionArea` regions now receive pointer focus, so copy, select-all,
and Escape reach the selected region without an application-supplied `Focus`
wrapper. Regions neither autofocus nor introduce a Tab stop by default. An
optional caller-owned `focusNode` supports explicit focus and traversal;
nested fields and buttons retain their own focus behavior. The ambient root
selection preserves the application's active focus chain and shortcuts.

The guide demonstrates the handoff from a Reply field to a selectable note.
Each source tab starts with the relevant interaction and offers the complete
file in a disclosure. Terminal setup appears before the examples. Nested
scrolling has named, visible pane boundaries and a checkbox for comparing
bubbling with containment; row hover is visible over the nested Pin button.
The custom tile uses I for details, avoiding the terminal Ctrl+I/Tab alias.
The proposed custom button builder remains deferred.

Current validation: 3,255 core tests and 1,200 styled-widget tests passed (one
existing skip in each suite), all 60 focused Chrome tests and five guide tests
passed, and all eight fast performance gates passed. Core analysis has no
new findings; five existing informational lints remain in unchanged files.
The production website build passed, including documentation checks and
example compilation, and generated 144 pages. The embedded browser client
was rebuilt with fingerprint `cabd3b149c33a277`.

In the live guide, typing in Reply followed by selecting the note moved
keyboard focus to the region; Ctrl+A selected all 51 note characters without
altering Reply, and Escape cleared the selection. Native browser wheel input
revealed July through April with bubbling, while containment kept the outer
pane fixed and showed the final three Recent items. Clicking Pin preserved
the row's hover highlight, and the complete-source disclosure opened correctly.
These are browser checks; the earlier PTY receipts above were not rerun for
this pass.
