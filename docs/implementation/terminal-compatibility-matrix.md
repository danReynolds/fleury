# Terminal Compatibility Matrix

**Status:** Active Phase 2 evidence workspace
**Milestone:** M2.10 active capability probes and real-terminal compatibility

## Purpose

Collect comparable `fleury diagnose --probe --json` evidence across real
terminals before Fleury makes strong compatibility claims or feeds active probe
results into default startup capability summaries. Confirmed active evidence
can be used explicitly through `additionalAvailableFeatures` when resolving
requirements for a diagnosed session.

The matrix should answer:

- What did passive environment detection claim?
- What did active terminal probes confirm, reject, skip, or time out?
- Did passive and active evidence agree?
- Which OS/Dart runtime produced the capture?
- Was the session affected by tmux, SSH, an IDE console, pipes, or a small
  terminal size?

## Capture Command

Run this from the workspace root inside the terminal being tested:

```sh
dart tool/fleury_dev.dart terminal-matrix --label=<terminal-name>
```

Useful variants:

```sh
dart tool/fleury_dev.dart terminal-matrix --label=iterm2 --probe-timeout=250
dart tool/fleury_dev.dart terminal-matrix --label=tmux-kitty --output=docs/implementation/terminal-matrix/tmux-kitty.json
dart tool/fleury_dev.dart terminal-matrix --label=passive-only --no-probe
dart tool/fleury_dev.dart terminal-matrix --label=ghostty-main --review-note="profile: default, font ligatures off"
```

Label clean terminal captures with the target first, optionally followed by a
profile or version suffix, such as `iterm2-3-5`, `wezterm-nightly`, or
`windows-terminal-powershell`. Label terminal contexts with the context first,
such as `tmux-kitty` or `ssh-iterm2`; those entries satisfy the `tmux` or
`ssh` targets but do not satisfy the underlying clean terminal target.

The launcher writes a JSON entry under `docs/implementation/terminal-matrix/`
unless `--output` is provided. Each entry wraps raw diagnosis JSON with a
matrix summary so future reviews do not have to diff full terminal reports.
Use repeated `--review-note=<text>` flags to preserve capture-time context such
as terminal version, profile, tmux/SSH host, unusual prompt integration, or why a
`needsAttention` entry is still useful. Notes are additive only; they do not
override automatic `review.status` or `review.issues`.

## Audit Command

Run this after collecting or reviewing entries:

```sh
dart tool/fleury_dev.dart terminal-matrix-audit
```

Run the combined MVP external-evidence gate with:

```sh
dart tool/fleury_dev.dart mvp-readiness
dart tool/fleury_dev.dart mvp-readiness --strict
dart tool/fleury_dev.dart mvp-readiness --write-report=docs/implementation/mvp-readiness-report.md
dart tool/fleury_dev.dart mvp-final-gate
dart tool/fleury_dev.dart mvp-evidence-refresh
```

Useful variants:

```sh
dart tool/fleury_dev.dart terminal-matrix-audit --json
dart tool/fleury_dev.dart terminal-matrix-audit --strict
dart tool/fleury_dev.dart terminal-matrix-audit --write-plan=docs/implementation/terminal-matrix-collection-plan.md
dart tool/fleury_dev.dart terminal-matrix-audit --write-review=docs/implementation/terminal-matrix-review-packet.md
dart tool/fleury_dev.dart terminal-matrix-audit --target-preset=windows --write-plan=docs/implementation/windows-validation-plan.md
dart tool/fleury_dev.dart terminal-matrix-audit --target=iterm2 --target=tmux-kitty
dart tool/fleury_dev.dart terminal-matrix-accept --label=wezterm-nightly --accepted-by=reviewer --note="Reviewed passive mismatch"
```

The audit does not create compatibility evidence. It scans collected entries,
counts review statuses and platforms, flags invalid JSON files, and reports
which target labels still lack a `readyForReview` matrix entry. `--strict`
exits non-zero when any requested target is missing ready evidence or invalid
entries are present. Target matching accepts exact labels, target-prefixed
clean captures such as `iterm2-3-5`, and context-labeled `tmux` / `ssh`
captures such as `tmux-kitty`.
The default `launch` preset is the narrowed MVP strict target set:
`macos-terminal` and `tmux`. Use explicit `--target=<name>` flags or the
[terminal matrix external handoff](terminal-matrix-external-handoff.md) for the
post-MVP iTerm2, Kitty, Ghostty, Alacritty, WezTerm, and SSH captures. Use
`--target-preset=windows` for the post-MVP M2.9 Windows validation lane. It
expands to `windows-terminal`, `windows-conhost`, `windows-powershell`, and
`windows-ide`, with generated capture notes for each target.

