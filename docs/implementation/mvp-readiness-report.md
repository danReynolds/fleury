# Fleury MVP Readiness Audit

**Directory:** docs/implementation/terminal-matrix
**Strict pass:** true
**Launch terminal targets ready:** 2/2
**Post-MVP Windows validation targets ready:** 0/4
**Windows validation MVP status:** deferred

## Local Implementation Evidence

- Status: documentedLocalRcGate
- Audit: docs/implementation/mvp-completion-audit.md
- Note: This command audits external evidence readiness. Run `dart tool/fleury_dev.dart check` separately for a fresh local RC gate.

## Remaining Blockers

- None.

## Evidence Gates

- Final MVP gate: `dart tool/fleury_dev.dart mvp-final-gate`
- Launch terminal strict gate: `dart tool/fleury_dev.dart terminal-matrix-audit --strict`
- Local RC gate: `dart tool/fleury_dev.dart check`

## Missing Targets

- Launch terminal matrix: None.

## Post-MVP Windows Validation

- Status: deferred out of MVP; current evidence 0/4 ready.
- Strict gate for the later Windows pass: `dart tool/fleury_dev.dart terminal-matrix-audit --target-preset=windows --strict`
- Missing Windows targets: windows-terminal, windows-conhost, windows-powershell, windows-ide

## Deferred Out Of MVP

- Dune/dune_cli flagship integration
- fleury_acp package and ACP-specific widgets
- extended terminal matrix coverage for iTerm2, Kitty, Ghostty, Alacritty, WezTerm, and SSH
- real Windows validation across Windows Terminal, conhost, PowerShell, and IDE terminals
- public adoption/release collateral until API freeze
- full replay/shareable replay artifacts and browser/devtools protocol
- expanded peer benchmarks and public superiority comparison copy

