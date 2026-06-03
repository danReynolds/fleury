# Terminal Matrix Entries

This directory is the default output location for:

```sh
dart tool/fleury_dev.dart terminal-matrix --label=<terminal-name>
```

Audit collected entries with:

```sh
dart tool/fleury_dev.dart terminal-matrix-audit
```

Accept a reviewed entry that has explainable issues with:

```sh
dart tool/fleury_dev.dart terminal-matrix-accept --label=<entry-label> --accepted-by=<name> --note="Reviewed issue and accepted for launch evidence"
```

Audit the combined MVP external evidence state with:

```sh
dart tool/fleury_dev.dart mvp-readiness --write-report=docs/implementation/mvp-readiness-report.md
```

Run the full final MVP gate with:

```sh
dart tool/fleury_dev.dart mvp-final-gate
```

Refresh all generated evidence docs with:

```sh
dart tool/fleury_dev.dart mvp-evidence-refresh
```

Write a durable capture/review checklist with:

```sh
dart tool/fleury_dev.dart terminal-matrix-audit --write-plan=docs/implementation/terminal-matrix-collection-plan.md
```

Write a target-by-target reviewer packet with:

```sh
dart tool/fleury_dev.dart terminal-matrix-audit --write-review=docs/implementation/terminal-matrix-review-packet.md
```

Generate the post-MVP Windows-specific validation lane with:

```sh
dart tool/fleury_dev.dart terminal-matrix-audit --target-preset=windows --write-plan=docs/implementation/windows-validation-plan.md --write-review=docs/implementation/windows-validation-review-packet.md
```

Review generated JSON before committing it. Real-terminal captures are useful
Phase 2 evidence, but labels, tmux/SSH context, and surprising compatibility
findings should be understandable from the file name, the matrix tracker, or
the execution journal.

Use repeated `--review-note=<text>` flags when capturing entries to preserve
human context that the passive/active probes cannot infer, such as terminal
version, profile name, SSH host shape, tmux nesting, or why an automatic
`needsAttention` entry is still useful. Capture notes do not override automatic
review status or issues.

Each entry includes a `review` object. Prefer committing entries with
`review.status` set to `readyForReview`. Entries marked `needsAttention` can
be promoted to `acceptedForLaunch` with `terminal-matrix-accept` after a human
reviewer explains the issue. Entries marked `nonInteractive` are not launch
coverage unless explicitly accepted with `--allow-non-interactive` as control
or degradation evidence.

Each entry also includes `summary.activeProbes.summary` so confirmed,
unsupported, skipped, timed-out, and errored probes are visible without
inspecting every raw probe record.

Each entry includes `summary.platform` copied from `diagnosis.platform`.
Review Windows, macOS, Linux, IDE, tmux, and CI captures against this platform
evidence instead of inferring the host only from terminal environment strings.

Each entry includes `summary.diagnostics` with fallback, warning, and
unsupported feature counts plus the corresponding codes. The audit command
aggregates those counts so degraded captures are visible before review.

Use target-first labels for clean terminal captures, such as `iterm2-3-5` or
`ghostty-main`. For post-MVP Windows validation, labels such as
`windows-terminal-powershell` remain valid. Use context-first labels for
context captures, such as `tmux-kitty` or `ssh-iterm2`. The audit command
counts those context labels toward `tmux` or `ssh`, not toward the underlying
clean terminal target.

The launcher preserves inherited stdio for `fleury diagnose` and asks diagnose
to write JSON through `--json-output=<path>`. Do not replace this with a stdout
pipe; active probes and terminal interactivity checks must see the same TTY the
developer is testing.

The `script(1)` pseudo-terminal test in `terminal_probe_test.dart` is useful
transport coverage, but it is not a matrix entry and should not be used as
real-terminal launch evidence.

The audit command is a readiness check over collected evidence, not evidence
itself. Use `--strict` only when the named target labels are expected to have
`readyForReview` entries.

The audit JSON also includes readiness totals and a `collectionPlan` for
missing targets. The human audit output prints suggested capture commands;
`--write-plan` writes those target statuses, suggested commands, matched
entries, and review criteria as Markdown.
`--write-review` writes a reviewer packet with matched entry details, issues,
notes, terminal/platform facts, active probe summaries, compatibility
summaries, and unmatched entries.
Run those commands from the actual terminal, tmux session, SSH session, or
Windows host named by the target before treating the matrix as launch
evidence.
