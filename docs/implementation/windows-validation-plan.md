# Terminal Matrix Collection Plan

**Directory:** docs/implementation/terminal-matrix
**Targets ready:** 0/4
**Entries:** 2 (invalid: 0)

Run each capture command from the actual terminal, tmux session,
SSH session, or Windows host named by the target. Do not collect
launch evidence from an IDE output panel, CI pipe, or non-TTY
wrapper unless the entry is intentionally a control case.

## Targets

### windows-terminal

- Status: not ready
- Next action: capture
- Capture: `dart tool/fleury_dev.dart terminal-matrix --label=windows-terminal`
- Note: Run on a real Windows host inside Windows Terminal and add profile/shell/version context with --review-note.

### windows-conhost

- Status: not ready
- Next action: capture
- Capture: `dart tool/fleury_dev.dart terminal-matrix --label=windows-conhost`
- Note: Run in classic Windows Console Host/conhost, not Windows Terminal.

### windows-powershell

- Status: not ready
- Next action: capture
- Capture: `dart tool/fleury_dev.dart terminal-matrix --label=windows-powershell`
- Note: Run from a PowerShell host on Windows and note whether the wrapper is Windows Terminal, conhost, or an IDE.

### windows-ide

- Status: not ready
- Next action: capture
- Capture: `dart tool/fleury_dev.dart terminal-matrix --label=windows-ide`
- Note: Run from a Windows IDE integrated terminal and include IDE/version context with --review-note.

## Review Checklist

- Entry was captured in the named terminal.
- `review.status` is `readyForReview` or `acceptedForLaunch`.
- `stdinIsTerminal` and `stdoutIsTerminal` are true for interactive entries.
- Active probes are not skipped for interactive entries.
- Unexpected passive-unverified findings are reviewed.
- Accepted entries preserve reviewer notes and original issues.
- tmux and SSH entries keep the context first in the label.

