# Core API/DX Audit — Findings (2026-07-04)

Decision-ready output of the deferred core API/DX audit (teed up by
`core-api-dx-audit-readiness.md` once the perf/frame-path line closed). Feeds an
**API-freeze** decision — public docs/collateral are blocked on freeze, and the
breaking-change window is open now, so API-shape items here are timing-sensitive.

## Method

Hands-on first: exercised the API as a user would (built a form, wired inputs,
crossed the package split), then two inventory passes — the full public widget
surface, and the samples + website docs. Every candidate was re-checked against
Flutter and peer-TUI conventions (Textual, Bubble Tea/Huh, Nocterm, Ratatui).
Judgment applied throughout to separate **real fleury drift** from
**Flutter-faithful** (familiar = acceptable, even if not internally uniform).

## Headline

The **onboarding is world-class** — `getting-started` → `tutorial` → a 76-entry
live widget catalog → a `coming-from-flutter` cheat sheet; a newcomer is running
in minutes. So the yield is **not** the front door. It is:

- **A. Pre-freeze API drift** — small inconsistencies that are cheap now and
  breaking later. This is the audit's time-sensitive core.
- **B. The "second-app" tier** — forms, shared state, layout recipes, boilerplate.
  Additive, not freeze-gated, but it's where the DX thins out.

| # | Finding | Impact | Effort | Breaking? | Verdict |
| --- | --- | --- | --- | --- | --- |
| A1 | `TextInput` has no `onChanged` | High | Low | No (additive) | **Fix now** |
| A2 | `label` vs `semanticLabel` vs `placeholder` — no consistent "field name" | Med-High | Med | Yes | Decide |
| A3 | core ↔ `fleury_widgets` seam is arbitrary (`TextInput` core, `Checkbox` not) | Med | Low–Med | Yes if moved | Decide |
| A4 | Uneven styling access (granular `CellStyle` vs `variant`-only vs theme-only) | Med-Low | Med | Maybe | Decide |
| B1 | No shipped `Panel` (title+border+focused pane) — every sample reinvents it | Med-High | Low-Med | No | **Do** |
| B2 | Thin intermediate docs (forms, shared state, recipes, modals, focus decision) | Med | Med | No | Do (parallel) |
| B3 | `Form`/file/image/log are terminal-only — two-surface caveat | Med | Med-High | No | Later |
| B4 | `FocusNode`×N + scaffold boilerplate | Low-Med | Med | No | Later |

---

## A. Pre-freeze API drift

### A1 — `TextInput` has no `onChanged` *(highest; fix now)*

`TextInput` (`packages/fleury/lib/src/widgets/text_input.dart:476`) exposes
`onSubmit` (Enter) and `onEscape` but **no per-keystroke `onChanged`**. To react
to live edits you must attach a `controller` and add a listener. Yet
`NumberInput` — which *wraps* `TextInput` — has **both** `onChanged` and
`onSubmit` (`packages/fleury_widgets/lib/src/number_input.dart:53`), and Flutter's
`TextField` has `onChanged`. So the single most-used input is the odd one out, in
a way a Flutter dev will trip on immediately.

- **Why it matters:** live-filter boxes, search-as-you-type, and any "mirror the
  value into state" pattern all need a controller+listener today (`tutorial.md`
  shows exactly this workaround: `_controller.addListener(() => setState(...))`).
- **Fix:** add `void Function(String)? onChanged` to `TextInput`, fired on every
  edit. Non-breaking (new optional param). Cascades to `PasswordInput` for free.
- **Effort:** low. **Recommend: land pre-freeze.**

### A2 — No consistent "field name" parameter *(decide)*

`label` is overloaded:
- **Visible text** on `Checkbox`/`Toggle`/`Switch`/`Radio`/`Button`
  (`controls.dart:197,576`).
- **Accessibility name** on `Table`/`DataTable` (`table.dart:119`, `label:` →
  semantics only, no visual change).
- Inputs use a *third* convention: `semanticLabel` for the a11y name
  (`text_input.dart:495`) and `placeholder` for the hint — and no visible label
  at all (you hand-place a `Text` above the field).

So "what is this field called?" has three different answers depending on the
widget. A labeled form is therefore more verbose than Flutter's
`InputDecoration(labelText:)`.

- **Options:** (a) standardize `label` = visible, `semanticLabel` = a11y-only,
  everywhere; give inputs an optional visible `label`. (b) Ratify the split as
  intentional and document it. Either way it's a naming decision that is
  **breaking to defer** past freeze.

### A3 — The core ↔ `fleury_widgets` seam is arbitrary at the edge *(decide)*

