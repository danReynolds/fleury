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

## Security matrix

| Boundary | Threat | Owner tests | Status |
| --- | --- | --- | --- |
| Terminal sanitizer corpus | ANSI/OSC/DCS/APC/C0/C1 bytes become active terminal protocol. | `../rendering/text_sanitizer_test.dart`, `terminal_security_boundary_test.dart` | Covered |
| Widget text to terminal cells | App/file/model text bypasses sanitizer before the cell buffer. | `terminal_security_boundary_test.dart`, `../widgets/*`, `../../../fleury_widgets/test/*sanitizes*` | Covered |
| Runtime stray stdout/stderr | `print()` or direct stdout/stderr writes replay hostile controls after `runApp` restores the terminal. | `terminal_security_boundary_test.dart`, `../runtime/run_app_test.dart` | Covered |
| Subprocess task output | Tool output writes terminal controls into task events/log views. | `terminal_security_boundary_test.dart`, `../effects/process_task_test.dart` | Covered |
| Served spawn logs | `fleury serve --spawn` mirrors child output to the developer terminal as active controls. | `../remote/serve_spawn_test.dart` | Covered |
| Clipboard effects | Untrusted content writes OSC 52 or platform clipboard unexpectedly. | `../runtime/clipboard_test.dart`, widget copy tests using `ClipboardWritePolicy.inProcessOnly` or redaction | Covered |
| External processes and editors | File paths or command metadata cross into shell execution unintentionally. | `effects_security_boundary_test.dart`, `../effects/external_editor_test.dart`, `../effects/process_task_test.dart` | Covered |
| Terminal input parser | Malformed byte streams, truncated CSI/OSC/paste, or random input crash or amplify events. | `../terminal/input_parser_test.dart` seeded fuzzing | Covered |
| WebSocket serve origin and frames | Cross-site WebSocket hijack, oversized frames, malformed frames, stale handles, or broad static serving. | `../remote/serve_integration_test.dart`, `../remote/remote_protocol_test.dart`, `../remote/serve_stale_handle_test.dart`, `../remote/remote_codec_test.dart` | Covered |
| Browser DOM cell text | Cell text becomes HTML/DOM instead of text. | `../../../fleury_web/test/security/browser_security_boundary_test.dart`, `../../../fleury_web/test/dom_grid_surface_test.dart`, `../../../fleury_web/test/cell_grid_html_test.dart` | Covered |
| Browser semantic links | Unsafe or disabled links become navigable browser links. | `../../../fleury_web/test/security/browser_security_boundary_test.dart`, `../../../fleury_web/test/semantic_dom_presenter_test.dart` | Covered |
| Native protocol/image payloads | Framework-owned image/protocol bytes leak through browser DOM or untrusted text APIs. | `../../../fleury_web/test/security/browser_security_boundary_test.dart`, `../rendering/ansi_renderer_test.dart`, `../../../fleury_widgets/test/*image*` | Covered |
| Semantics/debug/export text | Labels, state, debug snapshots, exports, and search indexes preserve terminal controls or secrets. | `../semantics/*`, `../debug/*`, `../remote/remote_semantics_test.dart`, widget sanitizer/export tests | Covered |
| Local shell/serve IPC handles | Stale or competing local handles hijack sessions. Same-user possession of a live socket/env handle remains the documented OS trust boundary. | `../remote/serve_stale_handle_test.dart`, `../remote/shell_lifecycle_test.dart`, `../remote/serve_spawn_test.dart` | Covered to stated boundary |
| Capability-gated effects | Clipboard, image, link, mouse, keyboard, tmux, and fallback behavior silently use unavailable or prohibited terminal capabilities. | `../terminal/capability_requirements_test.dart`, `../terminal/diagnostics_test.dart`, widget capability tests | Covered |

When a new feature can write to a terminal, browser DOM, clipboard, shell,
external editor, file, URL opener, or native terminal protocol, add a row here
with a concrete owner test before calling the feature complete.
