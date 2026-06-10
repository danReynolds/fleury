# RFC 0011: Semantic App Graph

**Status:** Proposal  
**Date:** 2026-05-31  
**Decision point for:** M1.1 semantic tree v0, semantic tester queries,
debug inspector expansion, prompt/fallback modes, and future agent/adaptor
operation.

## 1. Summary

Fleury needs a durable meaning layer above rendered cells. Today tests can
inspect widgets and rendered text, but there is no first-class app graph that
answers questions like:

- What command is focused?
- Which row is selected?
- What action will Enter invoke?
- What terminal capability fallback is active?
- What value is in the composer?
- Which validation error is attached to this field?

This RFC proposes a **semantic app graph**: a tree of semantic nodes derived
from widgets, app structures, commands, routes, data regions, and terminal
capability policy. The graph is not a second rendering system. It is the
framework-owned source of meaning for testing, inspection, accessibility,
prompt-mode/fallback UI, debug capture, and future automation.

The v0 goal is deliberately small: provide enough semantics for the demo-app
scenario and Phase 1 widgets without freezing a broad accessibility or agent
protocol too early.

## 2. Motivation

Terminal UIs are hard to test and operate if the only inspectable artifact is a
screen of characters. A golden can tell us that a table was painted, but not
that the table's selected row has id `run-042`, that the filter text is
`failed`, or that `Ctrl+K` exposes a disabled `Cancel Active Task` command.

The demo-app scenario in
[../implementation/demo-app-scenario.md](../implementation/demo-app-scenario.md)
requires semantics for:

- Sidebar routes and active screen.
- Command palette entries with IDs, labels, descriptions, and enabled state.
- Table rows, cells, columns, selected row, visible range, sort/filter state.
- Composer and filter values.
- Progress, cancellation, and worker status.
- Streamed transcript/log regions.
- Terminal diagnostics and active fallbacks.
- Debug-capture action.

Those are app meanings, not cell meanings. They need a stable API.

## 3. Goals

- Provide a first-class semantic node model.
- Let core and widget-catalog widgets contribute semantic nodes automatically.
- Let `FleuryTester` query by role, label, value, action, focus, selection,
  validation, and capability state.
- Let debug tools inspect the semantic graph beside widget/render/focus state.
- Support virtualized data widgets without pretending every off-screen row is a
  mounted widget.
- Keep the v0 public API conservative enough to evolve.

## 4. Non-Goals

- Full accessibility API parity with Flutter, ARIA, or platform screen-reader
  protocols.
- Full replay artifact format.
- ACP, agent protocol, or external automation transport.
- Semantic styling or layout.
- Replacing render goldens. Semantic tests complement visual snapshots.
- Source compatibility with Flutter's `Semantics` APIs.

## 5. Design Principles

1. **Meaning is not paint.** Rendering tells us what cells were drawn; semantics
   tells us what the app means.
2. **Built-in widgets should contribute automatically.** App authors should not
   manually annotate every `Button`, `TextInput`, or `Table`.
3. **Public shape stays narrow.** Expose stable fields needed for testing and
   inspection; keep richer internal metadata private until proven.
4. **Virtualized data is semantic data.** A table can expose row count, visible
   range, selected key, sort/filter state, and row actions without mounting
   100k row widgets.
5. **Commands and actions are semantic.** A command palette entry is not only a
   list row; it is an invokable app action with identity and enabled state.
6. **Capability fallbacks are visible.** If a widget degrades because the
   terminal lacks mouse, color depth, image support, clipboard, or hyperlink
   capability, tests and diagnostics should see it.

## 6. Core Types

Names are proposed, not final.

```dart
final class SemanticNodeId {
  const SemanticNodeId(this.value);
  final String value;
}

enum SemanticRole {
  app,
  screen,
  route,
  region,
  navigation,
  list,
  listItem,
  table,
  tableRow,
  tableCell,
  text,
  textField,
  textArea,
  button,
  checkbox,
  radio,
  toggle,
  menu,
  menuItem,
  commandPalette,
  command,
  dialog,
  progress,
  log,
  diagnostic,
  status,
  tab,
  tree,
  treeItem,
}

enum SemanticAction {
  focus,
  activate,
  submit,
  select,
  copy,
  clear,
  open,
  close,
  dismiss,
  navigate,
  increment,
  decrement,
  start,
  cancel,
  diagnose,
  captureDebug,
}
```

