# Workstream: Text Editing Engine

## Purpose

Make Fleury text input trustworthy enough for production developer tools,
agent consoles, forms, command palettes, search boxes, and config editors.

## Current State

- `TextInput` and `TextArea` exist.
- M1.2 now has a first pure editing model:
  `TextRange`, `TextSelection`, `TextEditingValue`, and `TextEditingModel`.
- `TextEditingController` now stores a `TextEditingValue` internally while
  preserving `text` and integer `selection` compatibility accessors.
- `TextHistoryController` now provides opt-in command/submission history for
  single-line inputs.
- `TextCompletionController` now provides completion range/query/options
  state and selected replacement application.
- `TextPastePolicy`/`TextPasteSession` now provide chunked large-paste
  scheduling for `TextInput` and `TextArea`.
- `TextEditingKeymap` now provides default single-line/multiline maps,
  custom bindings, and Emacs-style movement presets over shared editing
  actions.
- `TextHistoryController` and `TextCompletionController` now have explicit
  disposal semantics matching the main editing controller: readable final state,
  transient state cleanup, and mutation rejection after teardown.
- `CompletionTextInput` now provides provider-backed rendered completion UI in
  `fleury_widgets`, including semantic menu close and row select/activate
  actions that use the same completion acceptance path as Tab.
- The demo app Transcript composer now uses `CompletionTextInput` with
  deterministic slash-command and mention suggestions plus
  `TextHistoryController` submission history, proving rendered completion and
  history navigation in an app-scale workflow rather than only focused widget
  tests.
- `Autocomplete` now has a labeled `TextInput` surface plus semantic suggestion
  menu/menu-item nodes with query state and select/activate actions, preserving
  parent-owned Up/Down behavior while making suggestion workflows testable.
- `TextInput` now exposes a small `semanticLabel`/`semanticState` extension
  seam so specialized text-entry controls can add domain metadata while
  preserving core text-field roles, actions, selection, paste, redaction, and
  clipboard semantics. `NumberInput` uses this seam for constrained numeric
  text entry, and `PasswordInput` uses it for secret-field metadata without
  leaking raw values.
- `TextEditingValue`, `TextEditingModel`, and `TextEditingController` now have
  composition seams for future input-method adapters: composing ranges, interim
  updates, commit, cancel, and semantic composing state.
- `TextEditingController` now has explicit disposal semantics: values remain
  readable after teardown, transient undo/redo/composition state is cleared, and
  all mutating operations reject post-dispose use.
- `SB.2 Text Editing Composer Stress` now gives a scenario baseline for the
  core text stack under a 10k-character mixed-width editor, chunked paste,
  selection, undo/redo, history, completion acceptance, secret redaction, and
  semantic query pressure.
- Current limitations include full terminal IME protocol behavior and
  optional Vi-style modal editing.
- Input dispatch and parser foundations exist, and RFC 0008 covers input
  dispatch direction.

## Target Capabilities

- Pure `TextEditingValue`, `TextSelection`, and `TextRange` model.
- Grapheme-indexed cursoring and editing.
- Single-line and multiline fields sharing one editing core.
- Selection, word movement, line movement, undo/redo, history, completion,
  bracketed paste, clipboard policy, password policy, and validation.
- Optional Emacs-style keymap presets, with Vi-style modal editing deferred.
- Future-safe IME/composition hooks.

## Milestone Checklist

- [x] TEE.1 Write text editing v2 RFC.
  - Intent: Define the editing model before changing widgets.
  - Acceptance: RFC covers values, selection, ranges, grapheme indexing,
    keymaps, paste, clipboard, undo, completion, history, validation,
    password policy, and IME extension points.
  - Evidence: [RFC 0014: Text editing v2](../../rfcs/0014-text-editing-v2.md).
  - Notes: Keep rendering out of the model.

