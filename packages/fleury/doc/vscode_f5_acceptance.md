# VS Code F5 acceptance gate

Fleury's automated suite proves the generated Dart-Code configuration, a fresh
project's analysis/tests/executable compilation, tester-level keyboard and
mouse behavior, the VM-service reload contract, and native PTY rendering,
keyboard input, and cleanup. It cannot honestly prove VS Code's UI, Debug
Adapter Protocol, terminal backend, or a real terminal mouse click without
running the full VS Code Extension Host with Dart-Code installed.

Run this acceptance gate before a Fleury release that changes project creation,
terminal startup, or hot reload.

## Record the environment

| Field | Value |
| --- | --- |
| Date | |
| Tester | |
| Fleury commit SHA | |
| Operating system and version | |
| VS Code version | |
| Dart-Code extension version | |
| Dart SDK version | |
| CLI install source/command | |
| Integrated terminal backend/profile | |
| Result (pass/fail) | |

Repeat on macOS, Linux, and Windows. On Windows, record whether the integrated
terminal is using ConPTY; a Windows compile job is not a substitute for this
interactive check.

## Fresh-project flow

1. Using a fresh `PUB_CACHE`, install the CLI with the current command from the
   Getting Started guide and confirm the installed `fleury --help` works.
2. Run `fleury create f5_acceptance` and open that directory in VS Code. Before
   the hosted packages are published, add `--dependency-source=git`.
3. Press F5.
4. Confirm VS Code opens an integrated terminal, the counter renders, and no
   `runApp needs an interactive terminal` error appears.
5. Press Enter and confirm the counter increments.
6. Click **Increment** and confirm the counter increments again.
7. Set a breakpoint in `_increment`, press Enter, and confirm the Dart debugger
   stops there. Resume and confirm the UI remains interactive.
8. Change and save visible source text, run **Dart: Hot Reload**, and confirm
   the new text appears while the current count is preserved.
9. Stop the session, use the inline **Run** action above `main`, and confirm it
   also opens an integrated terminal.
10. Press Ctrl+C and confirm the cursor, mouse handling, and normal terminal
   screen are restored.

## Blocking automated receipts

- `test/cli/create_command_test.dart`
- `test/integration/create_project_test.dart`
- `test/remote/shell_cli_e2e_test.dart`
- `test/runtime/hot_reload_controller_test.dart`
- `test/animation/reassemble_test.dart`
- `test/widgets/reassemble_test.dart`
- `tool/hot_reload_probe/driver.dart`
- the `create-smoke` macOS/Linux/Windows CI matrix

Do not mark a platform's F5 path verified from the automated receipts alone.
