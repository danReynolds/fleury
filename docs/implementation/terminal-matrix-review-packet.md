# Terminal Matrix Review Packet

**Directory:** docs/implementation/terminal-matrix
**Targets ready:** 2/2
**Entries:** 2 (invalid: 0)
**Strict pass:** true

Use this packet to review collected terminal evidence target by target.
It is generated from the same audit model as the strict gate; do not
treat an entry as launch evidence until the source JSON review status
is ready and the checklist item below has been reviewed.

## Target Review

### macos-terminal

- Status: ready
- Next action: complete

Matched entries:
  - [ ] `macos-terminal-terminalapp-2026-06-02` (`readyForReview`, targetPrefix)
    - Path: docs/implementation/terminal-matrix/2026-06-02T20-46-01Z-macos-terminal-terminalapp-2026-06-02.json
    - Platform: macos
    - Dart: 3.11.5 (stable) (Wed Apr 15 00:36:32 2026 -0700) on "macos_arm64"
    - Terminal: xterm-256color Apple_Terminal
    - Interactive: true
    - stdin/stdout: true/true
    - tmux/ssh: false/false
    - Active probes: {confirmed: 1, unsupported: 2, skipped: 0, timeout: 0, error: 0}
    - Compatibility: {confirmed: 0, activeConfirmed: 0, passiveUnverified: 0, unsupported: 2, inconclusive: 0}
    - Fallbacks: 2
    - Warnings: 0
    - Unsupported features: 2
    - Notes:
      - Captured-from-Apple-Terminal.app-via-osascript-from-Codex

### tmux

- Status: ready
- Next action: complete
- Note: Run from inside tmux and keep the context first in the label.

Matched entries:
  - [ ] `tmux-terminal-terminalapp-2026-06-02` (`readyForReview`, contextToken)
    - Path: docs/implementation/terminal-matrix/2026-06-02T20-50-27Z-tmux-terminal-terminalapp-2026-06-02.json
    - Platform: macos
    - Dart: 3.11.5 (stable) (Wed Apr 15 00:36:32 2026 -0700) on "macos_arm64"
    - Terminal: tmux-256color tmux
    - Interactive: true
    - stdin/stdout: true/true
    - tmux/ssh: true/false
    - Active probes: {confirmed: 1, unsupported: 2, skipped: 0, timeout: 0, error: 0}
    - Compatibility: {confirmed: 0, activeConfirmed: 0, passiveUnverified: 0, unsupported: 2, inconclusive: 0}
    - Fallbacks: 2
    - Warnings: 1
    - Unsupported features: 2
    - Notes:
      - captured inside tmux
      - Captured-from-tmux-inside-Apple-Terminal.app-via-osascript-from-Codex

## Review Checklist

- [ ] Entry labels match the actual terminal/session context.
- [ ] Accepted entries preserve reviewer notes and original
      issues in `review.acceptanceNotes` / `review.issues`.
- [ ] `stdinIsTerminal` and `stdoutIsTerminal` are true for
      interactive launch evidence.
- [ ] Active probes are not skipped for interactive entries.
- [ ] Unexpected passive-unverified, fallback, warning, and
      unsupported-feature findings are explained.
- [ ] tmux and SSH entries keep the context first in the label.
- [ ] Non-ready entries were either recaptured or explicitly kept as
      control/degradation evidence, not launch coverage.