```dart
final class SemanticNode {
  const SemanticNode({
    required this.id,
    required this.role,
    this.label,
    this.value,
    this.hint,
    this.enabled = true,
    this.focused = false,
    this.selected = false,
    this.checked,
    this.expanded,
    this.busy = false,
    this.validationError,
    this.actions = const {},
    this.children = const [],
    this.state = const SemanticState.empty(),
  });

  final SemanticNodeId id;
  final SemanticRole role;
  final String? label;
  final Object? value;
  final String? hint;
  final bool enabled;
  final bool focused;
  final bool selected;
  final bool? checked;
  final bool? expanded;
  final bool busy;
  final String? validationError;
  final Set<SemanticAction> actions;
  final List<SemanticNode> children;
  final SemanticState state;
}
```

`SemanticState` is an extensible typed property bag for v0 fields that are
important but not common enough to be constructor parameters:

- `routeName`
- `commandId`
- `shortcut`
- `progressCurrent`
- `progressTotal`
- `progressLabel`
- `collectionRowCount`
- `collectionColumnCount`
- `visibleRangeStart`
- `visibleRangeEnd`
- `selectedKey`
- `sortColumn`
- `sortDirection`
- `filterText`
- `terminalCapability`
- `capabilityRequirement`
- `activeFallback`
- `severity`
- `source`

Keep this structured, not `Map<String, Object?>` as the public surface. The
implementation can use an internal map while exposing typed getters.

## 7. Contribution Model

Widgets contribute semantics through one of three paths:

1. **Automatic widget contribution.** Built-in widgets such as `TextInput`,
   `Button`, `Table`, `Dialog`, `ProgressBar`, and `Navigator` create nodes
   from their own state.
2. **Structural semantic wrapper.** A `Semantics` widget lets app code annotate
   app-specific regions, screens, and custom controls.
3. **Framework registries.** App-kernel concepts such as commands, actions,
   routes, workers, diagnostics, and capability fallbacks can contribute nodes
   even when they are not visible as mounted widgets.

Proposed wrapper:

```dart
class Semantics extends SingleChildRenderObjectWidget {
  const Semantics({
    super.key,
    required this.role,
    this.label,
    this.value,
    this.actions = const {},
    this.enabled = true,
    super.child,
  });

  final SemanticRole role;
  final String? label;
  final Object? value;
  final Set<SemanticAction> actions;
  final bool enabled;
}
```

This wrapper is for app-specific meaning. First-party widgets should not force
users to add it in common cases.

## 8. Collection And Lifecycle

The semantic graph is collected after build and before or during render
inspection:

```text
Element tree
  -> widget semantic contributors
  -> render/focus/capability state joins
  -> app registries for commands/routes/workers
  -> SemanticTree snapshot
```

Important lifecycle rules:

- A semantic snapshot is immutable.
- Node IDs are stable across pumps when widget keys, route IDs, command IDs, or
  row keys are stable.
- Nodes without stable app keys may use element identity for test-frame
  stability, but should not be persisted across sessions.
- Focus state is joined from `FocusManager`.
- Geometry can be kept internal for inspector/debug tools; v0 tester queries
  should not depend on cell positions.

## 9. Virtualized Data Semantics

Data widgets need semantics beyond mounted rows.

For `Table`/future `DataTable`, the table node should expose:

- Total row count.
- Column count and column labels.
- Visible row range.
- Selected row key and selected visible index.
- Sort column/direction when present.
- Filter/search text when present.
- Available table actions: select, copy, sort, filter, open.

Visible rows should have `tableRow` nodes. Visible cells should have
`tableCell` nodes. Off-screen rows do not need full child nodes in v0, but the
table node must expose enough collection metadata for tests and diagnostics to
understand that virtualization is active.

This avoids painting or mounting every row while still preserving semantic
testability.

## 10. Tester API

Add semantic queries to `FleuryTester` without replacing existing finders.

Proposed shape:

```dart
final tree = tester.semantics();

final runs = tree.single(
  role: SemanticRole.table,
  label: 'Runs',
);

expect(runs.state.collectionRowCount, 100000);
expect(runs.state.selectedKey, 'run-00042');

final composer = tree.single(role: SemanticRole.textArea, label: 'Composer');
expect(composer.value, '/deploy staging');
expect(composer.focused, isTrue);

final start = tree.single(
  role: SemanticRole.command,
  label: 'Start Fake Task',
);
expect(start.actions, contains(SemanticAction.activate));
```

