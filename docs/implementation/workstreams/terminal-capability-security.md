# Workstream: Terminal Capability And Security

## Purpose

Make terminal behavior explicit, diagnosable, degradable, and safe when apps
display untrusted output or use advanced terminal features.

## Current State

- Fleury has terminal drivers, capability types, input parsing, ANSI rendering,
  width resolution, clipboard, output capture, and text sanitizer code. Runtime
  `LogBuffer` output capture now rejects post-dispose appends while keeping
  final captured lines readable.
- Capability detection is now centralized in the terminal capability layer and
  feeds both runtime shell handshakes and diagnosis output.
- `TerminalDiagnosis` provides the first machine-readable terminal profile,
  capability, fallback, warning, and unsupported-feature snapshot.
- A pure `CapabilityRequirement`/`CapabilityResolution` model now lets
  widgets and services declare required, preferred, optional, or prohibited
  terminal features before broad widget integration.
- `Image` is the first widget integration: semantic snapshots report native
  image availability, glyph fallback state, active protocol, color mode, tmux
  passthrough, and frame metadata.
- `MarkdownText` link semantics now report OSC 8 hyperlinks as disabled by
  default with visible URL fallback and safe-scheme metadata.
- Clipboard writes now return structured reports for transport, policy,
  fallback, payload size, SSH, and emitted OSC 52 state while preserving the
  existing simple `write()` API.
- `TextInput` and `TextArea` semantic state now exposes clipboard policy,
  capability, resolution, fallback, and redaction state.
- `DataTable` selected-row copy uses sanitized export text, framework clipboard
  writes, and semantic copy/capability metadata.
- The demo app Diagnostics screen now renders resolver-backed capability rows
  for color, inline images, markdown links, clipboard writes, and OSC 52.
- Native subprocess task output is now sanitized with `sanitizeForDisplay`,
  capped by `ProcessTaskController.maxOutputLineLength`, decoded with
  malformed-UTF-8 replacement, and annotated with safety metadata before
  task/event/semantic storage.
- `SB.9 Subprocess Handoff And Untrusted Output` now repeatedly verifies that
  unsafe subprocess and captured-output payloads do not reach visible output,
  copied text, or semantic artifacts while terminal handoff state is restored.
- The first opt-in active probe layer now exists behind
  `fleury diagnose --probe`. It can confirm primary device attributes, Kitty
  keyboard status, and Kitty graphics query support with bounded timeouts and
  structured skipped evidence in non-TTY environments.
- `TerminalDiagnosis` now includes a compatibility comparison report when
  active probes are attached, so matrix collection can distinguish passive and
  active agreement, active-only confirmations, passive-unverified claims,
  unsupported features, and inconclusive probe evidence.
- `dart tool/fleury_dev.dart terminal-matrix` now captures
  `fleury diagnose --probe --json-output=<path>` into a labeled matrix-entry
  JSON file with inherited stdio preserved for active probes, plus a compact
  summary and automatic review triage for non-interactive captures, skipped
  probes, inconclusive findings, passive-unverified features, tmux/SSH notes,
  and active-only confirmations.
- `dart tool/fleury_dev.dart terminal-matrix-audit` now scans collected matrix
  entries and reports review status, platform coverage, invalid files, and
  target labels that still lack ready reviewed evidence. The audit can write a
  generated collection plan and a target-by-target reviewer packet from the
  same readiness model, keeping capture and review artifacts aligned with the
  strict gate.
- `dart tool/fleury_dev.dart mvp-readiness` now combines the launch-terminal
  matrix audit and Windows validation preset audit into one external-evidence
  readiness gate and Markdown report.
- `dart tool/fleury_dev.dart mvp-final-gate` now runs the local RC gate and
  then enforces the combined external-evidence readiness gate.
- `dart tool/fleury_dev.dart mvp-evidence-refresh` now regenerates the launch
  collection plan, launch review packet, Windows validation plan, Windows
  review packet, and MVP readiness report from the current matrix state.
- `dart tool/fleury_dev.dart terminal-matrix-accept` now records reviewer
  acceptance for explainable `needsAttention` captures as `acceptedForLaunch`
  while preserving original issues and notes.
- The debug Tree tab now renders active/passive compatibility report summaries
  from `TerminalDiagnosis`, including confirmed, active-confirmed,
  passive-unverified, unsupported, and inconclusive finding counts plus
  per-feature probe/passive status summaries.
