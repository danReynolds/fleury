# Agent-driving guide DX audit — 2026-09-21

## Outcome

The underlying MCP path works end to end, but the old guide taught the wrong
starting point. It opened with manually authored `Semantics` nodes even though
ordinary Fleury controls already expose the roles, labels, values, and actions
an agent needs. The rewritten guide now starts with one normal release workflow,
runs that same widget in the browser, and proves the complete flow through the
real MCP bridge.

The follow-through pass includes MCP-layer changes where the guide exposed a
clear protocol or round-trip defect: stateless positional target references,
modern protocol discovery/envelopes, strict tool metadata, and corrected
post-action guidance. Widget identity, compact projection, and launcher design
remain separate decisions below.

## MCP reassessment and framework follow-through

The original server targeted `2025-06-18`. MCP `2026-07-28` removed the
connection-scoped initialization model: each request now names its protocol and
capabilities, `server/discover` advertises the server, and cross-call state must
travel as an explicit handle. Fleury's `_lastServedNodes` cache was therefore a
correctness risk for interleaved agent tasks even though it protected a single
legacy session from positional retargeting.

The server now:

- supports `server/discover` and current stateless result envelopes while
  retaining the existing initialization path for legacy hosts;
- returns an opaque `targetRef` with every actionable positional node and
  requires current-protocol callers to echo it with `invoke_action` or
  `set_value`;
- keeps the old last-read fallback only for legacy calls, so compatibility does
  not define the modern architecture;
- advertises strict input schemas, baseline object output schemas, tool titles,
  and conservative read/mutation annotations;
- requires the last opaque, instance-scoped `uiRevision` when a current client
  calls `wait_for_change`, closing the lost-update window between a read and
  wait while rejecting handles from an earlier server instance;
- withholds the focus-relative `type_text` and `press_key` tools from stateless
  discovery until their requests can carry an explicit target or focus lease;
- treats resource subscription and protocol logging as legacy-only features;
  `wait_for_change` and explicit debug tools remain the current portable path.

Protocol tests cover discovery, unsupported-version reporting, modern response
metadata, explicit-reference independence from unrelated reads, and stale
reference rejection. Official MCP conformance-suite qualification is still a
release gate, not implied by those local tests.

## Evidence gathered

- `dart test test/mcp_showcase_e2e_test.dart --reporter expanded` passed the
  existing five real-sample MCP cases before the rewrite.
- A direct stdio session successfully initialized `fleury_mcp`, attached to the
  Forms sample, read the UI with `get_ui`, and narrowed it with `find_nodes`.
- The Forms sample's first full read reported 61 nodes: 44 text nodes and 17
  actions. Much of the payload was visual fallback material, including repeated
  panel borders. `find_nodes(role: "button")` returned the one actionable node
  much more economically.
- The guide example uses ordinary `TextInput`, `Checkbox`, and `Button`
  controls. An MCP integration test selects each next target from the settled
  UI returned by the previous action and verifies that `set_value` +
  `invoke_action` completes the workflow.
- An initial test put `ValueKey`s on all three controls and asserted durable
  MCP identity. It failed: the nested semantic target still reported a
  positional `auto:...` id and `stableId: false`.
- The docs browser test mounted the guide example at its declared 46×15 frame,
  typed `1.0.0`, toggled the semantic checkbox, activated the semantic button,
  and observed `Ready to publish 1.0.0`. A rendered preview pass confirmed the
  split code/demo layout and the same visible interaction.

## DX findings

### 1. The default teaching path overstated manual semantics work

The old counter built its button by hand with `Semantics`, a role, an action,
and an action handler. That contradicted the adjacent promise that an existing
Fleury app needs no MCP code. Manual semantics belong under custom controls,
after ordinary controls have demonstrated the zero-integration path.

**Guide resolution:** fixed in the rewrite.

### 2. Full-tree discovery is noisy for visually framed apps

`get_ui` is faithful to the presented semantic tree, including text-coverage
fallback nodes. In a framed application, that can spend a large part of the
first model read on border glyphs and duplicated visual labels. The server's
node cap prevents an unbounded response, but it does not make the first read
high-signal.

**Framework candidate:** add a compact agent projection that omits
`semanticFallback` nodes with no interactive or structural value, while keeping
the complete tree available for accessibility/debug consumers. An explicit
`get_ui(compact: true)` is safer than globally weakening semantic coverage.

### 3. First-party controls cannot request a durable semantic id

A public widget `Key` identifies the control's widget element, but the semantic
contributor is currently nested below it through unkeyed internal elements. As
a result, putting a `ValueKey` on `TextInput`, `Checkbox`, or `Button` does not
make the returned MCP target durable. Wrapping the control in another
`Semantics` node would either duplicate the contract or require the application
to rebuild semantics that the control already knows.

**Framework candidate:** add a semantic identity surface to first-party
controls, or derive the nested semantic node's stable id from the keyed public
control. Either design needs reconciliation tests proving that ids survive
ordinary rebuilds and never retarget a different logical control.

**Current mitigation:** shipped at the MCP boundary. Positional nodes now carry
an explicit opaque `targetRef`, so the safety contract no longer depends on one
connection-global "last read" snapshot and detectable replacement tokens fail
closed. Semantically identical unkeyed replacements remain indistinguishable,
so this does not make the id durable or remove the first-party identity API gap.

### 4. Pre-release installation is the roughest setup step

While packages are unpublished, the reliable executable comes from a matching
Fleury checkout and a path activation. The final user experience should be an
app-local dev dependency or one discoverable `fleury mcp -- <app>` command that
cannot drift from the framework wire version.

**Product/tooling candidate:** decide whether the separate executable remains
the public entry point or the main `fleury` CLI delegates to its matching MCP
package. Do not add a second launcher until publication/version ownership is
settled.

### 5. The post-action result and `get_ui` description disagree

Every mutating tool returns the settled `ui` and records it as the agent's fresh
positional-target baseline. That lets an agent chain the guide workflow without
an extra `get_ui` call after every mutation. However, the current `get_ui` tool
description says to call it "after each action," which teaches a redundant
round trip and hides the stronger action-result contract.

**Framework/tooling candidate:** revise the MCP tool copy so `get_ui` is the
initial read, while action results are the normal subsequent reads. Keep
`find_nodes` as the compact follow-up when a capped tree omits the desired node.

**Resolution:** implemented in the tool description, server instructions,
package README, and guide.

### 6. The tool split is good once the reader sees one workflow

`set_value` handles fields and checkboxes without focus choreography;
`invoke_action` handles the button; `find_nodes` keeps targeted reads small;
and machine-readable error codes make recovery explicit. The old guide listed
these before giving them a job, which made a coherent interaction contract feel
like a large API inventory.

**Guide resolution:** the rewrite teaches the release task first and moves the
tool reference behind it.

## Recommended next decision

Next, design the first-party semantic identity surface as a separate framework
change: the failed keyed-control assertion is direct evidence that the current
API is insufficient. Measure a compact MCP projection separately against larger
framed apps, keep CLI consolidation independent of both changes, and run the
official MCP conformance suite before claiming release-level `2026-07-28`
qualification. An MCP App rendering the live Fleury surface beside the
conversation is worth a later oversight experiment, not part of the driving
contract.
