# Terminal Matrix External Handoff

**Status:** Post-MVP evidence handoff
**Date:** 2026-06-02
**Purpose:** Record terminal/session coverage deferred outside the MVP goal.

## Current MVP State

- MVP terminal evidence: 2/2 ready.
- MVP-covered targets:
  - `macos-terminal`
  - `tmux`
- Post-MVP targets:
  - `iterm2`
  - `kitty`
  - `ghostty`
  - `alacritty`
  - `wezterm`
  - `ssh`
- Windows validation is also post-MVP and is not part of this gate.

## Existing Evidence

- [Apple Terminal capture](terminal-matrix/2026-06-02T20-46-01Z-macos-terminal-terminalapp-2026-06-02.json)
- [tmux capture](terminal-matrix/2026-06-02T20-50-27Z-tmux-terminal-terminalapp-2026-06-02.json)
- [Current readiness report](mvp-readiness-report.md)
- [Generated collection plan](terminal-matrix-collection-plan.md)
- [Generated review packet](terminal-matrix-review-packet.md)

## Local Availability Findings

- The Codex shell is not valid launch evidence: `tty` reports `not a tty`, and
  `TERM=dumb`.
- Apple Terminal.app was available and produced valid `macos-terminal`
  evidence.
- `tmux` was available and produced valid `tmux` evidence from inside Apple
  Terminal.app.
- iTerm2, Kitty, Ghostty, Alacritty, and WezTerm are not installed locally as
  usable apps or CLIs.
- Localhost SSH through the system service is unavailable:
  `ssh -o BatchMode=yes -o ConnectTimeout=3 localhost true` returns
  `Connection refused`.
- A temporary user-space localhost `sshd` verified key-only login from the
  Codex shell, but the Terminal.app-launched SSH capture did not produce a
  matrix entry. No SSH evidence was kept from that attempt.

## Post-MVP Capture Commands

Run each command from the real terminal/session named by the target. Do not run
these from an IDE output pane, CI pipe, or this Codex shell.

```sh
dart tool/fleury_dev.dart terminal-matrix --label=iterm2 --review-note="Captured from iTerm2 <version/profile>"
dart tool/fleury_dev.dart terminal-matrix --label=kitty --review-note="Captured from Kitty <version/profile>"
dart tool/fleury_dev.dart terminal-matrix --label=ghostty --review-note="Captured from Ghostty <version/profile>"
dart tool/fleury_dev.dart terminal-matrix --label=alacritty --review-note="Captured from Alacritty <version/profile>"
dart tool/fleury_dev.dart terminal-matrix --label=wezterm --review-note="Captured from WezTerm <version/profile>"
```

For SSH, run from inside a real SSH session with an allocated TTY:

```sh
dart tool/fleury_dev.dart terminal-matrix --label=ssh-terminal --review-note="Captured over SSH from <local terminal> to <host/profile>"
```

## Review Rules

- The entry must have `stdinIsTerminal: true`, `stdoutIsTerminal: true`, and
  `isInteractive: true`.
- Active probes should not be skipped for interactive evidence.
- `review.status` should be `readyForReview` unless the entry has explainable
  issues.
- If an entry has explainable `needsAttention` issues, preserve the original
  issues and run:

```sh
dart tool/fleury_dev.dart terminal-matrix-accept --label=<entry-label> --accepted-by=<reviewer> --note="<why this is acceptable launch evidence>"
```

## After Captures Land

```sh
dart tool/fleury_dev.dart mvp-evidence-refresh
dart tool/fleury_dev.dart mvp-readiness --strict
dart tool/fleury_dev.dart mvp-final-gate
```

These commands are no longer required for the MVP goal. They become useful when
the extended terminal matrix is reopened after the MVP gate passes.
