# RFC 0026: Reusable native terminal sessions

Status: implemented and locally qualified for native macOS/Linux TTY sessions.
Windows and redirected input reuse remain explicitly unsupported.

Date: 2026-09-24. Historical investigation baseline: `35d60473`. Production
evidence below records the current implementation, including uncommitted work.

## Decision

Support sequential `await runApp(...)` calls without new application lifecycle
APIs. Each invocation owns a fresh runtime and driver. It borrows the terminal
for that invocation and returns only after successful terminal-critical cleanup.

Replace the default macOS/Linux TTY driver's subscription to process-global Dart
`stdin` with an internal, cancellable native input lease. Use an OS wake-up
primitive to stop the reader, await actual reader completion, and close only
Fleury-owned handles. Use the same stop/reacquire operation for handoff and
suspension. Keep all keyboard/protocol decoding in the existing Dart input parser.

This is an input and lifecycle change. Inline placement, widget APIs, and
rendering remain separate concerns. Sequential sessions can choose different
terminal modes. Switching the mode of an active session is not part of this RFC.

## Application contract

```dart
final outcome = await runApp(
  picker,
  mode: const TerminalMode.inline(rows: 10),
  enableHotReload: false,
);

if (outcome.signal case final signal?) {
  exitCode = switch (signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
  };
  return;
}
if (selected == null) return; // Cancellation reported by the picker's callback.

print('Installing dependencies…');
await installDependencies();

await runApp(
  confirmation,
  mode: const TerminalMode.inline(rows: 6),
  enableHotReload: false,
);
```

- An ordinary completion means the terminal can be used by the caller: ordinary
  output, a synchronous stdin prompt, an inherited-stdio child, or another UI.
- Handle signal outcomes before starting another interaction. A hangup releases
  Fleury's resources but cannot make a disconnected terminal usable again.
- Explicit cancellation and signal outcomes retain the current `AppExit` API.
- Startup failure permits retry with a new `runApp` if cleanup succeeded.
- Overlapping or nested `runApp` calls fail before terminal or capture mutation.
  They are not silently queued, because queuing a nested awaited call deadlocks.
- Each default call constructs a fresh driver. Native driver instances remain
  one-shot, including after a failed entry; a spent instance gets a clear error.
- No public `initializeTerminal`, `disposeTerminal`, or global input manager.
- The supported native application model has one UI-owning Dart isolate.
  An isolate-local admission guard does not enforce exclusivity against another
  isolate or unrelated process. Do not describe it as a universal OS lock.
  Cross-isolate terminal ownership is outside this feature's supported contract.

This does not make Dart's own stdin stream reusable. If another library has
an active asynchronous stdin subscriber, it must relinquish input itself. If it
cancels and closes fd 0, Fleury cannot reconstruct the caller's closed input.
The feature must not replace `stdin` with an IOOverride or silently reopen
`/dev/tty`/`CONIN$` to bypass redirected or closed input.

Hot restart reruns the whole entrypoint, including earlier prompts and side
effects. Short production CLI flows should disable the development supervisor;
the framework should not pretend a restart resumes only the current step.

## Historical findings

These findings motivated the change. They describe the investigation baseline,
not the current macOS/Linux TTY implementation:

1. `PosixTerminalDriver` and `WindowsTerminalDriver` subscribed to Dart stdin
   and cancelled that subscription on restore. The single-subscription stream
   was spent, and on POSIX cancellation closed fd 0 asynchronously. The
   `_globalStdinConsumed` guard made this failure legible but could not solve it.
2. Keeping that subscription paused still occupied the Dart stream and kept
   the process alive. A real PTY probe remained alive two seconds after main
   finished. Replacing it with `File('/dev/fd/0').openRead()` also failed: cancel
   waited on an outstanding idle read for the two-second probe deadline.
3. `requestExit()` targeted one mutable global completer. A timer created by
   session A successfully exited session B after 87 ms, although B was intended
   to run for 700 ms. Fresh fake drivers reproduced this without the stdin limit.
4. The active completer was installed late and cleared before terminal/capture
   cleanup. It could not serve as the acquisition lock.
5. Terminal restore and stdio-capture timeouts were diagnostic and could still
   yield an orderly result. A delayed restore could mutate a later UI.
6. An active inherited-stdio handoff was not drained by driver restoration.
   Its child could still own stdin after `runApp` returned.