The JSON audit includes `targetCount`, `readyTargetCount`,
`missingTargetCount`, `nonReadyTargetCount`, `strictPass`, `targetsNeedingReview`,
and a `collectionPlan` for missing targets. Each target report includes a
`nextAction` of `complete`, `capture`, or `review-or-recapture`, plus ready and
non-ready entry counts. The human audit output prints missing-target capture
commands and separates targets that already have non-ready captures, so the
next collection pass can be run from the actual terminals without hand-building
labels or overlooking captures that need review.
Use `--write-plan=<path>` to write the same target status, suggested commands,
matched entries, and review checklist as a Markdown file that can be handed to
whoever is collecting real-terminal captures.
Use `--write-review=<path>` to write a reviewer packet from the same audit
state. The packet groups entries by target, includes status/issues/notes,
terminal/platform facts, active probe summaries, compatibility summaries, and
unmatched entries so review can happen without hand-reading every JSON file
first. The source JSON remains authoritative.
Use `terminal-matrix-accept` when a human reviewer accepts an entry whose
automatic status was `needsAttention`. Accepted entries preserve their original
issues plus reviewer notes and count as ready coverage. Non-interactive entries
are refused unless `--allow-non-interactive` is passed for explicit control or
degradation evidence.
`mvp-readiness` combines the launch-terminal audit and the Windows target
preset audit into one current-state report. It does not run the local test
suite; run `dart tool/fleury_dev.dart check` separately for a fresh local RC
gate.
`mvp-final-gate` runs the local RC gate first, then enforces external evidence
readiness. Use `--skip-local` only when the local gate has already run in the
same review context.
`mvp-evidence-refresh` regenerates the launch collection plan, launch review
packet, Windows validation plan, Windows review packet, and MVP readiness
report from the current matrix state.

## Entry Shape

Each saved entry uses:

```json
{
  "schemaVersion": 1,
  "kind": "fleuryTerminalMatrixEntry",
  "label": "iterm2",
  "capturedAt": "2026-06-01T00:00:00.000000Z",
  "command": [
    "dart",
    "run",
    "bin/fleury.dart",
    "diagnose",
    "--json-output=<matrix-diagnosis-json>",
    "--probe"
  ],
  "summary": {
    "platform": {},
    "terminal": {},
    "capabilities": {},
    "diagnostics": {
      "fallbackCount": 0,
      "warningCount": 0,
      "unsupportedFeatureCount": 0,
      "fallbackCodes": [],
      "warningCodes": [],
      "unsupportedFeatures": []
    },
    "activeProbes": {
      "summary": {},
      "probeStatuses": {}
    },
    "compatibility": {}
  },
  "review": {
    "status": "readyForReview",
    "issues": [],
    "notes": []
  },
  "diagnosis": {}
}
```

The matrix launcher writes diagnose JSON through `--json-output` while
preserving inherited stdio for the diagnose subprocess. That matters for
active probes: piping diagnose stdout would make the child report
`stdoutIsTerminal: false` even when the launcher itself is run from a real
terminal.

`summary.platform` is copied from `diagnosis.platform` and records the OS,
OS version, and Dart runtime string. Use it to distinguish Windows Terminal,
conhost, IDE terminal, macOS, Linux, and CI evidence without guessing from
`TERM` alone.

`summary.diagnostics` gives the compact fallback, warning, and unsupported
feature picture for the capture. Review those counts before accepting a matrix
entry for a launch claim; a `readyForReview` capture can still show expected
degradations that should be understood.

The most important field for M2.10 is
`summary.compatibility.summary`, which counts:

- `confirmed`: passive detection and active probe both indicate support.
- `activeConfirmed`: the active probe found support passive detection did not
  claim.
- `passiveUnverified`: passive detection claimed support but the active probe
  did not confirm it.
