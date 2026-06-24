# RFC: Stable semantic node identity + parameterized `setValue`

**Status:** Draft / Proposed (2026-06-24)
**Owner:** Semantic app graph, core widgets, `fleury_mcp` (and the future
`fleury_acp`).
**Related:** [Agent adapter boundary](agent-adapter-boundary.md);
[`fleury_mcp` PR #19](https://github.com/danReynolds/fleury/pull/19);
[decision log](decision-log.md).

## Summary

Two core changes to the semantic layer, surfaced while building the MCP server
and a [code review](https://github.com/danReynolds/fleury/pull/19) of it, then
pressure-tested against prior art:

1. **Identity** — replace auto-generated `SemanticNodeId('element-$hashCode')`
   with **key-derived ids** (fold the nearest ancestor widget `Key` chain),
   falling back to a **role-qualified structural path anchored at the nearest
   keyed ancestor**. Pair durable ids with a **structure-generation stamp**
   (bumped only on tree-shape changes) so a stale *structural* reference *fails
   safely* instead of silently driving the wrong node.

2. **Actions with a payload** — give `SemanticAction` an optional argument so a
   first-class **`setValue`** action can carry the value to set, generalizing to
   text fields, sliders, selects, and date pickers.

Both are deliberately *out of scope* for the `fleury_mcp` package: they touch
the core action contract and the id generator, which serve tests, accessibility,
`fleury serve`, and any future `fleury_acp` — so they belong here, reviewed on
their own merits.

## Motivation

The MCP server reads a node id in `get_ui` and reuses it in a later
`invoke_action`. Two seams showed up where "a layer built for one-way inspection
and accessibility" meets "a layer an external agent operates and holds
references into":

- **`element-$hashCode` ids are not a durable handle.** They are stable per
  element *instance* within a session, but any rebuild that mints a new element
  (a recycled list row, a recreated widget) churns the id; they carry no
  meaning; they vary per run. The code review found the concrete failure
  (finding #6): a stale id that still resolves but now denotes a *different*
  logical node is acted on silently. We patched it with ambiguity-rejection and
  a "re-read get_ui" hint, but the underlying id model is the problem.

- **Text/value entry has no semantic verb.** The 16 `SemanticAction`s cover
  `focus`/`activate`/`select`/`submit`/… but not "set this field to *X*". Text
  goes through raw `TextInputEvent` keystrokes — the one place the agent must
  drop below *meaning* to *input events*.

## Prior art (researched, cited)

A [deep-research pass](https://github.com/danReynolds/fleury/pull/19) (25 claims
verified, 0 refuted; primary vendor + peer-reviewed sources) established:

- **Two-tier "explicit key, else structural" is the established pattern.** Keys
  survive reorder (Flutter matches children by `type + key`; `GlobalKey`
  reparents the element + subtree —
  [Inside Flutter](https://docs.flutter.dev/resources/inside-flutter)). The
  identity contract everyone converges on is *stable-over-time **and**
  unique-per-node*; SwiftUI states it almost verbatim — *"a new identifier
  represents a new item with a new lifetime"*, *"each identifier should map to a
  single view"* ([WWDC21 #10022](https://developer.apple.com/videos/play/wwdc2021/10022/)).
  Content-addressing (id derived from value) is explicitly the wrong move.

- **UI Automation already names our exact split, almost 1:1:**
  - **`RuntimeId`** is ephemeral, opaque, *"reused over time"*, *"used only for
    comparison"*, and must **not** be stored
    ([RuntimeId](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationelement-getruntimeid)).
    **This is exactly `element-$hashCode`.**
  - **`AutomationId`** is durable, author-assigned, inspect-once/reuse-later —
    **exactly the key-derived id** — but is *only sibling-unique*, so you
    disambiguate by walking *"a parent and, if necessary, a grandparent"*
    ([AutomationId](https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/use-the-automationid-property)).
    This validates folding the ancestor key-chain *and* keeping a structural
    tiebreak.

- **Absolute structural paths are the brittle edge**, and the closest production
  analog to our system does not rely on cross-frame stable ids at all.
  Playwright says *"CSS and XPath are not recommended as the DOM can often
  change"*; role/test-id are *"the most resilient"*
  ([locators](https://playwright.dev/docs/locators)). **Playwright's own MCP
  server** re-snapshots each step with **ephemeral refs** (`e1, e2, …`,
  renumbered whenever the DOM changes —
  [MCP snapshots](https://playwright.dev/mcp/snapshots)); LLM-agent benchmarks
  do the same (WebArena assigns ids *"when traversing the … accessibility
  tree"* — [WebArena](https://webarena.dev/static/paper.pdf)); and the hardened
  variant attaches a **snapshot version** to each ref so that *"if the versions
  mismatch, the action fails safely"*
  ([arXiv 2511.19477](https://arxiv.org/html/2511.19477v1)).

- **Parameterized value-setting is universal in accessibility APIs** — UIA
  `IValueProvider::SetValue`
  ([UIA](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-ivalueprovider-setvalue)),
  Android `ACTION_SET_TEXT` / `ACTION_SET_PROGRESS`, AppKit
  `setAccessibilityValue`, ARIA `aria-valuenow` — and it is **fallible** (a
  field reports *"ACTION_SET_PROGRESS has failed on the element"* when
  preconditions aren't met —
  [Appium](https://discuss.appium.io/t/action-set-progress-has-failed-on-the-element-in-android/33847)),
  so it must return a status, not fire-and-forget.

**The one belief this changed:** the goal is *not* "make ids foolproof enough to
hold across frames." It is **durable-where-keyed ids + a version stamp so the
inevitable staleness is detectable and safe.** Nobody ships foolproof structural
ids; they ship safe failure.

## Proposal

### Part A — Semantic node identity

**A1. Key-derived ids (the AutomationId model).** When a node has no explicit
`Semantics(id:)`, derive its id from the element tree instead of `hashCode`:

```
id = <keyed-ancestor path> "/" <role> [ "#" <disambiguator> ]
```

- **Keyed-ancestor path:** walk up the element tree to the nearest ancestors
  that carry a `Key` (the same keys reconciliation already uses) and fold their
  `ValueKey`/`Key` values in, e.g. `table[processes]/row[1234]`. A node under a
  keyed list row is then *reorder-proof* — the row keyed `pid:1234` keeps its id
  wherever it moves. Fleury's data widgets already key their rows
  (`DataTable.rowKeyBuilder`, `Tree`'s `row.key`), so this lights up for the
  apps an agent cares about.
- **Role + disambiguator:** the node's own `role`, plus a tiebreak **only when
  needed**, computed **at the level where a collision actually occurs**
  (UIA's sibling-unique rule), not a positional index at every level.

**A2. Structural fallback, anchored — not root-absolute.** Where no ancestor is
keyed, fall back to a structural path, but **anchored at the nearest keyed
ancestor and role-qualified** (`…/region/list/listItem#2`), so only the unkeyed
*tail* is positional. This is the single most important deviation from a naive
"XPath from root", which the research flags as maximally brittle. This tail is
the one part that shifts under reorder — which is exactly what A3's version
check exists to make safe.

**Derivation invariants.** The generator must also honor:

- **GlobalKey anchoring.** A `GlobalKey` is identity that survives *reparenting*
  — its whole point. So when a node or an ancestor (up to the nearest keyed one)
  carries a `GlobalKey`, anchor the id *at* that `GlobalKey` and do **not** fold
  ancestors above it; the id then travels with the subtree the way the element
  does. Folding the ancestor chain unconditionally would churn the id for
  exactly the construct designed to keep it stable.
- **Collision at mint.** Duplicate sibling `ValueKey`s are a real app bug (the
  framework rejects duplicate `GlobalKey`s; it does *not* reject duplicate
  `ValueKey`s). On a collision, append a stable disambiguator **and** emit a
  framework diagnostic; if uniqueness can't be reached, mark the colliding nodes
  so resolution fails `ambiguous` rather than silently driving one of them.
- **Privacy.** Key values can be sensitive (`ValueKey(user.email)`, a session
  token) and the id crosses the boundary to an external agent — while the rest of
  the snapshot is already redaction-aware. So **key values folded into an id run
  through the same sanitization/redaction policy**, and a widget may opt a key
  out of derivation or supply a non-revealing stable surrogate. An id must never
  become an exfiltration channel for data the snapshot redacts.
- **Cost.** Deriving the id walks the ancestor chain (O(depth) per node) plus a
  sibling scan for the disambiguator — too expensive to recompute for every node
  every frame (the old `hashCode` id was O(1)). **Memoize the id on the
  `SemanticsElement`**, invalidating only when an ancestor key or the node's
  keyed-path position changes; a steady-state frame recomputes nothing.

**A3. Versioned handle — make staleness *safe* (the hardening).** Durable ids
reduce churn; they don't eliminate it. The version check exists to protect the
**structural-fallback ids (A2)** — whose unkeyed tail *does* shift under a
sibling insert or reorder. Fully-keyed ids are stable by construction and need
no check.

- Track a **structure generation** on the tree: a counter that bumps **only when
  the tree's shape changes** (a node added, removed, or reparented; a keyed
  ancestor changes) — *not* on every value tick. A naive per-frame counter would
  be wrong: it would mark an unchanged node stale one frame after it was read.
- Each emitted snapshot carries `structureGeneration`; the agent passes it back
  with an action as `(id, observedGeneration)`.
- Resolution: resolve `id` in the current tree. A **fully-keyed id** is honored
  regardless of generation (it re-resolves to the same logical node by
  construction). An id whose tail is **structural/positional** is honored only
  if `observedGeneration == currentGeneration`; otherwise the shape moved under
  it and the dispatcher returns a typed **`stale`** status ("re-read get_ui")
  instead of acting on whatever now occupies that path.
- Floor, independent of the generation: an id resolving to **zero or more than
  one** node fails `notFound` / `ambiguous` (what the MCP server already
  enforces — now belt-and-suspenders, not the only guard).

The dispatcher needs **no stored snapshots and no echoed attributes**: the id
string itself reveals whether its tail is keyed or positional, and the
generation reveals whether the shape moved. This is the `1:10` versioned-ref
pattern on machinery we already have, and the concrete answer to "the structural
fallback isn't foolproof": it doesn't have to be.

### Part B — Parameterized `setValue`

**B1. Optional action payload.** Today `SemanticActionFrame(id, action)` and
`onAction: FutureOr<void> Function(SemanticAction)` carry no value. The payload
is **additive on the wire** — absent for the existing 16 actions, so old frames
decode unchanged — but a **clean breaking change to the handler signature**
(Fleury is pre-1.0; we make breaking API changes cleanly, no compat shims):

- wire: `SemanticActionFrame(id, action, value?)` — extend `encodeSemanticAction`
  with an optional payload; absent ⇒ null.
- handler: `onAction` receives a `SemanticActionInvocation { action, value }`
  rather than a bare `SemanticAction`. Every existing handler migrates to read
  `invocation.action` — a mechanical, repo-wide change, **not** a silent no-op;
  it pairs with the existing `SemanticActionInvocationResult` / `…Status`.
- `invokeSemanticActionFromElement(..., {Object? value})`.

**B2. `setValue` action + generalization.** Add `SemanticAction.setValue`. Input
widgets advertise it and apply the payload directly: `TextInput`/`TextField` set
their controller text; this generalizes cleanly to `Slider` (`setValue: 0.7`),
`Select` (`setValue: "Enterprise"`), `DatePicker` (an ISO date). One semantic
call replaces the focus-then-keystroke dance.

**B3. Fallible by contract.** `setValue` returns a status (it can be rejected:
disabled field, out-of-range, validation). The agent/test reads the result; the
MCP `set_value(id, value)` tool surfaces failure as a tool error.

**B4. Payload contract — typed, coerced, validated.** The value crosses the wire
as a JSON scalar, so a bare `Object?` is not a contract on its own; coercion and
validation are defined centrally, not per widget:

- **Typed per role.** `Slider`/`spinButton` → number; `DatePicker` → ISO-8601
  date; `Select` → an option value from the advertised set; text field → string.
  Define the expected type per role (or carry a small discriminated value) and
  coerce centrally (`"0.7"` → `0.7`, ISO parse) so widgets don't each reinvent
  it.
- **Typed failure.** Out-of-range, parse-failure, and not-an-option map to
  distinct statuses on `SemanticActionInvocationResult`, which the MCP
  `set_value` tool surfaces as an actionable error (not a generic "failed").
- **Preconditions.** `setValue` **auto-acquires focus** (no prior `focus`
  round-trip required) and is **idempotent** (setting the current value is a
  no-op success). Pin these per widget as it adopts the action, checked against
  the UIA/Android/AX contracts.

## Where the changes land

| Change | Files / types |
| --- | --- |
| A1/A2 id derivation | the semantics id assignment that currently mints `element-$hashCode` (`lib/src/semantics/…`, the `SemanticsElement` path) |
| A derivation invariants | id generator: `GlobalKey` anchoring, duplicate-`ValueKey` collision diagnostic, key-value redaction, id memoized on `SemanticsElement` |
| A3 structure-gen + stale check | `SemanticInspectionSnapshot` (carry `structureGeneration`), `invokeSemanticActionFromElement` (optional `observedGeneration` + `stale` status); `fleury_mcp` (`get_ui` stamps it, `invoke_action` passes it back) |
| B1 action payload | `SemanticAction`, `SemanticActionFrame`, `encodeSemanticAction`/`decodeSemanticAction`, `Semantics.onAction`, `invokeSemanticActionFromElement` |
| B2 widget adoption | `TextInput`/`TextField`, `Slider`, `Select`, `DatePicker` |
| B3 / MCP surface | `SemanticActionInvocationResult`; `fleury_mcp` `set_value` tool |

## Impact on consumers

- **Tests** get stable, meaningful ids (`single(id: 'table[processes]/row[1234]')`)
  and `invokeSemanticAction(setValue, value: 'x')` instead of simulated keys.
- **Accessibility** gets meaningful node ids and a `setValue` that maps to the
  platform "set value" verb.
- **`fleury serve` / browser client** is unaffected by A1/A2 (it consumes ids
  opaquely); it gains the payload field passively.
- **`fleury_mcp`** is where A3 and B3 pay off; mostly additive.

## Alternatives considered

- **Pure ephemeral refs, re-snapshot every call (the Playwright-MCP model).**
  Viable and proven, but it throws away the legibility and cross-call durability
  that *keyed* nodes can genuinely provide, and pushes a re-read onto every step.
  We take the better half of both: durable-where-keyed ids **plus** the version
  stamp for safety. Not either/or.
- **Content-addressed ids (role+label+value hash).** Rejected — collides on
  look-alikes and changes whenever the value changes (a counter's id would churn
  every tick). The research is explicit that content-addressing is the wrong
  move.
- **Online tree-matching (GumTree / tree-edit-distance) to re-identify nodes
  per frame.** Rejected for the hot path — it's an offline-diff tool
  (AST matching across commits), too heavy for per-frame id assignment;
  key + structural + version is the right weight.
- **Keep parameterless actions; model text via focus → clear → type_text.** The
  status quo. Works, but it's the one place the agent leaves the semantic
  abstraction; every major a11y API instead models a payload-carrying setValue.

## Risks & open questions

- **Id-string format is a soft contract.** Ids were never stable before, so
  changing the scheme breaks nothing today — but once agents/tests rely on the
  new format we should treat it as semi-stable and document the grammar.
- **`AutomationId` is only sibling-unique and not stable across app *builds*.**
  Fine — we only need within-session stability; we do not promise cross-build.
- **Exact fold depth & disambiguator placement** (fold the whole ancestor
  key-chain vs. stop at the nearest keyed ancestor; where to inject the sibling
  index) need pinning with concrete tree fixtures before implementation.
- **Structure-generation granularity.** "Shape change" must be defined precisely:
  add/remove/reparent and keyed-ancestor changes bump it; a label or value tick
  must **not** (or A3 over-fires and forces a re-read every step). Pin the exact
  mutation set that bumps the generation.
- **Privacy audit.** A3/A-invariants route folded key values through redaction;
  audit that path end-to-end so a sensitive `ValueKey` cannot leak through an id
  even as the snapshot redacts the value.
- **`setValue` preconditions** are specified (auto-focus, idempotent) but should
  be checked against the UIA/Android/AX contracts the research gathered but did
  not deep-verify, and validated per widget.

## Rollout (phased, independently landable)

1. **Phase 1 — id scheme (A1/A2).** Replace `element-$hashCode`. Pure win for
   tests/a11y/MCP; lowest risk (ids were never a stable contract). No action-API
   change.
2. **Phase 2 — versioned handle (A3).** Compute a **structure generation** (in
   core, or derived in `fleury_mcp` from the snapshot's node set — *not* the
   bridge's per-frame `revision`, which is the wrong, too-fine granularity), have
   `get_ui` stamp it and `invoke_action` pass it back, then optionally push the
   `stale` status into the core invoke path. Retires the stale-id band-aids.
3. **Phase 3 — `setValue` (B1–B3).** The larger change (action payload contract
   + per-widget adoption); sequence it after the identity work and design the
   payload contract for tests/a11y, not just MCP.

## References

Flutter [Inside Flutter](https://docs.flutter.dev/resources/inside-flutter) ·
SwiftUI [WWDC21 #10022](https://developer.apple.com/videos/play/wwdc2021/10022/) ·
UIA [AutomationId](https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/use-the-automationid-property) /
[RuntimeId](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationclient/nf-uiautomationclient-iuiautomationelement-getruntimeid) /
[IValueProvider::SetValue](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-ivalueprovider-setvalue) ·
Playwright [locators](https://playwright.dev/docs/locators) /
[MCP snapshots](https://playwright.dev/mcp/snapshots) ·
[WebArena](https://webarena.dev/static/paper.pdf) ·
[SeeAct](https://osu-nlp-group.github.io/SeeAct/) ·
[arXiv 2511.19477 (versioned refs)](https://arxiv.org/html/2511.19477v1) ·
[Apple setAccessibilityValue](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/1535339-setaccessibilityvalue)
