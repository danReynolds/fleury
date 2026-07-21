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
isolates, e.g. `getIsolate`, also hang; in the self-reload shape the
requesting isolate itself freezes, so the process is fully wedged).

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

Two files plus a `pubspec.yaml` depending on `vm_service` (any recent
version; used only as a convenience client).

`lib/marker.dart`:

```dart
String greeting() => 'ALPHA';
```

`bin/repro.dart`:

```dart
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:reload_repro/marker.dart' as m;
import 'package:vm_service/vm_service.dart' hide Isolate;
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  File('lib/marker.dart').writeAsStringSync("String greeting() => 'ALPHA';\n");
  final uri = (await developer.Service.controlWebServer(
    enable: true,
    silenceOutput: true,
  )).serverUri!;
  final ws = uri.replace(
      scheme: 'ws',
      path: uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws');
  final vm = await vmServiceConnectUri(ws.toString());
  final selfId = developer.Service.getIsolateId(Isolate.current)!;
  print('before: ${m.greeting()}');
  // The trigger: an actual on-disk change before the reload.
  File('lib/marker.dart').writeAsStringSync("String greeting() => 'BETA';\n");
  final sw = Stopwatch()..start();
  try {
    final r =
        await vm.reloadSources(selfId).timeout(const Duration(seconds: 20));
    print('reload success=${r.success} in ${sw.elapsedMilliseconds}ms; '
        'after: ${m.greeting()}');
  } on TimeoutException {
    print('HANG (>20s)'); // Never prints: the requester itself is seized.
  }
  exit(0);
}
```

Run:

```sh
dart bin/repro.dart              # kernel-service crash on stderr; process wedges
dart --enable-vm-service=0 bin/repro.dart
                                 # control: "reload success=true in 46ms; after: BETA"
```

Observed (crash case): the kernel-service stack above on stderr, then the
process hangs until killed. Note even the in-process 20-second `timeout` never
fires — the reload operation seizes the requester's own group. (An external
timeout: `timeout 40 dart bin/repro.dart` exits 124.)

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
