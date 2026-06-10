# RFC 0013: Capability And Security Contract

**Status:** Proposal  
**Date:** 2026-05-31  
**Decision point for:** M1.7 terminal diagnose and capability model, M1.11
sanitized output pipeline, semantic capability state, image/link/clipboard
widgets, subprocess output, debug inspector expansion, and future adapter
packages such as `fleury_acp`.

## 1. Summary

Fleury should treat terminal features as explicit app capabilities, not hidden
renderer trivia. Widgets and app services need a way to declare that they
require, prefer, optionally use, or prohibit terminal features such as
truecolor, mouse input, bracketed paste, Kitty keyboard events, clipboard
writes, OSC 8 hyperlinks, native image protocols, alternate screen, and tmux
passthrough.

Fleury should also treat terminal output as active content. Untrusted logs,
subprocess output, markdown, diffs, transcripts, model output, and future
agent/tool output must not be able to emit arbitrary terminal control
sequences. The framework should preserve useful formatting when safe, but raw
escape bytes should only reach stdout through framework-owned, policy-gated
paths.

This RFC proposes two connected contracts:

- A **capability contract** for requirement declaration, fallback resolution,
  diagnostics, semantics, and inspector state.
- A **security policy** for sanitized text, parsed ANSI, links, clipboard,
  images, markdown, subprocess output, malformed Unicode, huge lines, and
  secret redaction hooks.

The v0 goal is not perfect terminal probing. It is to make capabilities,
fallbacks, and output trust visible and testable before Phase 1 widgets and app
kernel features depend on them.

## 2. Motivation

Terminal support is uneven across emulator, multiplexer, SSH, OS, and user
settings. Rich terminal features are also active I/O:

- OSC 52 can write the user's clipboard.
- OSC 8 can create clickable links to browser, file, and custom URI handlers.
- Native image protocols inject large OSC/DCS/APC payloads.
- Mouse reporting can take over normal terminal selection.
- Bracketed paste and keyboard protocols change input event shape.
- tmux and SSH can change where clipboard, image, and link effects land.
- Raw ANSI from a process can clear the screen, move the cursor, hide content,
  set window titles, or trigger proprietary terminal behavior.

Fleury already has the beginning of a good boundary:

- `TerminalCapabilities` reports color mode, image protocol, alternate screen,
  cursor hiding, and tmux passthrough.
- `TerminalMode` controls raw input, alternate screen, cursor visibility,
  bracketed paste, Kitty keyboard, mouse, and mouse motion.
- `PosixTerminalDriver` detects color/image capability from environment,
  handles raw mode and restore ordering, and enables/disables terminal modes.
- `sanitizeForDisplay` replaces C0/C1 controls, DEL, and ESC before text
  reaches the cell buffer.
- `OutputCapture` intercepts stray stdout/stderr during a TUI session.
- `Clipboard` uses platform tools, OSC 52, and an in-process register.
- `Image` can render through glyph fallbacks or Kitty/iTerm2/Sixel protocol
  cells.
- `MarkdownText` renders links as visible text plus URL rather than emitting
  OSC 8 today.
- `fleury diagnose` exists, but it is not yet machine-readable.

The missing piece is the contract that ties these together.

## 3. Protocol References

These are the primary references that shaped the v0 contract:

