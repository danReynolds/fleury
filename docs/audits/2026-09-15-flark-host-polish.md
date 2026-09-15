# Flark host follow-up, September 15

Based on Fleury main `f52b0007`. Isolated from the older local launch-audit
checkout; unrelated changes there were not included.

- Default TextInput/TextArea keymaps support Ctrl/Cmd+A and Command copy/cut/
  undo/redo. Explicit Emacs Ctrl+A still wins. Selection completes an accepted
  scheduled paste before reading its extent, using the current TextPasteDriver.
- ColorPicker exposes optional row spacing and optional focused help. Defaults
  preserve existing layouts. Keyboard and pointer selection follow painted rows.
- Pinned wide DOM runs fill the same cell box as styled/caret runs, preventing
  baseline shifts next to wide characters. Regenerated the embedded client.
- Export CaretHost and make FocusNode's attach/detach contract available to
  custom editors. Flark supplies local caret geometry; Fleury derives screen
  placement and clipping. Identity-checked detach preserves a replacement host.

Local review and checks on macOS ARM64, Dart 3.12.2:

- Core unit suite: 3,529 passed, one skipped. Input subset: 139 passed.
- Public caret contract: one new test passed.
- ColorPicker: 16 tests passed.
- Web VM/Chrome suite: 536 passed, including measured DOM baseline regression.
- Fast performance gates passed; live serve wire gate passed.
- Changed core-file and web-package analysis clean. The full `check` stopped
  at 14 pre-existing info-level lints in unchanged core/test files. This is not
  a claim that the repository-wide check is green.
- Flark's migrated host: 63 tests, playground: five tests passed against this
  checkout. Current input details, derived paint geometry, and CaretHost APIs
  required host migration; no private Fleury imports were added.

CI intentionally skipped at the user's request. This does not qualify physical
IME, terminal protocols, screen readers or sustained Flark frame latency.
