// Probe target: exercises the three load-bearing properties for
// state-preserving hot reload. See ../README.md for context.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';

class Counter {
  int value = 0;

  // The literal in this string is mutated by the driver between
  // snapshots to verify that method bodies dispatch to reloaded code.
  String label() => 'Counter v1: $value';
}

// Heap reference captured at startup. The driver checks that
// `identityHashCode(instance)` is stable across the reload.
late final Counter instance;

// Captured before reload; compared after reload.
late final Type capturedRuntimeType;
late final int capturedIdentityHash;

void main() {
  instance = Counter();
  instance.value = 5;
  capturedRuntimeType = instance.runtimeType;
  capturedIdentityHash = identityHashCode(instance);

  registerExtension('ext.fleury.probe', (method, parameters) async {
    final fresh = Counter();
    final snapshot = <String, Object?>{
      'instance_identity_hash': identityHashCode(instance),
      'captured_identity_hash': capturedIdentityHash,
      'identity_preserved': identityHashCode(instance) == capturedIdentityHash,
      'instance_value': instance.value,
      'instance_label': instance.label(),
      'fresh_label': fresh.label(),
      'instance_runtime_type_string': instance.runtimeType.toString(),
      'fresh_runtime_type_string': fresh.runtimeType.toString(),
      'captured_runtime_type_string': capturedRuntimeType.toString(),
      'instance_type_equals_fresh': instance.runtimeType == fresh.runtimeType,
      'instance_type_identical_fresh': identical(
        instance.runtimeType,
        fresh.runtimeType,
      ),
      'instance_type_equals_captured':
          instance.runtimeType == capturedRuntimeType,
      'instance_type_identical_captured': identical(
        instance.runtimeType,
        capturedRuntimeType,
      ),
    };
    return ServiceExtensionResponse.result(jsonEncode(snapshot));
  });

  // Signal readiness on a known line so the driver can sync without
  // depending on Observatory banner formatting.
  print('PROBE_TARGET_READY');

  // Keep the isolate alive long enough for the driver to do its work.
  Timer(const Duration(seconds: 60), () {
    // Driver should have exited by now; exit cleanly if it didn't.
  });
}
