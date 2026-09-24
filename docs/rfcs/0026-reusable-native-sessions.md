# RFC 0026: Reusable native terminal sessions

Status: proposed; input transport prototyped, production runtime unchanged.

Date: 2026-09-24. Implementation baseline: `35d60473`.

## Decision

Support sequential `await runApp(...)` calls without new application lifecycle
APIs. Each invocation owns a fresh runtime and driver. It borrows the terminal
for that invocation and returns only after successful terminal-critical cleanup.

Replace the native drivers' subscriptions to process-global Dart `stdin` with
an internal, cancellable native input lease. Use an OS wake-up primitive to stop
the reader, await actual reader completion, and close only Fleury-owned handles.
Use the same stop/reacquire operation for handoff and suspension. Keep all
keyboard/protocol decoding in the existing Dart input parser.

This is an input and lifecycle change. Inline placement, widget APIs, and
rendering remain separate concerns. Sequential sessions can choose different
terminal modes. Switching the mode of an active session is not part of this RFC.

## Application contract

```dart
await runApp(
  picker,
  mode: const TerminalMode.inline(rows: 10),
  enableHotReload: false,
);

print('Installing dependencies…');
await installDependencies();

await runApp(
  confirmation,
  mode: const TerminalMode.inline(rows: 6),
  enableHotReload: false,
);
```

- A successful return means the terminal can be used by the caller: ordinary
  output, a synchronous stdin prompt, an inherited-stdio child, or another UI.
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

## Findings from the current implementation

1. `PosixTerminalDriver` and `WindowsTerminalDriver` subscribe to Dart stdin
   and cancel that subscription on restore. The single-subscription stream is
   spent, and on POSIX cancellation closes fd 0 asynchronously. The existing
   `_globalStdinConsumed` guard makes this failure legible but cannot solve it.
2. Keeping that subscription paused still occupies the Dart stream and keeps
   the process alive. A real PTY probe remained alive two seconds after main
   finished. Replacing it with `File('/dev/fd/0').openRead()` also failed: cancel
   waited on an outstanding idle read for the two-second probe deadline.
3. `requestExit()` targets one mutable global completer. A timer created by
   session A successfully exited session B after 87 ms, although B was intended
   to run for 700 ms. Fresh fake drivers reproduce this without the stdin limit.
4. The active completer is installed late and cleared before terminal/capture
   cleanup. It cannot serve as the acquisition lock.
5. Terminal restore and stdio-capture timeouts are currently diagnostic and can
   still yield an orderly result. A delayed restore could mutate a later UI.
6. An active inherited-stdio handoff is not drained by driver restoration.
   Its child could still own stdin after `runApp` returns.
7. Native drivers are not reusable objects: restoration disposes the query
   runner, and parser, hangup, and geometry state are session-specific.

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

The intended private shape is deliberately small:

```dart
abstract interface class NativeInputLease {
  Future<void> stop();
}
```

Acquisition supplies byte, source-EOF, and error callbacks and starts only when
the driver is ready to accept input. Exact constructor naming is private.

`stop()` is an idempotent barrier, not merely a cancellation request:

1. Wake the OS wait; give stop priority over a simultaneous input-ready event.
2. Finish or fence outstanding deliveries belonging to this acquisition.
3. Stop native reads and restore any input file-status flags owned by the lease.
4. Wait for worker completion; close owned handles, ports, and subscriptions.
5. Resolve only after no callback/read from the lease can affect another owner.

Intentional stop does not emit EOF or synthesize SIGHUP. Actual terminal loss
retains the driver's current hangup semantics. Bound queued bytes; the prototype
permits one 4 KiB batch until acknowledged instead of unbounded SendPort traffic.
Production needs a measured throughput/fairness gate, not an arbitrary batch
size treated as a performance guarantee.

## POSIX transport choice

The leading implementation is a worker isolate using non-leaf FFI calls to
`poll` on the input handle and a private wake-up pipe. A regular Dart message
cannot wake an isolate blocked in `poll`. All reads must be nonblocking, even
after readiness, so a stop cannot be stranded behind a subsequent `read`.
This uses one worker thread while the lease is active; it is not a multiplexed
event loop. That is an explicit tradeoff for a single native UI owner.

Two handle strategies were implemented in the experiment:

