// Route names under the compilers apps ship with. A route is named after its
// screen's class, which tests and agents use to tell routes apart, but an
// optimized dart2js build minifies class names to tokens like `minified:hv`
// that a screen reader would announce as the page's name. Runs
// test/fixtures/route_label_probe.dart on the VM and as dart2js -O2 output
// under Node.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

const _probe = 'test/fixtures/route_label_probe.dart';

void main() {
  final node = _nodeExecutable();

  test(
    'the VM names a route after its screen class',
    () async {
      final run = await Process.run(Platform.resolvedExecutable, [
        'run',
        _probe,
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      // The probe prints the active route's label and routeName.
      expect((run.stdout as String).trim(), 'SettingsScreen SettingsScreen');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'an optimized web build leaves a route unnamed instead of minified',
    () async {
      final dir = Directory.systemTemp.createTempSync('fleury_route_label_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final js = '${dir.path}/probe.js';
      final compile = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'js',
        '-O2',
        _probe,
        '-o',
        js,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stdout}${compile.stderr}');

      // dart2js output expects the browser's `self` global.
      final runner = File('${dir.path}/run.js')
        ..writeAsStringSync(
          'globalThis.self = globalThis;\n${File(js).readAsStringSync()}',
        );
      final run = await Process.run(node!, [runner.path]);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect((run.stdout as String).trim(), 'null null');
    },
    skip: node == null ? 'needs Node.js on PATH to run dart2js output' : null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

String? _nodeExecutable() {
  final result = Process.runSync('which', ['node']);
  return result.exitCode == 0 ? (result.stdout as String).trim() : null;
}
