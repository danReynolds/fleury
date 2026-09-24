# Inline terminal commands

Use an inline viewport for a short picker, setup form, or other command that
belongs in the shell's normal flow. Full-screen applications keep the default
`TerminalMode.interactive`.

```dart
await runApp(
  FleuryApp(title: 'Choose a source', home: SourcePicker()),
  mode: const TerminalMode.inline(rows: 14, mouse: true),
  enableHotReload: false,
);
print('Source selected.');
```

Fleury reserves full-width rows beneath the current cursor, keeping earlier
output in the main buffer and scrollback. `rows` must be positive and is
clamped to the terminal height. Widgets see that smaller size through
`MediaQuery`; use ordinary `Expanded`, `ScrollView`, focus, and input widgets.
Exit clears the live region and parks the cursor at its start, ready for the
command's result. A partial line before entry is preserved.

Try `dart run example/inline_picker.dart` in `packages/fleury`.

## Changing height

From an interaction or lifecycle callback, request another height through
the session already installed by `runApp`:

```dart
final session = TerminalSession.of(context);
if (session.isInline) {
  await session.resizeInline(20);
}
```

The host erases the previous allocation, reserves the new one, and schedules
a full repaint. Requests made during suspend or subprocess handoff apply when
the app gets the terminal back. Full-screen and remote sessions reject this
operation; a browser embed controls its size through its containing element.

## Subprocesses and output

Use `TerminalSession.of(context).runWithHandoff(...)` for an editor, pager, or
any subprocess that inherits terminal input/output. Fleury clears its region,
restores terminal modes, then reserves a fresh region after the child exits.
The child's output remains above the resumed UI. Ctrl+Z follows the same
release/reacquire lifecycle.

The existing stray-output capture remains active: `print` and native output
are captured while the UI owns the terminal and replayed after exit. They do
not insert permanent lines above a running inline UI. Print a command summary
after awaiting `runApp`.

Development reload and restart work in inline mode. The supervisor records
the child's allocation and terminal modes for crash cleanup. Its VM-service
startup message may remain visible above the region. CLI commands that must
run their effectful startup only once can set `enableHotReload: false`.

## Support and limits

- Native macOS and Linux in a modern xterm-compatible terminal with cursor
  reporting. Without a cursor report, entry restores modes and fails instead
  of painting at a guessed origin. Piped input/output is not supported.
- Inline mouse input is opt-in, as in full-screen mode. Mouse capture affects
  terminal selection globally while enabled; earlier output remains available
  in scrollback.
- Height is explicit. Natural content height, inserting logs above the region,
  retaining the final frame, and native image protocols are not implemented.
  Images use glyph rendering. Windows inline mode is rejected before entry.
- Resize re-anchors from the reported cursor and the presenter's last local
  caret. Automated macOS/Linux PTY tests cover width/height changes, but terminal
  emulators differ in reflow behavior. If cleanup finds unprocessed geometry
  changes, it leaves uncertain rows alone instead of erasing shell content.

`TerminalMode(alternateScreen: false)` is still a low-level mode override; it
does **not** provide an inline viewport. Use `TerminalMode.inline(rows: ...)`.