- [x] TEE.2 Implement pure editing model.
  - Intent: Prove correctness without terminal rendering complexity.
  - Acceptance: Unit tests cover emoji, CJK, combining marks, wide
    characters, word movement, line movement, selection, undo, paste, history,
    and multiline behavior.
  - Evidence:
    [pure editing model](../../../packages/fleury/lib/src/editing/text_editing.dart),
    [history controller](../../../packages/fleury/lib/src/editing/text_history.dart),
    [completion controller](../../../packages/fleury/lib/src/editing/text_completion.dart),
    [keymap model](../../../packages/fleury/lib/src/editing/text_keymap.dart),
    [paste scheduling](../../../packages/fleury/lib/src/editing/text_paste.dart),
    [completion input](../../../packages/fleury_widgets/lib/src/completion_text_input.dart),
    [pure editing model tests](../../../packages/fleury/test/editing/text_editing_model_test.dart),
    [completion tests](../../../packages/fleury/test/editing/text_completion_test.dart),
    [keymap tests](../../../packages/fleury/test/editing/text_keymap_test.dart),
    [paste tests](../../../packages/fleury/test/editing/text_paste_test.dart),
    [completion input tests](../../../packages/fleury_widgets/test/completion_text_input_test.dart),
    [controller tests](../../../packages/fleury/test/widgets/text_editing_controller_test.dart),
    [text editing scenario benchmark](../../../packages/fleury/benchmark/scenario_benchmarks.dart),
    [text editing scenario baseline](../../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json).
  - Notes: Current slices cover value/range/selection primitives,
    grapheme-safe insertion/deletion/movement, shift-extension, single-line
    paste normalization, line movement, basic undo/redo, explicit paste
    routing, single-transaction paste undo, and contiguous typed-input
    coalescing, opt-in submission history with draft restore, arbitrary range
    replacement, completion option state/acceptance, and chunked large-paste
    scheduling. The first rendered completion UI lives in `fleury_widgets` as
    a provider-backed wrapper around core `TextInput`/`TextCompletionController`.
    Its completion menu now exposes semantic close plus row select/activate
    actions, preserving the controller-owned range replacement path. The demo
    app Transcript composer now adopts that widget for slash-command and
    mention completions, with semantic activation coverage over the same menu
    path. It also passes a `TextHistoryController` so submitted notes can be
    recalled with Up/Down when the completion menu is closed, while completion
    navigation remains higher priority when suggestions are open.
    Composition seams now cover composing range updates, commits, cancellation,
    grapheme-safe range snapping, single-line normalization, and one undo step
    for a committed composition. Word movement is now a pure editing-model
    operation over whitespace-delimited grapheme runs, and `TextEditingKeymap`
    resolves terminal key events to editing intents without baking policy into
    the model. Controller disposal is now explicit: disposed controllers retain
    their final readable value, clear transient history/composition state, and
    reject all mutating operations including no-op edit commands. Auxiliary
    history/completion controllers now follow the same lifecycle contract:
    history entries remain readable while browsing draft/selection state clears,
    completion state resets to inactive, and post-dispose mutation is rejected.

- [x] TEE.3 Replace widget internals with shared editor core.
  - Intent: Make `TextInput` and `TextArea` share behavior.
  - Acceptance: Existing public APIs continue where possible, while richer
    APIs expose value, selection, errors, completion state, and semantics.
  - Evidence:
    [TextInput controller integration](../../../packages/fleury/lib/src/widgets/text_input.dart),
    [TextArea controller integration](../../../packages/fleury/lib/src/widgets/text_area.dart),
    [TextInput behavior tests](../../../packages/fleury/test/widgets/text_input_test.dart),
    [TextArea behavior tests](../../../packages/fleury/test/widgets/text_area_test.dart).
  - Notes: Controller operations, TextArea line movement, undo/redo, typed
    transaction coalescing, paste transactions, validation state, read-only
    behavior, disabled state, and first clipboard policy semantics now use the
    shared model/controller layer. TextInput and TextArea render non-collapsed
    selection ranges. TextInput and TextArea now keep the active cursor/
    selection edge visible with horizontal scrolling. Field-level copy/cut now
    enforces `TextClipboardPolicy`. `TextInput` can opt into Up/Down history
    browsing with `TextHistoryController` without stealing those keys from
    parent-owned navigation surfaces by default. `TextInput` can also opt into
    `TextCompletionController` for active completion selection and Tab
    acceptance without adding popup UI to the core field. `TextInput` and
    `TextArea` both chunk large paste payloads across frames while preserving
    one undo transaction. `CompletionTextInput` composes core editing state,
    anchoring, overlay, and list primitives for a rendered menu. Input-method
    adapters can now drive composition through controller APIs without needing
    to mutate raw text directly. `TextInput` and `TextArea` now share keymap
    resolution for copy/cut, undo/redo, deletion, grapheme movement, word
    movement, line/document movement, submit/newline, completion, history, and
    escape behavior. `SB.2` now records 10k-character text editing pressure in
    the benchmark lab: cursor-move p95 798 us, insertion/deletion p95 641 us,
    selection p95 2191 us, chunked-paste completion p95 18573 us, and
    semantic-query p95 508 us on the first saved baseline.
    The current specialized-field slices add `TextInput.semanticLabel` and
    additive `semanticState` so wrappers such as `NumberInput` and
    `PasswordInput` can expose numeric bounds, parsed values, and secret-field
    metadata without forking text editing semantics or overriding redaction
    safety.
    CompletionTextInput suggestion rows now dispatch semantic select/activate
    through the same controller/range replacement path as Tab acceptance, and
    the demo app composer now uses that path for slash-command completion.
    The same composer now proves opt-in submission history semantics in the
    integrated demo workflow.

