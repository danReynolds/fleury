import 'dart:convert';
import 'dart:io';

import 'package:fleury_web/src/benchmark/web_benchmark_scenarios.dart';
import 'package:fleury_web/src/instrumentation/web_host_instrumentation.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final plan = _SuitePlan.fromOptions(options);
  if (options.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(plan.toJson()));
  }
  if (options.dryRun) {
    if (!options.json) {
      for (final command in plan.commands) {
        stdout.writeln(_displayCommand(command));
      }
    }
    return;
  }

  Directory(options.outputDir).createSync(recursive: true);
  if (plan.compileCommand != null) {
    await _runCommand(plan.compileCommand!);
  }
  try {
    for (final command in plan.captureCommands) {
      await _runCommand(command);
    }
    await _runCommand(plan.scoreboardCommand);
  } finally {
    if (plan.compiledPageDir != null && !options.keepTemp) {
      try {
        Directory(plan.compiledPageDir!).deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
    }
  }
  if (!options.json) {
    stdout.writeln('captures written under ${options.outputDir}');
    stdout.writeln('scoreboard written to ${options.scoreboardPath}');
  }
}

final class _SuitePlan {
  const _SuitePlan({
    required this.options,
    required this.scenarios,
    required this.compileCommand,
    required this.compiledPageDir,
    required this.captureCommands,
    required this.scoreboardCommand,
  });

  factory _SuitePlan.fromOptions(_Options options) {
    final scenarios = [
      for (final id in options.scenarioIds) webBenchmarkScenarioById(id)!,
    ];
    final compiledPageDir = options.compileOnce
        ? '${options.outputDir}${Platform.pathSeparator}.fleury-web-frame-page'
        : null;
    final compileCommand = compiledPageDir == null
        ? null
        : _Command('dart', [
            'run',
            'tool/web_frame_capture.dart',
            '--compile-only',
            '--page-dir=$compiledPageDir',
          ]);
    final captureCommands = <_Command>[];
    final runWidth = options.runs.toString().length;
    for (final scenario in scenarios) {
      for (var run = 1; run <= options.runs; run++) {
        final runLabel = run.toString().padLeft(runWidth, '0');
        captureCommands.add(
          _Command('dart', [
            'run',
            'tool/web_frame_capture.dart',
            '--scenario=${scenario.id}',
            '--warmup=${options.warmupFrames}',
            '--budget-ms=${options.frameBudgetMs}',
            '--output=${options.outputDir}/${scenario.id}-run-$runLabel.json',
            if (compiledPageDir != null) '--page-dir=$compiledPageDir',
            '--timeout=${options.timeoutSeconds}',
            if (options.frames != null) '--frames=${options.frames}',
            if (options.chromePath != null) '--chrome=${options.chromePath}',
            if (options.headful) '--headful',
            if (options.keepTemp) '--keep-temp',
          ]),
        );
      }
    }
    final scoreboardCommand = _Command('dart', [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${options.outputDir}',
      '--output=${options.scoreboardPath}',
      '--json-output=${options.scoreboardJsonPath}',
      '--min-runs=${options.minRuns}',
      if (options.gates.maxTotalFrameP95Ms != null)
        '--max-total-frame-p95-ms=${options.gates.maxTotalFrameP95Ms}',
      if (options.gates.maxDomApplyP95Ms != null)
        '--max-dom-apply-p95-ms=${options.gates.maxDomApplyP95Ms}',
      if (options.gates.maxSemanticApplyP95Ms != null)
        '--max-semantic-apply-p95-ms=${options.gates.maxSemanticApplyP95Ms}',
      if (options.gates.maxOverBudgetPercent != null)
        '--max-over-budget-percent=${options.gates.maxOverBudgetPercent}',
      if (options.gates.maxSemanticUncoveredCells != null)
        '--max-semantic-uncovered-cells=${options.gates.maxSemanticUncoveredCells}',
      if (options.thresholdsPath != null)
        '--thresholds=${options.thresholdsPath}',
      if (options.writeThresholdsPath != null)
        '--write-thresholds=${options.writeThresholdsPath}',
      '--threshold-headroom-percent=${options.thresholdHeadroomPercent}',
      '--threshold-min-headroom-ms=${options.thresholdMinHeadroomMs}',
      '--threshold-min-headroom-percent=${options.thresholdMinHeadroomPercent}',
      if (options.requireComparableRunEnvironment)
        '--require-comparable-environment',
      if (options.strictScoreboard) '--strict',
    ]);
    return _SuitePlan(
      options: options,
      scenarios: scenarios,
      compileCommand: compileCommand,
      compiledPageDir: compiledPageDir,
      captureCommands: captureCommands,
      scoreboardCommand: scoreboardCommand,
    );
  }