- The debug Tree tab now also aggregates semantic safety signals for redacted
  values, sanitized output, truncated output, and largest original output
  length so unsafe-content handling is visible without manually selecting every
  node.
- The same inspector capability section now aggregates semantic capability
  resolution states, including degraded, disabled-by-policy, unsupported,
  unsafe, and required-blocked counts, plus attention rows for the affected
  feature nodes.
- Active probe reports now include status summary counts, and transport
  `TimeoutException`s are classified as timed-out probes rather than generic
  probe errors.
- Remote shell/serve sessions now have bounded frame decoding, typed protocol
  errors, same-origin browser defaults with explicit `--allow-origin` opt-ins,
  bounded early browser-frame buffering, a private launch API boundary, and
  real shell lifecycle validation covering first paint, Space input, proxy
  teardown, terminal restore, and attached-app exit.
- `WindowsTerminalDriver` now exists as the first M2.9 native Windows slice.
  The native driver selector chooses it on Windows, enables Windows virtual
  terminal input/output console modes when available, uses Dart stdin raw-mode
  toggles, polls terminal size for resize events, and preserves terminal
  handoff semantics. Console-mode bit planning is now pure and unit-tested
  separately from the FFI adapter. `fleury diagnose` now uses the native driver
  selector, emits OS/Dart platform evidence in JSON, and terminal-matrix
  summaries carry that platform evidence for review. The launch API boundary
  now keeps Windows console-mode controller injection, bit-planning helpers,
  platform selector hooks, and raw terminal sequence builders internal while
  preserving public driver/probe/parser/test-driver extension points. Real-host
  Windows validation is deferred out of MVP while the Windows matrix preset and
  generated validation docs remain the post-MVP capture path.
- Real-terminal matrix evidence and compatibility policy are incomplete.
- [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md)
  defines the v0 capability requirement model and output-security policy.
- M1.7 is complete for the passive, env-derived MVP contract. Real-terminal
  diagnostic evidence, active probes, and policy-gated rich output opt-ins
  move to Phase 2 compatibility hardening.

## Target Capabilities

- Components declare required, preferred, and optional capabilities.
- Runtime reports terminal profile, detected capabilities, fallbacks, warnings,
  and unsupported features.
- `fleury diagnose --json` exposes machine-readable terminal information.
- `fleury diagnose --probe --json` exposes opt-in active probe evidence
  without making active terminal writes part of normal startup.
- Active probe output compares passive/env-derived support with active evidence
  so real-terminal matrix entries show agreement and mismatches explicitly.
- Native Windows sessions use a Windows-specific driver rather than the POSIX
  signal path.
- Sanitization policies cover raw ANSI, OSC 52, OSC 8, image protocols,
  markdown links, subprocess output, malformed Unicode, huge lines, and
  secret-shaped content.

## Milestone Checklist

- [x] TCS.1 Write capability requirement RFC.
  - Intent: Define how widgets request and degrade terminal features.
  - Acceptance: RFC covers color depth, mouse, keyboard protocols, clipboard,
    links, images, tmux/SSH, resize, and diagnostic output.
  - Evidence:
    [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md).
  - Notes: Capabilities should affect semantics and inspector output.

- [x] TCS.2 Write security policy v0.
  - Intent: Define safe defaults for untrusted terminal content.
  - Acceptance: Policy covers allowed, stripped, escaped, redacted, and
    opt-in behavior for control sequences and rich terminal features.
  - Evidence:
    [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md).
  - Notes: Start strict where output can perform actions.

- [x] TCS.3 Build diagnose command.
  - Intent: Make terminal quirks visible to developers and CI.
  - Acceptance: `fleury diagnose --json` reports terminal profile,
    capabilities, fallbacks, warnings, and unsupported features.
  - Evidence:
    [diagnosis model](../../../packages/fleury/lib/src/terminal/diagnostics.dart),
    [CLI diagnose wiring](../../../packages/fleury/bin/fleury.dart),
    [diagnostics tests](../../../packages/fleury/test/terminal/diagnostics_test.dart).
  - Notes: Fake-driver coverage is in place. Local Dart is now 3.12.1, so the
    earlier SDK blocker is gone. The Phase 1 exit review reran
    `dart tool/fleury_dev.dart cli diagnose --json`, which produced
    machine-readable terminal profile, capability, fallback, warning, and
    unsupported-feature output. Real-terminal matrix notes are Phase 2 work.

