# Doc snippets

Compile-checked source behind the hand-written docs (tutorials and guides under
`website/src/content/docs/`).

The widget reference pages are generated, but most of their code samples are
hand-written strings, so `npm run check:snippets` (part of the docs build)
compiles every Dart block on them against the real packages. The prose docs are
the other risk: a code sample written by hand can quietly reference an API that
has since been renamed or removed. This directory closes that gap.

## The convention

When a prose doc walks the reader through a non-trivial program, put the
**finished program** here as a real, complete `.dart` file and keep the prose in
sync with it. `test/doc_snippets_test.dart` runs `dart analyze` over this folder,
so every program is continuously checked against the live framework — if an API
changes underneath a doc, the build goes red instead of the docs going stale.

| Program | Backs |
|---|---|
| `app_shell.dart` | [App entry points](../../src/content/docs/concepts/app-entry.md), [Theming](../../src/content/docs/guides/theming.mdx) |
| `terminal_modes/` and `terminal_modes.dart` | [Full-screen and inline UIs](../../src/content/docs/guides/terminal-modes.mdx); runnable mode choices, native resizing, repeated sessions, and subprocess handoff |
| `getting_started_app.dart`, `status_app_terminal.dart`, `status_app_web.dart` | The finished web-safe `lib/app.dart` and its native and browser entrypoints in [Getting started](../../src/content/docs/getting-started.mdx) and [App entry points](../../src/content/docs/concepts/app-entry.md) |
| `web_app_shell.dart` | The `web/main.dart` that [App entry points](../../src/content/docs/concepts/app-entry.md), [Coming from Flutter](../../src/content/docs/coming-from-flutter.mdx) and the `fleury_web` README show verbatim |
| `coming_from_flutter.dart`, `flutter_counter_main.dart`, `../lib/flutter_map.dart` | [Coming from Flutter](../../src/content/docs/coming-from-flutter.mdx); the page shows `#docregion` excerpts of `flutter_map.dart`, whose widgets the live demos run, and `coming_from_flutter.dart` checks its remaining hand-written fences |
| `filterable_list.dart` | [Tutorial: a filterable list](../../src/content/docs/tutorial.mdx); its `app` region renders as the tutorial's finished file |
| `keyboard_tour.dart` | [Key handling](../../src/content/docs/guides/key-handling.mdx) |
| `focus_tour.dart` | [Focus management](../../src/content/docs/guides/focus.mdx) |
| `core_widgets.dart` | Loading data, Input & gestures, Theming (RichText) |
| `navigation_demo.dart`, `navigation_advanced_demos.dart` | [Navigation](../../src/content/docs/guides/navigation.mdx)'s hand-written fences; its live demos and editable code come from `../lib/registry.dart` |
| `theming.dart` | [Theming](../../src/content/docs/guides/theming.mdx)'s hand-written fences |
| `../lib/lists/`, `../test/lists_guide_test.dart` | [Lists & scrolling](../../src/content/docs/guides/lists-and-scrolling.mdx); source and tests are paired with each live demo |
| `layout_demo.dart` | [Layout](../../src/content/docs/guides/layout.mdx)'s hand-written fences |
| `shared_state.dart`, `../lib/state_management_guide.dart` | [State management](../../src/content/docs/guides/state-management.mdx); the guide shows `#docregion` excerpts and the live demos render the same widgets |
| `loading_data.dart`, `../lib/loading_data_guide.dart` | [Loading data](../../src/content/docs/guides/loading-data.mdx); the guide shows `#docregion` excerpts and the live demos render the same widgets |
| `animation.dart` | [Animation](../../src/content/docs/guides/animation.mdx)'s hand-written fences; its live demos and editable code come from `../lib/registry.dart` |
| `testing.dart`, `../lib/testing/`, `../test/testing/`, `../test/testing_guide_test.dart` | [Testing](../../src/content/docs/guides/testing.mdx); the guide shows each library under `lib/testing/` and each test under `test/testing/` whole, and `testing_guide_test.dart` runs them all |
| `semantic_actions.dart` | [Built for agents](../../../docs/agents-and-semantics.md) |

Keep each entrypoint a complete program with real imports and a `main`; shared
libraries should be imported by every target-specific entrypoint they support.
When you add or change documented code, add or update the matching source here
too.

Prefer showing the compiled code itself over a hand-copied fence. Mark the
part a guide shows with `// #docregion <name>` and `// #enddocregion <name>`,
then render it with `<SourceExcerpt code={source} region="<name>" />`
(`website/src/components/SourceExcerpt.astro`), importing the file with
`?raw`. The page build fails if the region is missing, and the excerpt can't
drift from the program `doc_snippets_test.dart` analyzes. Hand-copied fences
are checked by nothing but review; that is how the Animation guide came to
show a `700.ms` duration extension that doesn't exist.
