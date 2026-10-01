# Docs launch readiness — 2026-09-30

> **Status, October 1, 2026: resolved.** Every P0 and P1 item below, and the
> P2 polish, was fixed in [#292](https://github.com/danReynolds/fleury/pull/292),
> along with product bugs the fixes uncovered (key sequences in dialogs, held
> keys replayed into a dialog, Ctrl+Z under the dev supervisor, `fleury shell`
> signal keys, focus reporting, and widget bugs). The decisions at the end were
> made: restart stays Ctrl+G then F5 with documented caveats; Ctrl+Z is
> dispatched first and suspends only when unhandled; demos stay dark; debug
> tooling is on only in development runs; the LineChart lab is a draft page; Pad
> capacity is unchanged. The items that needed further decisions (a second
> debug-panel expand key, the mouse under `fleury shell`, a suspend request for
> apps whose text field always has focus, and editable demos that hid their
> data) were resolved in the follow-up after #292. The text below is the
> original audit.

**Verdict: close, not ready.**

The site's machinery is sound: every page builds, every link and anchor resolves, and every demo mounts at its declared grid. The editable Pads also work from the live origin.

The rest is content. Fourteen items would mislead or stall a first-time reader (P0), then there are reference gaps (P1) and polish (P2). None needs a redesign. Most are copy, doc-comment, or small generator changes; the exceptions are three product decisions listed at the end.

## What was checked

- **Five read-only reviews** covered, claim by claim against `packages/` source:
  - start-here and concepts;
  - the nine UI guides;
  - the keyboard, dev-loop, and shipping guides;
  - the widget reference and showcases;
  - architecture and cross-site consistency.

  The Getting started and tutorial steps were compiled and run.
- **A fresh production build** (158 pages):
  - every internal link, anchor, and GitHub deep link, with the checker first shown to catch planted failures;
  - all 168 external URLs.
- **A browser sweep of all 157 pages** at 375px (light and dark) and at 1280px with `devicePixelRatio` 1 (light). It recorded:
  - console errors;
  - horizontal overflow;
  - each demo's rendered grid against its declared grid;
  - whether each Pad's editor mounts;
  - each demo's theme.
- **The live site after #284**, on the real origin: edit, Run, press, Hot reload (state kept), Revert.
  - Warm compiles took about 0.9 s for Run and 1.2 s for a reload.
  - One reload right after the release took 12 s.

## Fixed in this pass

- **#284 (merged):** every docs demo is editable and hot-reloadable on the live site.
- **#288:**
  - Demos show their exact grid at every pixel ratio; at ratio 1 the last row was lost.
  - 85 of 106 widget pages no longer scroll sideways on phones.
  - A showcase file name no longer overflows.
  - A Pad's run keeps its demo's theme.

## P0 — fix before launch

Each of these misleads a first-time reader, or leaves them stuck.

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | `getting-started.mdx:154`, `tutorial.mdx:131`, `guides/hot-reload.mdx:81`, `guides/debugging.mdx:124`; `create_command.dart:141` | **Hot restart (Ctrl+G, then F5) fails for the default setup.** VS Code's integrated terminal keeps F5, which starts a second copy under the debugger using the scaffold's `launch.json`. Mac laptops need Fn. The handler only exists under `fleury run` or a supervised `dart run`. `fleury create` itself says "Press F5". | Needs a decision (D1). Either change the chord or document the editor's own restart. |
| 2 | `docs/architecture-deep-dive.md:10, 80-83, 111-118, 160-165, 219-222, 302-311`; `docs/architecture-overview.md:27` | **The deep dive teaches the June damage model.** It says "damage-tracked CellBuffer", "presenters fall back to buffer diffs", and "Conservative damage is a feature", and contradicts itself at `:278-281`. The loop derives damage by comparing buffers (`tui_frame_loop.dart:92-115`). | Rewrite as "damage is derived, not reported". Edit `docs/`; the site copy is synced. |
| 3 | `guides/state-management.mdx:99-111` | **The `state.cart-notifier` "context.listen" tab is dead.** `CartDemo` builds only `CartView`, so edits to that tab never show on Run. | Render both readers over one cart, or make that tab read-only. |
| 4 | `gen-widget-pages.mjs:1097` → `showcases/files.mdx:15` | **Wrong "Try it" instruction.** "arrow through the tree — the preview swaps viewers" is false; the preview changes on Enter or click only (`Tree.onSelect`). | Fix the copy. |
| 5 | `coming-from-flutter.mdx:138-148, 240`, `concepts/app-entry.md:12, 19-25, 52-56` | **The Flutter mapping misleads the core audience.** | See the five problems listed below the table. |
| 6 | `docs/serving-and-embedding.md:3-7, 97, 187, 205-207`, `guides/deployment.md:129, 148-149`, `coming-from-flutter.mdx:132` | **Browser-parity claims are stale, mostly underselling:** | See the three claims below the table. |
| 7 | `docs/architecture-overview.md:30`, `docs/performance.md:17, 20, 39, 48-58`, `comparison.mdx:101`, `README.md:23` | **Performance claims are stale or overstated:** | See the three problems below the table. |
| 8 | `index.mdx:101`, `comparison.mdx:96, 103-108` | **Overclaims and an internal source:** | See the problems below the table. |
| 9 | `docs/agents-and-semantics.md:123-144` | **The "What an agent sees" JSON doesn't match the DataTable beside it.** The label is "Data table", not "People"; cells carry text plus a column id, not "typed cell values". | Paste real `semanticInspectionJson()` output. |
| 10 | `guides/input-and-gestures.mdx:91-108`, `guides/theming.mdx` (`hovered`) | **Hover in a terminal needs `TerminalMode(mouseMotion: true)`.** The scaffold sets only `mouse: true`, and the requirement appears last. | Note it in the hover section. |
| 11 | `guides/focus-and-keyboard.mdx`, `guides/debugging.mdx:113-114`, `showcases/sprite.mdx:15` | **The keys Fleury takes first are undocumented, and one claim is wrong:** | See the list below the table. Needs a decision (D2). |
| 12 | `guides/deployment.md` | **Three shipping blockers are missing:** | See the list below the table. |
| 13 | `linechart-lab.mdx` | **A maintainer page is public.** It is in the sitemap, and calls the 2px band the default; the default is 1px (`line_chart.dart:1247`). | Mark it draft or unpublish it (D4). |
| 14 | `/pad/` (`FleuryPad.astro`, `pad/client.ts`) | **The Pad page has no way back.** Once edited, nothing returns to the example; "Run the example" runs the saved draft. The `Widget buildApp()` rule is never stated, and there is no friendly busy message. | Add Reset to the example, a starter comment, and a busy state. |

**#5, the Flutter mapping.**

- `ListView` is listed as transferring unchanged. Fleury's `ListView` is a selection list with a three-argument builder and a required `itemCount`.
- The mouse is opt-in, and the page's own `main` gets no clicks in a terminal.
- The `bin/run_app.dart` snippet is not the generated file; pasting it drops `mouse: true`.
- `fleury serve` is offered as a way to deploy.
- `MyApp` means two different things across pages, so readers end up nesting `FleuryApp`.

**#6, browser parity.**

- Embeds are said to lack pixel images; they render them.
- Three pages say file and log widgets can't run in an embed; `fleury_widgets_web` exports them.
- Bridge mode is called a "shared session"; it serves one browser at a time (`bin/fleury.dart:851-861`).

**#7, performance.**

- Four pages say "paint is reused". Layout is incremental; paint re-walks from the root except at repaint boundaries.
- Markdown is said to re-parse the whole document on every append. It has been incremental since #272.
- The agent numbers are undated, and the gate is far looser than the quoted figures:

  | Metric | Quoted | Gate |
  |---|---|---|
  | Delta vs full re-read | ~0.3% | < 2% |
  | Id lookup vs tree walk | ~477× | ≥ 2× |

**#8, overclaims.**

- The "parity oracle… can't drift" and "cell for cell" wording describes what are regression tests.
- The comparison page quotes an internal planning doc (`peer-scorecards.md`, which says it is "not marketing copy"), with no date and internal SB labels.

**#11, keys Fleury takes first.**

- Ctrl+Z suspends natively (`posix_driver.dart:59`), so TextInput's Ctrl+Z undo and the sprite showcase's "Ctrl+Z to undo" suspend the app instead.
- Ctrl+G and F12 are consumed whenever debug tooling is on, not only while the panel is open.
- An unhandled Ctrl+C exits.

**#12, shipping blockers.**

- `runApp` refuses a non-TTY stdout, so a CLI in a pipe or CI fails.
- The debug panel is on in any non-AOT build (`debug_state.dart:52`), so apps installed with `pub global activate` ship Ctrl+G to end users.
- `serve`, `shell` and `fleury_mcp` use Unix sockets, so they run on macOS and Linux only.

## P1 — reference gaps and should-fix

### Widget reference (mostly generator and doc comments)

- **Parameter descriptions keep only their first paragraph.**
  - `_docText` (`website/examples/bin/api_extract.dart:465`) drops everything after it, for about 58 parameters.
  - Examples of lost rules: `ListView.itemKeyBuilder` (keys must be unique), `KeyBindings.modal`, `DataTable.onSort` (fires only for `sortable` columns), `TextInput.clipboardPolicy`.
- **Keyboard behaviour is missing or stale in class docs:**
  - KeyBindings: precedence, printable keys under a focused text field, `modal`.
  - Navigator: no Details at all, including Esc, focus trapping, `PopScope`, and the default fade.
  - TextInput: stale key list; Tab accepts a completion.
  - FileBrowser: a doubled sentence and no keys.
  - LogRegion: one line, with nothing on follow-tail.
  - TreeTable: internal caching prose.
  - DataTable: sort.
  - Nine list and viewer widgets say "navigate with the keyboard" without naming keys.
- **Button** points readers at the internal `FocusableControl`. **Focus** keeps a "footgun" design-history aside.
- **`validationError` "displayed by the underlying input"** is false for PasswordInput, Autocomplete and CompletionTextInput; only `FormField` draws messages.
- **Usage snippets and editable demos depend on hidden sample data:** MarkdownView, CodeView, DiffView, PatchReview, LogRegion, WorkflowSnapshot, TerminalOutputRegion, CalendarHeatmap.
- **Showcases:**
  - "Widgets used" misses `CommandPalette.open(` (regex at `gen-widget-pages.mjs:1143`).
  - The dashboard claims a "sortable" process table; it isn't sortable.
- **No pages** for FleuryApp, Theme, Scrollbar, SelectionArea, FocusScope or PopScope. The extractor only scans `src/widgets`.

### Guides

- **Layout:** the `colorScheme.surface` Container snippet paints nothing, because `surface` is null in the default themes. Use `Container.filled`.
- **Theming:** there is no reference of `ThemeData` fields and `ColorScheme` roles, subtree `Theme`, or extensions. The `fleury_themes` install step is missing.
- **Lists:**
  - There is no follow-tail coverage (`followTail`, `unseenCount`, `jumpToEnd`) and nothing on `itemKeyBuilder`.
  - The "controller options" link points at undocumented `ListController` members.
  - An external controller's disposal is unstated.
- **Navigation:**
  - The first editable demo hides the details screen and dialog code the steps exercise.
  - Guarded Back buttons need `Navigator.of(context).maybePop()`; `context.pop()` ignores `PopScope`.
- **Animation:**
  - `AnimatedVisibility` doesn't "reverse" asymmetric pairs.
  - The spring default is unstated.
  - `duration:` without `curve:` throws.
- **Commands and Testing:** both promise invoking a command by `CommandId` and never show `tester.invokeCommand`. There are no shortcut tests.
- **Hot reload and Debugging:**
  - "Works in any editor" doesn't hold: Windows has no save-to-reload, and IntelliJ consoles aren't TTYs, so `fleury shell` would be needed but is undocumented.
  - There is nothing on breakpoints.
  - F11 collides with host full-screen.
- **Terminal capabilities:**
  - There is no environment-variable reference (`FLEURY_WIDTH_PROBE`, `FLEURY_IMAGE_PROBE`, `FLEURY_EMOJI_WIDTH`, …).
  - `fleury diagnose` reports `0.0.0 - pre-release` (`bin/fleury.dart:1934`); the pubspecs say 0.1.0.
- **Shutdown:** the samples disable hot reload without saying why.
- **Driving with agents:**
  - There is no troubleshooting for `protocol_mismatch`, `app_exited`, `not_ready` or PATH.
  - It never says it runs on macOS and Linux only.
  - "HOST mcp add" is a placeholder.

### Site and repo

- **No GitHub link or edit links** in the docs chrome. Generated pages need `editUrl` overrides: architecture pages point at `docs/`; widget pages point at source or have none.
- **READMEs:**
  - The `fleury_widgets` README (its pub.dev page) doesn't link the docs, doesn't mention `fleury_widgets_web.dart`, and lists 35 of 106 widgets.
  - The `fleury` README links the GitHub copy of the hot-reload doc and keeps a pre-release migration note.
  - The `fleury_mcp` README has no docs link.
  - The GitHub repo's About description is empty.
- **The Pages deploy ships dart2js artifacts:** `.js.deps` files (109 KB, CI runner paths) and a 1.8 MB `.js.map`.

## P2 — polish

- **Naming drift:**
  - "debug shell" versus "debugger".
  - `Ctrl-X` versus `Ctrl+X`.
  - "Key handling" lives at `/guides/focus-and-keyboard/`. Rename the slug before launch links spread.
- **Wording:**
  - "every widget has a live demo": 20 of 106 don't.
  - The guides index says "every guide has live examples"; Deployment and Terminal capabilities have none.
  - The comparison page is dated "(July 2026)".
  - Implementer jargon on evaluator pages.
  - Mixed British and American spelling.
- **Visuals:**
  - Home LinkCards show double arrows.
  - The Showcases sidebar is in file-name order.
- **Editable code:**
  - `_…Tour` class names.
  - `// dart format width=60` pragmas.
  - The theming demo's `_noop` helper.
- **Demo sizes:** the guide pages declare different row counts from the registry for asteroids (30 vs 32) and commands (12 vs 13).
- **Grammar:** a garbled sentence on the inline showcase.

The full per-page notes, with every source citation, are in the five review reports. This list keeps the verified, user-visible items.

## Decisions for Dan

1. **Restart chord.**
   - Option A: keep Ctrl+G then F5 and document the editor-session caveat.
   - Option B: add a restart that isn't a function key, and have `fleury create` stop saying "Press F5". Possibly also write VS Code's `commandsToSkipShell` in the scaffold.
2. **Ctrl+Z policy** (launch audit 3.a).
   - Option A: keep suspend-by-default. Then native TextInput undo needs another chord, and the sprite showcase copy changes.
   - Option B: let undo win.
3. **Demo theme on the light site.** 105 pages pin demos dark; 4 follow the site.
   - Option A: keep dark "terminal windows".
   - Option B: follow the site everywhere.

   Pad runs now match whichever is chosen.
4. **LineChart lab.** Unpublish it, or turn it into a user-facing "choosing a marker" page linked from LineChart.
5. **Pad capacity for launch week.** The service is still named `fleury-pad-staging`. It has:
   - 1 instance and 8 concurrent requests;
   - a CA$20 cap;
   - no per-user rate limit.

   `/pad/` compiles on every visit.
6. **Debug tooling default for non-AOT distributions.** Should it stay on, or turn off outside the dev supervisor?

## Overlaps with publishing prep

- Flip the install docs.
- The comparison page says "distributed as a Git dependency today" (`comparison.mdx:228`).
- Fix the `fleury diagnose` version string.
- Update the package READMEs: docs links, the web import, and the pre-release notes.