  final _Options options;
  final List<WebBenchmarkScenario> scenarios;
  final _Command? compileCommand;
  final String? compiledPageDir;
  final List<_Command> captureCommands;
  final _Command scoreboardCommand;

  List<_Command> get commands => [
    if (compileCommand != null) compileCommand!,
    ...captureCommands,
    scoreboardCommand,
  ];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'kind': 'fleuryWebFrameSuitePlan',
      'outputDir': options.outputDir,
      'scoreboardPath': options.scoreboardPath,
      'scoreboardJsonPath': options.scoreboardJsonPath,
      'runsPerScenario': options.runs,
      'minRuns': options.minRuns,
      'strictScoreboard': options.strictScoreboard,
      'compileOnce': options.compileOnce,
      if (compiledPageDir != null) 'compiledPageDir': compiledPageDir,
      'requireComparableRunEnvironment':
          options.requireComparableRunEnvironment,
      'gates': options.gates.toJson(),
      if (options.thresholdsPath != null)
        'thresholdPolicyPath': options.thresholdsPath,
      if (options.writeThresholdsPath != null)
        'candidateThresholdPolicyPath': options.writeThresholdsPath,
      'thresholdHeadroomPercent': options.thresholdHeadroomPercent,
      'thresholdMinHeadroomMs': options.thresholdMinHeadroomMs,
      'thresholdMinHeadroomPercent': options.thresholdMinHeadroomPercent,
      'scenarioCount': scenarios.length,
      'plannedCaptureCount': captureCommands.length,
      'scenarios': [for (final scenario in scenarios) scenario.toJson()],
      'commands': [for (final command in commands) command.toJson()],
    };
  }
}

final class _Command {
  const _Command(this.executable, this.args);

  final String executable;
  final List<String> args;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'executable': executable,
      'args': args,
      'display': _displayCommand(this),
    };
  }
}

Future<void> _runCommand(_Command command) async {
  stdout.writeln(_displayCommand(command));
  final process = await Process.start(
    command.executable,
    command.args,
    workingDirectory: Directory.current.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln(
      'Command failed with exit code $exitCode: ${_displayCommand(command)}',
    );
    exit(exitCode);
  }
}

String _displayCommand(_Command command) {
  return [
    command.executable,
    ...command.args.map((arg) => arg.contains(' ') ? '"$arg"' : arg),
  ].join(' ');
}

final class _Options {
  const _Options({
    required this.help,
    required this.dryRun,
    required this.json,
    required this.scenarioIds,
    required this.runs,
    required this.frames,
    required this.warmupFrames,
    required this.frameBudgetMs,
    required this.outputDir,
    required this.scoreboardPath,
    required this.scoreboardJsonPath,
    required this.minRuns,
    required this.gates,
    required this.thresholdsPath,
    required this.writeThresholdsPath,
    required this.thresholdHeadroomPercent,
    required this.thresholdMinHeadroomMs,
    required this.thresholdMinHeadroomPercent,
    required this.strictScoreboard,
    required this.requireComparableRunEnvironment,
    required this.compileOnce,
    required this.chromePath,
    required this.timeoutSeconds,
    required this.headful,
    required this.keepTemp,
  });

