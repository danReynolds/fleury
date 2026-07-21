# DRAFT — dart-lang/sdk bug report (for review before filing)

> Status: draft. Verified on Dart 3.12.2 (stable) macOS arm64. Clone-and-run
> repro repo: <https://github.com/danReynolds/dart-reload-hang-repro> —
> re-verified from a fresh clone of that repo on this machine: 10/10 runs
> (5 control + 5 bug mode, `./verify.sh 5`). Tone note: written to present
> observations, not conclusions — we're first-time reporters in this repo and
> the mechanism section is explicitly a guess.

---

**Title:** `reloadSources` never completes (kernel-service crash) when the VM
service was enabled at runtime via `Service.controlWebServer`

## Summary

I hit this while building save-to-reload dev tooling for a terminal UI
framework. I haven't worked in this part of the SDK before, so apologies in
advance if I've misread something or this is known/expected behavior — happy
to be redirected.

What I observe: if a program enables the VM service **at runtime** with
`dart:developer`'s `Service.controlWebServer(enable: true)` (instead of the
`--enable-vm-service` flag) and a client then calls `reloadSources` **after a
source file changed on disk**, the kernel service crashes:

```
kernel-service: Error: Unhandled exception:
Bad state: No element
#0      Iterable.first (dart:core/iterable.dart:663:7)
#1      lookupOrBuildNewIncrementalCompiler (…/pkg/vm/bin/kernel_service.dart:518:45)
#2      _processLoadRequest (…/pkg/vm/bin/kernel_service.dart:981:22)
#3      _RawReceivePort._handleMessage (dart:isolate-patch/isolate_patch.dart:192:12)
```

…and the `reloadSources` RPC then never completes — no error response, no
timeout. The target isolate group appears to be left seized (service requests
against its isolates, e.g. `getIsolate`, also hang; in most orderings I saw,
the requesting isolate itself is seized too — in others it stays live but the
response simply never arrives).

The identical program started with `--enable-vm-service` reloads the same
edit successfully in <50 ms, and a reload with **no** changed sources
succeeds even on the runtime-enabled service — in everything I tried, the
crash needed both the runtime-enabled service and an actual source change.

The stack looks the same as the open #54905 (reached there via the internal
`--reload-every` flag). If this is really the same underlying issue, I'm
happy for this to become a comment on that issue instead — the parts that
seemed worth adding are the user-reachable path (`controlWebServer`) and the
hang: even if the crash itself is expected to be rare, the RPC hanging with
no response makes the failure hard for tooling to detect or recover from.
Whether that's one issue or two, you'll know better than I do.

## Reproduction

Two files, no dependencies. Clone-and-run:
<https://github.com/danReynolds/dart-reload-hang-repro> (includes a
`verify.sh` that runs both modes a few times and checks the observed
behavior). It has reproduced on every run I've tried on this machine —
10/10 from a fresh clone. The same two files inline:

`marker.dart`:

```dart
String greeting() => 'ORIGINAL';
```

`repro.dart` (raw-WebSocket VM-service client; handles the DDS handoff
event so the identical program is its own control under flags):

