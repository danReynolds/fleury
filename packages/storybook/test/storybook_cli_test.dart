import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  const cliTimeout = Timeout(Duration(seconds: 90));

  test('help documents query and launch options', () async {
    final result = await _runStorybook(<String>['--help']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final output = result.stdout.toString();
    expect(output, contains('verify'));
    expect(output, contains('snapshot'));
    expect(output, contains('coverage'));
    expect(output, contains('--story <id>'));
    expect(output, contains('--variant <id>'));
    expect(output, contains('--control <id=value>'));
    expect(output, contains('--theme <name>'));
    expect(output, contains('--size <preset>'));
  }, timeout: cliTimeout);

  test('list json exposes story metadata and typed controls', () async {
    final result = await _runStorybook(<String>['list', '--json']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded = jsonDecode(result.stdout.toString());
    expect(decoded, isA<Map<String, Object?>>());
    final catalog = decoded as Map<String, Object?>;
    final stories = catalog['stories'] as List<Object?>;
    expect(stories, isNotEmpty);

    final charts = stories.cast<Map<String, Object?>>().singleWhere(
      (story) => story['id'] == 'visualization.charts.line-chart',
    );
    expect(charts['category'], 'Visualization');
    expect(charts['widgets'], ['LineChart']);
    expect(charts['defaultControlValues'], containsPair('interactive', 1));

    final controls = (charts['controls'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(controls, contains(containsPair('type', 'number')));

    final variants = (charts['variants'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(variants, contains(containsPair('id', 'dense-interactive')));
  }, timeout: cliTimeout);

  test('verify renders selected story variants', () async {
    final result = await _runStorybook(<String>[
      'verify',
      '--story',
      'visualization.charts.line-chart',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(decoded['passed'], isTrue);
    expect(decoded['targetCount'], 3);
    final results = (decoded['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      results.map((result) => result['variantId']),
      contains('distribution'),
    );
  }, timeout: cliTimeout);

  test('verify accepts selected story control overrides', () async {
    final result = await _runStorybook(<String>[
      'verify',
      '--story',
      'visualization.charts.line-chart',
      '--default-only',
      '--control',
      'samples=16',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    final results = (decoded['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final controls = results.single['controls'] as Map<String, Object?>;
    expect(controls['samples'], 16);
  }, timeout: cliTimeout);

  test('verify accepts the explicit default variant target', () async {
    final result = await _runStorybook(<String>[
      'verify',
      '--story',
      'controls.boolean-buttons.button',
      '--variant',
      'default',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(decoded['passed'], isTrue);
    final results = (decoded['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(results.single['variantId'], 'default');
    final controls = results.single['controls'] as Map<String, Object?>;
    expect(controls['disabled'], 0);
  }, timeout: cliTimeout);

  test('snapshot writes selected target file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'fleury_storybook_snapshot_test_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final result = await _runStorybook(<String>[
      'snapshot',
      '--story',
      'data.tables.data-table',
      '--variant',
      'cell-selection',
      '--output',
      tempDir.path,
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(decoded['snapshotCount'], 1);
    final files = (decoded['files'] as List<Object?>).cast<String>();
    expect(
      files.single,
      endsWith('data.tables.data-table__cell-selection.txt'),
    );
    expect(
      File(files.single).readAsStringSync(),
      contains('# data.tables.data-table:cell-selection'),
    );
  }, timeout: cliTimeout);

  test('coverage strict passes for exported widget-like symbols', () async {
    final result = await _runStorybook(<String>[
      'coverage',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded =
        jsonDecode(result.stdout.toString()) as Map<String, Object?>;
    expect(decoded['complete'], isTrue);
    expect(decoded['missingWidgetCount'], 0);
  }, timeout: cliTimeout);

  test('invalid story exits before opening the TUI', () async {
    final result = await _runStorybook(<String>['--story', 'missing.story']);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('Unknown story: missing.story'));
  }, timeout: cliTimeout);

  test('the `help` subcommand prints usage and exits 0 (no TUI takeover)',
      () async {
    final result = await _runStorybook(<String>['help']);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final output = result.stdout.toString();
    expect(output, contains('Usage: dart run bin/storybook.dart'));
    expect(output, contains('Commands:'));
  }, timeout: cliTimeout);
}

Future<ProcessResult> _runStorybook(List<String> args) {
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/storybook.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}
