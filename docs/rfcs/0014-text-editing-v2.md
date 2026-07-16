# RFC 0014: Text Editing V2

Status: Draft  
Date: 2026-05-31
Amended: 2026-07-16 (prelaunch controller selection API convergence)

## Context

Text editing is a trust test for Fleury. Developer tools, command palettes,
agent consoles, config forms, commit editors, search boxes, and demo apps all
depend on fields that behave predictably under Unicode, paste, selection,
history, validation, and terminal constraints.

The original `TextEditingController` used one mutable string plus a code-unit
cursor index. That was enough for ASCII input, but it could split emoji and
combining sequences and left `TextInput` and `TextArea` duplicating editing
logic.

## Goals

- Provide a pure editing model independent from rendering, focus, and terminal
  I/O.
- Make `TextEditingController.selection` the canonical range-valued selection
  API, with a scalar `caretOffset` convenience for collapsed selections.
- Keep the API familiar to Flutter developers without giving up Fleury's
  grapheme-safe offset normalization or end-caret initialization policy.
- Share the same core between single-line and multiline fields.
- Give tests a model-level surface for movement, insertion, deletion, paste,
  range replacement, and line movement.
- Leave room for selection ranges, undo/redo, history, completion, validation,
  password policy, clipboard policy, and IME/composition without baking them
  into render objects.

## Non-Goals For The First Slice

- Full visual range selection painting inside editable fields.
- Vi/Emacs keymap presets.
- Complete undo/redo and command history.
- Completion popup APIs.
- Terminal IME guarantees beyond reserving model fields and extension points.
- Clipboard or password redaction policy finalization; those must align with
  RFC 0013.

## Model

### `TextRange`

`TextRange` is a half-open range: `start` is included and `end` is excluded.
Ranges can be directional at construction time, but consumers should use
normalized `start/end` when mutating strings.

Use cases:

- Selection payload ranges.
- Composing/IME range.
- Validation/error ranges.
- Future search-match and completion spans.

### `TextSelection`

`TextSelection` stores `baseOffset` and `extentOffset`.

- `baseOffset` is the anchor.
- `extentOffset` is the moving edge or caret.
- Collapsed selections have equal base and extent.
- `TextSelection.collapsed(offset: value)` uses Flutter's named-parameter call
  shape.
- Public offsets remain Dart string offsets for compatibility, but the model
  snaps them to extended grapheme boundaries.

The current widgets still paint a single caret. Range painting and shift-based
selection are follow-up widget work, not model blockers.

### `TextEditingValue`

`TextEditingValue` is immutable and contains:

- `text`
- `selection`
- `composing`

Constructors normalize selection and composing state against the current text.
All widget controllers should eventually hold a `TextEditingValue`, not a raw
string and cursor integer.

When no selection is supplied, Fleury initializes a collapsed selection at
`text.length`. A `TextEditingController(text: 'ship it')` therefore starts with
its caret at the end of the text. This intentionally preserves Fleury's useful
end-caret policy rather than adopting Flutter's invalid `-1` default selection.

### `TextEditingController`

The controller exposes one canonical selection model:

- `selection` gets or sets a directional `TextSelection`.
- `caretOffset` gets the active `extentOffset`; assigning it collapses
  `selection` at that offset.
- `value.selection` is the same normalized selection state, not a parallel
  controller representation.

Both range and scalar writes clamp to `0..text.length` and snap to extended
grapheme boundaries. The scalar convenience does not weaken range selection:
use `caretOffset` when an app only needs a caret, and `selection` when it needs
an anchor and moving edge.

This is a prelaunch convergence change. Code that previously assigned an
integer to `selection` should assign that integer to `caretOffset`; code that
used the transitional `textSelection` bridge should use `selection` directly.

## Editing Operations

The pure `TextEditingModel` owns editing transformations:

- Insert text.
- Replace selection.
- Backspace previous grapheme.
- Delete next grapheme.
- Move left/right by grapheme.
- Move to document start/end.
- Move to line start/end.
- Move line up/down by grapheme column.
- Normalize single-line pasted input by replacing line breaks with spaces.

Operations return a new `TextEditingValue` and do not notify listeners,
schedule frames, render, inspect focus, or touch terminal capabilities.

## Unicode Policy

The editing model uses extended grapheme clusters as the user-facing movement
unit. Dart string offsets remain the compatibility representation, but cursor
movement and deletion cannot land inside a grapheme cluster.

Required model tests:

- ASCII.
- Emoji and ZWJ-like multi-code-unit clusters.
- Combining marks.
- CJK characters.
- Mixed single-line and multiline text.

Width is not part of the editing model. Width belongs to rendering via
`WidthResolver`; the model should answer "which character boundary" while the
render layer answers "which cell".

## Single-Line And Multiline Behavior

Single-line fields use the same value model but normalize inserted pasted text
so CR/LF sequences become spaces. Pressing Enter remains a submit action for
`TextInput`.

Multiline fields preserve line breaks, and Enter inserts `\n`. Line movement
uses grapheme column rather than code-unit column.

## Keymaps

Phase 1 should keep key handling conservative:

- Default keymap: familiar terminal/editor keys already supported by
  `TextInput` and `TextArea`.
- Future optional presets: Emacs-style and Vi-style layers.

Keymaps should transform a key event plus a `TextEditingValue` into an editing
intent. They should not know about rendering.

## Paste And Clipboard

Bracketed paste should become an explicit editing input path:

- `TextInput`: normalize newlines to spaces and never submit.
- `TextArea`: preserve newlines.
- Large paste should be chunkable so the UI remains responsive.

Clipboard operations must align with RFC 0013:

- Clipboard writes are capability and policy gated.
- Secret/password fields need redaction policy before copy/cut behavior.
- OSC 52 must only be used through framework-owned clipboard services.

## Undo, History, And Completion

Undo/redo should record editing transactions, not raw key events. Paste should
usually be one transaction; typed graphemes can coalesce into word-like groups
until navigation or a pause splits the transaction.

History should be layered above the editing value for command palettes,
REPLs, and agent composers. Completion should be an editing-aware adjunct that
can read value, selection, token/range context, and validation state.

## Validation And Semantics

Validation should attach structured state to the editing value or controller:

- Valid/invalid/pending.
- Error message.
- Optional range.
- Source validator ID.

Semantic nodes for fields should expose:

- Label.
- Value or redacted value policy.
- Selection base/extent.
- Focus state.
- Validation error.
- Enabled/read-only state.
- Available actions.

## IME And Composition

Terminal IME support is inconsistent, but the model reserves `composing` so
future terminal protocols or hosts can represent composition ranges without
rewriting the value model.

The first implementation does not promise complete IME behavior.

## Implementation Plan

1. Add the pure editing model and model tests.
2. Route `TextEditingController` through `TextEditingValue`; expose
   range-valued `selection` as the canonical API and `caretOffset` as the
   scalar collapsed-selection convenience.
3. Route `TextInput` and `TextArea` through controller/model operations.
4. Add richer selection, undo/history, paste chunking, validation, and
   password/clipboard policy in later M1.2 slices.
5. Revisit rendering after the model is stable: horizontal scroll, visual
   selection ranges, soft wrap, and cursor geometry should consume model state
   rather than own editing rules.

## Open Questions

- Should launch expose `TextEditingValue` as stable API or mark it as early
  while the keymap/history/completion APIs settle?
- Which keymap preset, if any, must ship at launch?
- What is the minimum password/secret policy before copy/cut lands for editable
  fields?
