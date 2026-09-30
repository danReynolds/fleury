---
title: Terminal capabilities
description: Diagnose a terminal session, understand Fleury’s fallbacks, and fix differences in color, text, images, and input.
---

Fleury adapts its output to the terminal: colors can be reduced, images become
cell art, and links stop being clickable. When an app behaves
differently over SSH or inside tmux, inspect the session before changing the
widget code.

## Inspect the affected session

With the [Fleury CLI installed](/fleury/getting-started/#1-install-the-cli-and-create-a-project), run
this in the same terminal, SSH connection, and multiplexer pane as the app:

```sh
fleury diagnose
```

The report is Markdown, ready to paste into an issue. It includes the
environment, selected capabilities, and the reasons for fallbacks. For example,
a supported outer terminal can still produce these rows inside tmux:

```md title="Excerpt: a tmux session"
| Image protocol | halfBlock |
| OSC 8 hyperlinks | suppressed-under-tmux |

## Fallbacks
| | |
|---|---|
| image_multiplexer_fallback | info: Native images are disabled in this multiplexer session; images use cell art. |
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
| Links aren't clickable | OSC 8 hyperlinks | Check whether links are unsupported, suppressed, or explicitly disabled. |
| Clicks or held keys do nothing | App mouse mode; **Live → Keyboard** in the debug shell | Check enabled input modes and negotiated key events, not only terminal support. Multiplexers limit key events by default. |
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

Markdown links become clickable terminal hyperlinks when the terminal supports
them; otherwise the label stays underlined without a link. Either way,
`MarkdownText` shows the destination after the label as a dim `(url)` by
default, so a visible URL does not mean hyperlinks failed. Set
`inlineLinkUrls: false` to hide it for links that are clickable; a link that
isn't keeps its URL. The browser surface renders ordinary anchors.

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

Held keys require release events. Open the [debug shell](/fleury/guides/debugging/)
and inspect **Live → Keyboard** for the app's negotiated capabilities. A
successful standalone keyboard probe is not evidence that this running session
receives releases. Inside tmux, GNU Screen, or Zellij, Fleury requests a reduced
keyboard protocol by default, because a multiplexer may not pass the full one
through reliably: chords, arrows, and function keys are enhanced, but letters
arrive as plain text, so there is no held-key state. Held controls then use
their press-driven fallback.
[Key handling](/fleury/guides/focus-and-keyboard/) covers capability-aware
input.

To diagnose keyboard input, choose the protocol level explicitly:

```sh
FLEURY_KEYBOARD=legacy dart run bin/run_app.dart         # classic input only
FLEURY_KEYBOARD=disambiguated dart run bin/run_app.dart  # enhanced chords and arrows; no held keys
FLEURY_KEYBOARD=lifecycle dart run bin/run_app.dart      # every key, with repeats and releases
```

Use `lifecycle` inside a multiplexer only after verifying that the whole path
delivers releases. If a terminal misbehaves when Fleury queries its keyboard
support, `FLEURY_KEYBOARD_PROBE=0` skips the query and uses classic input.

For clipboard issues, run this from an app callback and inspect the result
in the debug shell’s **Logs** tab:

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

## Environment variables

Set these in the environment the app runs in, for example
`FLEURY_GLYPH_TIER=ascii dart run bin/run_app.dart`. The terminal and input
variables apply to native terminal sessions.

| Variable | Set it to | Effect |
| --- | --- | --- |
| `FLEURY_COLOR_DEPTH` | `none`, `16`, `256`, or `truecolor` | Render at this color depth instead of the detected one. A non-empty `NO_COLOR` still wins. |
| `FLEURY_GLYPH_TIER` | `ascii` or `unicode` | Force ASCII or Unicode drawing characters. `FLEURY_ASCII=1` also selects ASCII. |
| `FLEURY_HYPERLINKS` | `0` or `1` | Turn OSC 8 hyperlinks off, or force them on, even in a multiplexer. |
| `FLEURY_SYNC_OUTPUT` | `0` or `1` | Turn synchronized output off or on instead of following the terminal's reply. |
| `FLEURY_IMAGE_PROBE` | `0` | Skip the startup query for native image support when the environment doesn't name a protocol; images then use cell art. |
| `FLEURY_AMBIGUOUS_WIDTH` | `narrow` or `wide` | Width of East Asian ambiguous-width characters. |
| `FLEURY_EMOJI_WIDTH` | `narrow` or `wide` | Width of characters that display as emoji by default. |
| `FLEURY_VS16_WIDTH` | `narrow` or `wide` | Width of a character followed by the emoji variation selector (U+FE0F). |
| `FLEURY_CLUSTER_MODE` | `joined` or `split` | Keep an emoji ZWJ sequence, such as a family emoji, as one cluster, or draw it as its separate emoji. |
| `FLEURY_WIDTH_PROBE` | `0` | Skip the startup width measurement. The defaults apply, except where the four variables above override them. |
| `FLEURY_KEYBOARD` | `legacy`, `disambiguated`, or `lifecycle` | Request this keyboard protocol level (see [input](#check-input-and-clipboard-behavior)). |
| `FLEURY_KEYBOARD_PROBE` | `0` | Skip the keyboard query and use classic input. |
| `FLEURY_KEYPAD_DECIMAL` | A character | What the keypad's decimal key types when the terminal doesn't say. Defaults to `.`. |
| `FLEURY_FD_CAPTURE` | `0` | Stop capturing stray output; prints and native output go straight to the terminal. |
| `FLEURY_ANSI_CAPTURE` | A file path | Copy every byte the app writes to the terminal into that file. |
| `FLEURY_BYTE_TELEMETRY` | `1` | On exit, print the bytes written per frame, by kind, with estimated frame times for local, SSH, and slow links. |
| `FLEURY_HOT_RELOAD` | `0` | Turn off Fleury's own save-to-reload and hot restart ([Hot reload](/fleury/guides/hot-reload/#opting-out)). |
| `FLEURY_DEV_BOOTSTRAP_LOG` | A file path | Log what the hot-reload supervisor watches, sees, and reloads. |
| `FLEURY_UPDATE_GOLDENS` | `1` | Make `matchesGolden` in tests write golden files instead of comparing against them. |

Other `FLEURY_` variables are internal: Fleury's tools set them for the
processes they start, or framework tests and benchmarks use them. The exception
is `FLEURY_HANDLE`, which `fleury shell` and bridge-mode `fleury serve` print so
that an app started from another directory can find them.
