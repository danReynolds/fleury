@TestOn('vm')
import 'dart:io';

import 'package:test/test.dart';

const _layoutReadTokens = [
  'getBoundingClientRect',
  'getClientRects',
  'getComputedStyle',
  'offsetWidth',
  'offsetHeight',
  'clientWidth',
  'clientHeight',
  'scrollWidth',
  'scrollHeight',
];

void main() {
  test('retained DOM web public boundary is intentionally narrow', () {
    final barrel = File('lib/fleury_web.dart');
    final text = barrel.readAsStringSync();
    final exportLines = barrel
        .readAsLinesSync()
        .map((line) => line.trimLeft())
        .where((line) => line.startsWith('export '))
        .join('\n');

    expect(
      exportLines,
      contains("export 'src/run_tui_web_dom.dart' show runTuiWebDom;"),
      reason: 'runTuiWebDom is the explicit retained DOM browser entry point.',
    );
    expect(
      exportLines,
      contains("export 'src/run_tui_surface.dart' show TuiSurfaceHost;"),
      reason:
          'Callers must be able to name the host handle returned by '
          'runTuiWebDom.',
    );
    expect(
      exportLines,
      contains("export 'src/run_tui_web.dart' show runTuiWeb;"),
      reason: 'The xterm-compatible path remains public until Phase 6 retires.',
    );

    expect(
      exportLines,
      isNot(contains('runTuiSurface')),
      reason:
          'Lower-level surface assembly must stay package-owned until the web '
          'host boundary is stable.',
    );
    expect(
      exportLines,
      isNot(contains('DomGridSurface')),
      reason:
          'The retained DOM presenter implementation is not a public extension '
          'contract yet.',
    );
    expect(
      exportLines,
      isNot(contains('DomInputSource')),
      reason:
          'Browser event mapping remains host-owned while input semantics are '
          'still under web gate validation.',
    );
    expect(
      exportLines,
      isNot(contains('SemanticDomPresenter')),
      reason:
          'The accessibility DOM presenter remains package-owned until the '
          'screen-reader follow-up settles the public contract.',
    );
    expect(
      exportLines,
      isNot(contains('DomCellMetrics')),
      reason:
          'Browser layout reads should stay behind the retained DOM host, not '
          'become an app-facing API.',
    );

    expect(
      text,
      contains('runTuiWebDom'),
      reason: 'The package barrel should expose the retained DOM path.',
    );
    expect(
      text,
      contains('TuiSurfaceHost'),
      reason: 'The package barrel should expose the public host handle.',
    );
  });

  test('browser layout reads stay isolated to DOM metrics', () {
    final libDir = Directory('lib/src');
    final offenders = <String>[];
    for (final file
        in libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final path = file.path.replaceAll(r'\', '/');
      if (path == 'lib/src/metrics/dom_cell_metrics.dart') continue;
      final text = file.readAsStringSync();
      for (final token in _layoutReadTokens) {
        if (text.contains(token)) offenders.add('$path uses $token');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Browser layout reads must stay in DomCellMetrics.measure(), the '
          'host read phase. Frame presentation, semantic presentation, input, '
          'and focus code should consume cached measurements instead.',
    );
  });
}
