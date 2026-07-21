# DRAFT — dart-lang/sdk bug report (for review before filing)

> Status: draft. Verified on Dart 3.12.2 (stable) macOS arm64; the crashing
> `.first` is still present on sdk `main` (pkg/vm/bin/kernel_service.dart,
> `lookupOrBuildNewIncrementalCompiler`). Same crash signature as the open
> #54905, which reaches it via the internal `--reload-every` flag; this report
> covers the user-reachable path and the resulting protocol hang.

---

**Title:** `reloadSources` hangs forever (kernel-service crash) when the VM
service was enabled at runtime via `Service.controlWebServer`

## Summary

If a program enables the VM service **at runtime** with
`dart:developer`'s `Service.controlWebServer(enable: true)` (instead of the
`--enable-vm-service` flag) and a client then calls `reloadSources` **after a
source file changed on disk**, the VM's kernel service crashes:

```
kernel-service: Error: Unhandled exception:
Bad state: No element
#0      Iterable.first (dart:core/iterable.dart:663:7)
#1      lookupOrBuildNewIncrementalCompiler (…/pkg/vm/bin/kernel_service.dart:518:45)
#2      _processLoadRequest (…/pkg/vm/bin/kernel_service.dart:981:22)
#3      _RawReceivePort._handleMessage (dart:isolate-patch/isolate_patch.dart:192:12)
```

…and the `reloadSources` RPC then **never completes** — no error response, no
timeout. The target isolate group is left seized (service requests against its
isolates, e.g. `getIsolate`, also hang; in most observed orderings the
requesting isolate itself is seized too — in others it stays live but the
response simply never arrives).

Two defects, arguably:

1. The kernel service crashes (`.first` on an empty `isolateCompilers` in
   `lookupOrBuildNewIncrementalCompiler`) — same signature as #54905, which
   reaches it via the internal `--reload-every` flag.
2. The crash is not surfaced: `reloadSources` should fail with an RPC error,
   but instead hangs indefinitely, which makes the failure undetectable and
   unrecoverable for tooling.

The identical program started with `--enable-vm-service` flags reloads the
same edit successfully in <50 ms. A reload with **no** changed sources
succeeds even on the runtime-enabled service — the crash requires an actual
source change (the incremental-compile path).

## Reproduction

**Zero dependencies, two files, 100% reproducible** (8/8 runs across
variants on this machine). `marker.dart`:

```dart
String greeting() => 'ORIGINAL';
```

`repro.dart` (raw-WebSocket VM-service client; handles the DDS handoff
event so the identical program is its own control under flags):

```dart
// Repro: `reloadSources` never completes (VM kernel-service crash) when the
// VM service was enabled at runtime via Service.controlWebServer and a
// loaded source file changed on disk.
//
//   dart repro.dart                      -> kernel-service crash on stderr;
//                                           the reload RPC never answers and
//                                           the process hangs (kill it)
//   dart --enable-vm-service repro.dart  -> ReloadReport success:true;
//                                           greeting() becomes CHANGED
//
// Zero dependencies (raw WebSocket JSON-RPC). Handles the DDS handoff event
// so the same client works in both modes.
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
  File('${File.fromUri(Platform.script).parent.path}/marker.dart')
      .writeAsStringSync("String greeting() => 'CHANGED';\n");
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
# becomes CHANGED (~50ms)
```

Notes on the hang shape: the RPC never receives a response in any observed
variant. In most orderings the requesting isolate is seized outright (even
its own timers cannot fire); in some, the isolate stays live but the
response simply never arrives. An external client (separate process) shows
the same non-response, so it is not a self-connection artifact.

## Variants tested (all Dart 3.12.2 stable, macOS arm64)

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

The failing dimension is exclusively the **service origin**: every
runtime-enabled × edited-sources combination crashes and hangs; every
flag-enabled combination succeeds; every no-edit combination succeeds. The
external-client row shows it is not a self-connection artifact.

## Likely mechanism (hypothesis)

`lookupOrBuildNewIncrementalCompiler` clones from
`isolateCompilers.entries.first` ("use first compiler that should represent
main isolate as a source for cloning" — still present on `main`). When the VM
boots without service/reload flags, no incremental-compiler session appears to
be retained for the boot compilation, so the map is empty when a reload's
compile request arrives later, and `.first` throws `Bad state: No element`.
The reload operation then waits forever on a compile response that will never
come.

## Why this matters

`Service.controlWebServer` is the documented way for a program to opt into
the service at runtime; dev tools that use it (e.g. in-process reload
helpers, and our terminal-UI framework's dev supervisor — which now must
spawn a child process purely to get flag-origin service) silently hit an
unrecoverable hang rather than an error. Even if the crash itself is
non-trivial to fix, surfacing it as a failed `reloadSources` response instead
of a hang would make the failure mode tractable for tooling.

## Environment

- Dart SDK 3.12.2 (stable) — `dartvm` macOS arm64 (also inspected
  `pkg/vm/bin/kernel_service.dart` on current `main`: the `.first` remains)
- macOS 15.x (Darwin 25.2), Apple M1 Pro
- Related: #54905 (same crash signature via the internal `--reload-every`
  flag, filed by @dcharkes)
