// Route names under the compilers browser apps ship with. A route is named
// after its screen's class, which tests and agents use to tell routes apart,
// but an optimized dart2js build minifies class names to tokens like
// `minified:hv` that a screen reader would announce as the page's name.
// Compiles test/fixtures/route_label_probe.dart with dart2js and runs it under
// Node: unminified (-O1) as the control that names survive, and optimized (-O2)
// where the route must be left unnamed.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

const _probe = 'test/fixtures/route_label_probe.dart';

void main() {
  final node = _nodeAvailable();
  final skip = node ? null : 'needs Node.js on PATH to run dart2js output';

  test(
    'an unminified web build names a route after its screen class',
    () async {
      expect(
        await _probeOutput('-O1'),
        'label=SettingsScreen '
        'routeName=SettingsScreen',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'an optimized web build leaves a route unnamed instead of minified',
    () async {
      expect(await _probeOutput('-O2'), 'label=null routeName=null');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Compiles the probe with dart2js at [level], runs it under Node, and returns
/// what it printed.
Future<String> _probeOutput(String level) async {
  final dir = Directory.systemTemp.createTempSync('fleury_route_label_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final js = '${dir.path}/probe.js';
  final compile = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    level,
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
  final run = await Process.run('node', [runner.path]);
  expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
  return (run.stdout as String).trim();
}

bool _nodeAvailable() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
