# Doc snippets

Compile-checked source behind the hand-written docs (tutorials and guides under
`website/src/content/docs/`).

The widget reference pages can't drift — they're generated from `registry.dart`,
which compiles. The prose docs are the risk: a code sample written by hand can
quietly reference an API that has since been renamed or removed. This directory
closes that gap.

## The convention

When a prose doc walks the reader through a non-trivial program, put the
**finished program** here as a real, complete `.dart` file and keep the prose in
sync with it. `test/doc_snippets_test.dart` runs `dart analyze` over this folder,
so every program is continuously checked against the live framework — if an API
changes underneath a doc, the build goes red instead of the docs going stale.

| Program | Backs |
|---|---|
| `app_shell.dart` | [App entry points](../../src/content/docs/concepts/app-entry.md), [Theming](../../src/content/docs/guides/theming.md) |
| `status_app.dart`, `status_app_terminal.dart`, `status_app_web.dart` | Shared tree plus native/browser entrypoints in [Getting started](../../src/content/docs/getting-started.mdx) |
| `web_app_shell.dart` | Browser entry snippets in [App entry points](../../src/content/docs/concepts/app-entry.md) and [Coming from Flutter](../../src/content/docs/coming-from-flutter.md) |
| `coming_from_flutter.dart` | [Coming from Flutter](../../src/content/docs/coming-from-flutter.md) |
| `filterable_list.dart` | [Tutorial: a filterable list](../../src/content/docs/tutorial.md) |
| `core_widgets.dart` | Lists & scrolling, Loading data, Input & gestures, Theming (RichText) |
| `navigation_demo.dart` | [Navigation](../../src/content/docs/guides/navigation.md) |
| `forms.dart` | [Forms & validation](../../src/content/docs/guides/forms.md) |
| `shared_state.dart` | [State management](../../src/content/docs/guides/state-management.md) |
| `semantic_actions.dart` | [Built for agents](../../../docs/agents-and-semantics.md) |

Keep each entrypoint a complete program with real imports and a `main`; shared
libraries should be imported by every target-specific entrypoint they support.
When you add or change documented code, add or update the matching source here
too.