7. Restoration disposed the native driver's query runner, while parser, hangup,
   and geometry state belonged to that session. The solution preserves fresh
   one-shot drivers rather than trying to reset and reuse these objects.

Source anchors: [run_app.dart](../../packages/fleury/lib/src/runtime/run_app.dart),
[POSIX driver](../../packages/fleury/lib/src/terminal/posix_driver.dart),
[Windows driver](../../packages/fleury/lib/src/terminal/windows_driver.dart),
[driver contract](../../packages/fleury/lib/src/terminal/terminal_driver.dart).

## Ownership boundaries

### 1. Invocation scope

A private invocation scope owns an identity, completion request, admission
lease, and lifecycle state. Acquire admission synchronously before the first
startup await or fd-capture operation. Hold it through final restoration,
capture shutdown, output replay, and flush.

Register the identity in the existing guarded zone. A `requestExit()` made in
that zone targets that identity; after it expires the request returns false.
It must never fall through to a newer session. Preserve the current active-app
fallback for deliberately unscoped host calls; calls created outside the
session cannot be retrospectively attributed to it.

Hot-reload hooks are unpublished synchronously when disposal starts. Already
queued reload/report callbacks check the expired identity before acting.
Asynchronous cleanup may complete later but cannot publish stale callbacks.

### 2. Native driver

The driver remains the only terminal mode/geometry owner. It owns termios or
console state, signals, screen allocation, parser, query runner, and one input
lease at a time. Its public entered-session profile remains unchanged.

An input reader is a transport, not a second terminal driver. It receives bytes
and reports source EOF/errors. It does not interpret keys, run terminal probes,
choose application exit statuses, or manipulate screen buffers.

### 3. Input lease

The private production `PosixInputLease` exposes asynchronous `start()` and
`stop()` operations. Applications continue to use `runApp`.

Its constructor receives byte, source-EOF, and error callbacks. The driver stores
the lease before awaiting `start()`, so restoration also owns a partial startup.
The owning isolate allocates and releases the descriptors and native memory;
the worker borrows them until its actual exit.

`stop()` is an idempotent barrier, not merely a cancellation request:

1. Fence outstanding deliveries belonging to this acquisition.
2. Wake the OS wait; give stop priority over a simultaneous input-ready event.
3. Wait for the worker's `onExit` notification, proving native reads have ended.
4. Restore owned input file-status flags, then release handles, allocations,
   and the message port in the owning isolate.
5. Resolve only after no callback/read from the lease can affect another owner.

Intentional stop does not emit EOF or synthesize SIGHUP. Source EOF/errors remain
distinct from stop. Production permits one 4 KiB batch until acknowledged,
bounding queued SendPort traffic. A 1 MiB arbitrary-byte regression checks exact
delivery and that the owning isolate's timer continues to run; this is integrity
and basic fairness evidence, not a throughput or rendering-latency guarantee.

## POSIX transport choice

The production implementation uses a worker isolate with non-leaf FFI calls to
`poll` on two descriptors: the duplicated input and a private wake-up pipe. A
regular Dart message cannot wake an isolate blocked in `poll`. Reads remain
nonblocking after readiness, so stop cannot be stranded behind a subsequent
`read`. The pipe carries ACK/STOP commands, with stop taking priority over input.
This uses one worker thread while the lease is active; it is not a multiplexed
event loop. That is an explicit tradeoff for a single native UI owner.

The native wait has a 250 ms timeout. Ordinary stop wakes it immediately through
the pipe; the finite timeout also lets VM shutdown or worker cancellation make
progress if the owning isolate fails. An infinite non-leaf `poll` stranded
process shutdown in both JIT and AOT testing. An error message, timeout, or kill
request is not a join: the owner waits for actual `onExit` before freeing the
worker's borrowed memory or descriptors.

Two handle strategies were compared in the experiment:

| Strategy | Benefit | Obligation / limitation |
|---|---|---|
| Close-on-exec duplicate of the supplied stdin | Exact input source; no device path lookup or new access checks | File-status flags are shared. Own and restore only the `O_NONBLOCK` bit at every release; include it in supervisor crash recovery. |
| Reopen `ttyname_r(stdin)` with nonblocking, close-on-exec, no-follow, no-controlling-terminal flags | Independent file-status flags; caller's blocking mode stays unchanged while active | Adds pathname, permissions, namespace, revocation, and identity validation requirements. A valid inherited TTY need not be reopenable. |