| Strategy | Benefit | Obligation / limitation |
|---|---|---|
| Close-on-exec duplicate of the supplied stdin | Exact input source; no device path lookup or new access checks | File-status flags are shared. Own and restore only the `O_NONBLOCK` bit at every release; include it in supervisor crash recovery. |
| Reopen `ttyname_r(stdin)` with nonblocking, close-on-exec, no-follow, no-controlling-terminal flags | Independent file-status flags; caller's blocking mode stays unchanged while active | Adds pathname, permissions, namespace, revocation, and identity validation requirements. A valid inherited TTY need not be reopenable. |

Prefer source fidelity over an automatic pathname fallback. The final duplicate
backend is gated on exact shared-flag restoration and supervisor recovery tests.
Do not silently switch input sources when acquisition fails. A blocking-read
variant based only on readiness is not an adequate cancellation guarantee.

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

The initial production guarantee is native TTY sessions on macOS/Linux. Injected
test/custom streams and redirected pipes/files retain an explicit source-specific
contract; neither silently becomes a reopened terminal. File I/O cancellation
and piped input should not inherit unproven TTY promises.

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

Windows full-screen reuse needs this backend and real Windows tests before the
same support claim. Windows inline remains a separate feature. The POSIX work
can land first with the support matrix stated explicitly.

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
queries and repaint only if the same invocation is still running. The prototype
also tests a paused worker, but the measured acquire/release cost gives no reason
to keep that extra lifetime in the first implementation. An acknowledged pause
is viable; fresh acquisition is preferred here for its smaller lifecycle surface.

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

## Input and protocol boundaries

- Cancel pending queries and fence their timers/callbacks before releasing input.
  Retain the existing bounded late-response drain/quarantine discipline.
- A handoff boundary must resolve or discard unfinished UTF-8, Escape, and paste
  parser state deliberately. Do not call EOF finalization as if the terminal
  disconnected. Add a non-EOF parser reset/boundary operation if needed.
- Deliveries carry the acquisition/session identity. Already consumed input
  belongs to the old acquisition; never replay it into the next UI.
- Do not use blanket `tcflush` to make tests pass: that discards real type-ahead.
- Bytes still in the OS queue are not equivalent to queued Dart callbacks.
  Terminal protocols do not tag replies with session identities. A terminal
  replying after a release deadline can affect the next owner; tests must cover
  delayed responses, but the API must not promise impossible attribution across
  arbitrary terminal-owner boundaries. Avoid releasing with active probes.

## Evidence

Retained experiment: [source and runner](../../tool/experiments/reusable_terminal_input/README.md).

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
- Stale `requestExit` repro independently confirmed with the current runtime.

These are transport experiments, not integrated `runApp` acceptance, Windows
proof, minimum-SDK qualification, throughput benchmarks, or terminal-app visual
qualification. The prototype deliberately lacks production-grade failure
plumbing; it must not be moved into the shipping library unchanged.

## Implementation slices and acceptance gates

1. **Invocation isolation:** early admission guard, zone-bound exit identity,
   spent-driver checks, expired dev callbacks. Add regressions for old timer →
   new app, overlapping startup, closing admission, and failed-start retry.
2. **POSIX input lease:** owned descriptor + wakeable worker, bounded messages,
   error/EOF distinction, idempotent stop, complete worker failure handling,
   file-status restoration, minimum-SDK and compiled-binary tests. Replace
   `_globalStdinConsumed` only after actual sequential input works.
3. **Critical cleanup and handoff:** stop/reacquire, pending-query boundaries,
   drain active borrows, fail/quarantine uncertain teardown, restore blocking
   state in supervisor crash recovery. Test stop/start races and worker faults.
4. **Integrated qualification:** repeated inline → prompt → child → full-screen
   → inline; explicit cancel, Ctrl+C, SIGTERM, EOF/hangup, tiny terminals,
   resize, suspend/resume, hot restart, worker failure, and supervised child
   SIGKILL recovery. Verify bytes,
   termios, blocking flags, fd/worker counts, and natural exit on macOS/Linux.
   Include aliased stdin/stdout/stderr, both initial blocking modes, slow output
   consumers, and ancestor-held descriptors during supervised crash recovery.
   Include paste/Unicode and high-rate input so acknowledgment backpressure
   cannot starve rendering or drop events.
5. **Windows and guide:** implement/qualify the platform reader, keep inline's
   platform scope explicit, add a genuine two-session CLI showcase, then remove
   the one-session warning for qualified backends. Never show the browser demo
   as proof of native input ownership.

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