  final bool help;
  final bool dryRun;
  final bool json;
  final List<String> scenarioIds;
  final int runs;
  final int? frames;
  final int warmupFrames;
  final double frameBudgetMs;
  final String outputDir;
  final String scoreboardPath;
  final String scoreboardJsonPath;
  final int minRuns;
  final _GateOptions gates;
  final String? thresholdsPath;
  final String? writeThresholdsPath;
  final double thresholdHeadroomPercent;
  final double thresholdMinHeadroomMs;
  final double thresholdMinHeadroomPercent;
  final bool strictScoreboard;
  final bool requireComparableRunEnvironment;
  final bool compileOnce;
  final String? chromePath;
  final int timeoutSeconds;
  final bool headful;
  final bool keepTemp;

  static _Options parse(List<String> args) {
    var help = false;
    var dryRun = false;
    var json = false;
    List<String>? scenarioIds;
    var runs = 3;
    int? frames;
    var warmupFrames = 2;
    var frameBudgetMs = defaultWebFrameBudgetMs;
    String? outputDir;
    String? scoreboardPath;
    String? scoreboardJsonPath;
    int? minRuns;
    double? maxTotalFrameP95Ms;
    double? maxDomApplyP95Ms;
    double? maxSemanticApplyP95Ms;
    double? maxOverBudgetPercent;
    double? maxSemanticUncoveredCells;
    String? thresholdsPath;
    String? writeThresholdsPath;
    var thresholdHeadroomPercent = 20.0;
    var thresholdMinHeadroomMs = 1.0;
    var thresholdMinHeadroomPercent = 1.0;
    var strictScoreboard = true;
    var requireComparableRunEnvironment = true;
    var compileOnce = true;
    String? chromePath;
    var timeoutSeconds = 30;
    var headful = false;
    var keepTemp = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--json') {
        json = true;
      } else if (arg.startsWith('--scenarios=')) {
        scenarioIds = _splitIds(arg.substring('--scenarios='.length));
      } else if (arg.startsWith('--runs=')) {
        runs = _positiveInt(arg, '--runs=');
      } else if (arg.startsWith('--frames=')) {
        frames = _positiveInt(arg, '--frames=');
      } else if (arg.startsWith('--warmup=')) {
        warmupFrames = _nonNegativeInt(arg, '--warmup=');
      } else if (arg.startsWith('--budget-ms=')) {
        frameBudgetMs = _positiveDouble(arg, '--budget-ms=');
      } else if (arg.startsWith('--output-dir=')) {
        outputDir = arg.substring('--output-dir='.length).trim();
      } else if (arg.startsWith('--scoreboard=')) {
        scoreboardPath = arg.substring('--scoreboard='.length).trim();
      } else if (arg.startsWith('--scoreboard-json=')) {
        scoreboardJsonPath = arg.substring('--scoreboard-json='.length).trim();
        if (scoreboardJsonPath.isEmpty) {
          stderr.writeln('--scoreboard-json requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--min-runs=')) {
        minRuns = _positiveInt(arg, '--min-runs=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveDouble(arg, '--max-total-frame-p95-ms=');
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--thresholds=')) {
        thresholdsPath = arg.substring('--thresholds='.length).trim();
      } else if (arg.startsWith('--write-thresholds=')) {
        writeThresholdsPath = arg
            .substring('--write-thresholds='.length)
            .trim();
      } else if (arg.startsWith('--threshold-headroom-percent=')) {
        thresholdHeadroomPercent = _nonNegativeDouble(
          arg,
          '--threshold-headroom-percent=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-ms=')) {
        thresholdMinHeadroomMs = _nonNegativeDouble(
          arg,
          '--threshold-min-headroom-ms=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-percent=')) {
        thresholdMinHeadroomPercent = _nonNegativeDouble(
          arg,
          '--threshold-min-headroom-percent=',
        );
      } else if (arg == '--no-strict') {
        strictScoreboard = false;
      } else if (arg == '--no-require-comparable-environment') {
        requireComparableRunEnvironment = false;
      } else if (arg == '--no-compile-once') {
        compileOnce = false;
      } else if (arg.startsWith('--chrome=')) {
        chromePath = arg.substring('--chrome='.length).trim();
      } else if (arg.startsWith('--timeout=')) {
        timeoutSeconds = _positiveInt(arg, '--timeout=');
      } else if (arg == '--headful') {
        headful = true;
      } else if (arg == '--keep-temp') {
        keepTemp = true;
      } else {
        stderr.writeln('Unknown option for web_frame_suite: $arg');
        _printUsage();
        exit(2);
      }
    }

    final selectedIds =
        scenarioIds ??
        [for (final scenario in webBenchmarkScenarios) scenario.id];
    _validateScenarioIds(selectedIds);
    outputDir ??= _defaultOutputDir();
    scoreboardPath ??= '$outputDir/scoreboard.md';
    scoreboardJsonPath ??= '$outputDir/scoreboard.json';
    minRuns ??= runs;

    return _Options(
      help: help,
      dryRun: dryRun,
      json: json,
      scenarioIds: List.unmodifiable(selectedIds),
      runs: runs,
      frames: frames,
      warmupFrames: warmupFrames,
      frameBudgetMs: frameBudgetMs,
      outputDir: Directory(outputDir).absolute.path,
      scoreboardPath: File(scoreboardPath).absolute.path,
      scoreboardJsonPath: File(scoreboardJsonPath).absolute.path,
      minRuns: minRuns,
      gates: _GateOptions(
        maxTotalFrameP95Ms: maxTotalFrameP95Ms,
        maxDomApplyP95Ms: maxDomApplyP95Ms,
        maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
        maxOverBudgetPercent: maxOverBudgetPercent,
        maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      ),
      thresholdsPath: thresholdsPath == null || thresholdsPath.isEmpty
          ? null
          : File(thresholdsPath).absolute.path,
      writeThresholdsPath:
          writeThresholdsPath == null || writeThresholdsPath.isEmpty
          ? null
          : File(writeThresholdsPath).absolute.path,
      thresholdHeadroomPercent: thresholdHeadroomPercent,
      thresholdMinHeadroomMs: thresholdMinHeadroomMs,
      thresholdMinHeadroomPercent: thresholdMinHeadroomPercent,
      strictScoreboard: strictScoreboard,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
      compileOnce: compileOnce,
      chromePath: chromePath == null || chromePath.isEmpty
          ? null
          : File(chromePath).absolute.path,
      timeoutSeconds: timeoutSeconds,
      headful: headful,
      keepTemp: keepTemp,
    );
  }
}