`TextInput`/`TextArea` live in **core** (`fleury`); `Checkbox`/`Button`/`Select`/
`NumberInput`/`Radio` live in **`fleury_widgets`**. A *form* — a common task —
spans both packages, and the stated rationale ("primitives vs. rich controls")
doesn't explain why a text field is a primitive but a checkbox isn't. A newcomer
has to learn the boundary by trial (the quickstart imports only `fleury`; the
getting-started doc adds `fleury_widgets` at step 4 without flagging why).

- **Recommend:** ratify the boundary explicitly pre-freeze (moving a widget
  across the package line is breaking). Either document the rule crisply or move
  the basic form controls next to `TextInput`.

### A4 — Styling access is uneven *(decide)*

`TextInput` takes granular `style`/`placeholderStyle`/`cursorStyle`
(`CellStyle`s); `Button` takes only a `variant` enum — **no way to color a
one-off button** without a theme (`controls.dart:578`); `Select`/`Menu` read the
theme with no per-instance override. There's no uniform "style envelope."

- **Recommend:** decide a per-widget override convention (a small `…Style` object
  or a `style:` escape hatch on controls), or ratify "controls are theme-only, by
  design" and document it. Lower urgency than A1–A3.

### Challenged — NOT findings (Flutter-faithful)

The inventory pass flagged these; on judgment they are correct and should be left
alone:
- **`Button.onPressed`** and **`Menu`/`Autocomplete.onSelected`** — these are
  Flutter's exact conventions (`ElevatedButton.onPressed`, `Autocomplete.onSelected`).
- **The disable split** (`TextInput.enabled` flag vs `Checkbox(onChanged: null)`)
  — Flutter is split the *same* way (`TextField.enabled` + `Checkbox` nullable
  `onChanged`). Familiar beats a false uniformity.

---

## B. The "second-app" tier (additive)

### B1 — Ship a `Panel` *(highest additive; do)*

"Title + border + focused-pane styling" is the single most-repeated pattern in
the samples — `dashboard.dart` builds it 5×, `file_manager.dart` 2×, `agent_tui`
inlines its own — but it lives only in `packages/samples/lib/src/scaffold.dart`,
not the library. Nearly every real TUI screen is panes. Promote a `Panel` (and
likely a `SampleScaffold`-style app frame) into `fleury_widgets`.

### B2 — Intermediate docs gap *(do, parallel)*

Onboarding is excellent; the "now build a real app" tier is thin. Missing guides:
multi-field **forms + validation**; **shared state** (ChangeNotifier +
ListenableBuilder — docs show only `setState`, though the pieces exist); **layout
recipes** (sidebar/main, header/body/footer); **modals/dialogs** (`Dialog` exists
but isn't in onboarding); and a **Focus vs KeyBindings vs FocusNode decision
tree**. (These overlap the readiness doc's "state-management story needs a
concise authored guide.")

### B3 — `Form`/file/image/log are terminal-only *(later)*

`fleury_widgets_web.dart` excludes `file_browser`, `file_picker`, **`form`**,
`image`, `log_region`, `process_panel`, `terminal_output_region`,
`workflow_snapshot` (dart:io-gated; pinned by `web_barrel_parity_test`). For a
"one tree, two surfaces" framework, a chunk of the widget set silently doesn't
run on the web — and `Form` is a common one. The `Form`'s `dart:io` is *only* the
`path` field type; a **web-safe form core** (text/number/select/checkbox) with
the path-field as a native extension is feasible and would close the gap.
Separately, the spec-based `Form` (`FormFieldSpec.text(...)`, closed field-type
enum) diverges from Flutter's widget-based `Form`/`TextFormField` — worth a
deliberate ratify-or-revisit.

### B4 — Boilerplate: `FocusNode`×N + scaffold *(later)*

Multi-pane screens declare + dispose N `FocusNode`s by hand (`chat_demo.dart`
creates/disposes 3), and every app re-wraps `Theme + Toaster + Container` (not
injected by `runApp`). Conveniences — a `FocusGroup`/auto-dispose helper, and an
app scaffold — would cut per-screen boilerplate. First confirm whether `FleuryApp`
is already intended as the scaffold and simply isn't reached for in samples.

---

## Recommended sequence

1. **A1 `TextInput.onChanged`** — non-breaking, unambiguously right, highest-use
   widget. Start here; validate against a real form's impedance mismatch.
2. **A2 / A3 / A4** — bring to the maintainer as explicit pre-freeze **decisions**
   (naming, package boundary, styling convention). These gate API freeze.
3. **B1 `Panel`** — highest-value additive; can run alongside the decisions.
4. **B2 docs guides** — parallel, non-blocking.
5. **B3 / B4** — post-decision.

Exit criterion: A1 landed, A2–A4 decided (freeze the surface), B1 shipped, B2
under way → an API-freeze readiness statement.