- [x] TEE.4 Add editing semantics and tests.
  - Intent: Make text fields testable above rendered cells.
  - Acceptance: Tester can query label, value, cursor/selection state,
    validation error, password policy, enabled/read-only state, and available
    actions.
  - Evidence:
    [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
  - Notes: Label, value, focus, actions, password/redaction flag, collapsed/
    non-collapsed selection state, validation error, enabled/read-only state,
    clipboard policy, copy action availability, and history navigation state
    are queryable. Completion query/range/option/selection state is also
    queryable, and rendered completion rows can be selected or activated
    through semantic actions. Paste progress state and composing range state
    are queryable.
    Available actions cover focus, submit, copy, and editable-field state
    expected by current widgets.

## Implementation Notes

- Text quality will shape developer trust in the whole framework.
- Bracketed paste, clipboard policy, password/secret fields, malformed
  Unicode behavior, and copy redaction connect this workstream to
  [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md).
- Completion, autocomplete, and command palette should share editing
  primitives where possible.
- Keep provider/rendering widgets in `fleury_widgets`; keep value/state/key
  semantics in core.
- Keep public compatibility in mind: integer `selection` remains an accessor
  for now, but `textSelection`/`value` are the richer model surface.
- Treat composition as an adapter seam for now. The MVP exposes durable
  controller/model/semantic behavior, but does not promise native terminal IME
  protocol coverage.
- Treat controller mutation after disposal as a lifecycle error. Text fields are
  structural app state, so silent post-teardown edits hide bugs in screen,
  command, and async workflow cleanup.
- Keep auxiliary controller state readable after disposal where it is primary
  app data. History entries are retained; transient browsing drafts and
  completion menus are cleared.

## Risks And Open Questions

- Terminal IME support is uneven; composition seams exist, but native protocol
  handling still needs real-terminal research before any launch claim.
- Vi-style editing can expand scope quickly; make it optional and layered.
- Password and secret fields need policy hooks before clipboard/paste support
  becomes too permissive.

## Acceptance Evidence

- [RFC 0014: Text editing v2](../../rfcs/0014-text-editing-v2.md).
- [completion controller](../../../packages/fleury/lib/src/editing/text_completion.dart).
- [completion input](../../../packages/fleury_widgets/lib/src/completion_text_input.dart).
- [keymap model](../../../packages/fleury/lib/src/editing/text_keymap.dart).
- [pure editing model](../../../packages/fleury/lib/src/editing/text_editing.dart).
- [history controller](../../../packages/fleury/lib/src/editing/text_history.dart).
- [paste scheduling](../../../packages/fleury/lib/src/editing/text_paste.dart).
- [completion tests](../../../packages/fleury/test/editing/text_completion_test.dart).
- [keymap tests](../../../packages/fleury/test/editing/text_keymap_test.dart).
- [completion input tests](../../../packages/fleury_widgets/test/completion_text_input_test.dart).
- [paste tests](../../../packages/fleury/test/editing/text_paste_test.dart).
- [pure editing model tests](../../../packages/fleury/test/editing/text_editing_model_test.dart).
- [controller tests](../../../packages/fleury/test/widgets/text_editing_controller_test.dart).
- [TextInput behavior tests](../../../packages/fleury/test/widgets/text_input_test.dart).
- [TextArea behavior tests](../../../packages/fleury/test/widgets/text_area_test.dart).
- [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
- [Text editing scenario benchmark](../../../packages/fleury/benchmark/scenario_benchmarks.dart).
- [Text editing Phase 2 baseline](../../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json).