final class _GateOptions {
  const _GateOptions({
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
  });

  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (maxTotalFrameP95Ms != null) 'maxTotalFrameP95Ms': maxTotalFrameP95Ms,
      if (maxDomApplyP95Ms != null) 'maxDomApplyP95Ms': maxDomApplyP95Ms,
      if (maxSemanticApplyP95Ms != null)
        'maxSemanticApplyP95Ms': maxSemanticApplyP95Ms,
      if (maxOverBudgetPercent != null)
        'maxOverBudgetPercent': maxOverBudgetPercent,
      if (maxSemanticUncoveredCells != null)
        'maxSemanticUncoveredCells': maxSemanticUncoveredCells,
    };
  }
}

List<String> _splitIds(String value) {
  return [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

void _validateScenarioIds(List<String> ids) {
  if (ids.isEmpty) {
    stderr.writeln('--scenarios requires at least one scenario id.');
    exit(2);
  }
  for (final id in ids) {
    if (webBenchmarkScenarioById(id) == null) {
      stderr.writeln('Unknown web benchmark scenario: $id');
      _printScenarioList();
      exit(2);
    }
  }
}

int _positiveInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive integer.');
    exit(2);
  }
  return value;
}

int _nonNegativeInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative integer.');
    exit(2);
  }
  return value;
}

