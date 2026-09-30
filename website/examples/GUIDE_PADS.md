# Editable guide demos

`GuidePad` displays a real Fleury example with editable code. The shared Monaco
editor loads as the example approaches the viewport, without an activation step.
**Run** starts an isolated, compiled app;
subsequent **Hot reload** operations preserve that app's state. Merely reading
a guide makes no compiler requests. Language services start after an edit or
an explicit editor action; hovering over untouched code makes no requests.
Test examples remain references to the original example.

## One source for the preview and editor

The Dart registry and its imported example files are canonical.
`guide_projects.json` selects which declarations, methods, or constructor
expressions the reader edits. `bin/guide_projects.dart` collects the local
Dart dependencies, preserving their separate libraries and private names, and
emits `../src/guide_projects.json`. Do not edit that generated file.

Each generated project contains `main.dart`, its backing files, and named views.
A view selects an exact AST range in a file. A full-file view omits
`declaration`. `member` narrows a class to a method; `expression` selects a
constructor or method invocation within it (`occurrence` defaults to zero).
Selections must not overlap. The component renders those exact ranges as its
initial code; there is no separately maintained Markdown copy of the snippet.

The shared `SourceProject` applies edits to the original ranges and maps
completion offsets and diagnostics back to the visible code. Multiple views
can edit different regions in one file. Files remain real Dart libraries; they
are never concatenated. Compiler errors in hidden setup are shown with the
backing filename. Each demo has its own revision-bound local draft.

## Adding an example

1. Register the runnable widget and add its entry to `guide_projects.json`.
2. Use `<GuidePad id="example.id">` with the corresponding `FleuryExample` in
   its `demo` slot. Put optional test code in `references`.
3. Run `npm run guides:projects`, then `npm run check:docs` from `website/`.
4. Exercise Run, edit, reload, and error recovery against the local compiler.
   To compile the whole catalogue, run `python3 scripts/check-guide-projects.py`
   with `FLEURY_PAD_URL` set to a loopback compiler or authenticated local proxy.

The compiler accepts at most 24 Dart files / 64 KB total source. Relative
imports must resolve to supplied files. Parts, server filesystem access,
remote imports, and user-controlled compiler flags remain unavailable.
Examples run in Pad's sandboxed iframe, whose CSP allows network requests
only to `picsum.photos`, the image service the loading-data guide uses. Use
bundled data for other network demonstrations, or extend the frame policy in
`experiments/fleury_pad/dartpad/bin/server.dart` deliberately.
