// Smoke tests for HotReloadController. `tool/hot_reload_probe` proves the VM
// reload/state-preservation substrate; the Dart-Code → IsolateReload → Fleury
// UI path remains part of `doc/vscode_f5_acceptance.md`.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:fleury/src/runtime/hot_reload.dart';
import 'package:test/test.dart';

void main() {
  group('HotReloadController', tags: ['coverage-incompatible'], () {
    test(
      'persistent extensions dispatch in the current session zone',
      () async {
        final info = await developer.Service.getInfo();
        final uri = info.serverUri;
        if (uri == null) {
          markTestSkipped('Requires dart --enable-vm-service=0 test');
          return;
        }
        final vm = await connectVmServiceAt(uri);
        addTearDown(vm.dispose);
        final isolateId = developer.Service.getIsolateId(Isolate.current)!;
        final zoneKey = Object();
        final calls = <String>[];
        final errors = <String>[];
        var throwOnReload = false;
        Future<HotReloadController> attach(String name) => runZonedGuarded(
          () => HotReloadController.attach(
            onReassemble: () {
              calls.add('reload:${Zone.current[zoneKey]}');
              if (throwOnReload) throw StateError('reload callback failed');
            },
            onReloadReport: (_) => calls.add('report:${Zone.current[zoneKey]}'),
            onShutdownRequested: () =>
                calls.add('exit:${Zone.current[zoneKey]}'),
          ),
          (error, stack) => errors.add('$name:$error'),
          zoneValues: {zoneKey: name},
        )!;
        Future<void> invoke(String name) async {
          await vm
              .callServiceExtension('ext.fleury.$name', isolateId: isolateId)
              .timeout(const Duration(seconds: 2));
        }

        final first = await attach('first');
        addTearDown(first.dispose);
        await invoke('shutdown');
        await first.dispose();
        final second = await attach('second');
        addTearDown(second.dispose);
        // Disposing an older controller cannot unpublish the newer one.
        await first.dispose();
        await invoke('reassemble');
        await invoke('reloadReport');
        await invoke('shutdown');
        throwOnReload = true;
        await invoke('reassemble');
        expect(errors, ['second:Bad state: reload callback failed']);
        final disposing = second.dispose();
        await invoke('shutdown');
        await disposing;
        expect(calls, [
          'exit:first',
          'reload:second',
          'report:second',
          'exit:second',
          'reload:second',
        ]);
      },
    );

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
