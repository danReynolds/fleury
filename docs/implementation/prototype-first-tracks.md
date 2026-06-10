# Fleury Prototype-First Tracks

**Status:** Phase 0 definition complete  
**Milestone:** M0.7 Prototype-first tracks for progressive modes, replay, and
effects  
**Owner:** Shared across semantic app graph, app kernel, effects/workflow,
replay/devtools/testing, terminal capability/security, and the example
subpackage demo app.

## Purpose

Some ideas are strategically important but too easy to over-design before
Fleury has real app pressure. This document defines the narrow prototypes that
replace broad Phase 0 RFCs for:

- Progressive interaction modes.
- Debug capture and future replay.
- Effects, workers, and process workflows.

The goal is to preserve architectural room without freezing APIs too early.
Each track must prove one concrete scenario first. Surviving patterns can
become RFCs later.

## Current State

- [RFC 0011: Semantic app graph](../rfcs/0011-semantic-app-graph.md) creates
  the meaning layer that progressive modes and debug capture can share.
- [RFC 0012: App kernel](../rfcs/0012-app-kernel.md) defines commands, screens,
  status, and lifecycle, but intentionally keeps worker/process/effects as an
  adjacent milestone.
- [RFC 0013: Capability and security contract](../rfcs/0013-capability-security-contract.md)
  defines capability and output-safety state that debug capture, subprocess
  output, and future replay must respect.
- [Demo-app scenario](demo-app-scenario.md) defines the Phase 1 app pressure:
  screens, commands, composer input, data table, logs/output, diagnostics,
  selection, and debug capture.
- [Scope cut list](cut-list.md) explicitly cuts full progressive-mode and full
  replay RFCs from Phase 0.

## Prototype Rules

- Prototype against the example subpackage and Phase 1 primitives.
- Keep APIs internal or experimental until the demo app uses them twice.
- Prefer semantic assertions over rendered-cell assertions for behavior.
- Capture enough data to write a regression test; do not require shareable
  replay artifacts in Phase 1.
- Keep terminal safety and redaction before display, copy, debug capture, or
  future replay artifact writing.
- Write down what the prototype disproves, not only what works.
- Delete failed experiments instead of preserving compatibility with them.

## Track A: Progressive Interaction Modes

### Question

Can one workflow definition project into a full-screen surface and a
non-full-screen fallback without building two separate apps?

### Narrow Prototype Scenario

Build one deterministic **connection setup form** inside the example
subpackage:

- Fields: project name, environment select, region select, API key/password,
  confirm checkbox, and submit/cancel actions.
- Full-screen projection: normal Fleury widgets inside the demo app.
- Prompt projection: sequential prompt-style fallback driven by the same field
  definitions, validation, labels, defaults, and submit result.
- Test projection: semantic tester can fill fields and submit without relying
  on cell positions.

This is not a full forms framework. It is one workflow proving whether the
shared model is viable.

### Acceptance Evidence

- [x] One source workflow definition feeds both full-screen and prompt-mode
  projections.
- [x] Validation, required fields, password/secret policy, submit, cancel, and
  error state behave consistently in both projections.
- [x] Semantic nodes expose label, value/redacted value, required state, validation
  error, focus, and submit/cancel actions.
- [x] A test can run the workflow without a real terminal.
- [x] The prototype records which parts feel reusable and which should remain
  app-local.

### Implementation Evidence

- `FormDefinition`, `FormController`, `FormPanel`, and `FormPromptSession` now
  live in `fleury_widgets`.
- The demo app Connection screen uses the shared connection setup definition
  as a full-screen projection.
- `test/form_test.dart` covers full-screen semantics, inline layout semantics,
  required-field validation, redacted secret values, valid submit, and
  prompt-mode progression, plus shared number/date field parsing, bounds,
  snapshots, visual projections, and accessibility output.
- `demo_console_test.dart` covers demo-app navigation to the Connection
  screen, semantic form state, typed number/date field state, redacted API-key
  field state, keyboard filling, submit, and transcript feedback.

### Do Not Freeze Yet

- Public `Form` or `FormField<T>` API.
- Full field catalog.
- Wizard/page-flow API.
- Remote/browser projection.
- Accessibility claims beyond semantic state and prompt fallback.

### Phase 1 Hand-Off

If successful, feed the minimum shared field/value/validation shape into
M1.1 semantic tree, M1.2 text editing, M1.3 `FleuryApp`, and later M2.1 forms
framework work.

## Track B: Debug Capture And Future Replay

### Question

What is the minimum structured capture that lets a difficult TUI bug become a
regression test without promising full replay artifacts?

### Narrow Prototype Scenario