Production uses the duplicate backend, preserving the exact input source. It
does not fall back to pathname reopening when acquisition fails. Shared-flag
restoration, supervisor recovery, and ancestor-held descriptor tests are part
of the production evidence below. A blocking-read variant based only on
readiness is not an adequate cancellation guarantee.

`dup` shares file status and offsets; close-on-exec is a separate descriptor
flag. Capture the original blocking bit before mutation and restore that bit
without clobbering unrelated flags. Holding the duplicate alone is not input
exclusivity; only the currently admitted owner may read. Use atomic close-on-exec
creation where supported and review the platform's process-spawn race elsewhere.
Stdin, stdout, stderr, and an ancestor's terminal descriptor may also share that
open file description. Qualify output backpressure while input is active, and
verify restoration from an ancestor retaining its descriptor. Test both initially
blocking and initially nonblocking input; closing the duplicate is not restoration.
The current `stdio` terminal sink handles `EAGAIN` with a synchronous writable
wait. Check complete output under backpressure: an asynchronous teardown timer
cannot interrupt a synchronous native write/wait that blocks the UI isolate.
This proposal does not claim a universal in-process cleanup deadline under
undrained output. If qualification requires that guarantee, the output sink
needs interruptible/off-isolate I/O as a separate prerequisite.

Sequential native sessions are supported for macOS/Linux TTY input. Windows and
redirected process stdin retain the one-session restriction. Injected test/custom
streams retain their source-specific contract; neither they nor redirected
pipes/files silently become a reopened terminal. Pipe-based private transport
tests do not establish repeatable `runApp` support for redirected input.

## Windows path

Use the same private lease boundary with a platform reader. A promising design
duplicates the standard console input handle as non-inheritable, then waits on
`[stopEvent, consoleHandle]` and reads records with
`ReadConsoleInputExW(CONSOLE_READ_NOWAIT)`. With VT input enabled, convert relevant
key-record UTF-16 characters into UTF-8 for the existing parser. Preserve split
surrogates and define repeat/NUL handling through tests.

Console readiness includes non-character records, so readiness followed by
blocking `ReadFile` can still block. Cancellation must wait for completion and
handle the cancel-before-read race. Microsoft Edit demonstrates the NOWAIT
record approach; that is supporting implementation evidence, not Fleury Windows
qualification. Verify VT arrow/mouse/probe bytes rather than assuming parity.

This is a future backend, not part of the production change. Windows full-screen
reuse needs implementation and real Windows tests before the same support claim.
Windows inline remains a separate feature.

## Release, handoff, and failure semantics

Normal path:

```text
available → starting → running → closing → available
                         ↕
                     handed off
```

Handoff retains the UI invocation's admission lease but releases its input
reader and terminal modes. Await reader stop before handing control to the
callback or suspending the process. Reacquire input before new cursor/protocol
queries and repaint only if the same invocation is still running. Production
creates a fresh lease on reacquisition. The prototype also tested a paused
worker, but its measured acquire/release cost did not justify that extra lifetime.

Entering closing rejects queued handoffs. An existing callback is an outstanding
terminal borrow: normal close waits for it, then restores directly to the caller
without repainting. Fleury cannot cancel an arbitrary Future or infer which child
the callback owns. The callback must await its child and handle cancellation.

Bound that wait using the existing teardown policy. On timeout or uncertain
terminal/input/capture cleanup, fail `runApp` with a clear ownership error and
retain the admission lease until cleanup actually succeeds; quarantine it if
ownership cannot be proven released. Never mark the terminal available merely
because a timeout Future completed. A failed ownership return does not authorize
an ordinary prompt; the caller must resolve the outstanding operation or exit.
Clear quarantine only when all critical resources and outstanding borrows are
released, not just when the particular operation that timed out finally returns.
Keep second-signal/force-exit behavior effective while draining.

Worker failure must still allow the owning process to restore shared flags and
modes. Recovery after killing the whole UI process requires a surviving
supervisor with the saved restoration state. Uncatchable death of an
unsupervised process, including a production CLI with hot reload disabled, cannot
guarantee restoration; do not imply otherwise in examples or qualification.

Widget-disposal diagnostics remain distinct: they should not prevent cleanup of
the terminal. Conversely, successful widget disposal does not prove stdin or
stdout has been restored. Independently attempt necessary restoration even if
an earlier cleanup step fails.