- `unsupported`: active evidence says the feature is unsupported.
- `inconclusive`: probes were skipped, missing, timed out, or errored.

`summary.activeProbes.summary` counts raw probe outcomes by status:
`confirmed`, `unsupported`, `skipped`, `timeout`, and `error`. Use it to spot
transport failures or timeouts before relying on a terminal entry for launch
claims. `summary.activeProbes.probeStatuses` keeps the per-probe status by id
for quick review.

`review.status` is the first machine-readable triage pass:

- `readyForReview`: interactive capture with active compatibility evidence and
  no automatic issues.
- `needsAttention`: interactive capture with skipped/missing probes,
  inconclusive findings, or passive claims that active probes did not confirm.
- `nonInteractive`: stdin/stdout or terminal mode makes the entry useful only
  as a non-interactive control case.

`review.issues` should be resolved or explicitly explained before using an
entry for a public compatibility claim. `review.notes` can include tmux, SSH,
or active-only confirmations that need human interpretation.

## Protocol References

- [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
  recommends querying the current progressive enhancement status together with
  primary device attributes so unsupported terminals can be distinguished from
  non-responsive terminals.
- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
  defines the graphics query flow Fleury uses for opt-in image capability
  evidence.
- [XTerm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.pdf)
  documents primary device attributes (`CSI c`), which Fleury uses as the
  conservative sentinel response for active probes.

## Target Matrix

Collect entries for:

- macOS Terminal
- iTerm2
- Kitty
- Ghostty
- Alacritty
- WezTerm
- Windows Terminal
- SSH into a local host where feasible
- tmux inside at least one rich terminal

For launch claims, prefer a small number of clean, reviewed entries over a
large pile of unreviewed local captures.

## Review Checklist

- [ ] Entry was captured in the named terminal, not an IDE output panel.
- [ ] `review.status` is `readyForReview`, or every listed issue is explained.
- [ ] `terminal.stdoutIsTerminal` and `terminal.stdinIsTerminal` are both true
  unless the entry is intentionally a non-interactive/pipe case.
- [ ] `activeProbes.skippedReason` is absent for interactive matrix entries.
- [ ] `compatibility.summary` has no unexpected `passiveUnverified` findings
  without a note in this file or the execution journal.
- [ ] tmux/SSH entries are labeled as such.
- [ ] Any surprising active-confirmed feature is treated as reviewed evidence
  and only used through explicit `additionalAvailableFeatures`, not as an
  automatic startup override.

## Current State

- Passive diagnose JSON is implemented and tested.
- Opt-in active probes are implemented and tested.
- Passive/active compatibility findings are implemented and tested.
- Matrix entries now include automatic review triage for non-interactive
  captures, skipped/missing probes, inconclusive findings, passive-unverified
  features, tmux/SSH notes, and active-only confirmations.
- Matrix entries also include active-probe summary counts, and transport
  timeouts are distinguishable from non-timeout probe errors.
- Matrix capture now preserves inherited stdio for `fleury diagnose` and uses
  `--json-output` for machine-readable data, so interactive captures are not
  incorrectly marked non-interactive only because the launcher needed JSON.
- Matrix audit now reports entry readiness, platform coverage, invalid files,
  diagnostic totals, ready target entries, and missing ready target labels for
  the launch compatibility set. It accepts target-prefixed clean captures and
  context labels for tmux/SSH without treating context captures as clean
  terminal coverage.
- Matrix audit now distinguishes targets with no captures from targets with
  non-ready captures through `nextAction`, `nonReadyTargetCount`, and
  `targetsNeedingReview`, keeping review/recapture work visible instead of
  flattening everything into missing coverage.
- Matrix audit target matching and strict-mode failure behavior are covered by
  `packages/fleury/test/tool/terminal_matrix_tool_test.dart`, which runs the
  actual `dart tool/fleury_dev.dart terminal-matrix-audit` launcher command
  against temporary matrix entries.
- Matrix capture accepts repeated `--review-note=<text>` flags and preserves
  those notes in the entry `review.notes`, covered through the same black-box
  launcher test suite.
- Matrix audit can now write a Markdown collection plan with
  `--write-plan=<path>`, keeping the external capture checklist generated from
  the same target matching and review-state logic as the JSON audit.
- Real-terminal entries are still pending.
