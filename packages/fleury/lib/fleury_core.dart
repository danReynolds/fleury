/// Fleury — the platform-agnostic core.
///
/// Everything here is free of `dart:io`, so it compiles to the web (and any
/// other Dart target). The native umbrella `fleury.dart` re-exports this
/// plus the `dart:io`-backed pieces (native POSIX and Windows terminal drivers,
/// `runApp`, and stray-output capture). Platform hosts that mount and present a
/// Fleury tree should import `fleury_host.dart`, which re-exports this library
/// plus host-only runtime and presentation contracts.
///
/// See `docs/rfcs/0007-fleury-framework.md` for scope and gates.
library;

export 'src/primitives.dart';
export 'src/catalog/catalog.dart';
