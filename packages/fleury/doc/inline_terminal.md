# Inline terminal commands

The [Full-screen and inline UIs guide](https://danreynolds.github.io/fleury/guides/terminal-modes/)
is the user-facing reference for choosing a mode, sizing an inline region,
returning results, subprocess handoff, and current platform limits.
Its [source](../../../website/src/content/docs/guides/terminal-modes.mdx) lives
beside the other guides; edit it there so the site and package guidance agree.

From the repository root, compare the same form in both native modes:

```sh
dart run packages/samples/bin/samples.dart inline
dart run packages/samples/bin/samples.dart inline --full-screen
```

For the smallest entrypoint, see [inline_picker.dart](../example/inline_picker.dart).

The implementation treats inline as an owned viewport, with an origin, bounded
painting and clearing, and translated pointer/caret coordinates. Disabling the
alternate screen alone does not establish those bounds. The
[PTY checks](../../../tool/check_inline_tui.py) exercise region resizing,
handoff, suspend/resume, and development-session cleanup against terminal state.