### Physical hangup

Physical terminal loss is distinct from a delivered SIGHUP.
A signal, EOF, `EIO`, or `POLLERR` alone does not prove that a particular output
or input descriptor has disappeared. A zero-timeout `poll` checks `POLLHUP` on
the same saved, previously-terminal descriptor, with `POLLNVAL` excluded, before
accepting a completed terminal-I/O restoration failure as terminal loss. Invalid
descriptors remain errors. Input hangup cannot excuse a failure on a different
output descriptor.

That exception must not waive an unfinished cleanup barrier. Even when the
terminal is gone, input-worker exit, capture shutdown, outstanding handoffs, and
queued asynchronous writes still need to settle or keep admission quarantined.
The real-PTY runner closes the master in both inline and full-screen modes and
checks for `AppExit.hangup` and natural process exit. Completed platform runs are
recorded below; a passing hangup result does not relax the pending-operation rule.

## Input and protocol boundaries

- Cancel pending queries and fence their timers/callbacks before releasing input.
  Retain the existing bounded late-response drain/quarantine discipline.
- A handoff boundary uses `endInputOwnership` to resolve or discard unfinished
  UTF-8, Escape, and paste parser state deliberately. It does not use EOF
  finalization as if the terminal disconnected.
- Each lease receives deliveries through its own message port and fences them
  when stop begins. Already consumed input belongs to that acquisition; it is
  never replayed into the next UI.
- Do not use blanket `tcflush` to make tests pass: that discards real type-ahead.
- Bytes still in the OS queue are not equivalent to queued Dart callbacks.
  Terminal protocols do not tag replies with session identities. A terminal
  replying after a release deadline can affect the next owner; tests must cover
  delayed responses, but the API must not promise impossible attribution across
  arbitrary terminal-owner boundaries. Avoid releasing with active probes.

## Evidence

### Production implementation and local qualification

The production driver no longer consumes Dart stdin on macOS/Linux TTYs.
Invocation admission spans bootstrap through critical cleanup; stale exit/reload
callbacks are fenced. Handoff/suspend stop and reacquire the native reader, and
restoration drains outstanding terminal borrows. The supervisor restores the
original shared blocking bit after child restart or failure.

The integrated sequence is inline → synchronous prompt → inherited-stdio child
→ full-screen → inline → Dart async stdin → natural exit. The runner
also checks teardown during an active child handoff and actual PTY master
closure in inline and full-screen modes:

| Environment | JIT | AOT executable |
|---|---|---|
| macOS arm64, Dart 3.12.2 | Passed | Passed |
| macOS arm64, minimum SDK Dart 3.10.4 | Passed | Passed |
| Linux arm64 Docker, Dart 3.13.3 | Passed | Passed |

These are local runs. The fixture verifies Unicode bracketed paste, prompt/child
input, natural exit, exact termios, and the original blocking bit observed from
an ancestor-held descriptor. During active handoff, `runApp` must wait for the
child. Physical hangup must return `AppExit.hangup` without stranding the process.

Additional production evidence:

- Native PTY output backpressure on macOS and Linux: all 2 MiB were delivered
  after the consumer resumed draining, and the ancestor's original blocking bit
  was restored. This does not establish an undrained-output cleanup deadline.
- Supervised restart, child SIGKILL, and abrupt child exit restored terminal and
  shared blocking state on macOS and Linux. These results require the surviving
  supervisor; they do not promise unsupervised SIGKILL recovery.
- Native lease regressions cover stop/start races, partial acquisition,
  callback/worker failures, source EOF versus stop, initial blocking and
  nonblocking modes, and exact 1 MiB delivery with timer progress. Descriptor
  accounting runs in an isolated process: 100 successful cycles interleaved with
  failed acquisitions leave descriptor counts and input flags unchanged.
- The final runtime/terminal sweep passed: 768 tests passed and two were skipped.
  Real VM-service tests were also run separately with the service enabled.
- Invocation regressions cover stale callbacks, overlapping/nested startup,
  failed-start retry, pending-enter fatal errors, closing admission, cleanup
  timeout and eventual release, and permanent failure quarantine. Real
  VM-service tests cover controller generations and throwing callbacks. The
  retained stale-exit probe now returns `false` for the old callback while the
  second UI runs for its intended 700 ms.

Retained production checks:

- [Sequential PTY runner](../../tool/check_sequential_sessions.py) and
  [fixture](../../packages/fleury/test/fixtures/sequential_native_sessions_fixture.dart).