Capture a demo-app interaction around a flaky layout or workflow edge:

- Start demo app.
- Navigate to Runs.
- Resize from `80x24` to `120x40`.
- Start a fake worker.
- Append log output.
- Open command palette.
- Cancel worker.
- Capture debug snapshot.

The capture should include structured records only where useful.

### Acceptance Evidence

- Capture includes input events, resize events, fake time markers, active
  screen, focused semantic node, command registry snapshot, worker state,
  terminal profile, frame metadata, semantic snapshot, and sanitized output
  summary.
- Capture excludes secrets or records redacted values before writing.
- A developer can use the capture to write a targeted regression test.
- Capture size is bounded and does not include every frame by default.
- The prototype identifies which fields are stable enough for Phase 1 hook
  points.

### Do Not Freeze Yet

- Shareable replay artifact format.
- Full deterministic replay runner.
- Persistent timeline database.
- Browser/devtools protocol.
- Cross-version replay compatibility.

### Phase 1 Hand-Off

If successful, implement targeted hook points in RDT.2 and expose them in the
debug inspector work. Full replay can remain Phase 2 or Phase 3 unless the
demo app exposes bugs that require it earlier.

## Track C: Structured Effects And Workers

### Question

Can Fleury make async work observable, cancellable, testable, and safe without
making simple app code heavy?

### Narrow Prototype Scenario

Build one deterministic **fake task worker** used by the example subpackage:

- Emits progress from 0 to 100.
- Streams sanitized log chunks.
- Produces success, failure, and cancellation outcomes.
- Supports command actions: start, cancel, retry, copy output.
- Updates app status and semantic graph.
- Can be driven with fake time in tests.

This is not the full process runner or shell API.

### Acceptance Evidence

- Worker state is visible through app status, semantic nodes, and debug
  capture.
- Tests cover success, failure, cancellation, output ordering, and fake-time
  progress.
- Cancellation is deterministic and cleans up owned resources.
- Output passes through the sanitized output policy before display, copy, or
  debug capture.
- The API shape does not force every command to become async-heavy.

### Do Not Freeze Yet

- Public subprocess API.
- Process shell DSL.
- Permission/approval framework.
- Durable effect-log schema.
- Cross-isolate worker model.

### Phase 1 Hand-Off

If successful, feed the smallest useful state model into M1.6 worker/task
model, M1.10 debug inspector, M1.11 sanitized output pipeline, and the
demo-app journey scenario.

## Track D: Subprocess Handoff Boundary

### Question

What terminal lifecycle guarantees are mandatory before Fleury allows real
subprocess or external-editor handoff APIs?

### Narrow Prototype Scenario

Use fake-driver tests plus a minimal local process fixture:

- Suspend raw/mouse/alternate-screen state.
- Run a bounded command that writes stdout and stderr.
- Cancel it.
- Restore terminal state.
- Repeat for external-editor handoff shape without committing to editor API.

### Acceptance Evidence

- Terminal modes restore on success, failure, cancellation, and thrown errors.
- Captured output is clearly separated from framework frames.
- Unsafe output sequences are blocked or policy-gated.
- Debug capture records the handoff boundary without storing secrets.

### Do Not Freeze Yet

- Public process API.
- Shell quoting helpers.
- External editor integration API.
- PTY/session-management abstractions.

### Phase 1 Hand-Off

If successful, feed terminal restoration requirements into EWP.3 and
capability/security tests. If it proves larger than expected, keep only fake
worker output in Phase 1 and defer real process depth.

## Evidence Checklist

- [x] Progressive modes have one narrow prototype scenario.
- [x] Debug capture/future replay has one narrow prototype scenario.
- [x] Effects/workers have one narrow prototype scenario.
- [x] Subprocess handoff has a boundary prototype scenario.
- [x] Each track records acceptance evidence.
- [x] Each track explicitly lists APIs not to freeze yet.
- [x] Each track names Phase 1 hand-off work.

## Open Questions

- Should the progressive form prototype live in the example subpackage only,
  or should the smallest field model start inside core behind an experimental
  namespace?
- Should debug capture be a `FleuryTester` feature first or an in-app
  inspector action first?
- Should the fake worker API use a controller object, a declarative widget, or
  app-kernel services for v0?
- How much real subprocess behavior should be included before DataTable and
  text editing are stable?

## Stop Conditions

Stop a prototype and defer it if:

- It needs broad public API to prove the scenario.
- It blocks semantic tree, app shell, text editing, DataTable, or the example
  demo app.
- It requires full replay artifacts to be useful.
- It weakens strict defaults for untrusted output.
- It becomes a substitute for Phase 1 implementation rather than a de-risking
  slice.
