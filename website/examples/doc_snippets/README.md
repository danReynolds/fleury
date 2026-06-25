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
| `filterable_list.dart` | [Tutorial: a filterable list](../../src/content/docs/tutorial.md) |
| `core_widgets.dart` | Lists & scrolling, Loading data, Input & gestures, Theming (RichText) |
| `navigation_demo.dart` | [Navigation](../../src/content/docs/guides/navigation.md) |
| `semantic_actions.dart` | [Built for agents](../../../docs/agents-and-semantics.md) |

Keep each file a single, self-contained program (real imports, a `main`) so it
analyzes on its own. When you add or change documented code, add or update the
program here too.