- [Native backpressure runner](../../tool/check_native_input.py),
  [resource fixture](../../packages/fleury/test/fixtures/posix_input_resources_fixture.dart),
  and [lease tests](../../packages/fleury/test/terminal/posix_input_lease_test.dart).
- [Inline lifecycle runner](../../tool/check_inline_tui.py), including supervised
  restart and crash recovery.
- [Invocation tests](../../packages/fleury/test/runtime/run_app_invocation_test.dart)
  and [VM extension tests](../../packages/fleury/test/runtime/hot_reload_controller_test.dart).
  The latter run with
  `dart --enable-vm-service=0 test test/runtime/hot_reload_controller_test.dart`
  from `packages/fleury`.

The CI workflow now includes the sequential JIT/AOT and backpressure runners for
macOS and Linux; its updated run is not yet part of this evidence. Windows,
redirected-input reuse, and real terminal application visuals are not qualified
by these checks.

### Historical transport experiment

Retained experiment:
[source and runner](../../tool/experiments/reusable_terminal_input/README.md).

- macOS arm64, Dart 3.12.2: duplicate and reopened-handle variants pass 100 idle
  acquire/resume/stop cycles, failed acquisition cleanup, two raw input leases,
  synchronous prompts, an inherited-stdio shell child, an untouched Dart async
  stdin subscription afterward, and natural process exit.
- Linux arm64 Docker, Dart 3.13.3: both handle variants pass the same PTY flow.
  Network disabled; source and package mounts read-only.
- macOS compiled executable: duplicate/release variant passes the same flow.
- Descriptor counts remain stable through the repeated leases and failed entry;
  the harness independently checks final termios and blocking mode.
- Warm median duplicate acquisition was roughly 0.05–0.40 ms and release
  0.02–0.19 ms across these runs. This excludes UI startup and terminal probes;
  it just supports choosing fresh readers over a persistent pump.
- The stale `requestExit` bug was independently reproduced against the original
  runtime before invocation isolation was implemented.

These are transport experiments, not integrated `runApp` acceptance, Windows
proof, minimum-SDK qualification, throughput benchmarks, or terminal-app visual
qualification. The prototype deliberately lacks production-grade failure
plumbing; it must not be moved into the shipping library unchanged.

## Merge checks and support boundary

Run the updated CI workflow before treating local qualification as a merge check.
Keep the production runners as regressions for termios, shared flags, worker
exit, output backpressure, and ownership between sessions. Physical-hangup
handling must continue to distinguish completed terminal I/O from unfinished
reader, capture, child, and write operations that retain admission.

The guide and `inline --repeat` showcase now demonstrate successive UIs with an
ordinary prompt between them. No new public lifecycle API is needed. Windows and
redirected input remain one-session paths; Windows reuse needs its own reader and
native qualification. Concurrent UI ownership across isolates, active-session
mode switching, and a universal deadline under undrained synchronous output are
outside this change. Browser demos illustrate interaction and screen placement;
they do not qualify native terminal ownership.

## Primary references

- [Dart stdio implementation](https://github.com/dart-lang/sdk/blob/3.12.2/sdk/lib/io/stdio.dart)
  and [VM socket implementation](https://github.com/dart-lang/sdk/blob/3.12.2/sdk/lib/_internal/vm/bin/socket_patch.dart).
  The local 3.12.2 SDK was inspected, including `_FileStream._closeFile`.
- [dup](https://man7.org/linux/man-pages/man2/dup.2.html),
  [poll](https://man7.org/linux/man-pages/man2/poll.2.html),
  [close](https://man7.org/linux/man-pages/man2/close.2.html): shared file status,
  readiness, and why closing a descriptor from another thread is not a portable
  cancellation protocol.
- [ReadConsoleInputEx](https://learn.microsoft.com/en-us/windows/console/readconsoleinputex),
  [Microsoft Edit reader](https://github.com/microsoft/edit/blob/main/crates/edit/src/sys/windows.rs),
  [wait ordering](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitformultipleobjects),
  [I/O cancellation](https://learn.microsoft.com/en-us/windows/win32/fileio/canceling-pending-i-o-operations).
- [Dart blocking FFI restriction](https://api.dart.dev/dart-ffi/NativeFunctionPointer/asFunction.html):
  blocking waits must not use leaf calls.
