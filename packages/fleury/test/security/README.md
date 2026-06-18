# Fleury CLI security boundary tests

This directory is the regression surface for the CLI security contract from
`docs/rfcs/0013-capability-security-contract.md`.

The invariant is that untrusted text remains data. Text from app state, files,
subprocesses, stray `print()` calls, remote frames, markdown, logs, model
output, and semantic labels must not become terminal protocol, browser markup,
clipboard writes, process execution, or external navigation unless it passes
through an explicit framework-owned effect API.

## Research anchors

- MITRE CWE-150 treats escape/control sequence injection as an integrity issue:
  ANSI can move the cursor, clear the screen, spoof prompts, and in some
  terminal contexts trigger stronger behavior.
- xterm.js' security guide treats terminal I/O as untrusted whenever it crosses
  into DOM or application APIs; embedders must not feed terminal data into
  privileged sinks such as `innerHTML`, link handlers, or parser hooks.
- OWASP's WebSocket guidance calls out Origin validation, auth/session checks,
  transport security, and message-size/DoS controls as explicit WebSocket
  responsibilities.
- GitHub CLI and Dangerzone both shipped advisories for replaying attacker
  controlled logs/container output to a user's terminal without neutralizing
  terminal controls. Fleury's equivalent sinks are captured runtime output,
  subprocess output, served-app logs, and any future log/file/model viewers.

## Test layers

- `terminal_security_boundary_test.dart` covers terminal-bound text sinks:
  display text, runtime stray-output capture, `runTui` replay/hook delivery,
  and subprocess task output.
- `../rendering/text_sanitizer_test.dart` owns the sanitizer corpus and parser
  edge cases for CSI, OSC, DCS, APC, C0/C1, malformed strings, and Unicode.
- `../runtime/clipboard_test.dart` owns clipboard policy, OSC 52 caps, and
  in-process fallback behavior.
- `../remote/*` owns WebSocket origin checks, frame caps, malformed frames, and
  browser/app transport boundaries.
- `../effects/*` owns process and external-effect APIs.

When a new feature can write to a terminal, browser DOM, clipboard, shell,
external editor, file, URL opener, or native terminal protocol, add it to this
matrix or to the specific layer above.
