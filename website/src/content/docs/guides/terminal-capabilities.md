---
title: Terminal capabilities
description: Diagnose a terminal session, understand Fleury’s fallbacks, and fix differences in color, text, images, and input.
---

Fleury adapts its output to the terminal: colors can be reduced, images become
cell art, and links can fall back to visible URLs. When an app behaves
differently over SSH or inside tmux, inspect the session before changing the
widget code.

## Inspect the affected session

With the [Fleury CLI installed](/fleury/getting-started/#1-create-a-project), run
this in the same terminal, SSH connection, and multiplexer pane as the app:

```sh
fleury diagnose
```

The report includes the environment, selected capabilities, and the reasons
for fallbacks. For example, a supported outer terminal can still produce these
rows inside tmux:

```text title="Example: tmux fallback"
Image protocol    halfBlock
OSC 8 hyperlinks  suppressed-under-tmux

image_multiplexer_fallback
  Native images are disabled in this multiplexer session; images use cell art.
```

Here the renderer is deliberately choosing a fallback. Run the same app outside
the multiplexer to isolate that difference; changing its image widget would
not address the cause.

To ask the terminal for additional evidence, run:

```sh
fleury diagnose --probe
```

Probes are bounded queries, including keyboard and graphics support and glyph
width measurements. A timeout is **inconclusive**, not proof that a feature is
unsupported. Over a slow connection, increase the per-query budget with
`--probe-timeout=500`.

The report distinguishes detected support from runtime behavior. In particular,
**Mouse: availableOptIn** does not mean mouse reporting is enabled, and
**OSC 52 clipboard: policyGated** does not prove that copying reached the system
clipboard.

## Match the symptom to the evidence

| Symptom | Check | What to do next |
| --- | --- | --- |
| Colors are missing or reduced | Color mode, `NO_COLOR`, `COLORTERM`, `TERM` | Check the environment and compare color depths below. |
| Borders or emoji misalign | Glyph tier, measured widths, width policy | Probe in the affected session; inspect which width values came from a probe or an override. |
| Images turn into blocks | Image protocol and fallback reason | Compare a direct terminal session with the multiplexer session. |
| Links show their URL as text | OSC 8 hyperlinks | Check whether links are unsupported, suppressed, or explicitly disabled. |
| Clicks or held keys do nothing | App mouse mode; **Live → Keyboard** in the debugger | Check enabled input modes and negotiated key events, not only terminal support. |
| Copy works only inside the app | Clipboard write report | Check the transport and policy used for that operation. |
| Frames flicker or appear partially drawn | Synchronized output | Check whether the terminal confirmed support below. |

## Check color and text rendering

Fleury maps colors to the detected depth. A non-empty `NO_COLOR` disables color,
even when another setting requests it. Otherwise an explicit depth wins over
environment detection. Use it to reproduce a reduced palette locally:

```sh
FLEURY_COLOR_DEPTH=16 dart run bin/run_app.dart
FLEURY_COLOR_DEPTH=256 dart run bin/run_app.dart
```

The other accepted depths are `truecolor` and `none`. Choose colors in the
[theme](/fleury/guides/theming/); use an override to test a terminal constraint
or correct a known detection error.

Text width is separate from color depth. A non-UTF-8 locale or a basic terminal
can select ASCII drawing characters. Check `LC_ALL`, `LC_CTYPE`, and `LANG` in
that order; the first configured locale wins. To test the ASCII fallback:

```sh
FLEURY_GLYPH_TIER=ascii dart run bin/run_app.dart
```

If Unicode is enabled but columns drift, inspect the probe's **Width policy**.
Fleury records both the width and its source for ambiguous characters, emoji,
and composed sequences. Prefer measured values; use an override such as
`FLEURY_AMBIGUOUS_WIDTH=wide` only when you know the terminal uses that width.
A missing measurement leaves the default in place.

## Terminal images through multiplexers

The image widget selects native Kitty or iTerm2 output where supported, with
cell art as the portable fallback. tmux, GNU Screen, and Zellij select cell art
even when the outer terminal supports native images: a query response alone
does not establish reliable image redraw and resize behavior through that path.

Test both paths if images carry information in your app. The Windows driver and
native Sixel rendering remain preview capabilities; the supported baseline is
a modern UTF-8, xterm-compatible POSIX terminal.

## Terminal hyperlinks (OSC 8)

Markdown links use clickable terminal hyperlinks when detected. Otherwise the
label stays underlined and the URL is shown inline. The browser surface renders
ordinary anchors.

The diagnosis reports **supported**, **unsupported**, **suppressed-under-tmux**,
or **disabled-by-override**. Multiplexers are suppressed by default. Supported
terminal detection includes kitty, WezTerm, Ghostty, iTerm2 3.1+, VTE 0.50+, and
Windows Terminal.

To compare the fallback in the same app:

```sh
FLEURY_HYPERLINKS=0 dart run bin/run_app.dart
```

Setting it to `1` forces hyperlink output, including through a multiplexer.
Use that only after verifying that the whole terminal path handles OSC 8;
the override requests output rather than proving delivery.

## Check input and clipboard behavior

Mouse reporting is an app setting. Enable clicks, dragging, and scrolling with
`TerminalMode(mouse: true)`; use `mouseMotion: true` when the app also needs
hover. See [Input & gestures](/fleury/guides/input-and-gestures/) for the widget
side.

Held keys require release events. Open the [debugger](/fleury/guides/debugging/)
and inspect **Live → Keyboard** for the app's negotiated capabilities. A
successful standalone keyboard probe is not evidence that this running session
receives releases. [Key handling](/fleury/guides/focus-and-keyboard/) covers
capability-aware input.

For clipboard issues, run this from an app callback and inspect the result
in the debugger’s **Logs** tab:

```dart
final report = await ClipboardScope.of(context)
    .writeWithReport('Clipboard check');
print(report.toJson());
```

A successful platform-tool write, an emitted OSC 52 escape, and an in-process
copy are different outcomes. OSC 52 emission is unverified until you paste into
another application; over SSH, local platform tools are skipped by default.

## Synchronized output

For flicker or partially drawn frames, check synchronized output in the diagnosis.
Fleury brackets frames with synchronized output only when the terminal query
confirms mutable DEC mode 2026 support. Otherwise it sends ordinary ANSI frames.
For a terminal with a known incorrect report, `FLEURY_SYNC_OUTPUT=1` or `0`
overrides that decision. This affects frame presentation, not build or layout
cost; investigate slow frames in [Debugging](/fleury/guides/debugging/).

## Save evidence without changing the session

```sh
fleury diagnose --probe --json-output=terminal-report.json
```

Use the file option instead of redirecting stdout: redirecting makes stdout
non-interactive and prevents active probes. Include the report, the failing
interaction, and whether it also fails outside SSH or the multiplexer when
reporting a terminal-specific issue.
