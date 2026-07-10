// A minimal runApp app for serve --spawn debug-wire tests: connects via
// FLEURY_HANDLE auto-discovery and (under JIT) has debug tooling enabled by
// default — so whether it ANSWERS debugRequest frames over the wire is decided
// purely by the FLEURY_DEBUG_WIRE env `fleury serve` injects.

import 'package:fleury/fleury.dart';

Future<void> main() async {
  await runApp(const Text('serve debug fixture'));
}
