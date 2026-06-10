# Workstream: `fleury_acp` Fast-Follow Package

## Purpose

Define the optional fast-follow `fleury_acp` package that can add ACP
transport, protocol models, and ACP-specific widgets after Fleury launch
without coupling Fleury core to ACP.

## Current State

- Fleury has core TUI primitives that agent apps need: widgets, focus,
  key bindings, navigation, overlays, markdown, tables, trees, output capture,
  debug shell, and testing.
- Fleury launch is intentionally scoped to protocol-neutral foundations:
  semantics, commands/actions, effects, terminal output regions, selection,
  markdown/log/diff/data surfaces, replay hooks, and capability/security
  policy.
- [Agent adapter boundary](../agent-adapter-boundary.md) defines the launch
  readiness contract and the `fleury_acp` fast-follow package boundary.
- [Agent adapter readiness audit](../agent-adapter-readiness-audit.md)
  confirms Fleury launch surfaces are sufficient for a fast-follow adapter
  without adding ACP concepts to core.
- ACP-specific transport, schema handling, protocol models, and widgets are
  out of scope for Fleury launch.
- Dune/`dune_cli` is the later flagship app and may consume `fleury_acp` if
  ACP proves necessary after the core launch.

## Target Capabilities

- `fleury_acp` owns ACP JSON-RPC transport, schema/version handling,
  sessions, prompt turns, tool calls, permission requests, diffs, terminal
  output, progress, plans, cancellation, and replay fixtures.
- ACP-specific widgets live in `fleury_acp`, not `fleury` launch scope.
- `fleury_acp` maps ACP protocol objects into protocol-neutral Fleury
  semantics, commands/actions, effects, output regions, and replay hooks.
- `fleury_acp` depends on Fleury foundations; Fleury core does not import ACP
  schemas or JSON-RPC concepts.
- Dune/`dune_cli` can validate `fleury_acp` only after the launch foundations
  are stable enough to support a fast-follow package.

## Milestone Checklist

- [x] ACP.1 Define launch adapter-readiness requirements.
  - Intent: Specify what Fleury launch must provide so `fleury_acp` can be
    built cleanly later.
  - Acceptance: Requirements cover semantics, commands/actions, effects,
    output regions, replay hooks, selection/copy, capability/security policy,
    and general markdown/log/diff/data widgets.
  - Evidence: [Agent adapter boundary](../agent-adapter-boundary.md).
  - Notes: This is the only ACP-related launch requirement.

- [x] ACP.2 Define `fleury_acp` package boundary.
  - Intent: Keep ACP transport, schemas, protocol models, and widgets out of
    Fleury core.
  - Acceptance: Boundary identifies package dependencies, public model
    mapping, replay fixture ownership, testing strategy, and what stays
    protocol-neutral in Fleury.
  - Evidence: [Agent adapter boundary](../agent-adapter-boundary.md).
  - Notes: Core should never import ACP schemas or JSON-RPC transport types.

- [ ] ACP.3 Build `fleury_acp` v0 after Fleury launch foundations stabilize.
  - Intent: Ship ACP support as a fast-follow optional package.
  - Acceptance: Package maps ACP sessions, prompt turns, tool calls,
    permissions, diffs, terminal output, progress, and cancellation into
    Fleury UI and semantic state.
  - Evidence: Pending.
  - Notes: This should not block Fleury launch.

- [ ] ACP.4 Add ACP-specific widgets and replay fixtures.
  - Intent: Make agent workflow bugs reproducible.
  - Acceptance: ACP package includes message list, tool call cards, approval
    prompts, conversation navigation, and replay fixtures for prompt-turn
    scenarios.
  - Evidence: Pending.
  - Notes: Keep reusable widgets in `fleury_widgets` only when they are useful
    outside ACP.

## Implementation Notes

- Fleury launch should be agent-adapter ready, not ACP-native.
- `fleury_acp` should prove the extension model: domain packages can add deep
  protocol workflows without bloating core.
- If a widget is only meaningful in ACP terms, put it in `fleury_acp`.
- If a widget is broadly useful, such as markdown, logs, diffs, code, progress,
  or terminal output, keep it in `fleury_widgets` or core as appropriate.
- [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md)
  is the boundary `fleury_acp` should use for terminal output, clipboard,
  links, images, subprocess/tool logs, redaction, and capability fallbacks.
- [Agent adapter boundary](../agent-adapter-boundary.md) maps ACP sessions,
  prompt turns, plans, tool calls, permissions, terminal output, cancellation,
  and replay fixtures onto Fleury's protocol-neutral surfaces.
- M1.5 is closed for launch scope. `fleury_acp` can start later from this
  boundary once the example demo app and public API shape are stable enough.

## Risks And Open Questions

- ACP could change or lose momentum.
- `fleury_acp` could leak protocol concepts back into Fleury core.
- Dune/`dune_cli` timing may lag framework launch, which is acceptable because
  the current cycle uses an example subpackage first.
- The package split could duplicate widgets unless ownership is clear.

## Acceptance Evidence

- [Agent adapter boundary](../agent-adapter-boundary.md).
- [Agent adapter readiness audit](../agent-adapter-readiness-audit.md).
- Pending fast-follow implementation.