- [XTerm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
  for OSC handling, alternate screen, mouse modes, and bracketed paste.
- [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
  for unambiguous keyboard reporting and progressive enhancement.
- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
  for native graphics payloads and terminal-owned image state.
- [iTerm2 inline images](https://iterm2.com/3.5/documentation-images.html)
  for OSC 1337 image/file payloads and tmux chunking limits.
- [OSC 8 hyperlink specification](https://iterm2.com/feature-reporting/Hyperlinks_in_Terminal_Emulators.html)
  and [iTerm2 escape-code docs](https://iterm2.com/documentation-escape-codes.html)
  for hyperlink behavior and link security notes.
- [tmux manual](https://man.archlinux.org/man/tmux.1.en) for extended keys,
  clipboard behavior, `allow-passthrough`, alternate screen, titles, and
  passthrough limits.
- [NO_COLOR](https://no-color.org/) for user-controlled ANSI color opt-out.

## 4. Goals

- Let widgets and services declare capability requirements with fallbacks.
- Expose capability resolution through semantics, diagnostics, inspector, and
  tests.
- Add a machine-readable `fleury diagnose --json` contract.
- Centralize safe defaults for untrusted content.
- Keep raw terminal bytes behind framework-owned APIs.
- Preserve rich output for trusted app-owned widgets.
- Make clipboard, links, and native image output explicitly policy-gated.
- Support future adapter packages without adding ACP-specific concepts to
  Fleury core.

## 5. Non-Goals

- Perfect active probing of every terminal feature in Phase 1.
- A public plugin system for arbitrary escape-sequence passthrough.
- Full terminal emulator conformance testing.
- Full replay artifacts.
- ACP transport, ACP schemas, or ACP-specific widgets.
- Replacing terminfo. Fleury can use terminfo later where it helps, but this
  RFC focuses on the framework-level contract.
- Guaranteeing that every terminal that ignores standards behaves cleanly.

## 6. Design Principles

1. **Capabilities are product behavior.** If a widget degrades, users and
   developers should know why.
2. **Safe text is the default.** Strings from app data, logs, markdown, model
   output, and subprocess output are plain text unless a policy says otherwise.
3. **Raw bytes are privileged.** Escape payloads only reach stdout through
   renderer, driver, clipboard, image, hyperlink, or other framework-owned
   APIs.
4. **Fallbacks are first-class.** A missing capability should produce an
   intentional degraded path, not a silent broken UI.
5. **Trust is local to the content source.** A trusted app widget can render an
   image. An untrusted process line containing an image escape cannot.
6. **Testing sees the same contract as runtime.** Fake drivers should exercise
   the same requirement and security policy surfaces as real terminals.
7. **SSH and tmux are normal cases.** They should produce warnings and
   fallbacks, not surprising behavior.

## 7. Capability Model

Names are proposed, not final.

```dart
enum TerminalFeature {
  colorAnsi16,
  colorIndexed256,
  colorTruecolor,
  unicodeWidthProfile,
  alternateScreen,
  hideCursor,
  bracketedPaste,
  kittyKeyboard,
  mouse,
  mouseMotion,
  clipboardWrite,
  osc52Clipboard,
  hyperlinks,
  osc8Hyperlinks,
  inlineImages,
  imageKitty,
  imageIterm2,
  imageSixel,
  imageGlyphFallback,
  tmuxPassthrough,
  sshSession,
  rawAnsiParsing,
  synchronizedOutput,
}
```

`TerminalCapabilities` should grow from a small static snapshot into a typed
report:

```dart
final class TerminalProfileReport {
  const TerminalProfileReport({
    required this.terminal,
    required this.environment,
    required this.capabilities,
    required this.warnings,
  });

  final TerminalIdentity terminal;
  final TerminalEnvironment environment;
  final TerminalCapabilities capabilities;
  final List<CapabilityWarning> warnings;
}
```

The implementation can keep the current lightweight `TerminalCapabilities` as
the widget-facing summary while adding a richer report for diagnostics,
inspector, and tests.

## 8. Requirements And Resolution

Widgets, render islands, app services, and future adapters should describe what
they need with requirement records:

```dart
enum CapabilityLevel {
  required,
  preferred,
  optional,
  prohibited,
}

final class CapabilityRequirement {
  const CapabilityRequirement({
    required this.feature,
    required this.level,
    this.reason,
    this.fallback,
    this.securityPolicy,
  });

  final TerminalFeature feature;
  final CapabilityLevel level;
  final String? reason;
  final CapabilityFallback? fallback;
  final OutputSecurityPolicy? securityPolicy;
}
```

Resolution turns app intent plus terminal profile plus policy into explicit
state:

```dart
enum CapabilityResolutionState {
  available,
  degraded,
  disabledByPolicy,
  unsupported,
  unsafe,
}

final class CapabilityResolution {
  const CapabilityResolution({
    required this.feature,
    required this.level,
    required this.state,
    this.fallbackLabel,
    this.warning,
  });

  final TerminalFeature feature;
  final CapabilityLevel level;
  final CapabilityResolutionState state;
  final String? fallbackLabel;
  final String? warning;
}
```

Rules:

- `required + unsupported` is a developer-visible error for that widget or app
  surface.
- `preferred + unsupported` uses fallback and records a warning.
- `optional + unsupported` silently omits the enhancement unless diagnostics
  are open.
- `prohibited + available` disables the feature by policy and records that it
  was intentionally blocked.
- Every resolution should be available to semantic nodes and the inspector.

## 9. Feature Fallback Policy

### Color

- Respect `NO_COLOR` as the highest-priority color opt-out.
- Resolve style fidelity in this order: truecolor, 256-color, 16-color, no
  color.
- Renderer-level downsampling remains responsible for cell color output.
- Diagnostics should report the source of color detection: `NO_COLOR`,
  `COLORTERM`, `TERM`, forced color, or unknown.

### Keyboard

- Prefer bracketed paste for text editing and composer widgets.
- Prefer Kitty keyboard disambiguation where supported or safely ignored.
- Do not require Kitty keyboard for core navigation.
- Record when input is operating in fallback mode so tests can cover ambiguous
  chords.

### Mouse

- Mouse and mouse motion remain opt-in.
- Widgets that support mouse must also expose keyboard semantics.
- Mouse capture should warn that normal terminal selection can be affected.
- Hover-only affordances cannot be the only way to discover or invoke actions.

### Clipboard

- Clipboard writes are explicit user or command actions, not implicit rendering
  effects.
- Prefer local platform tools when they target the user's local clipboard.
- Use OSC 52 only through the clipboard service, with a size limit, policy
  check, and diagnostic warning under SSH/tmux.
- Always populate the in-process register when a write is requested.
- Clipboard reads stay in-process for v0.
- Secret fields and redacted content should be copy-blocked or copy-filtered by
  policy.

### Links

- Default markdown links remain visible text plus URL.
- OSC 8 hyperlinks are a trusted-output enhancement, not the default for
  untrusted markdown/log/process output.
- When emitting OSC 8, Fleury should also keep the URL visible or semantically
  inspectable.
- Only allow safe URL schemes by default: `https`, `http`, `mailto`, and
  carefully scoped `file` links when the app explicitly opts in.
- Custom schemes require opt-in policy.

### Images

- Trusted app-owned `Image` widgets may use native protocols when detected and
  allowed by policy.
- Untrusted terminal output must not pass through embedded image escape
  payloads.
- Fallback order: Kitty graphics, iTerm2 inline images, Sixel, glyph image
  renderers, text alternative.
- Native image payload size, chunking, and tmux wrapping must be visible in
  diagnostics.
- `tmuxPassthrough` should be treated as a compatibility mode with warnings,
  not as proof that every host terminal will accept the inner protocol.

### Alternate Screen And Cursor

- Full-screen apps prefer alternate screen and hidden cursor.
- Inline apps can disable alternate screen and cursor hiding.
- Exit cleanup remains mandatory and should be observable in tests with fake
  drivers.
- Diagnostics should report when stdout is not interactive.

### Unicode Width

- The width resolver remains the display authority.
- Diagnostic output should report the active width profile and ambiguity
  policy.
- Text editing tests must include emoji, combining marks, CJK, ambiguous-width
  characters, malformed Unicode, and replacement behavior.

## 10. Output Security Policy

The core policy should distinguish content source and trust level:

```dart
enum OutputTrustLevel {
  framework,
  trustedApp,
  trustedStructured,
  untrustedText,
  untrustedAnsi,
}

final class OutputSecurityPolicy {
  const OutputSecurityPolicy({
    this.allowAnsiSgr = false,
    this.allowCursorControls = false,
    this.allowOsc52 = false,
    this.allowOsc8 = false,
    this.allowImageProtocols = false,
    this.allowTitleChanges = false,
    this.allowBell = false,
    this.maxLineLength = 20000,
    this.maxPayloadBytes = 100000,
    this.redactionRules = const [],
  });

  final bool allowAnsiSgr;
  final bool allowCursorControls;
  final bool allowOsc52;
  final bool allowOsc8;
  final bool allowImageProtocols;
  final bool allowTitleChanges;
  final bool allowBell;
  final int maxLineLength;
  final int maxPayloadBytes;
  final List<RedactionRule> redactionRules;
}
```

Default policies:

| Source | Default behavior |
| --- | --- |
| Framework renderer | May emit framework-generated ANSI, protocol cells, mode setup, and cleanup. |
| Trusted app widget | May request rich features through typed APIs and capability policy. |
| Trusted structured text | May preserve style spans and semantic links, then render through framework APIs. |
| Untrusted plain text | Sanitize controls, preserve printable Unicode, wrap/truncate huge lines, redact secrets. |
| Untrusted ANSI/process output | Parse allowed SGR if explicitly enabled; strip or render-visible every other control sequence. |

The important boundary: a string containing `ESC` is not a widget-level escape
hatch. It is content to sanitize or parse.

## 11. Raw ANSI And Subprocess Output

Fleury should support two subprocess/log display modes:

1. **Plain mode:** sanitize every unsafe control rune and display text.
2. **Restricted ANSI mode:** parse a small safe subset, initially SGR styling
   only, into styled text spans; strip or visible-escape cursor movement, OSC,
   DCS, APC, PM, SOS, private modes, title changes, clipboard writes,
   hyperlinks, image payloads, bells, and device queries.

Restricted ANSI mode is useful for colorized logs, test output, diffs, and
compiler diagnostics. It must not be a raw passthrough.

Subprocess output should also get:

- malformed UTF-8 handling with visible replacement,
- maximum line length policy,
- maximum buffered bytes per region,
- backpressure hooks for workers,
- redaction hooks before display, copy, semantic snapshots, replay/debug
  capture, and persisted logs.

## 12. Markdown Policy

`MarkdownText` should remain safe by construction:

- No HTML passthrough.
- Links render as visible text and URL by default.
- Code blocks are plain styled text.
- Image syntax is not terminal image output.
- Any future OSC 8 link mode requires trusted source and explicit policy.
- Any future markdown table/image extensions should go through structured
  widgets, not raw escape output.

## 13. Secret Redaction Hooks

Redaction must happen before unsafe content enters display, copy, semantic
snapshots, debug captures, and future replay artifacts.

```dart
final class RedactionRule {
  const RedactionRule({
    required this.id,
    required this.pattern,
    this.replacement = '[redacted]',
  });

  final String id;
  final Pattern pattern;
  final String replacement;
}
```

Built-in v0 rules should cover common token shapes conservatively, but apps
must be able to add domain-specific rules. Redaction should report counts and
rule IDs in debug diagnostics without leaking the matched value.

## 14. Diagnostics Contract

`fleury diagnose --json` should print a stable machine-readable object:

```json
{
  "schemaVersion": 1,
  "terminal": {
    "term": "xterm-256color",
    "termProgram": "iTerm.app",
    "colorterm": "truecolor",
    "isInteractive": true,
    "stdinIsTerminal": true,
    "stdoutIsTerminal": true
  },
  "environment": {
    "ssh": false,
    "tmux": false,
    "noColor": false
  },
  "capabilities": {
    "colorMode": "truecolor",
    "imageProtocol": "iterm2",
    "alternateScreen": true,
    "hideCursor": true,
    "bracketedPaste": "enabledByDefault",
    "kittyKeyboard": "attempted",
    "mouse": "availableOptIn",
    "osc52Clipboard": "policyGated",
    "osc8Hyperlinks": "policyGated",
    "tmuxPassthrough": false
  },
  "fallbacks": [],
  "warnings": []
}
```

Human output can remain readable, but JSON is the contract for bug reports,
CI fixtures, peer compatibility notes, and the demo-app Diagnostics screen.

## 15. Semantics And Inspector Integration

Capability resolution should flow into the semantic app graph:

- App root exposes terminal profile summary.
- Widgets expose active requirement/fallback state.
- Diagnostics regions expose warnings and unsupported features.
- Image/link/clipboard widgets expose whether an advanced feature was used,
  degraded, or blocked by policy.
- Text/log regions expose active sanitization and redaction state.

The inspector should answer:

- What terminal profile is active?
- Which capabilities were detected from environment versus assumed?
- Which widgets requested capabilities?
- Which features degraded?
- Which features were disabled by security policy?
- Which output regions redacted or sanitized content?

## 16. Testing Strategy

Phase 1 tests should use fake drivers and pure policy tests before relying on
real terminals:

- Capability resolution matrix for required/preferred/optional/prohibited.
- Color fallback and `NO_COLOR`.
- Keyboard mode defaults and bracketed paste input.
- Mouse opt-in semantics.
- Clipboard platform/OSC52/in-process fallback with size and SSH/tmux cases.
- OSC 8 policy: visible link fallback, safe schemes, custom-scheme block.
- Image policy: trusted widget native path, untrusted escape stripping, glyph
  fallback.
- ANSI parser: SGR allowed, cursor/OSC/DCS/APC/title/bell stripped or rendered
  visible.
- Malformed Unicode and huge line handling.
- Secret redaction before display, copy, semantics, debug capture, and logs.
- `fleury diagnose --json` snapshot tests with fake environments.

Real-terminal checks should be manual evidence in Phase 1 and automated where
practical in Phase 2.

## 17. Implementation Plan

1. Extend capability types without removing current lightweight fields.
2. Add requirement/resolution types and fake-driver test helpers.
3. Add `OutputSecurityPolicy`, redaction rules, and sanitized output result
   types.
4. Route log/process/markdown display through explicit policy objects.
5. Add a restricted ANSI parser for SGR-only preservation.
6. Gate clipboard, OSC 8, and native images through policy and capability
   resolution.
7. Add semantic nodes/properties for capability and security state.
8. Expand inspector panels for terminal profile, requirements, fallbacks, and
   output sanitization.
9. Implement `fleury diagnose --json`.
10. Use the example demo app Diagnostics screen as the integration target.

## 18. Open Questions

- Should `TerminalCapabilities` itself grow all fields, or should it remain a
  compact widget-facing summary with `TerminalProfileReport` as the rich API?
- Should OSC 8 hyperlinks be part of core text rendering or a separate widget
  in `fleury_widgets`?
- Should native image output be blocked by default in tmux unless diagnostics
  verify passthrough support?
- How strict should built-in secret redaction be before apps add custom rules?
- Should `fleury diagnose --json` support active probes in Phase 1, or only
  report static/env-derived detection until Phase 2?
- What should the public API call the restricted ANSI parser: `AnsiText`,
  `SafeAnsiText`, `TerminalStyledText`, or a log-region option?

## 19. Acceptance For M0.4

This RFC satisfies M0.4 when:

- Capability declarations cover colors, mouse, keyboard protocols, clipboard,
  links, images, tmux/SSH awareness, diagnostic reporting, and fallbacks.
- Security policy covers raw ANSI, OSC 52, OSC 8, markdown, subprocess output,
  malformed Unicode, huge lines, image escapes, and secret redaction hooks.
- The plan feeds Phase 1 `fleury diagnose --json` and sanitized output tasks.
- The contract is linked from the implementation tracker, milestone checklist,
  terminal/security workstream, decision log, and roadmap.