Convenience finders can follow:

```dart
expect(tester.findSemantic.byRole(SemanticRole.button), hasLength(3));
expect(tester.findSemantic.byLabel('Capture Debug Snapshot'), findsOne);
```

The first implementation should favor direct tree queries over a large finder
DSL.

## 11. Built-In Widget Coverage For V0

Required for M1.1:

| Widget/concept | Required semantics |
| --- | --- |
| `Text` / `RichText` | `text`, label/value where useful. |
| `TextInput` | `textField`, label, value, focused, submit/clear actions. |
| `TextArea` | `textArea`, label, value, focused, selection if available. |
| `Button` | `button`, label, enabled, focused, activate action. |
| `Checkbox` / `Toggle` / `Radio` | role, label, checked/selected, enabled, activate action. |
| `Dialog` | `dialog`, label/title, dismiss action. |
| `Navigator` / routes | `screen`/`route`, route name, active state. |
| `CommandPalette` / commands | `commandPalette`, `command`, commandId, shortcut, enabled, activate action. |
| `ProgressBar` / `Spinner` | `progress`, busy, value/total/label where determinate. |
| `Table` | `table`, row/cell visible semantics, selected key, visible range, row count. |
| `LogView` | `log`, source/severity metadata where available, copy action. |
| terminal diagnostics | `diagnostic`, capability/fallback nodes. |

## 12. Demo-App Mapping

The demo app should produce semantic nodes for:

- App root: `app`, label `Fleury Example Console`.
- Sidebar: `navigation`, active screen and selectable screen items.
- Overview: `screen`, summary regions, progress nodes.
- Runs: `screen`, filter `textField`, table `Runs`, selected `tableRow`.
- Transcript: `screen`, streamed `log`/`region`, composer `textArea`.
- Diagnostics: `screen`, capability/fallback diagnostics, capture action.
- Command palette: `commandPalette` with command children.

This mapping becomes the acceptance fixture for M1.1.

## 13. Inspector And Debug Capture

The debug inspector should initially show:

- Focused semantic node.
- Active screen/route.
- Active command registry count and visible commands.
- Semantic node count by role.
- Capability fallback nodes.
- Selected table row/cell summary.

The first debug capture hook can serialize a redacted semantic snapshot plus
basic focus/capability metadata. It should not claim to be full replay.

## 14. Security And Privacy

Semantic values can contain user input, logs, paths, secrets, and process
output. Debug capture and future replay must support redaction before writing
or exporting semantic snapshots.

Rules:

- Tester APIs can expose full values in process.
- Debug UI can show values already visible in the app.
- Serialized capture should pass through redaction hooks.
- Widgets handling untrusted output should mark sanitized/fallback state where
  relevant.

## 15. Implementation Plan

1. Add core semantic types and immutable `SemanticTree` snapshot.
2. Add `Semantics` wrapper for app-specific annotations.
3. Add internal contribution hooks to `Element`/widgets or a parallel collector
   that walks mounted elements.
4. Join focus state from `FocusManager`.
5. Add `FleuryTester.semantics()` returning a snapshot.
6. Add v0 semantics to `Text`, `TextInput`, `TextArea`, `Navigator`, `Dialog`,
   `Button`, `CommandPalette`, `ProgressBar`, `Table`, and `LogView`.
7. Add inspector/debug surface for focused node, role counts, commands, and
   capability fallbacks.
8. Use the demo app to validate the graph before expanding public API.

## 16. Open Questions

- Should `Semantics` live in core public API immediately, or should the first
  version expose only tester snapshots and automatic widget semantics?
- Should semantic roles be one enum or split into control/data/app roles?
- How much command identity belongs in core before the app-kernel RFC lands?
- Should semantic collection happen on demand in tests/debug, or every frame?
- What is the minimal redaction API for debug capture?

## 17. Acceptance Criteria

M0.2 is complete when:

- This RFC defines node shape, ownership, lifecycle, and query model.
- RFC examples show `FleuryTester` querying role, label, value, focus, action,
  error, selection, table, command, progress, and capability state.
- The demo-app scenario has a concrete semantic mapping.
- Open questions that block M1.1 are recorded in the implementation tracker.
