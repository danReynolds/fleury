# Fleury Scope Cut List

**Status:** Planning guardrail  
**Purpose:** Keep the roadmap honest if team size or schedule is smaller than
the ambition.

## Team Size Assumptions

The roadmap is ambitious. If Fleury has fewer than three focused engineers,
Phase 1 must be narrowed aggressively.

## Phase 0 Cuts

Keep:

- Example subpackage proof-app scenario spec.
- Semantic app graph RFC.
- App kernel RFC.
- Capability/security contract RFC.
- Peer scorecard skeleton.

Cut or prototype instead of RFC:

- Full progressive mode RFC.
- Full replay log RFC.
- Full security policy expansion beyond the capability/security contract.
- Broad adoption assets beyond internal positioning notes.

## Phase 1 If 1-2 Engineers

Keep:

- Semantic tree v0.
- `FleuryApp` shell and command registry.
- Text editing v2 core.
- DataTable v1 and a narrow agent-adapter readiness boundary.
- Example subpackage scenario slice that proves the chosen wedge.
- Basic benchmark harness.
- Debug capture hook points only where they are needed by tests or the example
  proof app.

Defer:

- Full replay prototype and shareable replay artifacts.
- Broad worker/process model.
- Full `fleury diagnose`.
- Large widget suite expansion.
- Public docs site and distribution polish.
- Windows driver.

## Phase 1 If 3-4 Engineers

Keep:

- Semantic tree v0.
- Text editing v2.
- `FleuryApp` shell.
- DataTable v1.
- Agent-adapter readiness boundary.
- Worker/task model v0.
- Basic diagnose command.
- Example subpackage proof app v0.
- Scenario benchmark harness.

Defer:

- Full replay and shareable replay artifacts.
- Broad real-terminal matrix.
- Full adoption/public launch push.
- Plugin/extension story.

## Phase 1 If 5+ Engineers

Keep the full Phase 1 plan, but still avoid:

- Seven-engine package split.
- Broad plugin ecosystem.
- Public launch before the example proof app and benchmark claims are
  credible.
- Full accessibility claims beyond semantic state, keyboard operation, copy
  state, high contrast, reduced motion, and prompt fallback.

## Cut Order Within Phase 1

If schedule slips, cut in this order:

1. Public adoption assets.
2. Shareable replay artifacts.
3. Broad terminal compatibility matrix.
4. Full worker/process model depth.
5. Data widget breadth beyond DataTable.
6. Domain/protocol widget breadth beyond the example proof-app scenario.
7. Diagnostics polish.

Do not cut:

- Semantic tree v0.
- App kernel.
- Text editing core.
- Example proof-app slice.
- Benchmark harness.