double _positiveDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive number.');
    exit(2);
  }
  return value;
}

double _nonNegativeDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative number.');
    exit(2);
  }
  return value;
}

String _defaultOutputDir() {
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  return Directory('../../profiling/web/runs/$stamp-suite').absolute.path;
}

void _printScenarioList() {
  stderr.writeln('Web benchmark scenarios:');
  for (final scenario in webBenchmarkScenarios) {
    stderr.writeln('  ${scenario.id}');
  }
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_frame_suite.dart [options]');
  stdout.writeln('');
  stdout.writeln(
    'Runs repeated retained DOM captures for a scenario set and refreshes a strict scoreboard.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --scenarios=A,B         Scenario ids, default all web benchmark scenarios',
  );
  stdout.writeln('  --runs=N                Captures per scenario, default 3');
  stdout.writeln(
    '  --frames=N              Driven benchmark steps per capture',
  );
  stdout.writeln('  --warmup=N              Warmup frames, default 2');
  stdout.writeln(
    '  --budget-ms=N           Frame budget, default $defaultWebFrameBudgetMs',
  );
  stdout.writeln(
    '  --output-dir=DIR        Capture directory, default profiling/web/runs/<timestamp>-suite',
  );
  stdout.writeln(
    '  --scoreboard=PATH       Scoreboard output, default <output-dir>/scoreboard.md',
  );
  stdout.writeln(
    '  --scoreboard-json=PATH  Scoreboard JSON output, default <output-dir>/scoreboard.json',
  );
  stdout.writeln(
    '  --min-runs=N            Scoreboard min runs, default same as --runs',
  );
  stdout.writeln('  --max-total-frame-p95-ms=N       Gate median total p95.');
  stdout.writeln(
    '  --max-dom-apply-p95-ms=N         Gate median DOM apply p95.',
  );
  stdout.writeln(
    '  --max-semantic-apply-p95-ms=N    Gate median semantic apply p95.',
  );
  stdout.writeln(
    '  --max-over-budget-percent=N      Gate median percent over budget.',
  );
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N Gate max uncovered semantic cells.',
  );
  stdout.writeln(
    '  --thresholds=PATH       JSON threshold policy with defaults/scenarios.',
  );
  stdout.writeln(
    '  --write-thresholds=PATH Write a candidate JSON threshold policy after captures.',
  );
  stdout.writeln(
    '  --threshold-headroom-percent=N      Candidate threshold headroom, default 20.',
  );
  stdout.writeln(
    '  --threshold-min-headroom-ms=N       Candidate minimum timing headroom, default 1.',
  );
  stdout.writeln(
    '  --threshold-min-headroom-percent=N  Candidate minimum over-budget headroom, default 1.',
  );
  stdout.writeln(
    '  --no-strict             Do not strict-gate scoreboard min runs or supplied gates',
  );
  stdout.writeln(
    '  --no-require-comparable-environment Do not require identical run environment metadata.',
  );
  stdout.writeln(
    '  --no-compile-once     Compile benchmark JS separately for each capture.',
  );
  stdout.writeln('  --chrome=PATH           Chrome/Chromium executable');
  stdout.writeln(
    '  --timeout=N             Per-capture timeout seconds, default 30',
  );
  stdout.writeln('  --headful               Launch Chrome visibly');
  stdout.writeln(
    '  --keep-temp             Keep generated temp page/profile files',
  );
  stdout.writeln(
    '  --dry-run               Print planned commands without running Chrome',
  );
  stdout.writeln('  --json                  Print machine-readable suite plan');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  dart run tool/web_frame_suite.dart --scenarios=normal-80x24,large-160x50 --runs=3',
  );
  stdout.writeln(
    '  dart run tool/web_frame_suite.dart --runs=5 --output-dir=../../profiling/web/baselines/2026-06-08-baseline',
  );
}
