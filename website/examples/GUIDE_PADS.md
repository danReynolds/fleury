# Editable docs demos

Every docs demo that shows its code is editable in place. `GuidePad` displays a
prebuilt, live Fleury example beside the code that produced it. The shared
Monaco editor replaces the static code as the demo approaches the viewport,
without an activation step. **Run** (or ⌘/Ctrl+S) compiles the reader's edit
with Fleury Pad and starts it in an isolated frame; later edits **Hot reload**,
keeping that app's state. **Revert** restores the example's code and its
prebuilt preview.

Merely reading makes no compiler requests. The preview stays the prebuilt
example until the reader runs code, and language services start after an edit
or an explicit editor action; hovering over untouched code makes no requests.
Test code shown beside a demo stays a read-only reference to the original
example.

## One source for the preview and editor

The Dart registry and the example files it imports are canonical. A project is
built from the code its preview actually runs: the registry entry's builder
and the local libraries it reaches, preserving their separate libraries and
private names. `bin/guide_projects.dart` emits `../src/guide_projects.json`. Do
not edit that generated file.

Each generated project contains `main.dart`, its backing files, and named views.
A view is the code a reader edits:

- `region` selects a `#docregion`, the markers `SourceExcerpt` reads. A region
  whose blocks sit around other code spans them, skipping blocks that hold only
  imports; `block` picks one of its blocks instead.
- `declaration` selects a top-level declaration. `member` narrows a class to a
  method; `expression` selects a constructor or method invocation within it
  (`occurrence` defaults to zero). `through` instead extends the view to the
  end of a later top-level declaration, for declarations that read together,
  such as an app's command IDs and its root widget.
- A view with neither selects the whole file.

A file with a region or whole-file view keeps its comments, minus the marker
lines and any `// dart format width=` pragma, which only keeps the source
narrow in the repository. Other files are trimmed to the declarations the demo
needs. Views must not overlap. A region that should show the imports its code
relies on, such as prefixed ones, keeps them in the same block as that code.
The component renders their exact ranges as its initial code; there is no
separately maintained copy of a snippet.

The shared `SourceProject` applies edits to the original ranges and maps
completion offsets and diagnostics back to the visible code. Multiple views
can edit different regions in one file. Files remain real Dart libraries; they
are never concatenated. Compiler errors in hidden setup are shown with the
backing filename. Each demo has its own revision-bound local draft.

The registry's docs-only `_framed(...)` helper belongs in a builder, never in a
demo's own `build`, so the code a reader edits reads as app code. A builder
should only create the demo widget, `_framed(const _Demo())`, so its
`example()` hides nothing.

## Guide and reference demos

`guide_projects.json` lists each guide demo's views, keyed by example id.
Widget reference pages usually need no entry: a registry example in a widget
category edits its demo widget, that widget's State class, or else the
builder's expression. Keep the data and helpers a demo uses inside that view.
When the demo genuinely spans declarations, such as a `Toaster` host and the
widget below it that raises toasts, list a view for each here instead of
hiding one. Props-playground pages (`FleuryKnobs`) keep their knobs.

Every demo's views must show the code it runs. The generator fails when a
view refers to a declaration none of the views shows, when a view of part of a
class uses one of the class's members that no view shows, when the builder
does more than create the demo widget and no view shows it, or when no view
shows the widget the builder creates. A State class's view stands for its
widget. `hiddenByDesign` in `bin/guide_projects.dart` lists the few
deliberate exceptions, such as the input guide's excerpts, whose pages show
the whole file read-only; each entry says why, and an entry that no longer
matches anything fails too.

## Adding an example

1. Register the runnable widget. Keep code a guide shows in a web-safe library
   under `lib/`, with `#docregion` markers around what readers edit.
2. For a guide demo, add its views to `guide_projects.json`.
3. Use `<GuidePad id="example.id">` with the example's `FleuryExample` in its
   `demo` slot. Put read-only code, such as tests, in the `references` slot and
   name it with `referencesLabel`; `referencesOpen` shows it expanded. `mark`
   highlights lines of a single-view demo, and `compact` stacks the demo above
   its code for a narrow column.
4. Run `npm run guides:projects`, then `npm run check:docs` from `website/`.
5. Compile the whole catalogue with `python3 scripts/check-guide-projects.py`
   and `FLEURY_PAD_URL` set to a loopback compiler or authenticated local
   proxy. Then exercise Run, edit, reload, and error recovery in the docs.

The compiler accepts at most 24 Dart files / 64 KB total source. Relative
imports must resolve to supplied files. Parts, server filesystem access,
remote imports, and user-controlled compiler flags remain unavailable.
Examples run in Pad's sandboxed iframe, whose CSP allows network requests only
to `picsum.photos`, the image service the loading-data guide uses. Use bundled
data for other network demonstrations, or extend the frame policy in
`experiments/fleury_pad/dartpad/bin/server.dart` deliberately.

The frame reproduces the prebuilt preview. Its URL fragment carries the page's
theme and the example's grid; the frame measures cells in the docs font and
sizes the app to the same columns and rows.
