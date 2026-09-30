// Smoke tests for HotReloadController. `tool/hot_reload_probe` proves the VM
// reload/state-preservation substrate; the Dart-Code → IsolateReload → Fleury
// UI path remains part of `doc/vscode_f5_acceptance.md`.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:fleury/src/runtime/hot_reload.dart';
import 'package:test/test.dart';

void main() {
  group('reload recovery', () {
    const compilerDetail =
        "lib/app.dart:25:17: Error: Can't find ')' to match '('.";
    test('compiler rejection preserves the diagnostic and recommends save', () {
      final payload = <String, Object?>{
        'success': false,
        'notices': [
          {'type': 'ReasonForCancelling', 'message': compilerDetail},
        ],
      };
      final report = HotReloadReport(
        success: false,
        elapsed: Duration.zero,
        loadedLibraryCount: 0,
        message: compilerDetail,
        restartRequired: HotReloadReport.requiresRestart(payload),
      );
      final description = report.failureDescription(canRestart: true);
      expect(description, contains('Fix errors and save again'));
      expect(description, contains('your app is still running'));
      expect(description, contains(compilerDetail));
      expect(description, isNot(contains('F5')));
      expect(description, isNot(contains('restart')));
    });

    test('a rejected class migration teaches an available restart', () {
      final report = HotReloadReport(
        success: false,
        elapsed: Duration.zero,
        loadedLibraryCount: 0,
        message: 'Class cannot be redefined to be a enum class',
        restartRequired: HotReloadReport.requiresRestart({
          'success': false,
          'notices': [
            {
              'type': 'ReasonForCancelling',
              'class': {'type': '@Class', 'name': 'Kind'},
              'message': 'Class cannot be redefined to be a enum class',
            },
          ],
        }),
      );
      expect(report.failureDescription(canRestart: true), contains('F5'));
      expect(report.failureDescription(canRestart: true), contains('resets'));
      expect(report.failureDescription(canRestart: false), contains('rerun'));
      expect(
        report.failureDescription(canRestart: false),
        isNot(contains('F5')),
      );
    });

    test('unknown or mixed failures never promise a restart will fix them', () {
      for (final payload in <Map<String, Object?>>[
        {},
        {'success': false, 'notices': []},
        {
          'success': false,
          'notices': ['unknown'],
        },
        {
          'success': false,
          'notices': [
            {
              'class': {'name': 'Kind'},
            },
            {'message': compilerDetail},
          ],
        },
        {
          'success': true,
          'notices': [
            {
              'class': {'name': 'Kind'},
            },
          ],
        },
      ]) {
        expect(HotReloadReport.requiresRestart(payload), isFalse);
      }
    });
  });

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
        final reports = <HotReloadReport>[];
        var throwOnReload = false;
        Future<HotReloadController> attach(String name) => runZonedGuarded(
          () => HotReloadController.attach(
            onReassemble: () {
              calls.add('reload:${Zone.current[zoneKey]}');
              if (throwOnReload) throw StateError('reload callback failed');
            },
            onReloadReport: (report) {
              reports.add(report);
              calls.add('report:${Zone.current[zoneKey]}');
            },
            onShutdownRequested: () =>
                calls.add('exit:${Zone.current[zoneKey]}'),
          ),
          (error, stack) => errors.add('$name:$error'),
          zoneValues: {zoneKey: name},
        )!;
        Future<void> invoke(String name, {Map<String, String>? args}) async {
          await vm
              .callServiceExtension(
                'ext.fleury.$name',
                isolateId: isolateId,
                args: args,
              )
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
        await invoke(
          'reloadReport',
          args: {
            'success': 'false',
            'message': 'Class migration rejected',
            'restartRequired': 'true',
          },
        );
        expect(reports.single.restartRequired, isTrue);
        expect(reports.single.message, 'Class migration rejected');
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