- [x] TCS.4 Add sanitizer test suite.
  - Intent: Prevent unsafe output regressions.
  - Acceptance: Tests cover raw ANSI, OSC 52, OSC 8, image escapes, malformed
    Unicode, huge lines, markdown links, subprocess output, and redaction
    hooks.
  - Evidence:
    [text sanitizer tests](../../../packages/fleury/test/rendering/text_sanitizer_test.dart),
    [process task tests](../../../packages/fleury/test/effects/process_task_test.dart),
    [semantic redaction tests](../../../packages/fleury/test/semantics/semantics_test.dart),
    [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart),
    [debug shell tests](../../../packages/fleury/test/debug/debug_shell_test.dart),
    [clipboard tests](../../../packages/fleury/test/runtime/clipboard_test.dart),
    [markdown link policy tests](../../../packages/fleury_widgets/test/markdown_text_test.dart),
    [image capability tests](../../../packages/fleury_widgets/test/image_test.dart),
    [DataTable export tests](../../../packages/fleury_widgets/test/data_table_test.dart),
    [SB.9 subprocess/output baseline](../../../packages/fleury_widgets/benchmark/results/phase2-subprocess-output-2026-06-01.json).
  - Notes: Coordinate with TextEditing, Data widgets, and Agent workflows.
    Current coverage includes raw control replacement in text sanitizer and
    subprocess task output sanitization/line caps. OSC 52, OSC 8, DCS/Sixel,
    APC/Kitty image payload redaction, malformed process UTF-8, markdown link
    policy, image capability semantics, DataTable sanitized export/copy,
    clipboard behavior, redacted text-control semantics, debug capture
    redaction, debug Tree-tab redaction, and the `SB.9` repeated subprocess /
    captured-output leak check are now covered for the MVP.

- [x] TCS.5 Add capability requirement resolver.
  - Intent: Turn widget/service capability intent into explicit available,
    degraded, disabled, unsupported, or unsafe states.
  - Acceptance: Required unsupported features block, preferred features degrade
    through fallbacks, prohibited features are policy-disabled, and resolutions
    can feed semantics and diagnostics.
  - Evidence:
    [capability requirements](../../../packages/fleury/lib/src/terminal/capability_requirements.dart),
    [capability requirement tests](../../../packages/fleury/test/terminal/capability_requirements_test.dart).
  - Notes: First slice is a pure model. `Image`, `MarkdownText`, clipboard
    reports, text-control copy policy, and the demo app Diagnostics screen now
    consume it for semantic fallback state. Debug inspector integration is
    covered by the M1.10 terminal diagnosis rows; richer capability browsing
    can follow in Phase 2.

- [x] TCS.6 Integrate first widget capability semantics.
  - Intent: Prove the resolver on a real first-party widget.
  - Acceptance: A widget exposes resolved capability state, active fallback,
    and protocol-specific metadata through the semantic graph without changing
    rendering behavior.
  - Evidence:
    [image widget](../../../packages/fleury_widgets/lib/src/image.dart),
    [image tests](../../../packages/fleury_widgets/test/image_test.dart).
  - Notes: `Image` proves native/glyph fallback semantics. `MarkdownText`
    proves policy-disabled OSC 8 semantics while preserving visible URL
    rendering. `TextInput` and `TextArea` now expose clipboard policy semantics,
    and the demo app Diagnostics screen shows app-shaped capability rows.

- [x] TCS.7 Add safe markdown link policy semantics.
  - Intent: Keep markdown links inspectable and safe without raw terminal
    hyperlink escapes.
  - Acceptance: Markdown links expose URL, scheme safety, OSC 8 policy,
    capability resolution, and visible URL fallback in semantics; code fences
    do not create link nodes.
  - Evidence:
    [markdown text](../../../packages/fleury_widgets/lib/src/markdown_text.dart),
    [markdown tests](../../../packages/fleury_widgets/test/markdown_text_test.dart).
  - Notes: This does not emit OSC 8. A future trusted-link mode can reuse the
    same resolver and policy surface.