```dart
// Reproduction: `reloadSources` never completes (kernel-service crash on
// stderr) when the VM service was enabled at runtime via
// Service.controlWebServer and a loaded source file changed on disk.
//
//   dart repro.dart                      -> kernel-service crash on stderr;
//                                           the reload RPC never answers and
//                                           the process hangs (kill it)
//   dart --enable-vm-service repro.dart  -> ReloadReport success:true;
//                                           greeting() picks up the edit
//
// No dependencies (raw WebSocket JSON-RPC). Handles the DDS handoff event so
// the same client works in both modes. Each run writes a unique value into
// marker.dart so the repro works again even when a previous run left the
// file edited (`git checkout .` tidies up).
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'marker.dart' as m;

final _response = Completer<Map<String, Object?>>();

Future<void> _connectAndSend(Uri httpUri) async {
  final ws = await WebSocket.connect(
    httpUri
        .replace(
          scheme: 'ws',
          path: httpUri.path.endsWith('/')
              ? '${httpUri.path}ws'
              : '${httpUri.path}/ws',
        )
        .toString(),
  );
  ws.listen((data) {
    final msg = jsonDecode(data as String) as Map<String, Object?>;
    // Under --enable-vm-service, DDS attaches and closes this direct
    // connection; follow it to the new URI and retry there.
    final event = ((msg['params'] as Map?)?['event'] as Map?);
    if (event?['kind'] == 'DartDevelopmentServiceConnected') {
      unawaited(_connectAndSend(Uri.parse(event!['uri'] as String)));
      return;
    }
    if (msg['id'] == '1' && !_response.isCompleted) _response.complete(msg);
  });
  ws.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': '1',
      'method': 'reloadSources',
      'params': {'isolateId': developer.Service.getIsolateId(Isolate.current)},
    }),
  );
}

Future<void> main() async {
  var uri = (await developer.Service.getInfo()).serverUri;
  uri ??= (await developer.Service.controlWebServer(
    enable: true,
    silenceOutput: true,
  )).serverUri;

  print('before: ${m.greeting()}');
  // The trigger: a real on-disk change to a loaded source before the reload.
  // Unique per run, so the on-disk content always differs from what this
  // process was compiled from.
  File('${File.fromUri(Platform.script).parent.path}/marker.dart')
      .writeAsStringSync(
        "String greeting() => 'CHANGED ${DateTime.now().toIso8601String()}';\n",
      );
  await _connectAndSend(uri!);

  // In the failing mode this await never completes and the process must be
  // killed: the kernel-service crash (stderr) leaves the reload operation
  // wedged, and the requesting isolate is seized with it.
  final result = await _response.future;
  print('reload response: $result');
  print('after: ${m.greeting()}');
  exit(0);
}
```

Run:

```sh
dart repro.dart
# kernel-service crash on stderr; reloadSources never answers; process
# hangs until killed; greeting() still ORIGINAL

dart --enable-vm-service repro.dart
# control: "reload response: {…ReloadReport, success: true…}", greeting()
# picks up the edit (~50ms)
```

A note on the hang shape, since it varied a little: the RPC never received a
response in any variant I observed. In most orderings the requesting isolate
was seized outright (even its own timers stopped firing); in some it stayed
live but the response simply never arrived. An external client in a separate
process saw the same non-response, so it doesn't seem to be a
self-connection artifact.

## Variants tried (all Dart 3.12.2 stable, macOS arm64)

| target of reloadSources | service origin | sources edited | result |
| --- | --- | --- | --- |
| own (main) isolate group | runtime (`controlWebServer`) | no | ok, ~150 ms |
| own (main) isolate group | runtime | **yes** | **kernel-service crash + hang** |
| own (main) isolate group | `--enable-vm-service` | yes | ok, ~46 ms |
| `Isolate.spawnUri` child group | runtime | no | ok, ~160 ms |
| `Isolate.spawnUri` child group | runtime | **yes** | **kernel-service crash + hang** |
| `Isolate.spawnUri` child group | `--enable-vm-service` | yes | ok, ~50 ms |
| separate child **process**'s main group (external client) | runtime (child self-enabled) | **yes** | **hang** (crash on child stderr) |
| separate child process's main group (external client) | `--enable-vm-service` | yes | ok, ~35 ms |

In everything I tried, the outcome tracked only the service origin: every
runtime-enabled × edited-sources combination crashed and hung, every
flag-enabled combination succeeded, and every no-edit combination succeeded.

## Possibly-relevant code (my guess — could easily be wrong)

I'm not familiar with this code, so please take this as a pointer rather
than a diagnosis: `lookupOrBuildNewIncrementalCompiler` takes
`isolateCompilers.entries.first` (the comment there says "use first compiler
that should represent main isolate as a source for cloning"; the line looks
the same on current `main`). The stack suggests the map is empty when the
reload's compile request arrives in this configuration — maybe because a VM
booted without service/reload flags doesn't retain an incremental-compiler
session from the boot compilation? I may well be misreading how these pieces
fit together.

## Impact

`Service.controlWebServer` is the documented way for a program to opt into
the service at runtime, so tooling that uses it (in-process reload helpers;
in our case, a dev supervisor that now spawns a child process specifically to
get a flag-origin service instead) hits a silent, unrecoverable hang rather
than an error. Even if the crash itself turns out to be low priority, a
failed `reloadSources` response instead of a hang would make this detectable
for tooling — though I don't have a sense of how feasible that is on your
side.

## Environment

- Dart SDK 3.12.2 (stable), macOS arm64 (Darwin 25.2, Apple M1 Pro)
- Repro repo: <https://github.com/danReynolds/dart-reload-hang-repro>
- Possibly related: #54905 (same stack, reached via the internal
  `--reload-every` flag)
