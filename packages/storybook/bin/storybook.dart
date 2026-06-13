import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_storybook/src/storybook_runner.dart';
import 'package:fleury_storybook/storybook.dart';

Future<void> main(List<String> args) async {
  final options = _StorybookCliOptions.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  try {
    switch (options.command) {
      case _StorybookCommand.run:
        await _runInteractive(options);
      case _StorybookCommand.list:
        _printStoryCatalog(json: options.json);
      case _StorybookCommand.verify:
        _runVerify(options);
      case _StorybookCommand.snapshot:
        _runSnapshot(options);
      case _StorybookCommand.coverage:
        _runCoverage(options);
    }
  } on StorybookToolException catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }
}

Future<void> _runInteractive(_StorybookCliOptions options) async {
  final story = _storyForId(options.storyId);
  final overrides = _controlOverridesFor(story, options.controlSpecs);
  _validateVariant(story, options.variantId);

  await runTui(
    StorybookApp(
      initialStoryId: options.storyId,
      initialVariantId: options.variantId,
      initialControlValues: overrides,
      initialTheme: options.theme,
      initialViewport: options.viewport,
    ),
    mode: const TerminalMode(mouse: true),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.char == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

void _runVerify(_StorybookCliOptions options) {
  final story = _storyForId(options.storyId);
  final targets = storybookTargets(
    stories: storybookStories,
    storyId: options.storyId,
    variantId: options.variantId,
    includeVariants: options.includeVariants,
    controlOverrides: _controlOverridesFor(story, options.controlSpecs),
  );
  final size = _renderSize(options.viewport);
  final report = verifyStorybookTargets(
    targets,
    size: size,
    theme: options.theme,
  );

  if (options.json) {
    stdout.writeln(encodeJson(report.toJson()));
  } else {
    stdout.writeln(
      'Verified ${report.results.length}/${report.results.length + report.failures.length} '
      'storybook targets at ${size.cols}x${size.rows}.',
    );
    for (final failure in report.failures) {
      stdout.writeln('  FAIL ${failure.target.id}: ${failure.message}');
    }
  }
  if (!report.passed) exit(1);
}

void _runSnapshot(_StorybookCliOptions options) {
  final story = _storyForId(options.storyId);
  final targets = storybookTargets(
    stories: storybookStories,
    storyId: options.storyId,
    variantId: options.variantId,
    includeVariants: options.includeVariants,
    controlOverrides: _controlOverridesFor(story, options.controlSpecs),
  );
  final size = _renderSize(options.viewport);
  final report = verifyStorybookTargets(
    targets,
    size: size,
    theme: options.theme,
  );
  if (!report.passed) {
    if (options.json) {
      stdout.writeln(encodeJson(report.toJson()));
    } else {
      stderr.writeln('Snapshot capture failed:');
      for (final failure in report.failures) {
        stderr.writeln('  ${failure.target.id}: ${failure.message}');
      }
    }
    exit(1);
  }

  final output = Directory(options.outputPath ?? 'build/storybook-snapshots');
  final files = writeStorybookSnapshots(
    report.results,
    outputDirectory: output,
    theme: options.theme,
  );
  if (options.json) {
    stdout.writeln(
      encodeJson(<String, Object?>{
        'outputDirectory': output.path,
        'snapshotCount': files.length,
        'files': [for (final file in files) file.path],
        'results': [for (final result in report.results) result.toJson()],
      }),
    );
  } else {
    stdout.writeln('Wrote ${files.length} snapshots to ${output.path}');
    for (final file in files.take(8)) {
      stdout.writeln('  ${file.path}');
    }
    if (files.length > 8) stdout.writeln('  ... ${files.length - 8} more');
  }
}

void _runCoverage(_StorybookCliOptions options) {
  final exportedLibrary = File(
    options.widgetsExportPath ?? '../fleury_widgets/lib/fleury_widgets.dart',
  );
  if (!exportedLibrary.existsSync()) {
    throw StorybookToolException(
      'Widget export file not found: ${exportedLibrary.path}',
    );
  }
  final report = buildStorybookCoverageReport(
    stories: storybookStories,
    exportedLibrary: exportedLibrary,
  );
  if (options.json) {
    stdout.writeln(encodeJson(report.toJson()));
  } else {
    stdout.writeln(
      'Covered ${report.coveredWidgets.length}/${report.exportedWidgets.length} '
      'exported widget-like symbols.',
    );
    if (report.missingWidgets.isNotEmpty) {
      stdout.writeln('Missing: ${report.missingWidgets.join(', ')}');
    }
    if (report.extraCatalogWidgets.isNotEmpty) {
      stdout.writeln('Catalog-only: ${report.extraCatalogWidgets.join(', ')}');
    }
  }
  if (options.strict && !report.complete) exit(1);
}

Story? _storyForId(String? storyId) {
  if (storyId == null) return null;
  final story = storybookStories
      .where((story) => story.id == storyId)
      .firstOrNull;
  if (story == null) {
    throw StorybookToolException(
      'Unknown story: $storyId\n'
      'Run `dart run bin/storybook.dart list` to see stories.',
    );
  }
  return story;
}

Map<String, Object?> _controlOverridesFor(
  Story? story,
  List<String> controlSpecs,
) {
  if (controlSpecs.isEmpty) return const <String, Object?>{};
  if (story == null) {
    throw const StorybookToolException(
      '--control requires --story so control ids are unambiguous.',
    );
  }
  return parseControlOverrides(story, controlSpecs);
}

void _validateVariant(Story? story, String? variantId) {
  if (variantId == null) return;
  if (story == null) {
    throw const StorybookToolException('--variant requires --story.');
  }
  if (!story.variants.any((variant) => variant.id == variantId)) {
    throw StorybookToolException('Unknown variant for ${story.id}: $variantId');
  }
}

CellSize _renderSize(StorybookViewportPreset preset) {
  return storybookViewportSize(preset) ?? const CellSize(120, 40);
}

void _printUsage() {
  stdout.writeln('Fleury Storybook');
  stdout.writeln('');
  stdout.writeln('Usage: dart run bin/storybook.dart [command] [options]');
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln(
    '  run                 Open the interactive storybook. Default.',
  );
  stdout.writeln('  list                List stories, controls, and variants.');
  stdout.writeln('  verify              Render every selected story target.');
  stdout.writeln(
    '  snapshot            Capture text snapshots for story targets.',
  );
  stdout.writeln(
    '  coverage            Compare stories against exported widgets.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --help, -h              Show this help.');
  stdout.writeln(
    '  --json                  Emit JSON for list/verify/snapshot/coverage.',
  );
  stdout.writeln('  --story <id>            Select a story by id.');
  stdout.writeln('  --variant <id>          Select a story variant by id.');
  stdout.writeln(
    '  --control <id=value>    Override a selected story control.',
  );
  stdout.writeln(
    '  --theme <name>          terminal, dark, light, high-contrast.',
  );
  stdout.writeln(
    '  --size <preset>         fit, 80x24, 100x30, 120x40, or 60x20.',
  );
  stdout.writeln(
    '  --default-only          Skip variants for verify/snapshot.',
  );
  stdout.writeln('  --output <dir>          Snapshot output directory.');
  stdout.writeln(
    '  --widgets-export <path> Widget package export file for coverage.',
  );
  stdout.writeln(
    '  --strict                Fail coverage when exports are missing.',
  );
  stdout.writeln('');
  stdout.writeln('Legacy aliases:');
  stdout.writeln('  --list                  Same as `list`.');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dart run bin/storybook.dart');
  stdout.writeln('  dart run bin/storybook.dart list --json');
  stdout.writeln(
    '  dart run bin/storybook.dart verify --story visualization.charts.line-chart',
  );
  stdout.writeln(
    '  dart run bin/storybook.dart snapshot --story data.tables.data-table --variant cell-selection',
  );
  stdout.writeln(
    '  dart run bin/storybook.dart run --story visualization.charts.line-chart --control samples=16',
  );
}

void _printStoryCatalog({required bool json}) {
  if (json) {
    stdout.writeln(
      encodeJson(<String, Object?>{
        'stories': [for (final story in storybookStories) _storyJson(story)],
      }),
    );
    return;
  }

  for (final story in storybookStories) {
    stdout.writeln('${story.id}\t${story.category}\t${story.title}');
    for (final variant in story.variants) {
      stdout.writeln('  variant:${variant.id}\t${variant.label}');
    }
  }
}

Map<String, Object?> _storyJson(Story story) => <String, Object?>{
  'id': story.id,
  'title': story.title,
  'category': story.category,
  'description': story.description,
  'widgets': story.widgets,
  if (story.defaultControlValues.isNotEmpty)
    'defaultControlValues': story.defaultControlValues,
  'controls': [
    for (final control in story.controls)
      <String, Object?>{
        'id': control.id,
        'label': control.label,
        'type': control.type.name,
        if (control.options.isNotEmpty) 'options': control.options,
        'initialValue': control.initialValue,
        if (control.placeholder.isNotEmpty) 'placeholder': control.placeholder,
        if (control.min != null) 'min': control.min,
        if (control.max != null) 'max': control.max,
        if (control.step != null) 'step': control.step,
      },
  ],
  'variants': [
    for (final variant in story.variants)
      <String, Object?>{
        'id': variant.id,
        'label': variant.label,
        'description': variant.description,
        'controlValues': variant.controlValues,
      },
  ],
};

enum _StorybookCommand { run, list, verify, snapshot, coverage }

final class _StorybookCliOptions {
  const _StorybookCliOptions({
    required this.command,
    required this.help,
    required this.json,
    required this.strict,
    required this.includeVariants,
    required this.storyId,
    required this.variantId,
    required this.controlSpecs,
    required this.theme,
    required this.viewport,
    required this.outputPath,
    required this.widgetsExportPath,
  });

  final _StorybookCommand command;
  final bool help;
  final bool json;
  final bool strict;
  final bool includeVariants;
  final String? storyId;
  final String? variantId;
  final List<String> controlSpecs;
  final StorybookThemeMode theme;
  final StorybookViewportPreset viewport;
  final String? outputPath;
  final String? widgetsExportPath;

  static _StorybookCliOptions parse(List<String> args) {
    var command = _StorybookCommand.run;
    var start = 0;
    if (args.isNotEmpty && !args.first.startsWith('-')) {
      command = _parseCommand(args.first);
      start = 1;
    }

    var help = false;
    var json = false;
    var strict = false;
    var includeVariants = true;
    String? storyId;
    String? variantId;
    String? outputPath;
    String? widgetsExportPath;
    final controlSpecs = <String>[];
    var theme = StorybookThemeMode.terminal;
    var viewport = StorybookViewportPreset.fit;

    for (var i = start; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-h' || arg == '--help') {
        help = true;
      } else if (arg == '--list') {
        command = _StorybookCommand.list;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg == '--default-only') {
        includeVariants = false;
      } else if (arg == '--all-variants') {
        includeVariants = true;
      } else if (arg == '--story') {
        storyId = _readValue(args, ++i, '--story');
      } else if (arg.startsWith('--story=')) {
        storyId = arg.substring('--story='.length);
      } else if (arg == '--variant') {
        variantId = _readValue(args, ++i, '--variant');
      } else if (arg.startsWith('--variant=')) {
        variantId = arg.substring('--variant='.length);
      } else if (arg == '--control') {
        controlSpecs.add(_readValue(args, ++i, '--control'));
      } else if (arg.startsWith('--control=')) {
        controlSpecs.add(arg.substring('--control='.length));
      } else if (arg == '--theme') {
        theme = _parseTheme(_readValue(args, ++i, '--theme'));
      } else if (arg.startsWith('--theme=')) {
        theme = _parseTheme(arg.substring('--theme='.length));
      } else if (arg == '--size' || arg == '--viewport') {
        viewport = _parseViewport(_readValue(args, ++i, arg));
      } else if (arg.startsWith('--size=')) {
        viewport = _parseViewport(arg.substring('--size='.length));
      } else if (arg.startsWith('--viewport=')) {
        viewport = _parseViewport(arg.substring('--viewport='.length));
      } else if (arg == '--output') {
        outputPath = _readValue(args, ++i, '--output');
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg == '--widgets-export') {
        widgetsExportPath = _readValue(args, ++i, '--widgets-export');
      } else if (arg.startsWith('--widgets-export=')) {
        widgetsExportPath = arg.substring('--widgets-export='.length);
      } else {
        stderr.writeln('Unknown option: $arg');
        _printUsage();
        exit(2);
      }
    }

    return _StorybookCliOptions(
      command: command,
      help: help,
      json: json,
      strict: strict,
      includeVariants: includeVariants,
      storyId: storyId,
      variantId: variantId,
      controlSpecs: List<String>.unmodifiable(controlSpecs),
      theme: theme,
      viewport: viewport,
      outputPath: outputPath,
      widgetsExportPath: widgetsExportPath,
    );
  }
}

_StorybookCommand _parseCommand(String raw) {
  return switch (raw) {
    'run' => _StorybookCommand.run,
    'list' => _StorybookCommand.list,
    'verify' || 'smoke' => _StorybookCommand.verify,
    'snapshot' || 'snapshots' => _StorybookCommand.snapshot,
    'coverage' => _StorybookCommand.coverage,
    'help' => _StorybookCommand.run,
    _ => _unknownCommand(raw),
  };
}

_StorybookCommand _unknownCommand(String raw) {
  stderr.writeln('Unknown command: $raw');
  _printUsage();
  exit(2);
}

String _readValue(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('-')) {
    stderr.writeln('$option requires a value.');
    exit(2);
  }
  return args[index];
}

