---
title: Terminal capabilities
description: How Fleury detects what a terminal can do — native images, clickable hyperlinks — and degrades safely when it can't.
---

Terminals differ in what they can actually render — native image protocols,
clickable hyperlinks, color depth — and multiplexers like tmux sit in the
middle rewriting escapes. Fleury's policy is the same everywhere: **detect the
capability from the environment, use the richest safe form, and degrade to a
form that never lies** (cell art instead of a dropped image, a visible URL
instead of a dead link). This page covers the two capabilities with real
divergence in the wild; `fleury diagnose` and the debug shell's **Tree** tab
report exactly what was detected in your session.

## Terminal images through multiplexers

`Image` uses native Kitty, iTerm2, or Sixel graphics in a directly supported
terminal and falls back to cell art everywhere else. Fleury defaults to cell
art inside tmux, GNU Screen, and Zellij because multiplexers can drop or
transform native-image escapes and cannot safely model every protocol's raster
lifecycle across redraws and resizes.

Fleury currently keeps Kitty, iTerm2, and Sixel on cell art through those
multiplexers. Direct sessions still use their native image protocol. `fleury
diagnose` reports `image_multiplexer_fallback` when this policy suppresses a
detected native protocol.

## Terminal hyperlinks (OSC 8)

Widgets like `MarkdownText` emit **real clickable links** (the OSC 8 escape) on
terminals that support them, and fall back to plain underlined text with the
URL shown inline everywhere else — so a destination is never hidden behind a
link that doesn't work. The browser surface (`fleury serve`) always renders
links as anchors; on the terminal, support is **detected from the environment**.

**Detected terminals** (auto-enabled, default-deny for anything unlisted):

| Terminal | Detected via |
| --- | --- |
| iTerm2 (≥ 3.1) | `TERM_PROGRAM=iTerm.app` + `TERM_PROGRAM_VERSION` |
| WezTerm, Ghostty | `TERM_PROGRAM` |
| GNOME Terminal / VTE (≥ 0.50) | `VTE_VERSION ≥ 5000` |
| kitty | `KITTY_WINDOW_ID` or `TERM=xterm-kitty` |
| Windows Terminal | `WT_SESSION` |

**tmux (and other multiplexers) are suppressed by default.** OSC 8 through a
multiplexer needs an explicit `terminal-features` opt-in in your tmux config and
is unreliable without it, so detection reports links as unavailable under tmux
regardless of the outer terminal. Escape tmux, or force it with
`FLEURY_HYPERLINKS=1`.

**Override.** `FLEURY_HYPERLINKS` wins outright over detection: `1`/`true`/`yes`/
`on` forces links on (even under tmux, and on terminals Fleury can't confirm);
`0`/`false`/`no`/`off` forces them off. Leave it unset to use detection.

**Check what was detected.** `fleury diagnose` reports the exact state —
`supported`, `suppressed-under-tmux` (the outer terminal is capable but a
multiplexer is in the way), `disabled-by-override` (`FLEURY_HYPERLINKS=0`), or
`unsupported` — and the debug shell's **Tree** tab shows it alongside the other
detected capabilities.
