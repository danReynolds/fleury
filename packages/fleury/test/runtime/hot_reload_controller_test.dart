// Smoke tests for HotReloadController. `tool/hot_reload_probe` proves the VM
// reload/state-preservation substrate; the Dart-Code → IsolateReload → Fleury
// UI path remains part of `doc/vscode_f5_acceptance.md`.

import 'dart:developer' as developer;

import 'package:fleury/src/runtime/hot_reload.dart';
import 'package:test/test.dart';

void main() {
  group('HotReloadController', tags: ['coverage-incompatible'], () {
    test('attach registers the reassemble surface without throwing', () async {
      final controller = await HotReloadController.attach(onReassemble: () {});
      addTearDown(controller.dispose);

      // A unit test has no independent VM-service client with which to invoke
      // the extension. The VM reload substrate is exercised by
      // tool/hot_reload_probe; this is the controller registration smoke.
      expect(controller, isNotNull);
    });

    test('dispose is safe to call multiple times', () async {
      final controller = await HotReloadController.attach(onReassemble: () {});
      await controller.dispose();
      await controller.dispose(); // must not throw
    });

    test('dev is false when --enable-vm-service is not passed', () async {
      // The Dart test runner spawns isolates without --enable-vm-service
      // by default, so Service.getInfo().serverUri is null and we land
      // on the non-dev branch.
      final controller = await HotReloadController.attach(onReassemble: () {});
      addTearDown(controller.dispose);
      // We can't assert false here unconditionally because the user
      // may run `dart test --enable-vm-service` locally. Just verify
      // the field reflects whatever the VM is doing.
      final info = await developer.Service.getInfo();
      expect(controller.dev, info.serverUri != null);
    });
  });
}
