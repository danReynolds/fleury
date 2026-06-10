# Widget API Ergonomics Audit

**Date:** 2026-06-08
**Last updated:** 2026-06-09
**Status:** Current-state audit from local public barrels plus implementation
outcomes
**Scope:** Public widget surfaces exported by `package:fleury/fleury_core.dart`
and `package:fleury_widgets/fleury_widgets.dart`. Public controllers, records,
and copy/export helpers were reviewed as part of the widget contract, but the
matrix rows focus on author-facing widgets.

## Peer Anchors

The audit used these peer conventions as guardrails:

- Flutter: retained widget trees, controlled widgets, `BuildContext`,
  `Navigator`, `FutureBuilder`, `StreamBuilder`, `ListenableBuilder`,
  semantic labels, and nullable callbacks for disabled controls. Relevant
  anchors: [Checkbox.onChanged](https://api.flutter.dev/flutter/material/Checkbox/onChanged.html),
  [Switch.onChanged](https://api.flutter.dev/flutter/material/Switch/onChanged.html),
  [DropdownButton](https://api.flutter.dev/flutter/material/DropdownButton/DropdownButton.html),
  [TextField](https://api.flutter.dev/flutter/material/TextField-class.html),
  [DataTable](https://api.flutter.dev/flutter/material/DataTable-class.html),
  [Flutter widget catalog](https://docs.flutter.dev/ui/widgets).
- Textual: app actions, screen-local commands, command palette providers,
  data table, tree, and app-scale TUI structure. Relevant anchors:
  [Actions](https://textual.textualize.io/guide/actions/),
  [Command palette](https://textual.textualize.io/guide/command_palette/),
  [DataTable](https://textual.textualize.io/widgets/data_table/),
  [Tree](https://textual.textualize.io/widgets/tree/).
- Charm Bubble Tea/Bubbles/Huh: small composable terminal components and form
  primitives with simple value binding. Relevant anchors:
  [Bubbles](https://github.com/charmbracelet/bubbles),
  [Huh](https://github.com/charmbracelet/huh).
- Ink: React-style component familiarity for CLIs, where authoring familiarity
  is the main DX win. Anchor: [Ink README](https://github.com/vadimdemedes/ink).
- Ratatui: lower-level widget/rendering API with built-in table, chart, gauge,
  sparkline, tabs, scrollbar, and canvas-style primitives. Relevant anchors:
  [widgets concept](https://ratatui.rs/concepts/widgets/),
  [widget showcase](https://ratatui.rs/showcase/widgets/).
- Nocterm: closest Dart/Flutter-shaped peer, with `runApp`, stateful
  components, hot reload, testing, lints, and IDE assists. Anchor:
  [nocterm on pub.dev](https://pub.dev/packages/nocterm).
- OpenTUI: modern high-performance component architecture and TypeScript
  bindings. Anchor: [OpenTUI getting started](https://opentui.com/docs/getting-started/).

## Landed During This Pass

- `Checkbox`, `Toggle`, `Switch`, and `Radio` now accept nullable
  `onChanged`. Passing `null` disables the control, removes activation
  actions, and exposes disabled semantics. This matches the existing
  `Button(onPressed: null)` pattern and Flutter's control convention.
- `Table` and `DataTable` now expose a semantic `label` parameter. This makes
  semantic tests and automation less dependent on role-only matching while
  keeping visual output unchanged.
- `Select`, `DatePicker`, `Stepper`, `RangeSlider`, and `ColorPicker` now
  accept nullable `onChanged`. Passing `null` disables the widget, removes
  activation actions, keeps state readable in semantics, and uses muted visual
  styling.
- `MultiSelect<T>` now exists as the standalone peer to `Select<T>`, using the
  same `SelectOption<T>` model and a controlled `Set<T>` value.
- `ProgressBar` now accepts a configurable `semanticLabel`, closing the last
  obvious display-widget semantic-label gap found in this audit.

## Status Key

- **Improved:** Ergonomic change landed in this pass and is covered by tests.
- **Good:** API is clean enough for now; no immediate change recommended.
- **Decision:** The area was reviewed and intentionally left unchanged for now.
- **Needs sign-off:** There is a plausible ergonomic improvement, but it
  changes a broader convention, interaction model, or naming story. Do not
  land casually.

## Resolved Sign-off Items

| Priority | Area | Outcome | Read |
| --- | --- | --- | --- |
| P1 | Controlled input disabled states | Landed across `Select`, `DatePicker`, `Stepper`, `RangeSlider`, and `ColorPicker`. | Nullable callbacks are now the standard disabled-state API for controlled widgets where there is no separate `enabled` knob. |
| P1 | Standalone multi-select | Landed as `MultiSelect<T>`. | This keeps forms batteries-included while giving authors a direct primitive for sidebar filters, checklist panels, and setup flows. |
| P2 | Chart/data semantic labels | Tightened where the gap was found: `ProgressBar.semanticLabel`. | The chart family already had semantic labels/summaries in the important places; keep this as a rule for future display widgets rather than a broad rewrite. |
| P2 | First-class capability fallback knobs | No new constructor knobs for now. | `Image`, `Canvas`, and charts already expose semantic fallback state and compact rendering knobs. Add explicit fallback policy only when a widget has multiple useful author-facing fallback behaviors. |
| P2 | `Table` vs Flutter `Table` naming | Keep `Table`. | Fleury's table is terminal-display-oriented, but the existing name is useful and tested. Add an alias only if real author confusion shows up. |

## Core Widget Matrix

| Widget surface | Main peer comparison | Status | Read |
| --- | --- | --- | --- |
| `FleuryApp`, `FleuryAppController`, `FleuryAppScope`, `AppStatusBar`, `CommandScope` | Flutter `MaterialApp`/app shell, Textual `App` actions, Nocterm `runApp` | Good | Cleaner after removing framework screen registration. Global app commands plus scoped command registries are the right direction. |
| `Semantics` | Flutter semantics, Textual queryable widgets | Good | A differentiator. Keep improving inspection/devtools rather than changing the widget API. |
| `Focus`, `FocusScope`, `FocusWithin`, `ExcludeFocus`, `FocusTraversalGroup` | Flutter focus tree, Textual focusable widgets | Good | Explicit enough for TUI work and already supports scoped key/focus composition. |
| `KeyBindings`, `KeyHintBar` | Textual bindings/actions, Bubble Tea key maps | Good | Command/key separation is coherent. `KeyHintBar` is TUI-specific and justified. |
| `Navigator`, `PopScope`, `Overlay`, `Anchor`, `Follower` | Flutter `Navigator`/`Overlay`, Textual screens/overlays | Good | App-owned navigation is now less special and easier to reason about. |
| `LayoutBuilder`, `MediaQuery`, `Theme`, `DefaultTextStyle` | Flutter layout/theme context | Good | Familiar names and useful terminal-specific data. No ergonomic issue found. |
| `Text`, `RichText`, `TextSpan` | Flutter text widgets, Ratatui `Paragraph`/`Text` | Good | Terminal width/sanitizer behavior is the right Fleury-specific addition. |
| `Row`, `Column`, `Flex`, `Expanded`, `Flexible` | Flutter flex layout, Ink/Yoga flexbox | Good | Strong Flutter muscle-memory transfer. |
| `Stack`, `IndexedStack`, `Positioned`, `Wrap` | Flutter layout widgets | Good | Expected names and behavior. No current action. |
| `Align`, `Center`, `SizedBox`, `Padding`, `Container`, `ConstrainedBox`, `AspectRatio`, `EmptyBox`, `ErrorWidget` | Flutter primitives | Good | Constructor shape is close enough; terminal cell constraints justify differences. |
| `ListView`, `ListController`, `ScrollView`, `ScrollController`, `Scrollbar` | Flutter scrollables, Bubbles viewport, Ratatui scrollbar | Good | Controller lifecycle and scroll semantics are already hardened. |
| `FutureBuilder`, `StreamBuilder`, `AsyncSnapshot` | Flutter async builders | Good | Signatures match the expected mental model. Keep docs warning against inline future creation. |
| `ListenableBuilder` | Flutter `ListenableBuilder` | Improved | `listenable:` is now the primary parameter, with deprecated `animation:` compatibility. |
| `FrameBuilder`, `AnimationBuilder`, `TickerMode`, `Animate`, `Effects`, `Reveal`, `Spinner` | Flutter animation widgets, Ink/Ratatui spinners | Good | TUI animation policy exists and the API is readable. No immediate change. |
| `SelectionArea`, `Selectable`, `SelectionScope`, `SelectionRegistrar`, `RepaintBoundary` | Flutter selection/paint boundaries | Good | Advanced but coherent. Keep as lower-level primitives until examples prove higher-level sugar. |
| `TextInput`, `TextArea`, `BlinkingCursor` | Flutter `TextField`, Bubbles text input/area, Ink text input | Good | Rich terminal editing contract is justified. `enabled` and `readOnly` already exist on completion input; keep parity pressure on core docs. |

## First-party Widget Matrix

| Widget surface | Main peer comparison | Status | Read |
| --- | --- | --- | --- |
| `CommandPalette`, `Command` | Textual command palette/providers, GitHub-style palettes | Good | `CommandPalette.open(context)` plus registry-backed source context is clean and better than the earlier app-prefixed API. |
| `Button` | Flutter buttons | Good | Nullable `onPressed` disabling was already correct and now sets the pattern for controls. |
| `Checkbox`, `Toggle`, `Switch`, `Radio` | Flutter selection controls | Improved | Nullable `onChanged` now disables the controls with disabled semantics and no activation actions. |
| `Select`, `SelectOption` | Flutter dropdowns, Huh select, Ink select input | Improved | `onChanged: null` now disables the whole control with muted style, no open action, and disabled semantics. |
| `MultiSelect` | Huh multi-select, CLI checkbox prompts, setup/filter panels | Improved | Standalone controlled `Set<T>` selection now exists beside `Select`, using the same option model and disabled semantics. |
| `NumberInput`, `PasswordInput`, `CompletionTextInput`, `Autocomplete` | Flutter text fields, Bubbles input, Huh input | Good | The controller/focus/placeholder/on-submit shape is consistent and pragmatic. |
| `Stepper`, `RangeSlider`, `DatePicker`, `ColorPicker` | Flutter slider/date picker/spinbox conventions | Improved | Nullable `onChanged` now disables interaction consistently across focus, key, pointer, visual, and semantic paths. |
| `FormPanel`, `FormWizard` | Huh forms/groups, Textual forms | Good | Strong batteries-included story. `MultiSelect` is now also available when authors do not want a form shell. |
| `Dialog`, `Tooltip`, `Toaster`, `ToastAction` | Flutter modal/tooltip/snackbar, Textual overlays | Good | APIs are simple, terminal-specific, and compose through `Navigator`/`Overlay`. |
| `Menu`, `MenuItem`, `SubMenu`, `MenuSeparator` | Textual menus/actions, Flutter menus | Good | Entry model is conventional; no immediate action. |
| `Tabs`, `TabController`, `TabItem` | Flutter `TabBar`/`TabController`, Ratatui tabs, Ink tab bar | Good | Controller-owned tabs fit the command-scope direction. Future examples should show scoped tab commands. |
| `Tree`, `TreeNode` | Textual tree, Ratatui tree ecosystem | Good | Small API is readable. Keep advanced hierarchy features in `TreeTable`. |
| `Table`, `TableController` | Flutter `Table`, Ratatui table, Bubbles table | Improved | Now has semantic `label`. Naming decision: keep `Table` despite imperfect Flutter name parity; revisit only if confusion appears. |
| `DataTable`, `DataTableController` | Flutter `DataTable`, Textual `DataTable`, Ratatui table | Improved | Virtualized, copy/export, semantic-row API is justified. Semantic `label` landed. |
| `TreeTable`, `TreeTableController` | Textual tree/data table, filesystem/process trees | Good | Heavy but coherent. It is one of Fleury's app-grade differentiators, not a Flutter parity target. |
| `FileBrowser`, `FilePicker` | Huh file picker, Textual directory tree patterns | Good | File-system widgets are useful and clear. Keep security/capability policy documented. |
| `FileMentionPicker` | IDE/agent composer mentions, Textual command providers | Good | Good developer-tool-specific widget. Query/controller/copy contracts are consistent. |
| `SearchPanel`, `SearchResult` | Command palettes, IDE search panels, Textual search widgets | Good | Clear query/result/controller shape. |
| `ConversationNavigator` | Agent chat/session sidebars | Good | Domain-specific but justified by Fleury's developer-tool focus. |
| `ContextPanel` | Agent context inspectors | Good | Strong copy/export/sanitize/semantic contract. No current API change. |
| `MessageList`, `MessageListController` | Chat transcript panels, log viewers | Good | Good controlled selection/tail behavior and copy/export contract. |
| `LogRegion`, `TerminalOutputRegion` | Bubbles viewport, Textual log widgets | Good | Clear separation between generic logs and terminal process output. |
| `ProcessPanel` | Textual workers/process logs, CLI task panels | Good | Thin composition over task/process records is appropriate. |
| `TraceTimeline` | Devtools traces, task timelines | Good | Domain-specific but useful; copy/export and semantics are consistent. |
| `TaskGraph` | Agent plan/task displays | Good | Better as a first-party developer-tool widget than an app-owned one-off. |
| `ToolCallCard`, `ApprovalPrompt`, `ModelStatusBar`, `TokenMeter` | Agent/tooling widgets | Good | These are intentionally opinionated. Keep them in `fleury_widgets`, not core. |
| `PatchReview` | Code review/diff workflows | Good | Rich API is justified; copy/export and sanitized output are present. |
| `CodeView`, `DiffView`, `JsonView`, `MarkdownText`, `MarkdownView` | IDE viewers, Textual rich widgets, Bubbles viewport | Good | Document/source constructors plus controllers are ergonomic. Keep parse helpers public. |
| `BarChart`, `LineChart`, `Sparkline`, `Histogram`, `Heatmap`, `CalendarHeatmap` | Ratatui charts/sparkline/calendar, Textual rich display widgets | Good | API is data-first and compact. Semantic labels/summaries are already present where this audit found meaningful gaps. |
| `Gauge`, `ProgressBar`, `Digits` | Ratatui gauge/line gauge, Bubbles progress/spinners | Improved | `ProgressBar.semanticLabel` landed; the display widgets now have the expected automation/accessibility hook. |
| `Canvas`, `Image` | Ratatui canvas, terminal image protocols, OpenTUI rendering | Decision | Useful escape hatches. Keep current compact rendering knobs plus semantic fallback state; do not add broad fallback-policy constructors without a concrete need. |
| `WorkflowSnapshot`, `WorkflowSummary` | Agent workflow state adapters | Good | Data snapshot rather than widget, but it supports the catalog coherently. Keep protocol-neutral. |

## Current Take

Fleury's widget API surface is not in a broad DX emergency. The main surface is
coherent: Flutter-shaped core widgets, TUI-specific focus/key/navigation,
controller-backed high-level widgets, semantic inspection, and copy/export
contracts for developer-tool views.

The highest-value widget API issues from this audit are now resolved. The
remaining widget-DX work is not another broad constructor sweep; it is
evidence-driven polish:

1. Keep adding semantic labels/summaries to new display widgets as a default
   rule.
2. Add capability fallback constructor knobs only when a concrete widget has
   multiple useful author-facing fallback policies.
3. Revisit `Table` naming only if real usage shows confusion with Flutter's
   layout table.

Everything else is lower priority than devtools/inspection, CLI polish, and
the later storybook/cookbook work already scoped separately.
