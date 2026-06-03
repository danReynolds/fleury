# Terminal Matrix Collection Plan

**Directory:** docs/implementation/terminal-matrix
**Targets ready:** 2/2
**Entries:** 2 (invalid: 0)

Run each capture command from the actual terminal, tmux session,
SSH session, or Windows host named by the target. Do not collect
launch evidence from an IDE output panel, CI pipe, or non-TTY
wrapper unless the entry is intentionally a control case.

## Targets

### macos-terminal

- Status: ready
- Next action: complete
- Matched entries:
  - `macos-terminal-terminalapp-2026-06-02` (readyForReview, targetPrefix): docs/implementation/terminal-matrix/2026-06-02T20-46-01Z-macos-terminal-terminalapp-2026-06-02.json

### tmux

- Status: ready
- Next action: complete
- Note: Run from inside tmux and keep the context first in the label.
- Matched entries:
  - `tmux-terminal-terminalapp-2026-06-02` (readyForReview, contextToken): docs/implementation/terminal-matrix/2026-06-02T20-50-27Z-tmux-terminal-terminalapp-2026-06-02.json

## Review Checklist

- Entry was captured in the named terminal.
- `review.status` is `readyForReview` or `acceptedForLaunch`.
- `stdinIsTerminal` and `stdoutIsTerminal` are true for interactive entries.
- Active probes are not skipped for interactive entries.
- Unexpected passive-unverified findings are reviewed.
- Accepted entries preserve reviewer notes and original issues.
- tmux and SSH entries keep the context first in the label.