StorybookThemeMode _parseTheme(String raw) {
  final normalized = raw.toLowerCase().replaceAll('_', '-');
  return switch (normalized) {
    'terminal' || 'default' => StorybookThemeMode.terminal,
    'dark' => StorybookThemeMode.dark,
    'light' => StorybookThemeMode.light,
    'high-contrast' || 'highcontrast' => StorybookThemeMode.highContrast,
    _ => _failTheme(raw),
  };
}

StorybookThemeMode _failTheme(String value) {
  stderr.writeln('Unknown theme: $value');
  stderr.writeln('Expected terminal, dark, light, or high-contrast.');
  exit(2);
}

StorybookViewportPreset _parseViewport(String raw) {
  final normalized = raw.toLowerCase().replaceAll('_', '-');
  return switch (normalized) {
    'fit' || 'auto' => StorybookViewportPreset.fit,
    '80x24' ||
    'compact' ||
    'compact80x24' ||
    'compact-80x24' => StorybookViewportPreset.compact80x24,
    '100x30' ||
    'standard' ||
    'standard100x30' ||
    'standard-100x30' => StorybookViewportPreset.standard100x30,
    '120x40' ||
    'wide' ||
    'wide120x40' ||
    'wide-120x40' => StorybookViewportPreset.wide120x40,
    '60x20' ||
    'narrow' ||
    'narrow60x20' ||
    'narrow-60x20' => StorybookViewportPreset.narrow60x20,
    _ => _failViewport(raw),
  };
}

StorybookViewportPreset _failViewport(String value) {
  stderr.writeln('Unknown size preset: $value');
  stderr.writeln('Expected fit, 80x24, 100x30, 120x40, or 60x20.');
  exit(2);
}
