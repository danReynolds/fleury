# Native mouse pointers

Fleury's native POSIX host uses the same `MouseRegion.cursor` hints as browser
apps. Buttons and other `FocusableControl`s request a hand pointer, text inputs
request the text cursor, and disabled controls request the ordinary cursor.
Custom clickable widgets can use:

```dart
MouseRegion(
  cursor: enabled ? MouseCursor.pointer : MouseCursor.basic,
  child: yourControl,
)
```

Start a native app with `TerminalMode(mouseMotion: true)` to receive hover
reports. No application escape sequences or host-name checks are needed.

The POSIX driver batches an [OSC 22 capability query](https://sw.kovidgoyal.net/kitty/pointer-shapes/)
into its existing bounded startup negotiation. It requires an affirmative reply
for every supported Fleury shape before enabling output. Unsupported terminals,
non-interactive streams, sessions without mouse motion, multiplexers, and the
currently queryless Windows driver retain their existing pointer appearance.
No terminal compatibility is inferred from an executable name.

The pointer router resolves the frontmost live region using existing hit-test
geometry and clipping, then searches its ancestors for an explicit hint. It
reconciles stationary hover after layout, restores the ordinary cursor on
focus loss, leave, resize and failed frames, and emits only changes. Cursor
hints do not add focus or click behavior. A foreground gesture boundary blocks
unrelated hints behind it. Widgets that draw custom controls should annotate
their existing region, including a basic cursor when disabled.

The native driver pushes one shape after successful negotiation and pops it
before surrendering the screen. Handoff, controlled suspension, resume and
idempotent restoration keep those pushes and pops balanced on the same screen.
Only enum-owned protocol names reach output; query replies go through the
existing bounded parser and late-reply quarantine.

Validation covers query parsing, fragmented and late replies, runtime output
with and without support, control state and removal, foreground overlap,
focus loss, and driver suspend/handoff/restore on both terminal screens.
Browser pointer regression tests cover existing DOM cursor behavior. These
checks do not establish support in every terminal emulator.