- [x] TCS.8 Add clipboard policy and report semantics.
  - Intent: Make copy behavior observable without exposing users to unsafe
    clipboard transports by accident.
  - Acceptance: Clipboard writes report selected transport, capability
    resolution, policy, payload size, SSH state, OSC 52 emission, platform-tool
    attempts, and in-process fallback; text fields expose copy policy and
    redaction state through semantics.
  - Evidence:
    [clipboard runtime](../../../packages/fleury/lib/src/runtime/clipboard.dart),
    [clipboard tests](../../../packages/fleury/test/runtime/clipboard_test.dart),
    [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
  - Notes: The old `Clipboard.write()` return shape is preserved. Richer
    diagnostics use `writeWithReport`; text controls and `DataTable` copy now
    expose clipboard policy/capability semantics instead of inferring behavior
    from terminal transport alone.

- [x] TCS.9 Surface capability diagnostics in the demo app.
  - Intent: Prove the capability model in an app workflow, not only unit tests
    and individual widgets.
  - Acceptance: The demo app Diagnostics screen exposes terminal diagnosis
    summary state and per-capability semantic rows for available, degraded, and
    policy-disabled outcomes.
  - Evidence:
    [demo app diagnostics](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app tests](../../../packages/fleury_example_console/test/demo_console_test.dart).
  - Notes: The current demo screen uses deterministic `MediaQuery`-derived
    capabilities for stable tests. Real-terminal evidence remains a separate
    manual validation pass once the local Dart SDK matches package constraints.

- [~] TCS.10 Add opt-in active probe evidence.
  - Intent: Let developers collect real terminal support evidence without
    changing default app startup or passive diagnosis behavior.
  - Acceptance: Active probes are explicit, bounded by timeout, testable
    through a fake transport, represented in `diagnose --json`, and skipped
    with structured evidence when stdin/stdout are not both terminals.
  - Evidence:
    [diagnosis model](../../../packages/fleury/lib/src/terminal/diagnostics.dart),
    [terminal probe model](../../../packages/fleury/lib/src/terminal/terminal_probe.dart),
    [`fleury diagnose --probe` wiring](../../../packages/fleury/bin/fleury.dart),
    [terminal matrix tracker](../terminal-compatibility-matrix.md),
    [repo-local matrix capture command](../../../tool/fleury_dev.dart),
    [terminal probe tests](../../../packages/fleury/test/terminal/terminal_probe_test.dart),
    [terminal diagnostics tests](../../../packages/fleury/test/terminal/diagnostics_test.dart).
  - Notes: First slice probes primary device attributes as the sentinel, Kitty
    keyboard status via `CSI ? u`, and Kitty graphics query support via a
    non-displaying query action followed by DA. Second slice adds
    `TerminalCompatibilityReport`, comparing passive diagnosis against active
    probe evidence for Kitty keyboard and Kitty graphics support. Third slice
    adds the repo-local `terminal-matrix` capture workflow and matrix tracker.
    Current slice adds machine-readable review triage to every matrix entry,
    making non-interactive captures, skipped probes, inconclusive findings,
    passive-unverified features, tmux/SSH context, and active-only
    confirmations visible before entries are treated as launch evidence.
    Latest slice classifies transport `TimeoutException`s separately from
    non-timeout transport errors and includes active-probe status counts in
    raw diagnosis and compact matrix summaries. Current matrix-capture
    hardening preserves inherited stdio for `fleury diagnose` and writes JSON
    through `--json-output`, avoiding false non-interactive entries caused by a
    stdout pipe. Current platform-evidence slice adds platform JSON to
    diagnosis and compact matrix summaries. Current active-evidence slice
    exposes compatibility-confirmed feature sets and
    `TerminalDiagnosis.confirmedAvailableFeatures`, so explicit active probe
    evidence can feed `resolveCapabilityRequirement` through
    `additionalAvailableFeatures` without changing passive startup detection.
    Current audit-tooling slice adds `terminal-matrix-audit`, which summarizes
    committed entry readiness and can fail in strict mode when target labels
    lack `readyForReview` entries or invalid JSON files are present. Latest
    audit hardening accepts target-prefixed clean labels such as `iterm2-3-5`
    and context-first labels such as `tmux-kitty`, while not counting context
    captures as clean terminal coverage. Matrix summaries and audits now also
    expose fallback, warning, and unsupported-feature counts/codes so degraded
    captures are visible before hand-reviewing raw diagnosis JSON. Latest
    inspector slice renders the same compatibility finding counts and
    per-feature active/passive summaries in the debug Tree tab. Latest
    audit-planning slice adds readiness totals, `strictPass`, and a
    missing-target `collectionPlan` to `terminal-matrix-audit`, and prints
    suggested capture commands in the human audit output. This still does not
    create evidence; it only makes the external terminal collection pass more
    explicit.
    Latest audit-test slice adds black-box launcher coverage for target
    matching, tmux/SSH context-label classification, strict-mode invalid-entry
    failure, and missing-target collection-plan output. The matcher now reports
    context labels such as `tmux-kitty` as `contextToken` evidence for the tmux
    target instead of a generic target-prefix match. Current capture-context
    slice adds additive `--review-note=<text>` support to `terminal-matrix`, so
    real captures can carry terminal version, profile, tmux/SSH, and
    reviewer-context notes without hand-editing JSON or changing automatic
    review status. Current audit-readiness slice separates targets with no
    captures from targets with non-ready captures in `terminal-matrix-audit`
    JSON and human output through `nextAction`, ready/non-ready entry counts,
    `nonReadyTargetCount`, and `targetsNeedingReview`. Current collection-plan
    slice adds `terminal-matrix-audit --write-plan=<path>` and the generated
    [terminal matrix collection plan](../terminal-matrix-collection-plan.md),
    making the external capture checklist durable while keeping it generated
    from the same audit state as JSON. Current review-packet slice adds
    `terminal-matrix-audit --write-review=<path>` and the generated
    [terminal matrix review packet](../terminal-matrix-review-packet.md),
    grouping matched entries, issues, notes, terminal/platform facts, active
    probe summaries, compatibility summaries, and unmatched entries into a
    single review artifact. Current MVP-readiness slice adds
    `dart tool/fleury_dev.dart mvp-readiness` and the generated
    [MVP readiness report](../mvp-readiness-report.md), combining launch
    terminal and Windows validation evidence into one strict gate. Current
    final-gate slice adds `dart tool/fleury_dev.dart mvp-final-gate`, pairing
    a fresh local RC gate with external evidence enforcement. Current refresh
    slice adds `dart tool/fleury_dev.dart mvp-evidence-refresh`, keeping all
    generated evidence artifacts in sync after captures land. Current accepted
    review slice adds `dart tool/fleury_dev.dart terminal-matrix-accept`, so
    reviewed `needsAttention` captures can count as ready evidence without
    hand-editing JSON or hiding their original issues.
    Remaining work is reviewed real terminal matrix collection, PTY-backed
    compatibility fixtures where feasible, and platform-specific probes only
    when their latency/security behavior is understood.

- [x] TCS.11 Add native Windows terminal driver.
  - Intent: Make Windows a first-class native terminal target instead of
    accidentally running the POSIX driver path.
  - Acceptance: `runTui` chooses a Windows driver on Windows; the driver
    enables virtual terminal input/output modes, enters/restores raw input and
    screen modes, emits resize events without POSIX signals, and preserves
    handoff behavior.
  - Evidence:
    [native driver selector](../../../packages/fleury/lib/src/terminal/native_driver.dart),
    [Windows terminal driver](../../../packages/fleury/lib/src/terminal/windows_driver.dart),
    [shared terminal sequences](../../../packages/fleury/lib/src/terminal/terminal_sequences.dart),
    [native driver tests](../../../packages/fleury/test/terminal/native_driver_test.dart),
    [terminal public API boundary tests](../../../packages/fleury/test/terminal/terminal_public_api_boundary_test.dart).
  - Notes: Microsoft documents `SetConsoleMode` as the API for enabling
    virtual terminal input and output processing. This slice wires those flags
    through Dart FFI without adding them to app startup on non-Windows hosts.
    Current hardening extracts pure console-mode planning so flag changes are
    testable without a Windows host, and includes delayed newline auto-return
    with VT output to better match terminal-emulator final-column behavior.
    `fleury diagnose` now routes through the native driver selector and emits
    platform evidence for later Windows matrix captures. The planner is tested
    for interactive mode, raw-input opt-out, already-enabled modes, and
    unavailable handles. Current API-boundary hardening removes public
    console-mode controller injection from `WindowsTerminalDriver`, adds
    terminal public API boundary tests, and keeps the pure planner/controller
    surface test-owned. Current Windows validation-planning slice adds
    `terminal-matrix-audit --target-preset=windows`, plus the generated
    [Windows validation plan](../windows-validation-plan.md) and
    [Windows validation review packet](../windows-validation-review-packet.md)
    for Windows Terminal, conhost, PowerShell, and Windows IDE terminal
    captures. Real Windows validation is post-MVP and is no longer a strict
    MVP readiness blocker.

## Implementation Notes

- Capability handling is product surface: developers should understand why a
  widget degraded.
- Security policy must compose with theme, renderer, markdown, logs, code,
  diffs, and subprocess output.
- Treat terminal output as active content.
- Current code already has useful raw ingredients: `TerminalCapabilities`,
  `TerminalMode`, `PosixTerminalDriver`, `sanitizeForDisplay`,
  `OutputCapture`, `Clipboard`, protocol cells, image protocol rendering,
  markdown link fallback, and a human-readable `fleury diagnose`.
- RFC 0013 keeps these pieces and adds the missing contract: capability
  requirements, resolution/fallback state, JSON diagnostics, trust levels,
  policy-gated OSC 52/OSC 8/native images, restricted ANSI parsing, huge-line
  handling, malformed Unicode behavior, and redaction hooks.
- `TaskOutput` carries `sanitized`, `truncated`, and `originalLength` metadata
  so status surfaces, semantic graph, inspector, and future replay/debug
  artifacts can explain when output was changed before display/storage.
- `sanitizeForDisplay` collapses active terminal sequences as units. CSI style
  controls, OSC 52 clipboard payloads, OSC 8 hyperlink targets, DCS/Sixel
  payloads, and APC/Kitty graphics payloads are represented by one visible
  replacement glyph rather than leaking their printable payload after the
  leading control byte is stripped.
- Native process output uses a malformed-tolerant UTF-8 decoder by default so
  bad subprocess bytes become visible replacement characters instead of failing
  the task.
- The default diagnosis model remains passive: it reports static/env-derived
  capabilities through `TerminalDriver`. Active probes are now available only
  through `fleury diagnose --probe`, where their latency and terminal writes
  are explicit developer choices.
- Active probe evidence now creates a compatibility report, but it still does
  not change startup capabilities by default. Compatibility-confirmed features
  are exposed as an explicit set that apps/tests can pass as
  `additionalAvailableFeatures` when resolving a capability requirement.
- The `script(1)` pseudo-terminal fixture in `terminal_probe_test.dart` is a
  transport smoke test, not real terminal-emulator evidence. It proves the
  active probe suite can write/read through a PTY-shaped subprocess boundary
  when available while keeping launch compatibility claims tied to reviewed
  matrix entries.
- Matrix entries are internal evidence artifacts. Review labels, tmux/SSH
  context, and passive-unverified findings before committing generated JSON.
- Matrix audits are readiness gates, not compatibility evidence by themselves:
  they can prove whether collected entries are present and reviewed, but they
  cannot replace captures from the actual terminal emulators named in the
  launch matrix.
- Windows driver validation should become part of the terminal matrix rather
  than relying on macOS analyzer coverage. The current macOS tests prove
  platform selection, off-Windows FFI no-op behavior, and pure console-mode
  flag planning only.
- The terminal launch API intentionally exposes extension points developers can
  build against: `TerminalDriver`, `TerminalMode`, `TerminalHandoffDriver`,
  native driver construction, `InputParser`, `TuiEventSink`,
  `TerminalProbeTransport`, `runTerminalProbeSuite`, and
  `FakeTerminalDriver`. Windows FFI adapters, console-mode controllers,
  platform selector hooks, and raw enter/exit sequence builders stay internal
  until real platform evidence proves a public contract is needed.
  `FakeTerminalDriver` now treats `dispose` as a terminal lifecycle boundary:
  final output, size, mode, and call-count state stay inspectable, while new
  writes, resize/enqueue calls, terminal handoffs, enter calls, and
  `isInteractive` mutation after disposal fail explicitly.
- Capability resolution currently uses the lightweight `TerminalCapabilities`
  summary plus explicit `additionalAvailableFeatures`, `policyBlockedFeatures`,
  and `unsafeFeatures` sets. That keeps v0 testable while leaving room for a
  richer terminal profile report later.
- Widget integration should preserve render behavior first and add semantic
  evidence around it. The image slice follows that rule: no renderer path
  changes, only explicit capability/fallback state.
- Markdown link policy follows the same rule: rendered output remains visible
  text plus URL, while semantic state explains why OSC 8 is not used.
- Clipboard policy now has two related but distinct surfaces: runtime write
  reports for actual transport/fallback decisions, and text-control semantics
  for whether a field allows, redacts, or disables copy/cut.
- Redaction flags are data contracts, not widget-only hints. Debug capture,
  inspector summaries, and future adapter surfaces must consume
  `redactedValue`, `obscureText`, and `clipboardRedacted` before displaying
  semantic values, validation errors, query strings, or token-shaped state.
- The demo app Diagnostics screen should stay deterministic enough for tests
  while still exercising the same resolver and diagnosis types that real app
  diagnostics will use.

## Risks And Open Questions

- Active probing can be slow or intrusive.
- Active probe results can differ under tmux, SSH, nested terminals, and IDE
  consoles; matrix evidence needs to record the outer terminal and transport.
- Passive/active mismatches are evidence, not automatic runtime overrides.
  Promote confirmed probe features into runtime summaries only after the
  terminal matrix shows stable behavior.
- Terminal behavior differs under SSH and tmux.
- Windows behavior differs across Windows Terminal, conhost, PowerShell hosts,
  IDE terminals, SSH, and WSL handoff contexts; this remains a post-MVP
  validation risk rather than an MVP gate.
- Strict security defaults may surprise local-only apps unless opt-ins are
  clear.

## Acceptance Evidence

- [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md).
- [Terminal diagnosis model](../../../packages/fleury/lib/src/terminal/diagnostics.dart).
- [`fleury diagnose --json` wiring](../../../packages/fleury/bin/fleury.dart).
- [Terminal diagnostics tests](../../../packages/fleury/test/terminal/diagnostics_test.dart).
- [Capability requirement resolver](../../../packages/fleury/lib/src/terminal/capability_requirements.dart).
- [Capability requirement tests](../../../packages/fleury/test/terminal/capability_requirements_test.dart).
- [Image capability semantics](../../../packages/fleury_widgets/lib/src/image.dart).
- [Image capability tests](../../../packages/fleury_widgets/test/image_test.dart).
- [Markdown link policy semantics](../../../packages/fleury_widgets/lib/src/markdown_text.dart).
- [Markdown link policy tests](../../../packages/fleury_widgets/test/markdown_text_test.dart).
- [Clipboard write reports](../../../packages/fleury/lib/src/runtime/clipboard.dart).
- [Clipboard report tests](../../../packages/fleury/test/runtime/clipboard_test.dart).
- [Text clipboard semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
- [Demo app Diagnostics screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Diagnostics tests](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [Text sanitizer tests](../../../packages/fleury/test/rendering/text_sanitizer_test.dart).
- [Process task sanitizer tests](../../../packages/fleury/test/effects/process_task_test.dart).
- [Semantic redaction tests](../../../packages/fleury/test/semantics/semantics_test.dart).
- [Debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
- [Debug shell tests](../../../packages/fleury/test/debug/debug_shell_test.dart).
- [Terminal probe model](../../../packages/fleury/lib/src/terminal/terminal_probe.dart).
- [Terminal probe tests](../../../packages/fleury/test/terminal/terminal_probe_test.dart).
- [Terminal compatibility matrix tracker](../terminal-compatibility-matrix.md).
- [Repo-local matrix capture command](../../../tool/fleury_dev.dart).
- [Native driver selector](../../../packages/fleury/lib/src/terminal/native_driver.dart).
- [Windows terminal driver](../../../packages/fleury/lib/src/terminal/windows_driver.dart).
- [Native driver tests](../../../packages/fleury/test/terminal/native_driver_test.dart).
- [Remote protocol tests](../../../packages/fleury/test/remote/remote_protocol_test.dart).
- [Remote driver tests](../../../packages/fleury/test/remote/remote_driver_test.dart).
- [Serve integration tests](../../../packages/fleury/test/remote/serve_integration_test.dart).
- [Serve spawn tests](../../../packages/fleury/test/remote/serve_spawn_test.dart).
- [Shell lifecycle tests](../../../packages/fleury/test/remote/shell_lifecycle_test.dart).
- Phase 1 passive diagnosis evidence is complete; Phase 2 now has an opt-in
  active probe path, passive/active compatibility comparison, a matrix capture
  workflow, a PTY-shaped active-probe fixture, and the first native Windows
  driver slice. Reviewed non-Windows real-terminal diagnose matrix evidence is
  still pending for MVP; real Windows host evidence is post-MVP.
