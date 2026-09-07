# Shared lifecycle correctness audit

Final baseline: `944f7fb71e9b99ec6644b797ecbb1d4b6ecc09b8`, main after #226.
The pass started after #225 and was rebased when the pointer/gesture work
merged. The three affected production files are identical between those two
baselines. All 13 defect reproductions were rerun against the newer main and
failed there before restoring the candidate source.

## Method and scope

The audit concentrated on state transitions at ownership boundaries:
navigation cancellation, overlay attachment, and remote session startup and
teardown. Source review also covered notification removal/disposal,
inherited subscriptions, failed-mount cleanup, frame scheduling and semantic
flush ownership. Existing reconciliation, rendering, semantic, remote and
browser suites provide regression coverage for the combined change.

Each finding was reproduced before editing its implementation. Changes were
reviewed locally and run through the affected suites before proceeding. A
follow-up review of remote cancellation exposed the INIT-to-continuation gap;
two further regressions pin peer BYE and transport failure in that gap.

This is a bounded source and automated-test audit, not an independent review
or a complete launch certification. Native terminal and accessibility
walkthroughs, long-session memory qualification and arbitrary custom widget
implementations are outside this pass. The newly merged pointer/gesture work
is integrated and exercised by qualification, with its own separate review.

## Findings and fixes

### C1: Cancelled navigation can remove the destination route

Start an animated `pushReplacement` or `pushAndClear`, push another route
before the entrance completes, then call `popToRoot` or `popUntil`. Removing
the intermediate route disposes its animation, which completes its pending
future. The old entrance callback checked only navigator mountedness and the
route's leaving flag. An outright removal did not set that flag, so the
cancelled callback still applied replacement/clear and deleted the route just
revealed. All four reproductions reduced the stack depth from one to zero.

Entrance and exit completion callbacks now require the route to remain in
the navigator's owned stack. Tests verify the destination's painted text,
route context, result futures, and a subsequent push/pop round trip. Local
review checked ordinary entrance/exit, immediate routes, modal opacity,
replacement results, focus restoration and navigator teardown. No transition
timing or navigation policy changes.

### C2: Failed overlay operations corrupt entry ownership

An insertion with an absent above/below anchor attached the entry and
registered a listener before checking the anchor. It then threw, leaving an
entry that could not be inserted again without an explicit repair. Inserting
through a disposed overlay state had the same partial-attachment problem.
Separately, `initialEntries` could silently take an entry already owned by a
different overlay; later removal no longer removed it from its original host.

Anchor validation now precedes attachment. Entry attachment runs inside the
state update, after its disposed-state check. Initial lists are validated in
full before taking ownership, including identity duplicates and entries owned
by another overlay. Ownership and mutually exclusive anchors are checked in
all build modes. Seven tests cover failed-insertion retries, cross-overlay
ownership, duplicate entries, conflicting anchors and disposed owners. The
duplicate-initial-entry case was already rejected later by reconciliation on
main; it is a cleanup control, not a newly discovered failure.

### C3: Remote startup can outlive cancellation or lose its waiter

`RemoteTerminalDriver` had several gaps before it set `isActive`:

- `restore()` cancelled the stream subscription without completing the
  handshake. A supervised session could wait forever because it has no
  handshake timeout.
- A second `enter()` replaced the first handshake completer and subscription.
  The second caller succeeded while the first was stranded.
- After INIT completed the handshake, local restore, peer BYE or a transport
  error could occur before the awaiting continuation resumed. Startup still
  reported success and set the driver active.

The driver now permits one startup attempt, shares one teardown future,
resolves an unfinished handshake during teardown, and checks termination
before activation. A startup failure retains its original error/stack even
when INIT already completed the future. Frames arriving after startup failure
or teardown are ignored. Five regressions cover these interleavings, including
a synchronous peer that makes the microtask boundary deterministic.

The existing timeout, supervised-standby, protocol negotiation, disconnect,
input, image, caret and clipboard behavior remains covered. The error/restore
paths were reviewed for duplicate completion, late frames and cancellation
before/after INIT; no wire format changes.

## Qualification

- Final `dart tool/fleury_dev.dart check`: all package analyses and **5,552
  tests passed**, including 534 web tests, 78 documentation/guide tests,
  browser/dart2js smoke and 64 integration tests. Two existing skips.
- **16 new regression/control tests**. The selected **13 defect reproductions
  all fail on current main**; their passing counterparts are in the full gate.
- Focused suites before rebase: 54 navigation, 31 overlay and 30 remote-driver/
  clipboard tests passed. The full final gate repeats them after integration.
- `dart tool/fleury_dev.dart benchmark gates`: **all eight fast gates passed**.
- `dart tool/fleury_dev.dart benchmark wire-gate`: **passed** (three terminal
  scenarios, three runs each).
- `dart tool/fleury_dev.dart benchmark serve-wire-live`: **passed** (dashboard,
  log, counter and closed-loop input; three runs each). Timing axes are
  informational and varied; no latency improvement is claimed.
- No gate baseline or tolerance changed. Final local review found no further
  actionable issue in the retained changes. Hosted CI attaches to the PR head.
- Browser JavaScript remains **401,255 bytes, byte-identical to baseline**;
  the regenerated source fingerprint is `e163b801162ef83f`.

The generated client is rebuilt from final source. Baseline failure output and
source/log hashes are recorded in the
[evidence manifest](evidence/2026-09-07-core-correctness.json). The two earlier
interrupted contributor checks were stopped for the peer-cancellation fix
and the main integration; neither is counted as final qualification.
