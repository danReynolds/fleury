import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

Future<void> main(List<String> rawArgs) async {
  final parsed = _ParsedArgs.parse(rawArgs);
  if (parsed.help || parsed.command == null) {
    _printUsage();
    exit(parsed.help ? 0 : 2);
  }

  final root = _repoRoot();
  final runner = _Runner(root: root, dryRun: parsed.dryRun);
  final args = parsed.args;

  switch (parsed.command) {
    case 'list':
      _printCatalog();
      return;
    case 'bootstrap':
      await runner.bootstrap();
      return;
    case 'check':
      await runner.check(quick: args.contains('--quick'));
      return;
    case 'coverage':
      await runner.coverage(args);
      return;
    case 'build-remote-client':
      await runner.buildRemoteClient(args);
      return;
    case 'demo':
      await runner.demoApp();
      return;
    case 'storybook':
      await runner.storybookApp(args);
      return;
    case 'samples':
      await runner.samplesApp(args);
      return;
    case 'core-demo':
      await runner.coreDemo(_requiredName(args, 'core-demo'));
      return;
    case 'widget-demo':
      await runner.widgetDemo(_requiredName(args, 'widget-demo'));
      return;
    case 'cli':
      await runner.fleuryCli(args);
      return;
    case 'terminal-matrix':
      await runner.terminalMatrix(args);
      return;
    case 'terminal-matrix-audit':
      await runner.terminalMatrixAudit(args);
      return;
    case 'terminal-matrix-accept':
      await runner.terminalMatrixAccept(args);
      return;
    case 'mvp-readiness':
      await runner.mvpReadiness(args);
      return;
    case 'mvp-final-gate':
      await runner.mvpFinalGate(args);
      return;
    case 'mvp-evidence-refresh':
      await runner.mvpEvidenceRefresh(args);
      return;
    case 'benchmark':
      await runner.benchmark(args);
      return;
    case 'benchmark-manifest':
      await runner.benchmarkManifest(args);
      return;
    case 'benchmark-result':
      await runner.benchmarkResult(args);
      return;
    case 'benchmark-variance':
      await runner.benchmarkVariance(args);
      return;
    case 'activate-cli':
      await runner.activateCli();
      return;
    case 'build-cli':
      await runner.buildCli();
      return;
    default:
      stderr.writeln('Unknown command: ${parsed.command}');
      _printUsage();
      exit(2);
  }
}

String _repoRoot() {
  final script = File(Platform.script.toFilePath()).absolute;
  return script.parent.parent.path;
}

/// Stable content hash of the remote client's SOURCE closure, read from the
/// dart2js `<output>.deps` file. Hashes only committed `.dart` source *under
/// the repo* ([repoRoot]). Three exclusions make it deterministic across
/// machines, SDKs, and pub resolutions:
///   - SDK libraries (the `org-dartlang-sdk:` scheme) — bytes vary by SDK
///     version, the drift the old byte-compare gate tripped on;
///   - pub-cache dependencies — versions float (`pubspec.lock` is gitignored);
///   - generated tooling artifacts such as `.dart_tool/package_config.json` —
///     which live under the repo but embed machine-specific absolute paths, so
///     the `.dart`-only filter keeps them out.
/// What remains is exactly the committed Dart source that feeds the bundle.
/// Content-only and order-independent (per-file hashes are sorted): a moved
/// file is still caught via the importer whose text changed.
String _remoteClientSourceFingerprint(File depsFile, String repoRoot) {
  final hashes = <String>[];
  for (final line in depsFile.readAsLinesSync()) {
    final uri = line.trim();
    if (!uri.startsWith('file://')) continue;
    final path = Uri.parse(uri).toFilePath();
    // Trailing separator so a sibling dir sharing the prefix (repo `…/fleury`
    // vs `…/fleury-notes`) can't sneak in; drops SDK + pub-cache inputs.
    if (!path.startsWith('$repoRoot/')) continue;
    // `.dart` only: skip generated, machine-specific artifacts under the repo
    // (e.g. `.dart_tool/package_config.json`, whose absolute paths differ per
    // checkout) — hashing those would reintroduce cross-machine drift.
    if (!path.endsWith('.dart')) continue;
    hashes.add(_fnv1a64Hex(File(path).readAsBytesSync()));
  }
  hashes.sort();
  return _fnv1a64Hex(utf8.encode(hashes.join('\n')));
}

/// FNV-1a 64-bit hash as a zero-padded 16-char hex string. Not cryptographic —
/// this is change detection — but, unlike `Object.hashCode`, it is stable
/// across runs, isolates, and machines. Native-VM ints are fixed 64-bit and
/// wrap on overflow, which is the modular arithmetic FNV needs.
String _fnv1a64Hex(List<int> bytes) {
  var hash = 0xcbf29ce484222325; // FNV-1a 64-bit offset basis
  for (final b in bytes) {
    hash = (hash ^ b) * 0x100000001b3; // xor byte, multiply by the FNV prime
  }
  final hi = ((hash >> 32) & 0xffffffff).toRadixString(16).padLeft(8, '0');
  final lo = (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '$hi$lo';
}

/// The `remoteClientSourceFingerprint` currently committed in the generated
/// asset, or '' if absent. Parsed textually because this standalone tool has no
/// package resolution to import the asset library.
String _readCommittedFingerprint(File assetFile) {
  if (!assetFile.existsSync()) return '';
  final match = RegExp(
    r"remoteClientSourceFingerprint = '([0-9a-f]+)'",
  ).firstMatch(assetFile.readAsStringSync());
  return match?.group(1) ?? '';
}

String _requiredName(List<String> args, String command) {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      '$command requires a name. Run `dart tool/fleury_dev.dart list`.',
    );
    exit(2);
  }
  return args.first;
}

void _printUsage() {
  stdout.writeln('Fleury local development launcher');
  stdout.writeln('');
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart [--dry-run] <command> [args]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Canonical CLI forms after local activation: `fleury dev <command>` and '
    '`fleury benchmark <subcommand>`.',
  );
  stdout.writeln('');
  stdout.writeln('Primary contributor commands:');
  stdout.writeln('  list                          Show runnable demos');
  stdout.writeln(
    '  bootstrap                     Run dart pub get in local packages',
  );
  stdout.writeln(
    '  check [--quick]               Analyze and test local packages',
  );
  stdout.writeln('  coverage [options]            Run package coverage floors');
  stdout.writeln('  demo                          Run the integrated demo app');
  stdout.writeln(
    '  storybook [command/options]   Run, inspect, verify, or snapshot storybook',
  );
  stdout.writeln(
    '  samples <app>                 Run a showcase app (dashboard|files|agent)',
  );
  stdout.writeln(
    '  core-demo <name>              Run a packages/fleury example',
  );
  stdout.writeln(
    '  widget-demo <name>            Run a packages/fleury_widgets example',
  );
  stdout.writeln(
    '  cli <args...>                 Run packages/fleury/bin/fleury.dart',
  );
  stdout.writeln(
    '  benchmark <subcommand>        Run benchmark/profiling workflows',
  );
  stdout.writeln('');
  stdout.writeln('Evidence and release commands:');
  stdout.writeln(
    '  terminal-matrix [options]     Capture diagnose JSON as a matrix entry',
  );
  stdout.writeln(
    '  terminal-matrix-audit [options] '
    'Summarize collected terminal matrix entries',
  );
  stdout.writeln(
    '  terminal-matrix-accept [options] Accept a reviewed matrix entry',
  );
  stdout.writeln(
    '  mvp-readiness [options]       Audit MVP external evidence readiness',
  );
  stdout.writeln(
    '  mvp-final-gate [options]      Run local and external MVP gates',
  );
  stdout.writeln(
    '  mvp-evidence-refresh [options] Regenerate MVP evidence artifacts',
  );
  stdout.writeln('');
  stdout.writeln('Maintenance commands:');
  stdout.writeln(
    '  activate-cli                 dart pub global activate --source path packages/fleury',
  );
  stdout.writeln(
    '  build-cli                    Compile build/fleury from the local CLI',
  );
  stdout.writeln('');
  stdout.writeln('Legacy benchmark aliases:');
  stdout.writeln(
    '  benchmark-manifest [options]  Prefer `benchmark manifest [options]`',
  );
  stdout.writeln(
    '  benchmark-result [options]    Prefer `benchmark result [options]`',
  );
  stdout.writeln(
    '  benchmark-variance [options]  Prefer `benchmark variance [options]`',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  dart tool/fleury_dev.dart bootstrap');
  stdout.writeln('  dart tool/fleury_dev.dart coverage --strict');
  stdout.writeln('  dart tool/fleury_dev.dart demo');
  stdout.writeln('  dart tool/fleury_dev.dart storybook');
  stdout.writeln('  dart tool/fleury_dev.dart storybook verify');
  stdout.writeln('  dart tool/fleury_dev.dart storybook coverage --strict');
  stdout.writeln('  dart tool/fleury_dev.dart samples dashboard');
  stdout.writeln('  dart tool/fleury_dev.dart core-demo counter');
  stdout.writeln('  dart tool/fleury_dev.dart cli diagnose --json');
  stdout.writeln('  dart tool/fleury_dev.dart benchmark list');
  stdout.writeln(
    '  dart tool/fleury_dev.dart benchmark local SB.4 --warmup=1 --iterations=3 --json',
  );
  stdout.writeln('  dart tool/fleury_dev.dart benchmark wire sb4 --runs=3');
  stdout.writeln(
    '  dart tool/fleury_dev.dart benchmark wire sb3 --peers=ratatui,opentui --runs=3',
  );
  stdout.writeln('  dart tool/fleury_dev.dart benchmark manifest --json');
  stdout.writeln(
    '  dart tool/fleury_dev.dart benchmark result --input=peer-run.json --json',
  );
  stdout.writeln(
    '  dart tool/fleury_dev.dart benchmark variance --input=peer-runs --json',
  );
  stdout.writeln('  dart tool/fleury_dev.dart terminal-matrix --label=iterm2');
  stdout.writeln('  dart tool/fleury_dev.dart mvp-readiness');
}

void _printCatalog() {
  stdout.writeln('Core demos:');
  _coreDemos.forEach((name, path) => stdout.writeln('  $name -> $path'));
  stdout.writeln('');
  stdout.writeln('Widget demos:');
  _widgetDemos.forEach((name, path) => stdout.writeln('  $name -> $path'));
  stdout.writeln('');
  stdout.writeln('Demo app:');
  stdout.writeln(
    '  demo -> packages/fleury_example_console/bin/fleury_example_console.dart',
  );
  stdout.writeln('');
  stdout.writeln('Storybook:');
  stdout.writeln('  storybook -> packages/storybook/bin/storybook.dart');
  stdout.writeln('');
  stdout.writeln('Samples:');
  stdout.writeln('  samples <app> -> packages/samples/bin/samples.dart');
}

final _coreDemos = <String, String>{
  'counter': 'example/counter_quickstart.dart',
  'counter-full': 'example/counter_demo.dart',
  'chat': 'example/chat_demo.dart',
  'showcase': 'example/showcase.dart',
  'animation-showcase': 'example/animation_showcase.dart',
  'animation-recipes': 'example/animation_recipes.dart',
  'selection': 'example/selection_demo.dart',
  'hot-reload': 'example/hot_reload_demo.dart',
};

final _widgetDemos = <String, String>{
  'dashboard': 'example/dashboard_demo.dart',
  'dashboard-snapshot': 'example/dashboard_snapshot.dart',
  'image': 'example/image_demo.dart',
};

class _ParsedArgs {
  const _ParsedArgs({
    required this.dryRun,
    required this.help,
    required this.command,
    required this.args,
  });

  final bool dryRun;
  final bool help;
  final String? command;
  final List<String> args;

  static _ParsedArgs parse(List<String> rawArgs) {
    var dryRun = false;
    var help = false;
    final args = <String>[];
    for (final arg in rawArgs) {
      if (arg == '--dry-run') {
        dryRun = true;
      } else if ((arg == '-h' || arg == '--help') && args.isEmpty) {
        help = true;
      } else {
        args.add(arg);
      }
    }
    return _ParsedArgs(
      dryRun: dryRun,
      help: help,
      command: args.isEmpty ? null : args.first,
      args: args.length <= 1 ? const [] : args.sublist(1),
    );
  }
}

class _Runner {
  const _Runner({required this.root, required this.dryRun});

  final String root;
  final bool dryRun;

  String get fleury => '$root/packages/fleury';
  String get widgets => '$root/packages/fleury_widgets';
  String get web => '$root/packages/fleury_web';
  String get git => '$root/packages/fleury_git';
  String get demo => '$root/packages/fleury_example_console';
  String get storybook => '$root/packages/storybook';
  String get samples => '$root/packages/samples';
  String get mcp => '$root/packages/fleury_mcp';
  String get webExamples => '$root/website/examples';
  String get profiling => '$root/profiling';

  Future<void> bootstrap() async {
    for (final dir in [
      fleury,
      widgets,
      web,
      git,
      demo,
      storybook,
      samples,
      mcp,
      profiling,
      webExamples,
    ]) {
      await _run('dart', ['pub', 'get'], workingDirectory: dir);
    }
  }

  Future<void> check({required bool quick}) async {
    // Analyze EVERY package first, before any test suite runs. `_run` aborts
    // the whole check on the first failure, so an interleaved analyze/test
    // order lets a red test mask every analyze after it — which is how a DT1
    // change that broke `fleury_web`'s compile shipped green (the chronic
    // asset-freshness test red aborted `check` before the web analyze ran).
    // A compile break is the silent killer; front-loading analysis guarantees
    // it surfaces even when a downstream test is red. (Profiling is analyzed
    // too so a rename can't silently compile-out the wire-gate fixtures.)
    for (final dir in [
      fleury,
      widgets,
      git,
      demo,
      storybook,
      web,
      samples,
      mcp,
      profiling,
    ]) {
      await _run('dart', ['analyze'], workingDirectory: dir);
    }

    // Then the unit suites. The fleury INTEGRATION batch runs LAST (below),
    // not here: it's the slowest and currently carries the chronic
    // asset-freshness red, so keeping it out of the middle stops that one red
    // from masking every package test after it too.
    if (quick) {
      await _run('dart', [
        'test',
        'test/example/counter_quickstart_test.dart',
      ], workingDirectory: fleury);
    } else {
      await _run('dart', [
        'test',
        '-x',
        'integration',
      ], workingDirectory: fleury);
    }
    await _run(
      'dart',
      quick ? ['test', 'test/dashboard_demo_test.dart'] : ['test'],
      workingDirectory: widgets,
    );
    await _run('dart', ['test'], workingDirectory: git);
    await _run('dart', [
      'test',
      'test/demo_console_test.dart',
    ], workingDirectory: demo);
    await _run('dart', ['test'], workingDirectory: storybook);
    // Explicit platforms: fleury_web splits VM-safe suites from
    // @TestOn('browser') ones, and a bare `dart test` silently skips the
    // browser set.
    await _run('dart', [
      'test',
      '-p',
      'vm,chrome',
    ], workingDirectory: web);
    await _run('dart', ['test'], workingDirectory: samples);
    await _run('dart', ['test'], workingDirectory: mcp);
    if (!quick) {
      // dart2js smoke: the doc-examples entrypoint pulls in fleury_core,
      // fleury_widgets_web, fleury_web, and the samples — the whole
      // browser-safe surface compiles or this fails.
      await _run('dart', [
        'compile',
        'js',
        'web/main.dart',
        '-o',
        '${Directory.systemTemp.path}/fleury-check-examples.js',
        '-O1',
      ], workingDirectory: webExamples);

      // The fleury integration batch runs LAST: it's the slowest and carries
      // the chronic asset-freshness red, so every other package's analyze +
      // tests have already reported by the time it can abort the run.
      await _run('dart', [
        'test',
        '-t',
        'integration',
        '--concurrency=1',
      ], workingDirectory: fleury);
    }
  }

  /// Compiles the structured serve client (web/remote_client.dart) and
  /// regenerates the embedded asset
  /// (packages/fleury/lib/src/remote/remote_client_asset.dart). The
  /// freshness test fails if this is stale; run it after touching the
  /// remote-client source.
  Future<void> buildRemoteClient(List<String> args) async {
    final check = args.contains('--check');
    final tmp = '$root/.dart_tool/remote_client.js';
    final depsPath = '$tmp.deps';
    if (!check) {
      stdout.writeln('compiling web/remote_client.dart -> JS (-O2)…');
    }
    await _run('dart', [
      'compile',
      'js',
      'web/remote_client.dart',
      '-o',
      tmp,
      '-O2',
      // No source maps: production doesn't need them, and the
      // sourceMappingURL comment names the output file, which would make
      // the embedded bytes non-deterministic.
      '--no-source-maps',
    ], workingDirectory: web);
    final js = File(tmp).readAsBytesSync();
    // Fingerprint the client's SOURCE closure (the dart2js `.deps` inputs), not
    // the compiled bytes: dart2js output is not stable across SDK versions, so
    // byte-comparing it drifts red on any SDK skew between whoever ran
    // build-remote-client and CI. The fingerprint tracks whether the source
    // changed — the only thing a "did you forget to rebuild" gate should catch.
    final fingerprint = _remoteClientSourceFingerprint(File(depsPath), root);
    File(tmp).deleteSync();
    final depsFile = File(depsPath);
    if (depsFile.existsSync()) depsFile.deleteSync();

    final assetFile = File(
      '$fleury/lib/src/remote/remote_client_asset.dart',
    );

    // --check: verify freshness without rewriting the asset (the freshness
    // gate). The compile above doubles as a "still compiles" check.
    if (check) {
      final committed = _readCommittedFingerprint(assetFile);
      if (committed != fingerprint) {
        stderr.writeln(
          'remote client asset is STALE: committed source fingerprint '
          '"$committed" != current "$fingerprint".\n'
          'Run: dart run tool/fleury_dev.dart build-remote-client',
        );
        exit(1);
      }
      stdout.writeln(
        'remote client asset in sync (source fingerprint $fingerprint).',
      );
      return;
    }

    final b64 = base64.encode(js);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 100) {
      lines.add(
        "    '${b64.substring(i, math.min(i + 100, b64.length))}'",
      );
    }
    final out =
        '''// GENERATED — do not edit by hand.
//
// The compiled dart2js bundle for the structured serve client
// (web/remote_client.dart), embedded so `fleury serve` ships it inside the
// single binary. Regenerate with:
//
//     dart run tool/fleury_dev.dart build-remote-client
//
// The freshness gate (remote_client_asset_test) recompiles the client and
// compares [remoteClientSourceFingerprint] — a hash of the client's SOURCE
// closure — so it fails when the source changed without a rebuild, but does
// NOT drift on dart2js codegen differences between SDK versions.

import 'dart:convert';
import 'dart:typed_data';

/// Base64 of the compiled `remote_client.dart.js`.
const String _remoteClientJsBase64 =
${lines.join('\n')};

/// SDK-independent fingerprint of the client's source closure at build time.
/// The freshness gate compares this instead of the compiled bytes (which vary
/// by SDK). Regenerated with the bundle.
const String remoteClientSourceFingerprint = '$fingerprint';

/// The compiled client JavaScript bytes.
Uint8List remoteClientJs() => base64.decode(_remoteClientJsBase64);
''';
    assetFile.writeAsStringSync(out);
    stdout.writeln(
      'wrote remote_client_asset.dart '
      '(${js.length} JS bytes, source fingerprint $fingerprint)',
    );
  }

  Future<void> coverage(List<String> args) async {
    final options = _CoverageOptions.parse(args);
    final targets = <_CoveragePackageTarget>[
      _CoveragePackageTarget(
        label: 'core',
        packageName: 'fleury',
        packagePath: fleury,
        floorPercent: options.coreMinPercent,
        excludeIntegration: !options.includeIntegration,
        excludeCoverageIncompatible: true,
      ),
      _CoveragePackageTarget(
        label: 'widgets',
        packageName: 'fleury_widgets',
        packagePath: widgets,
        floorPercent: options.widgetsMinPercent,
        excludeIntegration: false,
        excludeCoverageIncompatible: false,
      ),
    ];

    if (dryRun) {
      for (final target in targets) {
        final args = _coverageTestArgs(target);
        final display = ['dart', ...args].join(' ');
        stdout.writeln('(${_relative(target.packagePath)}) $display');
        stdout.writeln(
          'floor ${target.label} >= ${_formatPercent(target.floorPercent)}%',
        );
      }
      return;
    }

    final results = <_CoveragePackageResult>[];
    for (final target in targets) {
      results.add(await _runCoveragePackage(target));
    }
    final strictPass = results.every((result) => result.strictPass);
    final summary = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'fleuryCoverage',
      'strictPass': strictPass,
      'packages': <Object?>[for (final result in results) result.toJson(root)],
    };

    if (options.json) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
    } else {
      _printCoverageSummary(results, strictPass: strictPass);
    }
    if (options.strict && !strictPass) exit(1);
  }

  List<String> _coverageTestArgs(_CoveragePackageTarget target) {
    return <String>[
      'test',
      if (target.excludeIntegration) ...['-x', 'integration'],
      if (target.excludeCoverageIncompatible) ...[
        '-x',
        'coverage-incompatible',
      ],
      '--concurrency=1',
      '--reporter=json',
      '--coverage-path=coverage/lcov.info',
      '--coverage-package=${target.packageName}',
    ];
  }

  Future<_CoveragePackageResult> _runCoveragePackage(
    _CoveragePackageTarget target,
  ) async {
    final lcovFile = File('${target.packagePath}/coverage/lcov.info');
    if (lcovFile.existsSync()) lcovFile.deleteSync();
    lcovFile.parent.createSync(recursive: true);

    final args = _coverageTestArgs(target);
    final result = await Process.run(
      'dart',
      args,
      workingDirectory: target.packagePath,
    );
    final stdoutText = result.stdout.toString();
    final stderrText = result.stderr.toString();
    if (result.exitCode != 0) {
      stderr.writeln(
        'Coverage test command failed in ${_relative(target.packagePath)} '
        'with exit code ${result.exitCode}: dart ${args.join(' ')}',
      );
      if (stdoutText.trim().isNotEmpty) stderr.writeln(stdoutText.trimRight());
      if (stderrText.trim().isNotEmpty) stderr.writeln(stderrText.trimRight());
      exit(result.exitCode);
    }

    final testCounts = _countJsonTestEvents(stdoutText);
    if (testCounts.start == 0 || testCounts.done == 0) {
      stderr.writeln(
        'Coverage sanity check failed for ${target.label}: '
        'JSON reporter saw ${testCounts.start} testStart and '
        '${testCounts.done} testDone events.',
      );
      exit(1);
    }
    if (!lcovFile.existsSync() || lcovFile.lengthSync() == 0) {
      stderr.writeln(
        'Coverage sanity check failed for ${target.label}: '
        'missing coverage/lcov.info.',
      );
      exit(1);
    }

    final lcov = _parseLcov(lcovFile.readAsStringSync());
    if (lcov.linesFound == 0) {
      stderr.writeln(
        'Coverage sanity check failed for ${target.label}: '
        'LCOV reported zero instrumented lines.',
      );
      exit(1);
    }

    final percent = (lcov.linesHit / lcov.linesFound) * 100;
    return _CoveragePackageResult(
      target: target,
      lcovPath: lcovFile.path,
      testStartCount: testCounts.start,
      testDoneCount: testCounts.done,
      linesHit: lcov.linesHit,
      linesFound: lcov.linesFound,
      linePercent: percent,
    );
  }

  Future<void> demoApp() {
    return _run('dart', [
      'run',
      'bin/fleury_example_console.dart',
    ], workingDirectory: demo);
  }

  Future<void> storybookApp(List<String> args) {
    return _run('dart', [
      'run',
      'bin/storybook.dart',
      ...args,
    ], workingDirectory: storybook);
  }

  Future<void> samplesApp(List<String> args) {
    return _run('dart', [
      'run',
      'bin/samples.dart',
      ...args,
    ], workingDirectory: samples);
  }

  Future<void> coreDemo(String name) {
    final path = _coreDemos[name];
    if (path == null) {
      stderr.writeln('Unknown core demo: $name');
      _printCatalog();
      exit(2);
    }
    return _run('dart', ['run', path], workingDirectory: fleury);
  }

  Future<void> widgetDemo(String name) {
    final path = _widgetDemos[name];
    if (path == null) {
      stderr.writeln('Unknown widget demo: $name');
      _printCatalog();
      exit(2);
    }
    return _run('dart', ['run', path], workingDirectory: widgets);
  }

  Future<void> fleuryCli(List<String> args) {
    return _run('dart', [
      'run',
      'bin/fleury.dart',
      ...args,
    ], workingDirectory: fleury);
  }

  Future<void> terminalMatrix(List<String> args) async {
    final options = _TerminalMatrixOptions.parse(root, args);
    final diagnosisTempDir = Directory.systemTemp.createTempSync(
      'fleury_terminal_matrix_',
    );
    final diagnosisPath = '${diagnosisTempDir.path}/diagnosis.json';
    final diagnoseArgs = <String>[
      'run',
      'bin/fleury.dart',
      'diagnose',
      '--json-output=$diagnosisPath',
      if (options.probe) '--probe',
      '--probe-timeout=${options.probeTimeoutMs}',
    ];
    final recordedCommand = <String>[
      'dart',
      'run',
      'bin/fleury.dart',
      'diagnose',
      '--json-output=<matrix-diagnosis-json>',
      if (options.probe) '--probe',
      '--probe-timeout=${options.probeTimeoutMs}',
    ];
    final outputPath = options.outputPath;
    final relativeOutput = _relative(outputPath);
    final display = 'dart ${diagnoseArgs.join(' ')}';
    if (dryRun) {
      stdout.writeln('(packages/fleury) $display');
      stdout.writeln('write $relativeOutput');
      try {
        diagnosisTempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
      return;
    }

    final process = await Process.start(
      'dart',
      diagnoseArgs,
      workingDirectory: fleury,
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      stderr.writeln(
        'Command failed in packages/fleury with exit code '
        '$exitCode: $display',
      );
      try {
        diagnosisTempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
      exit(exitCode);
    }

    final stdoutText = File(diagnosisPath).readAsStringSync();
    final Object? diagnosis;
    try {
      diagnosis = jsonDecode(stdoutText);
    } on FormatException catch (error) {
      stderr.writeln('diagnose did not produce valid JSON: $error');
      stderr.writeln(stdoutText);
      try {
        diagnosisTempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
      exit(1);
    }
    if (diagnosis is! Map<String, Object?>) {
      stderr.writeln('diagnose JSON root was not an object.');
      try {
        diagnosisTempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
      exit(1);
    }

    final entry = _buildTerminalMatrixEntry(
      label: options.label,
      capturedAt: DateTime.now().toUtc(),
      command: recordedCommand,
      diagnosis: diagnosis,
      reviewNotes: options.reviewNotes,
    );
    final outputFile = File(outputPath);
    outputFile.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    outputFile.writeAsStringSync('${encoder.convert(entry)}\n');
    try {
      diagnosisTempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup only.
    }

    final summary = entry['summary'] as Map<String, Object?>;
    final platform = summary['platform'] as Map<String, Object?>?;
    final terminal = summary['terminal'] as Map<String, Object?>;
    final compatibility = summary['compatibility'] as Map<String, Object?>?;
    final review = entry['review'] as Map<String, Object?>;
    stdout.writeln('Wrote $relativeOutput');
    if (platform != null) {
      stdout.writeln('Platform: ${platform['operatingSystem'] ?? '(unknown)'}');
    }
    stdout.writeln(
      'Terminal: ${terminal['term'] ?? '(unset)'} '
      '${terminal['termProgram'] ?? ''} '
      '${terminal['columns']}x${terminal['rows']}',
    );
    if (compatibility != null) {
      stdout.writeln('Compatibility: ${compatibility['summary']}');
    }
    stdout.writeln('Review: ${review['status']}');
    for (final issue in _list(review['issues'])) {
      stdout.writeln('  issue: $issue');
    }
    for (final note in _list(review['notes'])) {
      stdout.writeln('  note: $note');
    }
  }

  Future<void> terminalMatrixAudit(List<String> args) async {
    final options = _TerminalMatrixAuditOptions.parse(root, args);
    final relativeInput = _relative(options.inputPath);
    if (dryRun) {
      stdout.writeln('scan $relativeInput');
      if (options.json) stdout.writeln('write JSON audit to stdout');
      if (options.writePlanPath != null) {
        stdout.writeln('write ${_relative(options.writePlanPath!)}');
      }
      if (options.writeReviewPath != null) {
        stdout.writeln('write ${_relative(options.writeReviewPath!)}');
      }
      if (options.strict) stdout.writeln('enforce ready target coverage');
      return;
    }

    final audit = _buildTerminalMatrixAudit(
      root: root,
      inputPath: options.inputPath,
      targets: options.targets,
    );
    if (options.json) {
      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(audit));
    } else {
      _printTerminalMatrixAudit(audit);
    }
    if (options.writePlanPath != null) {
      final outputFile = File(options.writePlanPath!);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(_terminalMatrixAuditPlanMarkdown(audit));
      if (!options.json) {
        stdout.writeln('Wrote ${_relative(options.writePlanPath!)}');
      }
    }
    if (options.writeReviewPath != null) {
      final outputFile = File(options.writeReviewPath!);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(_terminalMatrixAuditReviewMarkdown(audit));
      if (!options.json) {
        stdout.writeln('Wrote ${_relative(options.writeReviewPath!)}');
      }
    }

    if (options.strict && !_terminalMatrixAuditStrictPass(audit)) {
      exit(1);
    }
  }

  Future<void> terminalMatrixAccept(List<String> args) async {
    final options = _TerminalMatrixAcceptOptions.parse(root, args);
    final relativeInput = _relative(options.inputPath);
    if (dryRun) {
      stdout.writeln('scan $relativeInput');
      stdout.writeln('accept ${options.label}');
      return;
    }

    final matches = <({File file, Map<String, Object?> entry})>[];
    final inputDirectory = Directory(options.inputPath);
    if (inputDirectory.existsSync()) {
      final files =
          inputDirectory
              .listSync(followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith('.json'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        try {
          final decoded = jsonDecode(file.readAsStringSync());
          final entry = _object(decoded);
          if (entry['kind'] != 'fleuryTerminalMatrixEntry') continue;
          if (entry['label']?.toString() == options.label) {
            matches.add((file: file, entry: entry));
          }
        } on Object {
          // Invalid entries are reported by terminal-matrix-audit. Acceptance
          // only mutates valid matrix entries with exact labels.
        }
      }
    }

    if (matches.isEmpty) {
      stderr.writeln(
        'No terminal matrix entry found with label: ${options.label}',
      );
      exit(2);
    }
    if (matches.length > 1) {
      stderr.writeln(
        'Multiple terminal matrix entries found with label: ${options.label}',
      );
      for (final match in matches) {
        stderr.writeln('  ${_relative(match.file.path)}');
      }
      exit(2);
    }

    final match = matches.single;
    final entry = match.entry;
    final review = <String, Object?>{..._object(entry['review'])};
    final previousStatus = review['status']?.toString() ?? 'unknown';
    if (previousStatus == 'nonInteractive' && !options.allowNonInteractive) {
      stderr.writeln(
        'Refusing to accept nonInteractive entry ${options.label}. '
        'Use --allow-non-interactive only for explicit control evidence.',
      );
      exit(2);
    }

    final notes = <String>[for (final note in _list(review['notes'])) '$note'];
    notes.addAll(options.notes);
    review['status'] = 'acceptedForLaunch';
    review['previousStatus'] = previousStatus;
    review['acceptedAt'] = DateTime.now().toUtc().toIso8601String();
    if (options.acceptedBy != null) {
      review['acceptedBy'] = options.acceptedBy;
    }
    review['acceptanceNotes'] = options.notes;
    review['notes'] = notes;
    entry['review'] = review;

    const encoder = JsonEncoder.withIndent('  ');
    match.file.writeAsStringSync('${encoder.convert(entry)}\n');
    stdout.writeln(
      'Accepted ${options.label} in ${_relative(match.file.path)} '
      '(previous status: $previousStatus).',
    );
  }

  Future<void> mvpReadiness(List<String> args) async {
    final options = _MvpReadinessOptions.parse(root, args);
    final relativeInput = _relative(options.inputPath);
    if (dryRun) {
      stdout.writeln('scan $relativeInput');
      if (options.json) stdout.writeln('write JSON readiness audit to stdout');
      if (options.writeReportPath != null) {
        stdout.writeln('write ${_relative(options.writeReportPath!)}');
      }
      if (options.strict) stdout.writeln('enforce MVP external evidence');
      return;
    }

    final readiness = _buildMvpReadinessAudit(
      root: root,
      inputPath: options.inputPath,
    );
    if (options.json) {
      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(readiness));
    } else {
      _printMvpReadinessAudit(readiness);
    }
    if (options.writeReportPath != null) {
      final outputFile = File(options.writeReportPath!);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(_mvpReadinessAuditMarkdown(readiness));
      if (!options.json) {
        stdout.writeln('Wrote ${_relative(options.writeReportPath!)}');
      }
    }

    if (options.strict && readiness['strictPass'] != true) {
      exit(1);
    }
  }

  Future<void> mvpFinalGate(List<String> args) async {
    final options = _MvpFinalGateOptions.parse(root, args);
    final relativeInput = _relative(options.inputPath);
    if (dryRun) {
      if (options.skipLocal) {
        stdout.writeln('skip local RC gate');
      } else {
        stdout.writeln(
          'run local RC gate: dart tool/fleury_dev.dart check'
          '${options.quick ? ' --quick' : ''}',
        );
      }
      stdout.writeln('scan $relativeInput');
      if (options.writeReportPath != null) {
        stdout.writeln('write ${_relative(options.writeReportPath!)}');
      }
      stdout.writeln('enforce MVP external evidence');
      return;
    }

    if (options.skipLocal) {
      stdout.writeln('Skipping local RC gate (--skip-local).');
    } else {
      await check(quick: options.quick);
    }

    final readiness = _buildMvpReadinessAudit(
      root: root,
      inputPath: options.inputPath,
    );
    if (options.writeReportPath != null) {
      final outputFile = File(options.writeReportPath!);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(_mvpReadinessAuditMarkdown(readiness));
      stdout.writeln('Wrote ${_relative(options.writeReportPath!)}');
    }
    _printMvpReadinessAudit(readiness);
    if (readiness['strictPass'] != true) {
      exit(1);
    }
    stdout.writeln('MVP final gate passed.');
  }

  Future<void> mvpEvidenceRefresh(List<String> args) async {
    final options = _MvpEvidenceRefreshOptions.parse(root, args);
    final relativeInput = _relative(options.inputPath);
    final relativeOutput = _relative(options.outputDir);
    if (dryRun) {
      stdout.writeln('scan $relativeInput');
      stdout.writeln(
        'write generated evidence artifacts under $relativeOutput',
      );
      if (options.strict) stdout.writeln('enforce MVP external evidence');
      return;
    }

    final launchAudit = _buildTerminalMatrixAudit(
      root: root,
      inputPath: options.inputPath,
      targets: _defaultTerminalMatrixTargets,
    );
    final windowsAudit = _buildTerminalMatrixAudit(
      root: root,
      inputPath: options.inputPath,
      targets: _windowsTerminalMatrixTargets,
    );
    final readiness = _buildMvpReadinessAudit(
      root: root,
      inputPath: options.inputPath,
    );

    final outputDir = Directory(options.outputDir)..createSync(recursive: true);
    final outputs = <String, String>{
      'terminal-matrix-collection-plan.md': _terminalMatrixAuditPlanMarkdown(
        launchAudit,
      ),
      'terminal-matrix-review-packet.md': _terminalMatrixAuditReviewMarkdown(
        launchAudit,
      ),
      'windows-validation-plan.md': _terminalMatrixAuditPlanMarkdown(
        windowsAudit,
      ),
      'windows-validation-review-packet.md': _terminalMatrixAuditReviewMarkdown(
        windowsAudit,
      ),
      'mvp-readiness-report.md': _mvpReadinessAuditMarkdown(readiness),
    };

    for (final entry in outputs.entries) {
      final path = '${outputDir.path}/${entry.key}';
      File(path).writeAsStringSync(entry.value);
      stdout.writeln('Wrote ${_relative(path)}');
    }

    stdout.writeln(
      'MVP evidence: launch ${launchAudit['readyTargetCount']}/${launchAudit['targetCount']} ready, '
      'post-MVP windows ${windowsAudit['readyTargetCount']}/${windowsAudit['targetCount']} ready.',
    );
    if (options.strict && readiness['strictPass'] != true) {
      exit(1);
    }
  }

  Future<void> benchmark(List<String> args) async {
    if (args.isEmpty ||
        args.first == '-h' ||
        args.first == '--help' ||
        args.first == 'help') {
      _printBenchmarkUsage();
      return;
    }

    final subcommand = args.first;
    final rest = args.sublist(1);
    switch (subcommand) {
      case 'list':
        benchmarkList(rest);
        return;
      case 'local':
        await benchmarkLocal(rest);
        return;
      case 'profile':
        await benchmarkProfile(rest);
        return;
      case 'wire':
        await benchmarkWire(rest);
        return;
      case 'wire-gate':
        await benchmarkWireGate(rest);
        return;
      case 'serve-wire-live':
        await benchmarkServeWireLive(rest);
        return;
      case 'serve-semantics-gate':
        await benchmarkServeSemanticsGate(rest);
        return;
      case 'image-bench':
        await benchmarkImageBench(rest);
        return;
      case 'bundle-size':
        await benchmarkBundleSize(rest);
        return;
      case 'alloc-gate':
        await benchmarkAllocGate(rest);
        return;
      case 'paint-gate':
        await benchmarkPaintGate(rest);
        return;
      case 'gates':
        await benchmarkGates(rest);
        return;
      case 'scoreboard':
        await benchmarkScoreboard(rest);
        return;
      case 'web-capture':
        await benchmarkWebCapture(rest);
        return;
      case 'web-suite':
        await benchmarkWebSuite(rest);
        return;
      case 'web-scoreboard':
        await benchmarkWebScoreboard(rest);
        return;
      case 'web-threshold-review':
        await benchmarkWebThresholdReview(rest);
        return;
      case 'web-semantic-audit':
        await benchmarkWebSemanticAudit(rest);
        return;
      case 'web-manual-validation':
        await benchmarkWebManualValidation(rest);
        return;
      case 'web-readiness':
        await benchmarkWebReadiness(rest);
        return;
      case 'web-readiness-bundle':
        await benchmarkWebReadinessBundle(rest);
        return;
      case 'web-automated-validation':
        await benchmarkWebAutomatedValidation(rest);
        return;
      case 'web-default-preflight':
        await benchmarkWebDefaultPreflight(rest);
        return;
      case 'web-report':
        await benchmarkWebReport(rest);
        return;
      case 'manifest':
        await benchmarkManifest(rest);
        return;
      case 'result':
        await benchmarkResult(rest);
        return;
      case 'variance':
        await benchmarkVariance(rest);
        return;
      default:
        stderr.writeln('Unknown benchmark subcommand: $subcommand');
        _printBenchmarkUsage();
        exit(2);
    }
  }

  void benchmarkList(List<String> args) {
    var json = false;
    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printBenchmarkListUsage();
        exit(0);
      } else if (arg == '--json') {
        json = true;
      } else {
        stderr.writeln('Unknown option for benchmark list: $arg');
        _printBenchmarkListUsage();
        exit(2);
      }
    }

    final catalog = _benchmarkCatalog();
    if (json) {
      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(catalog));
    } else {
      _printBenchmarkCatalog(catalog);
    }
  }

  Future<void> benchmarkLocal(List<String> args) async {
    if (args.isEmpty ||
        args.first == '-h' ||
        args.first == '--help' ||
        args.first == 'help') {
      _printBenchmarkLocalUsage();
      if (args.isEmpty) exit(2);
      return;
    }
    if (args.first == '--list') {
      await _listLocalBenchmarkRunners();
      return;
    }

    final selector = args.first;
    final forwarded = args.sublist(1);
    if (selector.toLowerCase() == 'all') {
      if (forwarded.any((arg) => arg.startsWith('--save='))) {
        stderr.writeln(
          'benchmark local all cannot use one --save path for multiple runners.',
        );
        stderr.writeln(
          'Run each scenario/package separately when saving JSON.',
        );
        exit(2);
      }
      for (final target in _uniqueLocalBenchmarkTargets()) {
        await _runLocalBenchmarkTarget(target, forwarded);
      }
      return;
    }

    final scenarioId = _normalizeBenchmarkScenarioId(selector);
    final target = _localBenchmarkTargetFor(scenarioId);
    if (target == null) {
      stderr.writeln('Unknown local benchmark scenario: $selector');
      _printBenchmarkLocalUsage();
      exit(2);
    }
    await _runLocalBenchmarkTarget(target, [
      '--filter=$scenarioId',
      ...forwarded,
    ]);
  }

  Future<void> benchmarkProfile(List<String> args) async {
    if (args.isEmpty ||
        args.first == '-h' ||
        args.first == '--help' ||
        args.first == 'help') {
      _printBenchmarkProfileUsage();
      if (args.isEmpty) exit(2);
      return;
    }
    await _run('dart', [
      'run',
      'tool/benchmark_profile.dart',
      ...args,
    ], workingDirectory: '$root/packages/fleury');
  }

  Future<void> benchmarkWire(List<String> args) async {
    final options = _BenchmarkWireOptions.parse(root, args);
    final configs = <String, _WireScenarioConfig>{
      for (final id in options.scenarioIds) id: _wireScenarioConfigs[id]!,
    };
    final firstConfig = configs.values.first;

    final outDir = Directory(options.outDir);
    final binaryDir = Directory('${outDir.path}/bin');
    if (!dryRun) {
      outDir.createSync(recursive: true);
      binaryDir.createSync(recursive: true);
    }
    final runStamp = _timestampForFile(DateTime.now().toUtc());
    final fleuryBinary =
        '${binaryDir.path}/fleury-${firstConfig.shortName}-wire-$runStamp';
    stdout.writeln(
      'wire scenario ${firstConfig.shortName}: '
      'peers ${configs.values.map((config) => config.peerId).join(', ')}',
    );

    await _run('dart', [
      'compile',
      'exe',
      firstConfig.fleurySource,
      '-o',
      fleuryBinary,
    ], workingDirectory: profiling);

    final peerBinaries = <String, String?>{};
    for (final entry in configs.entries) {
      final config = entry.value;
      final peerBinary = config.peerKind == 'go'
          ? '${binaryDir.path}/${config.peerId}-${config.shortName}-wire-$runStamp'
          : null;
      peerBinaries[entry.key] = peerBinary;
      if (config.peerKind == 'go') {
        await _run('go', [
          'build',
          '-o',
          peerBinary!,
          '.',
        ], workingDirectory: '$root/${config.peerFixturePath}');
      } else if (config.peerKind == 'dart') {
        await _ensureDartWireRequirements(config);
      } else if (config.peerKind == 'python') {
        await _ensurePythonWireRequirements(config);
      } else if (config.peerKind == 'node' || config.peerKind == 'bun') {
        await _ensureNodeWireRequirements(config);
      } else if (config.peerKind == 'rust') {
        await _run('cargo', [
          'build',
          '--release',
        ], workingDirectory: '$root/${config.peerFixturePath}');
      }
    }

    for (var run = 1; run <= options.runs; run++) {
      final suffix = options.runs == 1
          ? ''
          : '-r${run.toString().padLeft(2, '0')}';
      final fleuryBase =
          '${outDir.path}/fleury-${firstConfig.shortName}-wire-$runStamp$suffix';
      stdout.writeln('wire run $run/${options.runs}: capture fleury');
      final fleuryDebugCapturePath = options.debugCapture
          ? '$fleuryBase.debug.json'
          : null;
      final fleuryRuntimeMarkersPath = options.runtimeMarkers
          ? '$fleuryBase.runtime.json'
          : null;
      final fleuryEnvironment = <String, String>{
        if (fleuryDebugCapturePath != null)
          'FLEURY_DEBUG_CAPTURE': fleuryDebugCapturePath,
        if (fleuryRuntimeMarkersPath != null)
          'FLEURY_RUNTIME_MARKERS': fleuryRuntimeMarkersPath,
      };
      await _run(
        'dart',
        [
          'run',
          'capture_pty.dart',
          '--out',
          fleuryBase,
          '--timeout',
          '${_fleuryWireTimeoutSeconds(configs.values, options)}',
          '--cols',
          '${options.cols}',
          '--rows',
          '${options.ptyRows}',
          '--ui-mode',
          firstConfig.uiMode,
          '--frame-count',
          '${options.stepsFor(firstConfig) + 1}',
          if (firstConfig.resizeSequence.isNotEmpty) ...[
            '--resize-sequence',
            firstConfig.resizeSequence.join(','),
            '--resize-interval-ms',
            '${options.intervalMsFor(firstConfig)}',
          ],
          '--',
          fleuryBinary,
          '--rows=${options.rowsFor(firstConfig)}',
          if (firstConfig.usesAppend)
            '--append=${options.appendFor(firstConfig)}',
          '--steps=${options.stepsFor(firstConfig)}',
          '--interval-ms=${options.intervalMsFor(firstConfig)}',
        ],
        workingDirectory: profiling,
        environment: fleuryEnvironment.isEmpty ? null : fleuryEnvironment,
      );
      if (fleuryDebugCapturePath != null) {
        stdout.writeln(
          'wire run $run/${options.runs}: fleury debug capture '
          '$fleuryDebugCapturePath',
        );
      }
      if (fleuryRuntimeMarkersPath != null) {
        stdout.writeln(
          'wire run $run/${options.runs}: fleury runtime markers '
          '$fleuryRuntimeMarkersPath',
        );
      }

      final analyzeArgs = <String>['fleury=$fleuryBase'];
      for (final entry in configs.entries) {
        final config = entry.value;
        final peerBase =
            '${outDir.path}/${config.peerId}-${config.shortName}-wire-$runStamp$suffix';
        stdout.writeln(
          'wire run $run/${options.runs}: capture ${config.peerId}',
        );
        await _run(
          'dart',
          [
            'run',
            'capture_pty.dart',
            '--out',
            peerBase,
            '--timeout',
            '${options.timeoutSecondsFor(config)}',
            '--cols',
            '${options.cols}',
            '--rows',
            '${options.ptyRows}',
            '--ui-mode',
            config.uiMode,
            '--frame-count',
            '${options.stepsFor(config) + 1}',
            if (config.resizeSequence.isNotEmpty) ...[
              '--resize-sequence',
              config.resizeSequence.join(','),
              '--resize-interval-ms',
              '${options.intervalMsFor(config)}',
            ],
            '--',
            ..._peerWireCommand(
              config,
              options,
              peerBinary: peerBinaries[entry.key],
            ),
          ],
          workingDirectory: profiling,
          environment: _peerWireEnvironment(config),
        );
        analyzeArgs.add('${config.peerId}=$peerBase');
      }

      stdout.writeln('wire run $run/${options.runs}: analyze');
      await _run('dart', [
        'run',
        'analyze.dart',
        ...analyzeArgs,
      ], workingDirectory: profiling);
    }

    stdout.writeln('captures written under ${_relative(outDir.path)}');
    await _refreshWireScoreboard(outDir.path);
  }

  /// Fleury-only wire regression gate: re-runs a small scenario subset and
  /// fails on byte-axis regression vs `profiling/wire_gate_baseline.json`.
  Future<void> benchmarkWireGate(List<String> args) async {
    await _run('dart', [
      'run',
      'bin/fleury_wire_gate.dart',
      ...args,
    ], workingDirectory: profiling);
  }

  /// The live `fleury serve` wire regression gate — boots real serve processes
  /// and measures the actual socket bytes (plan + semantics) a browser
  /// receives, plus the closed-loop input→paint latency probe (G4, the
  /// `input-latency` scenario; latency axes warn-only, one-key⟹one-plan
  /// structural). On-demand; pass `--update-baseline` to rebaseline
  /// (`--scenario=ID --update-baseline` re-baselines one scenario, merging).
  Future<void> benchmarkServeWireLive(List<String> args) async {
    await _run('dart', [
      'run',
      'bin/serve_wire_live_gate.dart',
      ...args,
    ], workingDirectory: profiling);
  }

  /// Guards the semantics wire's anti-cliff invariant: the `SemanticsWireEncoder`
  /// diff must stay flat in tree size so a large served UI never falls off the
  /// 32 KiB DEFLATE cliff (a ~57x per-frame blow-up). Fast + deterministic.
  Future<void> benchmarkServeSemanticsGate(List<String> args) async {
    await _run('dart', [
      'run',
      'bin/serve_semantics_profile.dart',
      '--gate',
      ...args,
    ], workingDirectory: profiling);
  }

  /// Inline-image encoder bench — image bytes/frame + encode µs (protocols x
  /// static/animated). Pass `--gate` to guard the dedup + zero-image-fast-path
  /// invariants at the byte level. Fast + deterministic.
  Future<void> benchmarkImageBench(List<String> args) async {
    await _run('dart', [
      'run',
      'bin/image_bench.dart',
      ...args,
    ], workingDirectory: profiling);
  }

  /// First-load bundle-size gate for the served-browser client
  /// (remote_client.dart.js, served at GET /client) — raw + gzip of the shipped
  /// bytes. Pass `--gate` to fail on a size regression. Fast — no recompile.
  Future<void> benchmarkBundleSize(List<String> args) async {
    await _run('dart', [
      'run',
      'bin/bundle_size_gate.dart',
      ...args,
    ], workingDirectory: profiling);
  }

  /// Per-frame allocation regression gate (G3). Drives a steady-state reactive
  /// scenario through the real per-frame path (build → reconcile → layout →
  /// paint → AnsiRenderer diff) against a reused double-buffer and measures
  /// `package:fleury` allocation churn per frame via a self-connected VM
  /// service — deterministic byte-for-byte. Pass `--gate` to fail on a
  /// regression past tolerance, `--update-baseline` to rebaseline (after an
  /// intentional change or an SDK bump). The VM-service flags are required so
  /// the gate can self-connect for the allocation profile; `--deterministic`
  /// keeps background-JIT allocation sinking from nondeterministically
  /// deflating a window.
  Future<void> benchmarkAllocGate(List<String> args) async {
    await _run('dart', [
      // --deterministic pins JIT compilation order: otherwise a background
      // allocation-sinking tier can land mid-window at a nondeterministic
      // frame and collapse the measured churn (see bin/alloc_gate.dart).
      '--deterministic',
      '--enable-vm-service=0',
      '--disable-service-auth-codes',
      'bin/alloc_gate.dart',
      ...args,
    ], workingDirectory: profiling);
  }

  /// Paint-cost regression gate. Drives real-widget steady-state scenarios
  /// (ListView auto-boundaries, Overlay adaptive entry boundaries, the lazy
  /// toast layer) and gates on exact per-frame repaint-boundary counters —
  /// deterministic and machine-independent, zero tolerance. Paint-phase µs is
  /// recorded warn-only. Pass `--gate` to fail on counter drift,
  /// `--update-baseline` to rebaseline after an intentional change
  /// (structural invariants — e.g. "an idle app is pure pass-through" — are
  /// enforced even then, so a broken shape cannot be baselined away).
  Future<void> benchmarkPaintGate(List<String> args) async {
    await _run('dart', [
      'run',
      'bin/paint_gate.dart',
      ...args,
    ], workingDirectory: profiling);
  }

  /// Runs the fast, self-contained regression gates in sequence and prints a
  /// pass/fail summary (does not stop on the first failure, so one command
  /// reports the whole board). Exits non-zero if any gate failed. The heavier
  /// PTY/subprocess gates (`wire-gate`, `serve-wire-live`) are listed but not
  /// auto-run — invoke them explicitly. See docs/implementation/perf-gates.md.
  Future<void> benchmarkGates(List<String> args) async {
    const fast = <({String name, List<String> cmd})>[
      (name: 'serve-semantics-gate', cmd: [
        'run',
        'bin/serve_semantics_profile.dart',
        '--gate',
      ]),
      (name: 'image-bench', cmd: ['run', 'bin/image_bench.dart', '--gate']),
      (name: 'bundle-size', cmd: ['run', 'bin/bundle_size_gate.dart', '--gate']),
      (name: 'alloc-gate', cmd: [
        '--deterministic',
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        'bin/alloc_gate.dart',
        '--gate',
      ]),
      (name: 'paint-gate', cmd: ['run', 'bin/paint_gate.dart', '--gate']),
    ];
    final results = <({String name, bool ok, int ms})>[];
    for (final gate in fast) {
      stdout.writeln('\n─── ${gate.name} ───');
      if (dryRun) {
        stdout.writeln('(${_relative(profiling)}) dart ${gate.cmd.join(' ')}');
        results.add((name: gate.name, ok: true, ms: 0));
        continue;
      }
      final sw = Stopwatch()..start();
      final process = await Process.start(
        'dart',
        gate.cmd,
        workingDirectory: profiling,
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await process.exitCode;
      sw.stop();
      results.add((
        name: gate.name,
        ok: code == 0,
        ms: sw.elapsedMilliseconds,
      ));
    }

    stdout.writeln('\n=== perf gate summary ===');
    var allOk = true;
    for (final r in results) {
      stdout.writeln('  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name.padRight(22)} '
          '${(r.ms / 1000).toStringAsFixed(1)}s');
      allOk = allOk && r.ok;
    }
    stdout.writeln('  (heavier PTY/subprocess gates not auto-run — invoke '
        'explicitly: wire-gate, serve-wire-live)');
    if (!allOk) {
      stderr.writeln('\nperf gates: one or more gates FAILED — see output '
          'above and docs/implementation/perf-gates.md.');
      exit(1);
    }
    stdout.writeln('\nperf gates: all fast gates pass.');
  }

  Future<void> benchmarkScoreboard(List<String> args) async {
    final options = _BenchmarkScoreboardOptions.parse(root, args);
    final matrixLink = options.outputPath == null
        ? 'benchmarks/README.md'
        : _relativeFilePath(
            fromDirectory: File(options.outputPath!).parent.path,
            toPath: '$root/benchmarks/README.md',
          );
    await _run('dart', [
      'run',
      'scoreboard.dart',
      '--input=${options.inputDir}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      '--matrix-link=$matrixLink',
      if (options.json) '--json',
    ], workingDirectory: profiling);
  }

  Future<void> benchmarkWebCapture(List<String> args) async {
    final options = _BenchmarkWebCaptureOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_frame_capture.dart',
      '--scenario=${options.scenarioId}',
      '--warmup=${options.warmupFrames}',
      '--budget-ms=${options.frameBudgetMs}',
      '--output=${options.outputPath}',
      '--timeout=${options.timeoutSeconds}',
      if (options.frames != null) '--frames=${options.frames}',
      if (options.chromePath != null) '--chrome=${options.chromePath}',
      if (options.headful) '--headful',
      if (options.keepTemp) '--keep-temp',
      if (options.compileOnly) '--compile-only',
      if (options.heapProfile) '--heap-profile',
      if (options.traceFrames) '--trace-frames',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
    if (!options.compileOnly &&
        options.outputPath.startsWith('$root/profiling/web/')) {
      await benchmarkWebScoreboard([
        '--input=profiling/web',
        '--output=profiling/web/scoreboard.md',
        '--json-output=profiling/web/scoreboard.json',
      ]);
    }
  }

  Future<void> benchmarkWebSuite(List<String> args) async {
    final options = _BenchmarkWebSuiteOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_frame_suite.dart',
      '--scenarios=${options.scenarioIds.join(',')}',
      '--runs=${options.runs}',
      '--warmup=${options.warmupFrames}',
      '--budget-ms=${options.frameBudgetMs}',
      '--output-dir=${options.outputDir}',
      '--scoreboard=${options.scoreboardPath}',
      '--scoreboard-json=${options.scoreboardJsonPath}',
      '--min-runs=${options.minRuns}',
      '--timeout=${options.timeoutSeconds}',
      if (options.maxTotalFrameP95Ms != null)
        '--max-total-frame-p95-ms=${options.maxTotalFrameP95Ms}',
      if (options.maxDomApplyP95Ms != null)
        '--max-dom-apply-p95-ms=${options.maxDomApplyP95Ms}',
      if (options.maxSemanticApplyP95Ms != null)
        '--max-semantic-apply-p95-ms=${options.maxSemanticApplyP95Ms}',
      if (options.maxOverBudgetPercent != null)
        '--max-over-budget-percent=${options.maxOverBudgetPercent}',
      if (options.maxSemanticUncoveredCells != null)
        '--max-semantic-uncovered-cells=${options.maxSemanticUncoveredCells}',
      if (options.thresholdsPath != null)
        '--thresholds=${options.thresholdsPath}',
      if (options.writeThresholdsPath != null)
        '--write-thresholds=${options.writeThresholdsPath}',
      '--threshold-headroom-percent=${options.thresholdHeadroomPercent}',
      '--threshold-min-headroom-ms=${options.thresholdMinHeadroomMs}',
      '--threshold-min-headroom-percent=${options.thresholdMinHeadroomPercent}',
      if (options.frames != null) '--frames=${options.frames}',
      if (options.chromePath != null) '--chrome=${options.chromePath}',
      if (!options.strictScoreboard) '--no-strict',
      if (!options.requireComparableRunEnvironment)
        '--no-require-comparable-environment',
      if (!options.compileOnce) '--no-compile-once',
      if (options.headful) '--headful',
      if (options.keepTemp) '--keep-temp',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebScoreboard(List<String> args) async {
    final options = _BenchmarkWebScoreboardOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_frame_scoreboard.dart',
      '--input=${options.inputDir}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      '--min-runs=${options.minRuns}',
      if (options.maxTotalFrameP95Ms != null)
        '--max-total-frame-p95-ms=${options.maxTotalFrameP95Ms}',
      if (options.maxDomApplyP95Ms != null)
        '--max-dom-apply-p95-ms=${options.maxDomApplyP95Ms}',
      if (options.maxSemanticApplyP95Ms != null)
        '--max-semantic-apply-p95-ms=${options.maxSemanticApplyP95Ms}',
      if (options.maxOverBudgetPercent != null)
        '--max-over-budget-percent=${options.maxOverBudgetPercent}',
      if (options.maxSemanticUncoveredCells != null)
        '--max-semantic-uncovered-cells=${options.maxSemanticUncoveredCells}',
      if (options.thresholdsPath != null)
        '--thresholds=${options.thresholdsPath}',
      if (options.writeThresholdsPath != null)
        '--write-thresholds=${options.writeThresholdsPath}',
      '--threshold-headroom-percent=${options.thresholdHeadroomPercent}',
      '--threshold-min-headroom-ms=${options.thresholdMinHeadroomMs}',
      '--threshold-min-headroom-percent=${options.thresholdMinHeadroomPercent}',
      if (options.requireComparableRunEnvironment)
        '--require-comparable-environment',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebThresholdReview(List<String> args) async {
    final options = _BenchmarkWebThresholdReviewOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_threshold_review.dart',
      '--input=${options.inputPath}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.writePlanPath != null)
        '--write-plan=${options.writePlanPath}',
      if (options.reviewedBy != null) '--reviewed-by=${options.reviewedBy}',
      if (options.reviewedAt != null) '--reviewed-at=${options.reviewedAt}',
      if (options.reviewContext != null)
        '--review-context=${options.reviewContext}',
      if (options.reviewContextHint != null)
        '--review-context-hint=${options.reviewContextHint}',
      if (options.reviewNote != null) '--review-note=${options.reviewNote}',
      if (options.expectedInputFingerprint != null)
        '--expect-input-fingerprint=${options.expectedInputFingerprint}',
      if (options.allowOverBudgetThresholds) '--allow-over-budget-thresholds',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebSemanticAudit(List<String> args) async {
    final options = _BenchmarkWebSemanticAuditOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_semantic_coverage_audit.dart',
      '--input=${options.inputDir}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      if (options.maxFallbackCells != null)
        '--max-fallback-cells=${options.maxFallbackCells}',
      if (options.maxFallbackFramePercent != null)
        '--max-fallback-frame-percent=${options.maxFallbackFramePercent}',
      if (options.maxFallbackViewportPercent != null)
        '--max-fallback-viewport-percent=${options.maxFallbackViewportPercent}',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebManualValidation(List<String> args) async {
    final options = _BenchmarkWebManualValidationOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_manual_validation.dart',
      '--input=${options.inputDir}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.writePlanPath != null)
        '--write-plan=${options.writePlanPath}',
      if (options.writeTemplatePath != null)
        '--write-template=${options.writeTemplatePath}',
      if (options.writeStarterPath != null)
        '--write-starter=${options.writeStarterPath}',
      if (options.starterTemplatePath != null)
        '--starter-template=${options.starterTemplatePath}',
      if (options.updateProvenancePath != null)
        '--update-provenance=${options.updateProvenancePath}',
      if (options.updatePageSignalPath != null)
        '--update-page-signal=${options.updatePageSignalPath}',
      if (options.updateCheckPath != null)
        '--update-check=${options.updateCheckPath}',
      if (options.reviewedBy != null) '--reviewed-by=${options.reviewedBy}',
      if (options.capturedAt != null) '--captured-at=${options.capturedAt}',
      if (options.browserVersion != null)
        '--browser-version=${options.browserVersion}',
      if (options.signalId != null) '--signal-id=${options.signalId}',
      if (options.signalStatus != null)
        '--signal-status=${options.signalStatus}',
      if (options.observedValue != null)
        '--observed-value=${options.observedValue}',
      if (options.signalNotes != null) '--signal-notes=${options.signalNotes}',
      if (options.checkId != null) '--check-id=${options.checkId}',
      if (options.checkStatus != null) '--check-status=${options.checkStatus}',
      if (options.checkNotes != null) '--check-notes=${options.checkNotes}',
      if (options.entryStatus != null) '--entry-status=${options.entryStatus}',
      if (options.writeTemplatesDir != null)
        '--write-templates=${options.writeTemplatesDir}',
      if (options.templateTargetId != null)
        '--template-target=${options.templateTargetId}',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      '--target-preset=${options.targetPreset}',
      for (final targetId in options.targetIds) '--target=$targetId',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebReadiness(List<String> args) async {
    final options = _BenchmarkWebReadinessOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_readiness.dart',
      '--scoreboard=${options.scoreboardPath}',
      '--semantic-audit=${options.semanticAuditPath}',
      '--manual-audit=${options.manualAuditPath}',
      if (options.thresholdReviewPath != null)
        '--threshold-review=${options.thresholdReviewPath}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      '--min-scoreboard-runs=${options.minScoreboardRuns}',
      if (!options.requireComparableEnvironment)
        '--no-require-comparable-environment',
      if (!options.requireScoreboardGates) '--no-require-scoreboard-gates',
      if (!options.requireTotalFrameGate) '--no-require-total-frame-gate',
      if (!options.requireSemanticGates) '--no-require-semantic-gates',
      if (!options.requireReviewedThresholdPolicy)
        '--no-require-reviewed-threshold-policy',
      if (!options.requireThresholdReviewSummary)
        '--no-require-threshold-review-summary',
      if (!options.requireScenarioThresholds)
        '--no-require-scenario-thresholds',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebReadinessBundle(List<String> args) async {
    final options = _BenchmarkWebReadinessBundleOptions.parse(root, args);
    if (options.verifyPath != null) {
      await _run('dart', [
        'run',
        'tool/web_readiness_bundle.dart',
        '--verify=${options.verifyPath}',
        if (options.strict) '--strict',
        if (options.json) '--json',
      ], workingDirectory: '$root/packages/fleury_web');
      return;
    }
    await _run('dart', [
      'run',
      'tool/web_readiness_bundle.dart',
      '--captures=${options.captureDir}',
      '--manual=${options.manualDir}',
      '--output-dir=${options.outputDir}',
      '--min-runs=${options.minRuns}',
      if (options.maxTotalFrameP95Ms != null)
        '--max-total-frame-p95-ms=${options.maxTotalFrameP95Ms}',
      if (options.maxDomApplyP95Ms != null)
        '--max-dom-apply-p95-ms=${options.maxDomApplyP95Ms}',
      if (options.maxSemanticApplyP95Ms != null)
        '--max-semantic-apply-p95-ms=${options.maxSemanticApplyP95Ms}',
      if (options.maxOverBudgetPercent != null)
        '--max-over-budget-percent=${options.maxOverBudgetPercent}',
      if (options.maxSemanticUncoveredCells != null)
        '--max-semantic-uncovered-cells=${options.maxSemanticUncoveredCells}',
      if (options.thresholdsPath != null)
        '--thresholds=${options.thresholdsPath}',
      if (options.thresholdReviewPath != null)
        '--threshold-review=${options.thresholdReviewPath}',
      if (!options.requireComparableRunEnvironment)
        '--no-require-comparable-environment',
      if (options.maxFallbackCells != null)
        '--max-fallback-cells=${options.maxFallbackCells}',
      if (options.maxFallbackFramePercent != null)
        '--max-fallback-frame-percent=${options.maxFallbackFramePercent}',
      if (options.maxFallbackViewportPercent != null)
        '--max-fallback-viewport-percent=${options.maxFallbackViewportPercent}',
      '--target-preset=${options.targetPreset}',
      for (final targetId in options.targetIds) '--target=$targetId',
      if (!options.requireScoreboardGates) '--no-require-scoreboard-gates',
      if (!options.requireTotalFrameGate) '--no-require-total-frame-gate',
      if (!options.requireSemanticGates) '--no-require-semantic-gates',
      if (!options.requireReviewedThresholdPolicy)
        '--no-require-reviewed-threshold-policy',
      if (!options.requireThresholdReviewSummary)
        '--no-require-threshold-review-summary',
      if (!options.requireScenarioThresholds)
        '--no-require-scenario-thresholds',
      if (options.writeDefaultPreflights) '--write-default-preflights',
      if (options.completionAuditPath != null)
        '--completion-audit=${options.completionAuditPath}',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebAutomatedValidation(List<String> args) async {
    final options = _BenchmarkWebAutomatedValidationOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_automated_validation.dart',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebDefaultPreflight(List<String> args) async {
    final options = _BenchmarkWebDefaultPreflightOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_default_preflight.dart',
      '--readiness=${options.readinessPath}',
      if (options.bundlePath != null) '--bundle=${options.bundlePath}',
      if (options.automatedValidationPath != null)
        '--automated-validation=${options.automatedValidationPath}',
      '--target=${options.target}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.jsonOutputPath != null)
        '--json-output=${options.jsonOutputPath}',
      if (options.strict) '--strict',
      if (options.allowUnbundled) '--allow-unbundled',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> benchmarkWebReport(List<String> args) async {
    final options = _BenchmarkWebReportOptions.parse(root, args);
    await _run('dart', [
      'run',
      'tool/web_frame_report.dart',
      '--input=${options.inputPath}',
      '--budget-ms=${options.frameBudgetMs}',
      if (options.outputPath != null) '--output=${options.outputPath}',
      if (options.maxTotalFrameP95Ms != null)
        '--max-total-frame-p95-ms=${options.maxTotalFrameP95Ms}',
      if (options.maxDomApplyP95Ms != null)
        '--max-dom-apply-p95-ms=${options.maxDomApplyP95Ms}',
      if (options.maxSemanticApplyP95Ms != null)
        '--max-semantic-apply-p95-ms=${options.maxSemanticApplyP95Ms}',
      if (options.maxOverBudgetPercent != null)
        '--max-over-budget-percent=${options.maxOverBudgetPercent}',
      if (options.maxSemanticUncoveredCells != null)
        '--max-semantic-uncovered-cells=${options.maxSemanticUncoveredCells}',
      if (options.strict) '--strict',
      if (options.json) '--json',
    ], workingDirectory: '$root/packages/fleury_web');
  }

  Future<void> _refreshWireScoreboard(String outDir) async {
    final outputPath = '$outDir/scoreboard.md';
    stdout.writeln('refresh scoreboard ${_relative(outputPath)}');
    await _run('dart', [
      'run',
      'scoreboard.dart',
      '--input=$outDir',
      '--output=$outputPath',
      '--matrix-link=${_relativeFilePath(fromDirectory: outDir, toPath: '$root/benchmarks/README.md')}',
    ], workingDirectory: profiling);
  }

  Future<void> _ensurePythonWireRequirements(_WireScenarioConfig config) async {
    final fixtureDir = '$root/${config.peerFixturePath}';
    final siteDir = Directory('$fixtureDir/.python');
    if (Directory('${siteDir.path}/textual').existsSync()) return;
    if (!dryRun) siteDir.createSync(recursive: true);
    await _run(_benchmarkPythonExecutable(), [
      '-m',
      'pip',
      'install',
      '--target=.python',
      '-r',
      'requirements.txt',
    ], workingDirectory: fixtureDir);
  }

  Future<void> _ensureDartWireRequirements(_WireScenarioConfig config) async {
    final fixtureDir = '$root/${config.peerFixturePath}';
    if (File('$fixtureDir/.dart_tool/package_config.json').existsSync()) {
      return;
    }
    await _run('dart', ['pub', 'get'], workingDirectory: fixtureDir);
  }

  Future<void> _ensureNodeWireRequirements(_WireScenarioConfig config) async {
    final fixtureDir = '$root/${config.peerFixturePath}';
    if (Directory('$fixtureDir/node_modules').existsSync()) return;
    await _run(
      _benchmarkNpmExecutable(),
      ['ci'],
      workingDirectory: fixtureDir,
      environment: _nodeToolEnvironment(),
    );
  }

  double _fleuryWireTimeoutSeconds(
    Iterable<_WireScenarioConfig> configs,
    _BenchmarkWireOptions options,
  ) {
    if (options.timeoutSecondsOverride != null) {
      return options.timeoutSecondsOverride!;
    }
    var timeout = 0.0;
    for (final config in configs) {
      if (config.defaultTimeoutSeconds > timeout) {
        timeout = config.defaultTimeoutSeconds;
      }
    }
    return timeout <= 0 ? 8.0 : timeout;
  }

  Map<String, String>? _peerWireEnvironment(_WireScenarioConfig config) {
    if (config.peerKind == 'node' || config.peerKind == 'bun') {
      return _nodeToolEnvironment();
    }
    if (config.peerKind != 'python') return null;
    final fixtureDir = '$root/${config.peerFixturePath}';
    final sitePath = '$fixtureDir/.python';
    final current = Platform.environment['PYTHONPATH'];
    return <String, String>{
      'PYTHONPATH': current == null || current.isEmpty
          ? sitePath
          : '$sitePath${Platform.isWindows ? ';' : ':'}$current',
    };
  }

  List<String> _peerWireCommand(
    _WireScenarioConfig config,
    _BenchmarkWireOptions options, {
    required String? peerBinary,
  }) {
    final args = <String>[
      '--wire',
      '--rows=${options.rowsFor(config)}',
      if (config.usesAppend) '--append=${options.appendFor(config)}',
      '--steps=${options.stepsFor(config)}',
      '--interval-ms=${options.intervalMsFor(config)}',
      '--size=${options.cols}x${options.ptyRows}',
    ];
    if (config.peerKind == 'go') {
      return <String>[peerBinary!, ...args];
    }
    if (config.peerKind == 'python') {
      return <String>[
        _benchmarkPythonExecutable(),
        '$root/${config.peerFixturePath}/${config.peerWireScript}',
        ...args,
      ];
    }
    if (config.peerKind == 'dart') {
      final fixtureDir = '$root/${config.peerFixturePath}';
      return <String>[
        '/bin/sh',
        '-lc',
        'cd ${_shellQuote(fixtureDir)} && exec dart run '
            '${_shellQuote(config.peerWireScript!)} '
            '${args.map(_shellQuote).join(' ')}',
      ];
    }
    if (config.peerKind == 'node') {
      return <String>[
        _benchmarkNodeExecutable(),
        '$root/${config.peerFixturePath}/${config.peerWireScript}',
        ...args,
      ];
    }
    if (config.peerKind == 'bun') {
      return <String>[
        _benchmarkBunExecutable(config),
        '$root/${config.peerFixturePath}/${config.peerWireScript}',
        ...args,
      ];
    }
    if (config.peerKind == 'rust') {
      return <String>[
        '$root/${config.peerFixturePath}/target/release/${config.peerExecutable!}',
        ...args,
      ];
    }
    throw StateError('Unsupported wire peer kind: ${config.peerKind}');
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  String _benchmarkPythonExecutable() {
    final configured = Platform.environment['FLEURY_BENCHMARK_PYTHON']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final bundled =
          '$home/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3';
      if (File(bundled).existsSync()) return bundled;
    }
    return 'python3';
  }

  String _benchmarkNodeExecutable() {
    final configured = Platform.environment['FLEURY_BENCHMARK_NODE']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final bundled =
          '$home/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node';
      if (File(bundled).existsSync()) return bundled;
    }
    return 'node';
  }

  String _benchmarkNpmExecutable() {
    final configured = Platform.environment['FLEURY_BENCHMARK_NPM']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return 'npm';
  }

  String _benchmarkBunExecutable(_WireScenarioConfig config) {
    final configured = Platform.environment['FLEURY_BENCHMARK_BUN']?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final local = '$root/${config.peerFixturePath}/node_modules/.bin/bun';
    if (File(local).existsSync() || Link(local).existsSync()) return local;
    return 'bun';
  }

  Map<String, String> _nodeToolEnvironment() {
    final nodeExecutable = _benchmarkNodeExecutable();
    final nodeDir = File(nodeExecutable).parent.path;
    final current = Platform.environment['PATH'];
    return <String, String>{
      'PATH': current == null || current.isEmpty
          ? nodeDir
          : '$nodeDir${Platform.isWindows ? ';' : ':'}$current',
    };
  }

  Future<void> benchmarkManifest(List<String> args) async {
    final options = _BenchmarkManifestOptions.parse(root, args);
    final relativeInput = _relative(options.inputPath);
    if (dryRun) {
      stdout.writeln('read $relativeInput');
      if (options.outputPath != null) {
        stdout.writeln('write ${_relative(options.outputPath!)}');
      }
      return;
    }

    final inputFile = File(options.inputPath);
    if (!inputFile.existsSync()) {
      stderr.writeln('Benchmark manifest not found: $relativeInput');
      exit(1);
    }
    final text = inputFile.readAsStringSync();
    final manifest = _readBenchmarkManifest(text, source: relativeInput);

    if (options.outputPath != null) {
      final outputFile = File(options.outputPath!);
      outputFile.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      outputFile.writeAsStringSync('${encoder.convert(manifest)}\n');
    }

    if (options.json) {
      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(manifest));
    } else {
      _printBenchmarkManifest(manifest);
    }
  }

  Future<void> benchmarkResult(List<String> args) async {
    final options = _BenchmarkResultOptions.parse(root, args);
    final relativeManifest = _relative(options.manifestPath);
    final relativeInput = _relative(options.inputPath);
    if (dryRun) {
      stdout.writeln('read $relativeManifest');
      stdout.writeln('read $relativeInput');
      if (options.outputPath != null) {
        stdout.writeln('write ${_relative(options.outputPath!)}');
      }
      return;
    }

    final manifestFile = File(options.manifestPath);
    if (!manifestFile.existsSync()) {
      stderr.writeln('Benchmark manifest not found: $relativeManifest');
      exit(1);
    }
    final inputFile = File(options.inputPath);
    if (!inputFile.existsSync()) {
      stderr.writeln('Benchmark peer run not found: $relativeInput');
      exit(1);
    }

    final manifest = _readBenchmarkManifest(
      manifestFile.readAsStringSync(),
      source: relativeManifest,
    );
    final peerRun = _readBenchmarkPeerRun(
      inputFile.readAsStringSync(),
      manifest: manifest,
      source: relativeInput,
    );
    final summary = _benchmarkPeerRunSummary(
      manifest,
      peerRun,
      outputPath: options.outputPath == null
          ? null
          : _relative(options.outputPath!),
    );

    if (options.outputPath != null) {
      final outputFile = File(options.outputPath!);
      outputFile.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      final merged = _mergeBenchmarkPeerRun(manifest, peerRun);
      outputFile.writeAsStringSync('${encoder.convert(merged)}\n');
    }

    if (options.json) {
      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(summary));
    } else {
      _printBenchmarkPeerRunSummary(summary);
    }
  }

  Future<void> benchmarkVariance(List<String> args) async {
    final options = _BenchmarkVarianceOptions.parse(root, args);
    final relativeManifest = _relative(options.manifestPath);
    final relativeInputs = [
      for (final inputPath in options.inputPaths) _relative(inputPath),
    ];
    if (dryRun) {
      stdout.writeln('read $relativeManifest');
      for (final input in relativeInputs) {
        stdout.writeln('scan $input');
      }
      if (options.outputPath != null) {
        stdout.writeln('write ${_relative(options.outputPath!)}');
      }
      if (options.strict) stdout.writeln('enforce strict variance readiness');
      return;
    }

    final manifestFile = File(options.manifestPath);
    if (!manifestFile.existsSync()) {
      stderr.writeln('Benchmark manifest not found: $relativeManifest');
      exit(1);
    }
    final manifest = _readBenchmarkManifest(
      manifestFile.readAsStringSync(),
      source: relativeManifest,
    );
    final inputFiles = _benchmarkVarianceInputFiles(
      root: root,
      inputPaths: options.inputPaths,
    );
    if (inputFiles.isEmpty) {
      stderr.writeln('benchmark-variance found no JSON peer run artifacts');
      exit(1);
    }

    final peerRuns = <Map<String, Object?>>[];
    final runPaths = <String>[];
    for (final file in inputFiles) {
      final relativeInput = _relative(file.path);
      final peerRun = _readBenchmarkPeerRun(
        file.readAsStringSync(),
        manifest: manifest,
        source: relativeInput,
      );
      peerRuns.add(peerRun);
      runPaths.add(relativeInput);
    }

    final summary = _buildBenchmarkVariance(
      manifest: manifest,
      peerRuns: peerRuns,
      runPaths: runPaths,
      minRuns: options.minRuns,
    );

    if (options.outputPath != null) {
      final outputFile = File(options.outputPath!);
      outputFile.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      outputFile.writeAsStringSync('${encoder.convert(summary)}\n');
    }

    if (options.json) {
      const encoder = JsonEncoder.withIndent('  ');
      stdout.writeln(encoder.convert(summary));
    } else {
      _printBenchmarkVariance(summary);
    }

    if (options.strict && summary['strictPass'] != true) {
      exit(1);
    }
  }

  Future<void> activateCli() {
    return _run('dart', [
      'pub',
      'global',
      'activate',
      '--source',
      'path',
      'packages/fleury',
    ], workingDirectory: root);
  }

  Future<void> buildCli() {
    if (!dryRun) {
      Directory('$root/build').createSync(recursive: true);
    }
    return _run('dart', [
      'compile',
      'exe',
      'bin/fleury.dart',
      '-o',
      '../../build/fleury',
    ], workingDirectory: fleury);
  }

  Future<void> _run(
    String executable,
    List<String> args, {
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    final display = [
      executable,
      ...args.map((arg) => arg.contains(' ') ? '"$arg"' : arg),
    ].join(' ');
    final relativeDir = _relative(workingDirectory);
    if (dryRun) {
      stdout.writeln('($relativeDir) $display');
      return;
    }
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      stderr.writeln(
        'Command failed in $relativeDir with exit code $code: $display',
      );
      exit(code);
    }
  }

  String _relative(String path) {
    if (path == root) return '.';
    if (path.startsWith('$root/')) return path.substring(root.length + 1);
    return path;
  }

  Future<void> _listLocalBenchmarkRunners() async {
    for (final target in _uniqueLocalBenchmarkTargets()) {
      stdout.writeln('${target.label}:');
      await _run('dart', [
        'run',
        'benchmark/scenario_benchmarks.dart',
        '--list',
      ], workingDirectory: '$root/${target.packagePath}');
    }
  }

  Future<void> _runLocalBenchmarkTarget(
    _LocalBenchmarkTarget target,
    List<String> args,
  ) {
    final forwarded = args.map(_normalizeLocalBenchmarkArg).toList();
    return _run('dart', [
      'run',
      'benchmark/scenario_benchmarks.dart',
      ...forwarded,
    ], workingDirectory: '$root/${target.packagePath}');
  }

  String _normalizeLocalBenchmarkArg(String arg) {
    const prefix = '--save=';
    if (!arg.startsWith(prefix)) return arg;
    final path = arg.substring(prefix.length);
    if (path.isEmpty || _isAbsolutePath(path)) return arg;
    return '$prefix$root/$path';
  }

  bool _isAbsolutePath(String path) {
    if (path.startsWith('/')) return true;
    if (path.startsWith(r'\\')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }
}

final class _CoverageOptions {
  const _CoverageOptions({
    required this.strict,
    required this.json,
    required this.includeIntegration,
    required this.coreMinPercent,
    required this.widgetsMinPercent,
  });

  final bool strict;
  final bool json;
  final bool includeIntegration;
  final double coreMinPercent;
  final double widgetsMinPercent;

  static _CoverageOptions parse(List<String> args) {
    var strict = false;
    var json = false;
    var includeIntegration = false;
    var coreMinPercent = 80.0;
    var widgetsMinPercent = 85.0;
    for (final arg in args) {
      if (arg == '--help' || arg == '-h') {
        _printCoverageUsage();
        exit(0);
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--include-integration') {
        includeIntegration = true;
      } else if (arg.startsWith('--core-min=')) {
        coreMinPercent = _parseCoveragePercent(arg, '--core-min=');
      } else if (arg.startsWith('--widgets-min=')) {
        widgetsMinPercent = _parseCoveragePercent(arg, '--widgets-min=');
      } else {
        stderr.writeln('Unknown option for coverage: $arg');
        _printCoverageUsage();
        exit(2);
      }
    }
    return _CoverageOptions(
      strict: strict,
      json: json,
      includeIntegration: includeIntegration,
      coreMinPercent: coreMinPercent,
      widgetsMinPercent: widgetsMinPercent,
    );
  }
}

double _parseCoveragePercent(String arg, String prefix) {
  final raw = arg.substring(prefix.length);
  final parsed = double.tryParse(raw);
  if (parsed == null || parsed < 0 || parsed > 100) {
    stderr.writeln('$prefix requires a percentage from 0 to 100.');
    exit(2);
  }
  return parsed;
}

void _printCoverageUsage() {
  stdout.writeln('Usage: dart tool/fleury_dev.dart coverage [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --strict                 Exit non-zero when a floor fails');
  stdout.writeln(
    '  --json                   Print machine-readable summary JSON',
  );
  stdout.writeln(
    '  --include-integration    Include core integration-tagged tests',
  );
  stdout.writeln('  --core-min=PERCENT       Core package floor, default 80');
  stdout.writeln(
    '  --widgets-min=PERCENT    Widgets package floor, default 85',
  );
}

final class _CoveragePackageTarget {
  const _CoveragePackageTarget({
    required this.label,
    required this.packageName,
    required this.packagePath,
    required this.floorPercent,
    required this.excludeIntegration,
    required this.excludeCoverageIncompatible,
  });

  final String label;
  final String packageName;
  final String packagePath;
  final double floorPercent;
  final bool excludeIntegration;
  final bool excludeCoverageIncompatible;
}

final class _CoveragePackageResult {
  const _CoveragePackageResult({
    required this.target,
    required this.lcovPath,
    required this.testStartCount,
    required this.testDoneCount,
    required this.linesHit,
    required this.linesFound,
    required this.linePercent,
  });

  final _CoveragePackageTarget target;
  final String lcovPath;
  final int testStartCount;
  final int testDoneCount;
  final int linesHit;
  final int linesFound;
  final double linePercent;

  bool get strictPass => linePercent >= target.floorPercent;

  Map<String, Object?> toJson(String root) {
    return <String, Object?>{
      'label': target.label,
      'packageName': target.packageName,
      'packagePath': _relativeToRoot(root, target.packagePath),
      'lcovPath': _relativeToRoot(root, lcovPath),
      'testStartCount': testStartCount,
      'testDoneCount': testDoneCount,
      'linesHit': linesHit,
      'linesFound': linesFound,
      'linePercent': _roundCoveragePercent(linePercent),
      'floorPercent': _roundCoveragePercent(target.floorPercent),
      'strictPass': strictPass,
    };
  }
}

({int start, int done}) _countJsonTestEvents(String output) {
  var start = 0;
  var done = 0;
  for (final line in const LineSplitter().convert(output)) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    switch (decoded['type']) {
      case 'testStart':
        start += 1;
      case 'testDone':
        done += 1;
    }
  }
  return (start: start, done: done);
}

({int linesHit, int linesFound}) _parseLcov(String text) {
  var totalHit = 0;
  var totalFound = 0;
  var recordHit = 0;
  var recordFound = 0;
  var daHit = 0;
  var daFound = 0;
  var hasSummary = false;
  var hasRecord = false;

  void finishRecord() {
    if (!hasRecord) return;
    totalHit += hasSummary ? recordHit : daHit;
    totalFound += hasSummary ? recordFound : daFound;
    recordHit = 0;
    recordFound = 0;
    daHit = 0;
    daFound = 0;
    hasSummary = false;
    hasRecord = false;
  }

  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('SF:')) {
      finishRecord();
      hasRecord = true;
    } else if (line.startsWith('DA:')) {
      hasRecord = true;
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        final count = int.tryParse(parts[1]) ?? 0;
        daFound += 1;
        if (count > 0) daHit += 1;
      }
    } else if (line.startsWith('LH:')) {
      hasRecord = true;
      hasSummary = true;
      recordHit = int.tryParse(line.substring(3)) ?? recordHit;
    } else if (line.startsWith('LF:')) {
      hasRecord = true;
      hasSummary = true;
      recordFound = int.tryParse(line.substring(3)) ?? recordFound;
    } else if (line == 'end_of_record') {
      finishRecord();
    }
  }
  finishRecord();
  return (linesHit: totalHit, linesFound: totalFound);
}

void _printCoverageSummary(
  List<_CoveragePackageResult> results, {
  required bool strictPass,
}) {
  stdout.writeln('Coverage summary');
  for (final result in results) {
    stdout.writeln(
      '${result.target.label}: '
      '${_formatPercent(result.linePercent)}% lines '
      '(${result.linesHit}/${result.linesFound}), '
      '${result.testDoneCount} tests, '
      'floor ${_formatPercent(result.target.floorPercent)}%, '
      '${result.strictPass ? 'pass' : 'fail'}',
    );
  }
  stdout.writeln('Strict pass: $strictPass');
}

String _formatPercent(double value) {
  final rounded = _roundCoveragePercent(value);
  return rounded.roundToDouble() == rounded
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}

double _roundCoveragePercent(double value) =>
    double.parse(value.toStringAsFixed(1));

String _relativeToRoot(String root, String path) {
  if (path == root) return '.';
  if (path.startsWith('$root/')) return path.substring(root.length + 1);
  return path;
}

final class _LocalBenchmarkTarget {
  const _LocalBenchmarkTarget({
    required this.label,
    required this.packagePath,
    required this.scenarios,
  });

  final String label;
  final String packagePath;
  final List<String> scenarios;
}

const _coreBenchmarkTarget = _LocalBenchmarkTarget(
  label: 'Core package',
  packagePath: 'packages/fleury',
  scenarios: <String>['SB.1', 'SB.2', 'SB.12'],
);

const _widgetBenchmarkTarget = _LocalBenchmarkTarget(
  label: 'Widget package',
  packagePath: 'packages/fleury_widgets',
  scenarios: <String>[
    'SB.3',
    'SB.4',
    'SB.5',
    'SB.6',
    'SB.7',
    'SB.8',
    'SB.9',
    'SB.11',
  ],
);

const _demoBenchmarkTarget = _LocalBenchmarkTarget(
  label: 'Demo app',
  packagePath: 'packages/fleury_example_console',
  scenarios: <String>['SB.10'],
);

const _localBenchmarkTargets = <_LocalBenchmarkTarget>[
  _coreBenchmarkTarget,
  _widgetBenchmarkTarget,
  _demoBenchmarkTarget,
];

_LocalBenchmarkTarget? _localBenchmarkTargetFor(String scenarioId) {
  for (final target in _localBenchmarkTargets) {
    if (target.scenarios.contains(scenarioId)) return target;
  }
  return null;
}

List<_LocalBenchmarkTarget> _uniqueLocalBenchmarkTargets() {
  return _localBenchmarkTargets;
}

String _normalizeBenchmarkScenarioId(String value) {
  final upper = value.trim().toUpperCase();
  if (upper.startsWith('SB')) {
    final digits = upper.substring(2).replaceAll(RegExp('[^0-9]'), '');
    if (digits.isNotEmpty) return 'SB.$digits';
  }
  return upper;
}

String _normalizeWireScenario(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'sb1' || normalized == 'sb.1') {
    return 'sb1';
  }
  if (normalized == 'sb1-bt' || normalized == 'sb1-bubbletea') {
    return 'sb1-bubbletea';
  }
  if (normalized == 'sb1-textual' ||
      normalized == 'sb1-py' ||
      normalized == 'sb.1-textual') {
    return 'sb1-textual';
  }
  if (normalized == 'sb1-ink' || normalized == 'sb.1-ink') {
    return 'sb1-ink';
  }
  if (normalized == 'sb4' || normalized == 'sb.4') {
    return 'sb4';
  }
  if (normalized == 'sb4-bt' || normalized == 'sb4-bubbletea') {
    return 'sb4-bubbletea';
  }
  if (normalized == 'sb4-textual' ||
      normalized == 'sb4-py' ||
      normalized == 'sb.4-textual') {
    return 'sb4-textual';
  }
  if (normalized == 'sb4-opentui' ||
      normalized == 'sb4-ot' ||
      normalized == 'sb.4-opentui') {
    return 'sb4-opentui';
  }
  if (normalized == 'sb5' || normalized == 'sb.5') {
    return 'sb5';
  }
  if (normalized == 'sb5-bt' || normalized == 'sb5-bubbletea') {
    return 'sb5-bubbletea';
  }
  if (normalized == 'sb5-textual' ||
      normalized == 'sb5-py' ||
      normalized == 'sb.5-textual') {
    return 'sb5-textual';
  }
  if (normalized == 'sb5-ink' || normalized == 'sb.5-ink') {
    return 'sb5-ink';
  }
  if (normalized == 'sb6' || normalized == 'sb.6') {
    return 'sb6';
  }
  if (normalized == 'sb6-bt' || normalized == 'sb6-bubbletea') {
    return 'sb6-bubbletea';
  }
  if (normalized == 'sb6-ratatui' || normalized == 'sb.6-ratatui') {
    return 'sb6-ratatui';
  }
  if (normalized == 'sb6-opentui' ||
      normalized == 'sb6-ot' ||
      normalized == 'sb.6-opentui') {
    return 'sb6-opentui';
  }
  if (normalized == 'sb7' || normalized == 'sb.7') {
    return 'sb7';
  }
  if (normalized == 'sb7-textual' ||
      normalized == 'sb7-py' ||
      normalized == 'sb.7-textual') {
    return 'sb7-textual';
  }
  if (normalized == 'sb7-ratatui' || normalized == 'sb.7-ratatui') {
    return 'sb7-ratatui';
  }
  if (normalized == 'sb7-opentui' ||
      normalized == 'sb7-ot' ||
      normalized == 'sb.7-opentui') {
    return 'sb7-opentui';
  }
  if (normalized == 'sb8' || normalized == 'sb.8') {
    return 'sb8';
  }
  if (normalized == 'sb8-textual' ||
      normalized == 'sb8-py' ||
      normalized == 'sb.8-textual') {
    return 'sb8-textual';
  }
  if (normalized == 'sb8-ink' || normalized == 'sb.8-ink') {
    return 'sb8-ink';
  }
  if (normalized == 'sb8-bt' ||
      normalized == 'sb8-bubbletea' ||
      normalized == 'sb.8-bubbletea') {
    return 'sb8-bubbletea';
  }
  if (normalized == 'sb9' || normalized == 'sb.9') {
    return 'sb9';
  }
  if (normalized == 'sb9-textual' ||
      normalized == 'sb9-py' ||
      normalized == 'sb.9-textual') {
    return 'sb9-textual';
  }
  if (normalized == 'sb9-bt' ||
      normalized == 'sb9-bubbletea' ||
      normalized == 'sb.9-bubbletea') {
    return 'sb9-bubbletea';
  }
  if (normalized == 'sb9-opentui' ||
      normalized == 'sb9-ot' ||
      normalized == 'sb.9-opentui') {
    return 'sb9-opentui';
  }
  if (normalized == 'sb10' || normalized == 'sb.10') {
    return 'sb10';
  }
  if (normalized == 'sb10-textual' ||
      normalized == 'sb10-py' ||
      normalized == 'sb.10-textual') {
    return 'sb10-textual';
  }
  if (normalized == 'sb10-bt' ||
      normalized == 'sb10-bubbletea' ||
      normalized == 'sb.10-bubbletea') {
    return 'sb10-bubbletea';
  }
  if (normalized == 'sb10-ink' || normalized == 'sb.10-ink') {
    return 'sb10-ink';
  }
  if (normalized == 'sb11' || normalized == 'sb.11') {
    return 'sb11';
  }
  if (normalized == 'sb11-textual' ||
      normalized == 'sb11-py' ||
      normalized == 'sb.11-textual') {
    return 'sb11-textual';
  }
  if (normalized == 'sb11-ratatui' || normalized == 'sb.11-ratatui') {
    return 'sb11-ratatui';
  }
  if (normalized == 'sb11-opentui' ||
      normalized == 'sb11-ot' ||
      normalized == 'sb.11-opentui') {
    return 'sb11-opentui';
  }
  if (normalized == 'sb12' || normalized == 'sb.12') {
    return 'sb12';
  }
  if (normalized == 'sb12-nocterm') {
    return 'sb12-nocterm';
  }
  if (normalized == 'sb12-ratatui' || normalized == 'sb.12-ratatui') {
    return 'sb12-ratatui';
  }
  if (normalized == 'sb12-opentui' ||
      normalized == 'sb12-ot' ||
      normalized == 'sb.12-opentui') {
    return 'sb12-opentui';
  }
  if (normalized == 'sb2' || normalized == 'sb.2') {
    return 'sb2';
  }
  if (normalized == 'sb2-bt' || normalized == 'sb2-bubbletea') {
    return 'sb2-bubbletea';
  }
  if (normalized == 'sb2-textual' ||
      normalized == 'sb2-py' ||
      normalized == 'sb.2-textual') {
    return 'sb2-textual';
  }
  if (normalized == 'sb2-ink' || normalized == 'sb.2-ink') {
    return 'sb2-ink';
  }
  if (normalized == 'sb3' || normalized == 'sb.3') {
    return 'sb3';
  }
  if (normalized == 'sb3-textual' ||
      normalized == 'sb3-py' ||
      normalized == 'sb.3-textual') {
    return 'sb3-textual';
  }
  if (normalized == 'sb3-ratatui' || normalized == 'sb.3-ratatui') {
    return 'sb3-ratatui';
  }
  if (normalized == 'sb3-opentui' ||
      normalized == 'sb3-ot' ||
      normalized == 'sb.3-opentui') {
    return 'sb3-opentui';
  }
  return normalized;
}

final class _WireScenarioConfig {
  const _WireScenarioConfig({
    required this.shortName,
    required this.scenarioName,
    required this.peerId,
    required this.peerKind,
    required this.fleurySource,
    required this.peerFixturePath,
    this.peerWireScript,
    this.peerExecutable,
    this.uiMode = 'full-ui',
    required this.defaultRows,
    required this.usesAppend,
    required this.defaultAppend,
    required this.defaultSteps,
    required this.defaultIntervalMs,
    required this.defaultTimeoutSeconds,
    this.resizeSequence = const <String>[],
  });

  final String shortName;
  final String scenarioName;
  final String peerId;
  final String peerKind;
  final String fleurySource;
  final String peerFixturePath;
  final String? peerWireScript;
  final String? peerExecutable;
  final String uiMode;
  final int defaultRows;
  final bool usesAppend;
  final int defaultAppend;
  final int defaultSteps;
  final int defaultIntervalMs;
  final double defaultTimeoutSeconds;
  final List<String> resizeSequence;
}

const _sb7ResizeSequence = <String>[
  '80x24',
  '120x40',
  '200x60',
  '64x18',
  '48x12',
  '32x8',
  '160x20',
  '120x32',
];

const _wireScenarioConfigs = <String, _WireScenarioConfig>{
  'sb1-bubbletea': _WireScenarioConfig(
    shortName: 'sb1',
    scenarioName: 'SB.1 Counter/Startup',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb1_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb1_counter',
    defaultRows: 1,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 1,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 8,
  ),
  'sb1-textual': _WireScenarioConfig(
    shortName: 'sb1',
    scenarioName: 'SB.1 Counter/Startup',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb1_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb1_counter',
    peerWireScript: 'sb1_counter_benchmark.py',
    defaultRows: 1,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 1,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 15,
  ),
  'sb1-ink': _WireScenarioConfig(
    shortName: 'sb1',
    scenarioName: 'SB.1 Counter/Startup',
    peerId: 'ink',
    peerKind: 'node',
    fleurySource: 'bin/fleury_sb1_wire.dart',
    peerFixturePath: 'peer-fixtures/ink/sb1_counter',
    peerWireScript: 'bin/sb1_counter_benchmark.js',
    defaultRows: 1,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 1,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 15,
  ),
  'sb2-bubbletea': _WireScenarioConfig(
    shortName: 'sb2',
    scenarioName: 'SB.2 Text Editing',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb2_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb2_text_editing',
    uiMode: 'full-ui',
    defaultRows: 10000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 15,
  ),
  'sb2-textual': _WireScenarioConfig(
    shortName: 'sb2',
    scenarioName: 'SB.2 Text Editing',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb2_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb2_text_editing',
    peerWireScript: 'sb2_text_editing_benchmark.py',
    defaultRows: 10000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 20,
  ),
  'sb2-ink': _WireScenarioConfig(
    shortName: 'sb2',
    scenarioName: 'SB.2 Text Editing',
    peerId: 'ink',
    peerKind: 'node',
    fleurySource: 'bin/fleury_sb2_wire.dart',
    peerFixturePath: 'peer-fixtures/ink/sb2_text_editing',
    peerWireScript: 'bin/sb2_text_editing_benchmark.js',
    defaultRows: 10000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 20,
  ),
  'sb3-textual': _WireScenarioConfig(
    shortName: 'sb3',
    scenarioName: 'SB.3 DataTable',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb3_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb3_datatable',
    peerWireScript: 'sb3_datatable_benchmark.py',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 5,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 30,
  ),
  'sb3-ratatui': _WireScenarioConfig(
    shortName: 'sb3',
    scenarioName: 'SB.3 DataTable',
    peerId: 'ratatui',
    peerKind: 'rust',
    fleurySource: 'bin/fleury_sb3_wire.dart',
    peerFixturePath: 'peer-fixtures/ratatui/sb3_datatable',
    peerExecutable: 'ratatui_sb3_datatable',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 5,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 20,
  ),
  'sb3-opentui': _WireScenarioConfig(
    shortName: 'sb3',
    scenarioName: 'SB.3 DataTable',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb3_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb3_datatable',
    peerWireScript: 'bin/sb3_datatable_benchmark.js',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 5,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 20,
  ),
  'sb4-bubbletea': _WireScenarioConfig(
    shortName: 'sb4',
    scenarioName: 'SB.4 LogRegion Tailing And Scrollback',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb4_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb4_log_region',
    defaultRows: 200,
    usesAppend: true,
    defaultAppend: 10,
    defaultSteps: 5,
    defaultIntervalMs: 100,
    defaultTimeoutSeconds: 8,
  ),
  'sb4-textual': _WireScenarioConfig(
    shortName: 'sb4',
    scenarioName: 'SB.4 LogRegion Tailing And Scrollback',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb4_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb4_log_region',
    peerWireScript: 'sb4_log_benchmark.py',
    defaultRows: 200,
    usesAppend: true,
    defaultAppend: 10,
    defaultSteps: 5,
    defaultIntervalMs: 100,
    defaultTimeoutSeconds: 15,
  ),
  'sb4-opentui': _WireScenarioConfig(
    shortName: 'sb4',
    scenarioName: 'SB.4 LogRegion Tailing And Scrollback',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb4_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb4_log_region',
    peerWireScript: 'bin/sb4_log_region_benchmark.js',
    defaultRows: 200,
    usesAppend: true,
    defaultAppend: 10,
    defaultSteps: 5,
    defaultIntervalMs: 100,
    defaultTimeoutSeconds: 20,
  ),
  'sb5-bubbletea': _WireScenarioConfig(
    shortName: 'sb5',
    scenarioName: 'SB.5 Streaming Markdown',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb5_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb5_streaming_markdown',
    defaultRows: 200,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 16,
    defaultIntervalMs: 50,
    defaultTimeoutSeconds: 15,
  ),
  'sb5-textual': _WireScenarioConfig(
    shortName: 'sb5',
    scenarioName: 'SB.5 Streaming Markdown',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb5_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb5_streaming_markdown',
    peerWireScript: 'sb5_markdown_benchmark.py',
    defaultRows: 200,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 16,
    defaultIntervalMs: 50,
    defaultTimeoutSeconds: 20,
  ),
  'sb5-ink': _WireScenarioConfig(
    shortName: 'sb5',
    scenarioName: 'SB.5 Streaming Markdown',
    peerId: 'ink',
    peerKind: 'node',
    fleurySource: 'bin/fleury_sb5_wire.dart',
    peerFixturePath: 'peer-fixtures/ink/sb5_streaming_markdown',
    peerWireScript: 'bin/sb5_markdown_benchmark.js',
    defaultRows: 200,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 16,
    defaultIntervalMs: 50,
    defaultTimeoutSeconds: 20,
  ),
  'sb6-bubbletea': _WireScenarioConfig(
    shortName: 'sb6',
    scenarioName: 'SB.6 Dashboard Updates',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb6_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb6_dashboard',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 120,
    defaultIntervalMs: 16,
    defaultTimeoutSeconds: 15,
  ),
  'sb6-ratatui': _WireScenarioConfig(
    shortName: 'sb6',
    scenarioName: 'SB.6 Dashboard Updates',
    peerId: 'ratatui',
    peerKind: 'rust',
    fleurySource: 'bin/fleury_sb6_wire.dart',
    peerFixturePath: 'peer-fixtures/ratatui/sb6_dashboard',
    peerExecutable: 'ratatui_sb6_dashboard',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 120,
    defaultIntervalMs: 16,
    defaultTimeoutSeconds: 15,
  ),
  'sb6-opentui': _WireScenarioConfig(
    shortName: 'sb6',
    scenarioName: 'SB.6 Dashboard Updates',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb6_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb6_dashboard',
    peerWireScript: 'bin/sb6_dashboard_benchmark.js',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 120,
    defaultIntervalMs: 16,
    defaultTimeoutSeconds: 20,
  ),
  'sb7-textual': _WireScenarioConfig(
    shortName: 'sb7',
    scenarioName: 'SB.7 Resize Storm',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb7_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb7_resize_storm',
    peerWireScript: 'sb7_resize_storm_benchmark.py',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 20,
    resizeSequence: _sb7ResizeSequence,
  ),
  'sb7-ratatui': _WireScenarioConfig(
    shortName: 'sb7',
    scenarioName: 'SB.7 Resize Storm',
    peerId: 'ratatui',
    peerKind: 'rust',
    fleurySource: 'bin/fleury_sb7_wire.dart',
    peerFixturePath: 'peer-fixtures/ratatui/sb7_resize_storm',
    peerExecutable: 'ratatui_sb7_resize_storm',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 15,
    resizeSequence: _sb7ResizeSequence,
  ),
  'sb7-opentui': _WireScenarioConfig(
    shortName: 'sb7',
    scenarioName: 'SB.7 Resize Storm',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb7_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb7_resize_storm',
    peerWireScript: 'bin/sb7_resize_storm_benchmark.js',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 20,
    resizeSequence: _sb7ResizeSequence,
  ),
  'sb8-textual': _WireScenarioConfig(
    shortName: 'sb8',
    scenarioName: 'SB.8 Overlay/Palette Churn',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb8_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb8_overlay_palette',
    peerWireScript: 'sb8_overlay_palette_benchmark.py',
    defaultRows: 500,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 12,
    defaultIntervalMs: 40,
    defaultTimeoutSeconds: 20,
  ),
  'sb8-ink': _WireScenarioConfig(
    shortName: 'sb8',
    scenarioName: 'SB.8 Overlay/Palette Churn',
    peerId: 'ink',
    peerKind: 'node',
    fleurySource: 'bin/fleury_sb8_wire.dart',
    peerFixturePath: 'peer-fixtures/ink/sb8_overlay_palette',
    peerWireScript: 'bin/sb8_overlay_palette_benchmark.js',
    defaultRows: 500,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 12,
    defaultIntervalMs: 40,
    defaultTimeoutSeconds: 20,
  ),
  'sb8-bubbletea': _WireScenarioConfig(
    shortName: 'sb8',
    scenarioName: 'SB.8 Overlay/Palette Churn',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb8_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb8_overlay_palette',
    defaultRows: 500,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 12,
    defaultIntervalMs: 40,
    defaultTimeoutSeconds: 15,
  ),
  'sb9-textual': _WireScenarioConfig(
    shortName: 'sb9',
    scenarioName: 'SB.9 Subprocess/Untrusted Output',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb9_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb9_subprocess_output',
    peerWireScript: 'sb9_subprocess_output_benchmark.py',
    defaultRows: 400,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 10,
    defaultIntervalMs: 35,
    defaultTimeoutSeconds: 20,
  ),
  'sb9-bubbletea': _WireScenarioConfig(
    shortName: 'sb9',
    scenarioName: 'SB.9 Subprocess/Untrusted Output',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb9_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb9_subprocess_output',
    defaultRows: 400,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 10,
    defaultIntervalMs: 35,
    defaultTimeoutSeconds: 15,
  ),
  'sb9-opentui': _WireScenarioConfig(
    shortName: 'sb9',
    scenarioName: 'SB.9 Subprocess/Untrusted Output',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb9_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb9_subprocess_output',
    peerWireScript: 'bin/sb9_subprocess_output_benchmark.js',
    defaultRows: 400,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 10,
    defaultIntervalMs: 35,
    defaultTimeoutSeconds: 20,
  ),
  'sb10-textual': _WireScenarioConfig(
    shortName: 'sb10',
    scenarioName: 'SB.10 Demo-App Journey',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb10_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb10_demo_app',
    peerWireScript: 'sb10_demo_app_benchmark.py',
    defaultRows: 1000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 10,
    defaultIntervalMs: 50,
    defaultTimeoutSeconds: 20,
  ),
  'sb10-bubbletea': _WireScenarioConfig(
    shortName: 'sb10',
    scenarioName: 'SB.10 Demo-App Journey',
    peerId: 'bubbletea',
    peerKind: 'go',
    fleurySource: 'bin/fleury_sb10_wire.dart',
    peerFixturePath: 'peer-fixtures/bubbletea/sb10_demo_app',
    defaultRows: 1000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 10,
    defaultIntervalMs: 50,
    defaultTimeoutSeconds: 15,
  ),
  'sb10-ink': _WireScenarioConfig(
    shortName: 'sb10',
    scenarioName: 'SB.10 Demo-App Journey',
    peerId: 'ink',
    peerKind: 'node',
    fleurySource: 'bin/fleury_sb10_wire.dart',
    peerFixturePath: 'peer-fixtures/ink/sb10_demo_app',
    peerWireScript: 'bin/sb10_demo_app_benchmark.js',
    defaultRows: 1000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 10,
    defaultIntervalMs: 50,
    defaultTimeoutSeconds: 20,
  ),
  'sb11-textual': _WireScenarioConfig(
    shortName: 'sb11',
    scenarioName: 'SB.11 TreeTable/Filter/Copy',
    peerId: 'textual',
    peerKind: 'python',
    fleurySource: 'bin/fleury_sb11_wire.dart',
    peerFixturePath: 'peer-fixtures/textual/sb11_treetable_filter_copy',
    peerWireScript: 'sb11_treetable_filter_copy_benchmark.py',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 6,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 20,
  ),
  'sb11-ratatui': _WireScenarioConfig(
    shortName: 'sb11',
    scenarioName: 'SB.11 TreeTable/Filter/Copy',
    peerId: 'ratatui',
    peerKind: 'rust',
    fleurySource: 'bin/fleury_sb11_wire.dart',
    peerFixturePath: 'peer-fixtures/ratatui/sb11_treetable_filter_copy',
    peerExecutable: 'ratatui_sb11_treetable_filter_copy',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 6,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 15,
  ),
  'sb11-opentui': _WireScenarioConfig(
    shortName: 'sb11',
    scenarioName: 'SB.11 TreeTable/Filter/Copy',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb11_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb11_treetable_filter_copy',
    peerWireScript: 'bin/sb11_treetable_filter_copy_benchmark.js',
    defaultRows: 100000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 6,
    defaultIntervalMs: 80,
    defaultTimeoutSeconds: 20,
  ),
  'sb12-nocterm': _WireScenarioConfig(
    shortName: 'sb12',
    scenarioName: 'SB.12 Layout Dirtiness Cache',
    peerId: 'nocterm',
    peerKind: 'dart',
    fleurySource: 'bin/fleury_sb12_wire.dart',
    peerFixturePath: 'peer-fixtures/nocterm/sb12_layout_dirtiness',
    peerWireScript: 'bin/sb12_layout_dirtiness_benchmark.dart',
    defaultRows: 2000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 15,
  ),
  'sb12-ratatui': _WireScenarioConfig(
    shortName: 'sb12',
    scenarioName: 'SB.12 Layout Dirtiness Cache',
    peerId: 'ratatui',
    peerKind: 'rust',
    fleurySource: 'bin/fleury_sb12_wire.dart',
    peerFixturePath: 'peer-fixtures/ratatui/sb12_layout_dirtiness',
    peerExecutable: 'ratatui_sb12_layout_dirtiness',
    defaultRows: 2000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 15,
  ),
  'sb12-opentui': _WireScenarioConfig(
    shortName: 'sb12',
    scenarioName: 'SB.12 Layout Dirtiness Cache',
    peerId: 'opentui',
    peerKind: 'bun',
    fleurySource: 'bin/fleury_sb12_wire.dart',
    peerFixturePath: 'peer-fixtures/opentui/sb12_layout_dirtiness',
    peerWireScript: 'bin/sb12_layout_dirtiness_benchmark.js',
    defaultRows: 2000,
    usesAppend: false,
    defaultAppend: 0,
    defaultSteps: 8,
    defaultIntervalMs: 60,
    defaultTimeoutSeconds: 20,
  ),
};

int _positiveCliInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value < 1) {
    stderr.writeln('$prefix requires a positive integer.');
    exit(2);
  }
  return value;
}

int _nonNegativeCliInt(String arg, String prefix) {
  final value = int.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative integer.');
    exit(2);
  }
  return value;
}

String _normalizeWirePeerId(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'bt' || 'bubble-tea' || 'bubble_tea' => 'bubbletea',
    'py' || 'python' => 'textual',
    'ot' || 'open-tui' || 'open_tui' => 'opentui',
    'rat' || 'rust' => 'ratatui',
    'react' || 'node' => 'ink',
    _ => normalized,
  };
}

List<String> _wireScenarioIdsFor(String selector, Set<String> peerFilters) {
  final exact = _wireScenarioConfigs[selector];
  if (exact != null) {
    if (peerFilters.isNotEmpty && !peerFilters.contains(exact.peerId)) {
      stderr.writeln(
        'Peer filter ${peerFilters.join(', ')} does not match explicit '
        'wire scenario $selector (${exact.peerId}).',
      );
      exit(2);
    }
    return <String>[selector];
  }

  final matches = [
    for (final entry in _wireScenarioConfigs.entries)
      if (entry.value.shortName == selector &&
          (peerFilters.isEmpty || peerFilters.contains(entry.value.peerId)))
        entry.key,
  ];
  if (matches.isNotEmpty) return matches;

  final knownPeers = [
    for (final entry in _wireScenarioConfigs.entries)
      if (entry.value.shortName == selector) entry.value.peerId,
  ];
  if (knownPeers.isNotEmpty) {
    stderr.writeln(
      'No wire peers matched ${peerFilters.join(', ')} for $selector. '
      'Known peers: ${knownPeers.join(', ')}',
    );
  } else {
    stderr.writeln('Unsupported wire benchmark: $selector');
  }
  _printBenchmarkWireUsage();
  exit(2);
}

List<MapEntry<String, _WireScenarioConfig>> _wireScenarioEntriesForSelector(
  String selector,
) {
  final exact = _wireScenarioConfigs[selector];
  if (exact != null) {
    return <MapEntry<String, _WireScenarioConfig>>[
      MapEntry<String, _WireScenarioConfig>(selector, exact),
    ];
  }

  final matches = [
    for (final entry in _wireScenarioConfigs.entries)
      if (entry.value.shortName == selector) entry,
  ];
  if (matches.isNotEmpty) return matches;

  stderr.writeln('Unsupported wire benchmark: $selector');
  _printBenchmarkWireUsage();
  exit(2);
}

Map<String, List<_WireScenarioConfig>> _wireScenarioGroups() {
  final groups = <String, List<_WireScenarioConfig>>{};
  for (final config in _wireScenarioConfigs.values) {
    (groups[config.shortName] ??= <_WireScenarioConfig>[]).add(config);
  }
  return groups;
}

Map<String, Object?> _benchmarkCatalog() {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryBenchmarkCatalog',
    'command': 'fleury benchmark',
    'scoreboard': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'scoreboard',
        '--input=profiling/caps',
        '--output=profiling/caps/scoreboard.md',
      ],
      'defaultInput': 'profiling/caps',
      'defaultOutput': 'stdout',
      'autoRefreshedByWireRuns': true,
    },
    'webReport': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-report',
        '--input=profiling/web/<capture>.json',
        '--output=profiling/web/<capture>.md',
      ],
      'frameBudgetMs': 16.67,
      'axes': [
        'total frame p95',
        'runtime render p95',
        'span build p95',
        'DOM apply p95',
        'semantic apply p95',
        'dirty rows',
        'DOM nodes created',
        'style cache hit rate',
        'width cache hit rate',
        'semantic coverage fallback cells',
      ],
    },
    'webCapture': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-capture',
        '--scenario=normal-80x24',
        '--output=profiling/web/runs/normal-80x24.json',
      ],
      'defaultOutput': 'profiling/web/runs/<scenario>-<timestamp>.json',
      'harness': 'retained DOM browser host via headless Chrome + CDP',
      'retention':
          'generated default captures are ignored; promote reviewed baselines under profiling/web/baselines/',
      'scenarios': [
        'normal-80x24',
        'large-160x50',
        'stress-300x100',
        'noop-160x50',
        'single-dirty-cell-160x50',
        'dirty-row-160x50',
        'full-frame-churn-160x50',
        'scroll-row-churn-160x50',
        'cursor-blink-80x24',
        'text-input-burst-80x24',
        'resize-burst',
      ],
    },
    'webSuite': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-suite',
        '--runs=3',
        '--output-dir=profiling/web/runs/<timestamp>-suite',
      ],
      'defaultOutput': 'profiling/web/runs/<timestamp>-suite',
      'scoreboard': 'profiling/web/runs/<timestamp>-suite/scoreboard.md',
      'scoreboardJson': 'profiling/web/runs/<timestamp>-suite/scoreboard.json',
      'harness':
          'repeated retained DOM browser captures plus strict scoreboard',
      'retention':
          'generated default runs are ignored; promote reviewed baselines under profiling/web/baselines/',
      'defaultRunsPerScenario': 3,
      'scenarios': [
        'normal-80x24',
        'large-160x50',
        'stress-300x100',
        'noop-160x50',
        'single-dirty-cell-160x50',
        'dirty-row-160x50',
        'full-frame-churn-160x50',
        'scroll-row-churn-160x50',
        'cursor-blink-80x24',
        'text-input-burst-80x24',
        'resize-burst',
      ],
    },
    'webScoreboard': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-scoreboard',
        '--input=profiling/web',
        '--output=profiling/web/scoreboard.md',
        '--json-output=profiling/web/scoreboard.json',
      ],
      'defaultInput': 'profiling/web',
      'defaultOutput': 'profiling/web/scoreboard.md',
      'jsonOutput': 'profiling/web/scoreboard.json',
      'autoRefreshedByWebCaptures': true,
      'axes': [
        'total frame p95',
        'runtime render p95',
        'span build p95',
        'DOM apply p95',
        'semantic apply p95',
        'over-budget percent',
        'semantic uncovered cells',
      ],
    },
    'webThresholdReview': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-threshold-review',
        '--input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json',
        '--output=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json',
        '--json-output=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json',
        '--expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN',
        '--reviewed-by=REVIEWER',
        '--review-context=Chrome VERSION on PLATFORM, retained DOM product baseline',
        '--allow-over-budget-thresholds',
        '--review-note=Explain any accepted over-budget thresholds.',
      ],
      'planCommand': [
        'fleury',
        'benchmark',
        'web-threshold-review',
        '--input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json',
        '--write-plan=profiling/web/baselines/2026-06-08-dom-retained/threshold-review-plan.md',
      ],
      'purpose':
          'promote candidate web frame thresholds to a reviewed readiness policy without recapturing browser frames',
      'requires': [
        'candidate fleuryWebFrameThresholds policy',
        'human reviewer provenance',
        'accepted product/browser/environment review context',
      ],
      'artifacts': ['thresholds.json', 'threshold-review.json'],
    },
    'webSemanticAudit': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-semantic-audit',
        '--input=profiling/web',
        '--json-output=profiling/web/semantic-coverage.json',
      ],
      'defaultInput': 'profiling/web',
      'defaultOutput': 'stdout',
      'purpose': 'quantify semantic fallback reliance in retained DOM captures',
      'axes': [
        'fallback frames',
        'fallback cells',
        'fallback cells as viewport percent',
        'max fallback cells per frame',
        'max fallback nodes per frame',
      ],
      'artifacts': ['semantic-coverage.json', 'semantic-coverage.md'],
    },
    'webManualValidation': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-manual-validation',
        '--input=profiling/web/manual',
        '--json-output=profiling/web/manual/manual-validation-audit.json',
      ],
      'defaultInput': 'profiling/web/manual',
      'defaultOutput': 'stdout',
      'purpose':
          'audit manual retained DOM web evidence; current release gate is Chrome/macOS IME',
      'targetPreset': 'primary',
      'targets': ['chrome-ime-macos'],
      'artifacts': ['manual-validation-audit.json', 'review.md'],
    },
    'webReadiness': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-readiness',
        '--scoreboard=profiling/web/baselines/web-frame-scoreboard.json',
        '--semantic-audit=profiling/web/baselines/web-semantic-coverage.json',
        '--manual-audit=profiling/web/manual/manual-validation-audit.json',
        '--threshold-review=profiling/web/baselines/threshold-review.json',
        '--strict',
      ],
      'defaultFrameScoreboard':
          'profiling/web/baselines/web-frame-scoreboard.json',
      'defaultSemanticAudit':
          'profiling/web/baselines/web-semantic-coverage.json',
      'defaultManualAudit': 'profiling/web/manual/manual-validation-audit.json',
      'defaultThresholdReview': 'profiling/web/baselines/threshold-review.json',
      'purpose':
          'combine reviewed frame, semantic, and manual evidence into the Phase 6 web readiness gate',
      'requires': [
        'frame scoreboard strictPass with total-frame threshold gates',
        'matching threshold-review promotion summary for reviewed thresholds',
        'comparable run-environment enforcement',
        'semantic fallback audit strictPass with threshold gates',
        'manual primary IME evidence strictPass',
      ],
    },
    'webReadinessBundle': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-readiness-bundle',
        '--captures=profiling/web/baselines/2026-06-08-dom-retained',
        '--manual=profiling/web/manual',
        '--output-dir=profiling/web/baselines/2026-06-08-dom-retained/readiness',
        '--thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json',
        '--threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json',
        '--max-total-frame-p95-ms=16.67',
        '--max-fallback-cells=0',
        '--write-default-preflights',
        '--strict',
      ],
      'purpose':
          'generate the JSON artifact manifest consumed by the Phase 6 web readiness and default preflight gates',
      'verifyCommand': [
        'fleury',
        'benchmark',
        'web-readiness-bundle',
        '--verify=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json',
        '--strict',
      ],
      'artifacts': [
        'web-readiness-bundle.json',
        'scoreboard.json',
        'semantic-coverage.json',
        'manual-validation-audit.json',
        'web-readiness.json',
        'web-readiness.md',
        'web-default-preflight-make-dom-default.json',
        'web-default-preflight-make-dom-default.md',
        'web-default-preflight-retire-temporary-paths.json',
        'web-default-preflight-retire-temporary-paths.md',
      ],
    },
    'webAutomatedValidation': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-automated-validation',
        '--json-output=profiling/web/baselines/web-readiness-bundle/web-automated-validation.json',
        '--strict',
      ],
      'defaultOutput':
          'profiling/web/baselines/web-readiness-bundle/web-automated-validation.json',
      'purpose':
          'run retained DOM automated host tests and write durable evidence consumed by bundle-bound default preflights',
      'requires': [
        'retained DOM browser host tests',
        'retained DOM VM host tests',
        'current webAutomatedTestFiles source fingerprints',
      ],
      'artifacts': ['web-automated-validation.json'],
    },
    'webDefaultPreflight': <String, Object?>{
      'command': [
        'fleury',
        'benchmark',
        'web-default-preflight',
        '--readiness=profiling/web/baselines/web-readiness-bundle/web-readiness.json',
        '--bundle=profiling/web/baselines/web-readiness-bundle/web-readiness-bundle.json',
        '--automated-validation=profiling/web/baselines/web-readiness-bundle/web-automated-validation.json',
        '--target=make-dom-default',
        '--strict',
      ],
      'defaultInput':
          'profiling/web/baselines/web-readiness-bundle/web-readiness.json',
      'purpose':
          'block retained DOM default flips and temporary-path retirement until Phase 6 readiness has strictly passed',
      'requires': [
        'strict web-readiness JSON',
        'verified web-readiness-bundle.json',
        'strict web-automated-validation.json',
      ],
      'targets': ['make-dom-default', 'retire-temporary-paths'],
    },
    'localScenarios': <Map<String, Object?>>[
      for (final target in _localBenchmarkTargets)
        <String, Object?>{
          'label': target.label,
          'packagePath': target.packagePath,
          'command': [
            'fleury',
            'benchmark',
            'local',
            '<scenario>',
            '--warmup=1',
            '--iterations=3',
            '--json',
          ],
          'scenarios': target.scenarios,
        },
    ],
    'wireScenarioGroups': <Map<String, Object?>>[
      for (final entry in _wireScenarioGroups().entries)
        <String, Object?>{
          'id': entry.key,
          'scenario': entry.value.first.scenarioName,
          'command': ['fleury', 'benchmark', 'wire', entry.key, '--runs=3'],
          'peers': [for (final config in entry.value) config.peerId],
        },
    ],
    'wireScenarios': <Map<String, Object?>>[
      for (final entry in _wireScenarioConfigs.entries)
        <String, Object?>{
          'id': entry.key,
          'scenario': entry.value.scenarioName,
          'uiMode': entry.value.uiMode,
          'peer': entry.value.peerId,
          'command': ['fleury', 'benchmark', 'wire', entry.key, '--runs=3'],
          'axes': [
            'bytes on wire',
            'bytes per frame',
            'frames emitted',
            'control overhead',
            'time to first byte',
            'RSS max',
            'CPU load',
            'sustained FPS',
          ],
        },
    ],
    'peerFixtures': <Map<String, Object?>>[
      <String, Object?>{
        'peer': 'nocterm',
        'scenarios': ['SB.1', 'SB.2', 'SB.3', 'SB.4', 'SB.12'],
        'wire': ['SB.12 full-ui'],
      },
      <String, Object?>{
        'peer': 'bubbletea',
        'scenarios': [
          'SB.1',
          'SB.2',
          'SB.4',
          'SB.5',
          'SB.6',
          'SB.8',
          'SB.9',
          'SB.10',
        ],
        'wire': [
          'SB.1 full-ui',
          'SB.2 full-ui',
          'SB.4 reduced full-ui',
          'SB.5 full-ui',
          'SB.6 full-ui',
          'SB.8 full-ui',
          'SB.9 full-ui',
          'SB.10 full-ui',
        ],
      },
      <String, Object?>{
        'peer': 'textual',
        'scenarios': [
          'SB.1',
          'SB.2',
          'SB.3',
          'SB.4',
          'SB.5',
          'SB.7',
          'SB.8',
          'SB.9',
          'SB.10',
          'SB.11',
        ],
        'wire': [
          'SB.1 full-ui',
          'SB.2 full-ui',
          'SB.3 full-ui',
          'SB.4 full-ui',
          'SB.5 full-ui',
          'SB.7 full-ui',
          'SB.8 full-ui',
          'SB.9 full-ui',
          'SB.10 full-ui',
          'SB.11 full-ui',
        ],
      },
      <String, Object?>{
        'peer': 'opentui',
        'scenarios': ['SB.3', 'SB.4', 'SB.6', 'SB.7', 'SB.9', 'SB.11', 'SB.12'],
        'wire': [
          'SB.3 full-ui',
          'SB.4 full-ui',
          'SB.6 full-ui',
          'SB.7 full-ui',
          'SB.9 full-ui',
          'SB.11 full-ui',
          'SB.12 full-ui',
        ],
      },
      <String, Object?>{
        'peer': 'ratatui',
        'scenarios': ['SB.3', 'SB.6', 'SB.7', 'SB.11', 'SB.12'],
        'wire': [
          'SB.3 full-ui',
          'SB.6 full-ui',
          'SB.7 full-ui',
          'SB.11 full-ui',
          'SB.12 full-ui',
        ],
      },
      <String, Object?>{
        'peer': 'ink',
        'scenarios': ['SB.1', 'SB.2', 'SB.5', 'SB.8', 'SB.10'],
        'wire': [
          'SB.1 full-ui',
          'SB.2 full-ui',
          'SB.5 full-ui',
          'SB.8 full-ui',
          'SB.10 full-ui',
        ],
      },
    ],
    'docs': <String>[
      'benchmarks/README.md',
      'docs/implementation/profiling-harness.md',
      'docs/implementation/comparative-benchmark-manifest.json',
    ],
  };
}

final class _BenchmarkManifestOptions {
  const _BenchmarkManifestOptions({
    required this.inputPath,
    required this.json,
    this.outputPath,
  });

  final String inputPath;
  final bool json;
  final String? outputPath;

  static _BenchmarkManifestOptions parse(String root, List<String> args) {
    var inputPath =
        '$root/docs/implementation/comparative-benchmark-manifest.json';
    String? outputPath;
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printBenchmarkManifestUsage();
        exit(0);
      } else if (arg == '--json') {
        json = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
      } else {
        stderr.writeln('Unknown option for benchmark-manifest: $arg');
        _printBenchmarkManifestUsage();
        exit(2);
      }
    }

    return _BenchmarkManifestOptions(
      inputPath: _absolutePath(root, inputPath),
      outputPath: outputPath == null ? null : _absolutePath(root, outputPath),
      json: json,
    );
  }
}

final class _BenchmarkResultOptions {
  const _BenchmarkResultOptions({
    required this.manifestPath,
    required this.inputPath,
    required this.json,
    this.outputPath,
  });

  final String manifestPath;
  final String inputPath;
  final bool json;
  final String? outputPath;

  static _BenchmarkResultOptions parse(String root, List<String> args) {
    var manifestPath =
        '$root/docs/implementation/comparative-benchmark-manifest.json';
    var inputPath = '';
    String? outputPath;
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printBenchmarkResultUsage();
        exit(0);
      } else if (arg == '--json') {
        json = true;
      } else if (arg.startsWith('--manifest=')) {
        manifestPath = arg.substring('--manifest='.length).trim();
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
      } else {
        stderr.writeln('Unknown option for benchmark-result: $arg');
        _printBenchmarkResultUsage();
        exit(2);
      }
    }

    if (inputPath.isEmpty) {
      stderr.writeln('benchmark-result requires --input=<path>');
      _printBenchmarkResultUsage();
      exit(2);
    }

    return _BenchmarkResultOptions(
      manifestPath: _absolutePath(root, manifestPath),
      inputPath: _absolutePath(root, inputPath),
      outputPath: outputPath == null ? null : _absolutePath(root, outputPath),
      json: json,
    );
  }
}

final class _BenchmarkVarianceOptions {
  const _BenchmarkVarianceOptions({
    required this.manifestPath,
    required this.inputPaths,
    required this.minRuns,
    required this.json,
    required this.strict,
    this.outputPath,
  });

  final String manifestPath;
  final List<String> inputPaths;
  final int minRuns;
  final bool json;
  final bool strict;
  final String? outputPath;

  static _BenchmarkVarianceOptions parse(String root, List<String> args) {
    var manifestPath =
        '$root/docs/implementation/comparative-benchmark-manifest.json';
    final inputPaths = <String>[];
    String? outputPath;
    var minRuns = 3;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printBenchmarkVarianceUsage();
        exit(0);
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg.startsWith('--manifest=')) {
        manifestPath = arg.substring('--manifest='.length).trim();
      } else if (arg.startsWith('--input=')) {
        final value = arg.substring('--input='.length).trim();
        if (value.isNotEmpty) inputPaths.add(_absolutePath(root, value));
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
      } else if (arg.startsWith('--min-runs=')) {
        final value = int.tryParse(arg.substring('--min-runs='.length));
        if (value == null || value < 1) {
          stderr.writeln('--min-runs must be a positive integer.');
          exit(2);
        }
        minRuns = value;
      } else {
        stderr.writeln('Unknown option for benchmark-variance: $arg');
        _printBenchmarkVarianceUsage();
        exit(2);
      }
    }

    if (inputPaths.isEmpty) {
      stderr.writeln('benchmark-variance requires at least one --input=<path>');
      _printBenchmarkVarianceUsage();
      exit(2);
    }

    return _BenchmarkVarianceOptions(
      manifestPath: _absolutePath(root, manifestPath),
      inputPaths: List<String>.unmodifiable(inputPaths),
      outputPath: outputPath == null ? null : _absolutePath(root, outputPath),
      minRuns: minRuns,
      json: json,
      strict: strict,
    );
  }
}

final class _BenchmarkWireOptions {
  const _BenchmarkWireOptions({
    required this.scenarioIds,
    required this.runs,
    required this.rowsOverride,
    required this.appendOverride,
    required this.stepsOverride,
    required this.intervalMsOverride,
    required this.timeoutSecondsOverride,
    required this.cols,
    required this.ptyRows,
    required this.outDir,
    required this.debugCapture,
    required this.runtimeMarkers,
  });

  final List<String> scenarioIds;
  final int runs;
  final int? rowsOverride;
  final int? appendOverride;
  final int? stepsOverride;
  final int? intervalMsOverride;
  final double? timeoutSecondsOverride;
  final int cols;
  final int ptyRows;
  final String outDir;
  final bool debugCapture;
  final bool runtimeMarkers;

  int rowsFor(_WireScenarioConfig config) => rowsOverride ?? config.defaultRows;
  int appendFor(_WireScenarioConfig config) =>
      appendOverride ?? config.defaultAppend;
  int stepsFor(_WireScenarioConfig config) =>
      stepsOverride ?? config.defaultSteps;
  int intervalMsFor(_WireScenarioConfig config) =>
      intervalMsOverride ?? config.defaultIntervalMs;
  double timeoutSecondsFor(_WireScenarioConfig config) =>
      timeoutSecondsOverride ?? config.defaultTimeoutSeconds;

  static _BenchmarkWireOptions parse(String root, List<String> args) {
    if (args.isEmpty) {
      stderr.writeln('benchmark wire requires a scenario.');
      _printBenchmarkWireUsage();
      exit(2);
    }
    if (args.first == '-h' || args.first == '--help' || args.first == 'help') {
      _printBenchmarkWireUsage();
      exit(0);
    }

    final selector = _normalizeWireScenario(args.first);
    final rest = args.sublist(1);
    if (rest.any((arg) => arg == '-h' || arg == '--help' || arg == 'help')) {
      _printBenchmarkWireScenarioUsage(selector);
      exit(0);
    }
    if (rest.contains('--list-peers')) {
      final allowed = {'--list-peers', '--json'};
      final unknown = [
        for (final arg in rest)
          if (!allowed.contains(arg)) arg,
      ];
      if (unknown.isNotEmpty) {
        stderr.writeln(
          '--list-peers only accepts --json; unknown option: ${unknown.first}',
        );
        exit(2);
      }
      _printBenchmarkWireScenarioPeers(selector, json: rest.contains('--json'));
      exit(0);
    }

    final peerFilters = <String>{};
    for (final arg in rest) {
      if (arg.startsWith('--peer=')) {
        final peer = arg.substring('--peer='.length).trim();
        if (peer.isNotEmpty) {
          final normalizedPeer = _normalizeWirePeerId(peer);
          if (normalizedPeer == 'all') {
            peerFilters.clear();
          } else {
            peerFilters.add(normalizedPeer);
          }
        }
      } else if (arg.startsWith('--peers=')) {
        final value = arg.substring('--peers='.length).trim();
        if (value.toLowerCase() == 'all') {
          peerFilters.clear();
        } else {
          for (final peer in value.split(',')) {
            final trimmed = peer.trim();
            if (trimmed.isNotEmpty) {
              peerFilters.add(_normalizeWirePeerId(trimmed));
            }
          }
        }
      }
    }
    final scenarioIds = _wireScenarioIdsFor(selector, peerFilters);
    var runs = 1;
    int? rowsOverride;
    int? appendOverride;
    int? stepsOverride;
    int? intervalMsOverride;
    double? timeoutSecondsOverride;
    var cols = 120;
    var ptyRows = 32;
    var outDir = '$root/profiling/caps';
    var debugCapture = false;
    var runtimeMarkers = false;

    for (final arg in rest) {
      if (arg.startsWith('--runs=')) {
        runs = _positiveCliInt(arg, '--runs=');
      } else if (arg.startsWith('--rows=')) {
        rowsOverride = _positiveCliInt(arg, '--rows=');
      } else if (arg.startsWith('--append=')) {
        appendOverride = _positiveCliInt(arg, '--append=');
      } else if (arg.startsWith('--steps=')) {
        stepsOverride = _positiveCliInt(arg, '--steps=');
      } else if (arg.startsWith('--interval-ms=')) {
        intervalMsOverride = _positiveCliInt(arg, '--interval-ms=');
      } else if (arg.startsWith('--timeout=')) {
        final value = double.tryParse(arg.substring('--timeout='.length));
        if (value == null || value <= 0) {
          stderr.writeln('--timeout must be a positive number of seconds.');
          exit(2);
        }
        timeoutSecondsOverride = value;
      } else if (arg.startsWith('--cols=')) {
        cols = _positiveCliInt(arg, '--cols=');
      } else if (arg.startsWith('--pty-rows=')) {
        ptyRows = _positiveCliInt(arg, '--pty-rows=');
      } else if (arg.startsWith('--out-dir=')) {
        outDir = arg.substring('--out-dir='.length).trim();
      } else if (arg == '--debug-capture') {
        debugCapture = true;
      } else if (arg == '--runtime-markers') {
        runtimeMarkers = true;
      } else if (arg.startsWith('--peer=') || arg.startsWith('--peers=')) {
        continue;
      } else {
        stderr.writeln('Unknown option for benchmark wire: $arg');
        _printBenchmarkWireUsage();
        exit(2);
      }
    }

    return _BenchmarkWireOptions(
      scenarioIds: List<String>.unmodifiable(scenarioIds),
      runs: runs,
      rowsOverride: rowsOverride,
      appendOverride: appendOverride,
      stepsOverride: stepsOverride,
      intervalMsOverride: intervalMsOverride,
      timeoutSecondsOverride: timeoutSecondsOverride,
      cols: cols,
      ptyRows: ptyRows,
      outDir: _absolutePath(root, outDir),
      debugCapture: debugCapture,
      runtimeMarkers: runtimeMarkers,
    );
  }
}

final class _BenchmarkScoreboardOptions {
  const _BenchmarkScoreboardOptions({
    required this.inputDir,
    required this.outputPath,
    required this.json,
  });

  final String inputDir;
  final String? outputPath;
  final bool json;

  static _BenchmarkScoreboardOptions parse(String root, List<String> args) {
    var inputDir = '$root/profiling/caps';
    String? outputPath;
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkScoreboardUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputDir = _absolutePath(root, arg.substring('--input='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg == '--json') {
        json = true;
      } else {
        stderr.writeln('Unknown option for benchmark scoreboard: $arg');
        _printBenchmarkScoreboardUsage();
        exit(2);
      }
    }

    return _BenchmarkScoreboardOptions(
      inputDir: inputDir,
      outputPath: outputPath,
      json: json,
    );
  }
}

final class _BenchmarkWebCaptureOptions {
  const _BenchmarkWebCaptureOptions({
    required this.scenarioId,
    required this.frames,
    required this.warmupFrames,
    required this.frameBudgetMs,
    required this.outputPath,
    required this.chromePath,
    required this.timeoutSeconds,
    required this.headful,
    required this.keepTemp,
    required this.compileOnly,
    required this.heapProfile,
    required this.traceFrames,
    required this.json,
  });

  final String scenarioId;
  final int? frames;
  final int warmupFrames;
  final double frameBudgetMs;
  final String outputPath;
  final String? chromePath;
  final int timeoutSeconds;
  final bool headful;
  final bool keepTemp;
  final bool compileOnly;
  final bool heapProfile;
  final bool traceFrames;
  final bool json;

  static _BenchmarkWebCaptureOptions parse(String root, List<String> args) {
    var scenarioId = 'normal-80x24';
    int? frames;
    var warmupFrames = 2;
    var frameBudgetMs = 16.67;
    String? outputPath;
    String? chromePath;
    var timeoutSeconds = 30;
    var headful = false;
    var keepTemp = false;
    var compileOnly = false;
    var heapProfile = false;
    var traceFrames = false;
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebCaptureUsage();
        exit(0);
      } else if (arg.startsWith('--scenario=')) {
        scenarioId = arg.substring('--scenario='.length).trim();
      } else if (arg.startsWith('--frames=')) {
        frames = _positiveCliInt(arg, '--frames=');
      } else if (arg.startsWith('--warmup=')) {
        warmupFrames = _nonNegativeCliInt(arg, '--warmup=');
      } else if (arg.startsWith('--budget-ms=')) {
        frameBudgetMs = _positiveCliDouble(arg, '--budget-ms=');
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--chrome=')) {
        chromePath = _absolutePath(root, arg.substring('--chrome='.length));
      } else if (arg.startsWith('--timeout=')) {
        timeoutSeconds = _positiveCliInt(arg, '--timeout=');
      } else if (arg == '--headful') {
        headful = true;
      } else if (arg == '--heap-profile') {
        heapProfile = true;
      } else if (arg == '--trace-frames') {
        traceFrames = true;
      } else if (arg == '--keep-temp') {
        keepTemp = true;
      } else if (arg == '--compile-only') {
        compileOnly = true;
      } else if (arg == '--json') {
        json = true;
      } else {
        stderr.writeln('Unknown option for benchmark web-capture: $arg');
        _printBenchmarkWebCaptureUsage();
        exit(2);
      }
    }

    outputPath ??=
        '$root/profiling/web/runs/$scenarioId-${_timestampForFile(DateTime.now().toUtc())}.json';

    return _BenchmarkWebCaptureOptions(
      scenarioId: scenarioId,
      frames: frames,
      warmupFrames: warmupFrames,
      frameBudgetMs: frameBudgetMs,
      outputPath: outputPath,
      chromePath: chromePath,
      timeoutSeconds: timeoutSeconds,
      headful: headful,
      heapProfile: heapProfile,
      traceFrames: traceFrames,
      keepTemp: keepTemp,
      compileOnly: compileOnly,
      json: json,
    );
  }
}

final class _BenchmarkWebSuiteOptions {
  const _BenchmarkWebSuiteOptions({
    required this.scenarioIds,
    required this.runs,
    required this.frames,
    required this.warmupFrames,
    required this.frameBudgetMs,
    required this.outputDir,
    required this.scoreboardPath,
    required this.scoreboardJsonPath,
    required this.minRuns,
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
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
    required this.json,
  });

  final List<String> scenarioIds;
  final int runs;
  final int? frames;
  final int warmupFrames;
  final double frameBudgetMs;
  final String outputDir;
  final String scoreboardPath;
  final String scoreboardJsonPath;
  final int minRuns;
  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;
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
  final bool json;

  static _BenchmarkWebSuiteOptions parse(String root, List<String> args) {
    List<String>? scenarioIds;
    var runs = 3;
    int? frames;
    var warmupFrames = 2;
    var frameBudgetMs = 16.67;
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
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebSuiteUsage();
        exit(0);
      } else if (arg.startsWith('--scenarios=')) {
        scenarioIds = _csvOption(arg.substring('--scenarios='.length));
      } else if (arg.startsWith('--runs=')) {
        runs = _positiveCliInt(arg, '--runs=');
      } else if (arg.startsWith('--frames=')) {
        frames = _positiveCliInt(arg, '--frames=');
      } else if (arg.startsWith('--warmup=')) {
        warmupFrames = _nonNegativeCliInt(arg, '--warmup=');
      } else if (arg.startsWith('--budget-ms=')) {
        frameBudgetMs = _positiveCliDouble(arg, '--budget-ms=');
      } else if (arg.startsWith('--output-dir=')) {
        outputDir = _absolutePath(root, arg.substring('--output-dir='.length));
      } else if (arg.startsWith('--scoreboard=')) {
        scoreboardPath = _absolutePath(
          root,
          arg.substring('--scoreboard='.length),
        );
      } else if (arg.startsWith('--scoreboard-json=')) {
        final rawPath = arg.substring('--scoreboard-json='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--scoreboard-json requires a non-empty path.');
          _printBenchmarkWebSuiteUsage();
          exit(2);
        }
        scoreboardJsonPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--min-runs=')) {
        minRuns = _positiveCliInt(arg, '--min-runs=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveCliDouble(
          arg,
          '--max-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveCliDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveCliDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeCliDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeCliDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--thresholds=')) {
        thresholdsPath = _absolutePath(
          root,
          arg.substring('--thresholds='.length),
        );
      } else if (arg.startsWith('--write-thresholds=')) {
        writeThresholdsPath = _absolutePath(
          root,
          arg.substring('--write-thresholds='.length),
        );
      } else if (arg.startsWith('--threshold-headroom-percent=')) {
        thresholdHeadroomPercent = _nonNegativeCliDouble(
          arg,
          '--threshold-headroom-percent=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-ms=')) {
        thresholdMinHeadroomMs = _nonNegativeCliDouble(
          arg,
          '--threshold-min-headroom-ms=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-percent=')) {
        thresholdMinHeadroomPercent = _nonNegativeCliDouble(
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
        chromePath = _absolutePath(root, arg.substring('--chrome='.length));
      } else if (arg.startsWith('--timeout=')) {
        timeoutSeconds = _positiveCliInt(arg, '--timeout=');
      } else if (arg == '--headful') {
        headful = true;
      } else if (arg == '--keep-temp') {
        keepTemp = true;
      } else if (arg == '--json') {
        json = true;
      } else {
        stderr.writeln('Unknown option for benchmark web-suite: $arg');
        _printBenchmarkWebSuiteUsage();
        exit(2);
      }
    }

    outputDir ??=
        '$root/profiling/web/runs/${_timestampForFile(DateTime.now().toUtc())}-suite';
    scoreboardPath ??= '$outputDir/scoreboard.md';
    scoreboardJsonPath ??= '$outputDir/scoreboard.json';
    minRuns ??= runs;

    return _BenchmarkWebSuiteOptions(
      scenarioIds: List.unmodifiable(
        scenarioIds ?? _defaultWebBenchmarkScenarioIds,
      ),
      runs: runs,
      frames: frames,
      warmupFrames: warmupFrames,
      frameBudgetMs: frameBudgetMs,
      outputDir: outputDir,
      scoreboardPath: scoreboardPath,
      scoreboardJsonPath: scoreboardJsonPath,
      minRuns: minRuns,
      maxTotalFrameP95Ms: maxTotalFrameP95Ms,
      maxDomApplyP95Ms: maxDomApplyP95Ms,
      maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
      maxOverBudgetPercent: maxOverBudgetPercent,
      maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      thresholdsPath: thresholdsPath,
      writeThresholdsPath: writeThresholdsPath,
      thresholdHeadroomPercent: thresholdHeadroomPercent,
      thresholdMinHeadroomMs: thresholdMinHeadroomMs,
      thresholdMinHeadroomPercent: thresholdMinHeadroomPercent,
      strictScoreboard: strictScoreboard,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
      compileOnce: compileOnce,
      chromePath: chromePath,
      timeoutSeconds: timeoutSeconds,
      headful: headful,
      keepTemp: keepTemp,
      json: json,
    );
  }
}

final class _BenchmarkWebScoreboardOptions {
  const _BenchmarkWebScoreboardOptions({
    required this.inputDir,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.minRuns,
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
    required this.thresholdsPath,
    required this.writeThresholdsPath,
    required this.thresholdHeadroomPercent,
    required this.thresholdMinHeadroomMs,
    required this.thresholdMinHeadroomPercent,
    required this.requireComparableRunEnvironment,
    required this.json,
    required this.strict,
  });

  final String inputDir;
  final String? outputPath;
  final String? jsonOutputPath;
  final int minRuns;
  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;
  final String? thresholdsPath;
  final String? writeThresholdsPath;
  final double thresholdHeadroomPercent;
  final double thresholdMinHeadroomMs;
  final double thresholdMinHeadroomPercent;
  final bool requireComparableRunEnvironment;
  final bool json;
  final bool strict;

  static _BenchmarkWebScoreboardOptions parse(String root, List<String> args) {
    var inputDir = '$root/profiling/web';
    String? outputPath;
    String? jsonOutputPath;
    var minRuns = 1;
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
    var requireComparableRunEnvironment = false;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebScoreboardUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputDir = _absolutePath(root, arg.substring('--input='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--json-output=')) {
        final rawPath = arg.substring('--json-output='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printBenchmarkWebScoreboardUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--min-runs=')) {
        minRuns = _positiveCliInt(arg, '--min-runs=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveCliDouble(
          arg,
          '--max-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveCliDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveCliDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeCliDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeCliDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--thresholds=')) {
        thresholdsPath = _absolutePath(
          root,
          arg.substring('--thresholds='.length),
        );
      } else if (arg.startsWith('--write-thresholds=')) {
        writeThresholdsPath = _absolutePath(
          root,
          arg.substring('--write-thresholds='.length),
        );
      } else if (arg.startsWith('--threshold-headroom-percent=')) {
        thresholdHeadroomPercent = _nonNegativeCliDouble(
          arg,
          '--threshold-headroom-percent=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-ms=')) {
        thresholdMinHeadroomMs = _nonNegativeCliDouble(
          arg,
          '--threshold-min-headroom-ms=',
        );
      } else if (arg.startsWith('--threshold-min-headroom-percent=')) {
        thresholdMinHeadroomPercent = _nonNegativeCliDouble(
          arg,
          '--threshold-min-headroom-percent=',
        );
      } else if (arg == '--require-comparable-environment') {
        requireComparableRunEnvironment = true;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for benchmark web-scoreboard: $arg');
        _printBenchmarkWebScoreboardUsage();
        exit(2);
      }
    }

    return _BenchmarkWebScoreboardOptions(
      inputDir: inputDir,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      minRuns: minRuns,
      maxTotalFrameP95Ms: maxTotalFrameP95Ms,
      maxDomApplyP95Ms: maxDomApplyP95Ms,
      maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
      maxOverBudgetPercent: maxOverBudgetPercent,
      maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      thresholdsPath: thresholdsPath,
      writeThresholdsPath: writeThresholdsPath,
      thresholdHeadroomPercent: thresholdHeadroomPercent,
      thresholdMinHeadroomMs: thresholdMinHeadroomMs,
      thresholdMinHeadroomPercent: thresholdMinHeadroomPercent,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
      json: json,
      strict: strict,
    );
  }
}

final class _BenchmarkWebThresholdReviewOptions {
  const _BenchmarkWebThresholdReviewOptions({
    required this.inputPath,
    required this.outputPath,
    required this.writePlanPath,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewContext,
    required this.reviewContextHint,
    required this.reviewNote,
    required this.expectedInputFingerprint,
    required this.allowOverBudgetThresholds,
    required this.jsonOutputPath,
    required this.json,
  });

  final String inputPath;
  final String? outputPath;
  final String? writePlanPath;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? reviewContext;
  final String? reviewContextHint;
  final String? reviewNote;
  final String? expectedInputFingerprint;
  final bool allowOverBudgetThresholds;
  final String? jsonOutputPath;
  final bool json;

  static _BenchmarkWebThresholdReviewOptions parse(
    String root,
    List<String> args,
  ) {
    String? inputPath;
    String? outputPath;
    String? writePlanPath;
    String? reviewedBy;
    String? reviewedAt;
    String? reviewContext;
    String? reviewContextHint;
    String? reviewNote;
    String? expectedInputFingerprint;
    var allowOverBudgetThresholds = false;
    String? jsonOutputPath;
    var json = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebThresholdReviewUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputPath = _absolutePath(root, arg.substring('--input='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--write-plan=')) {
        final raw = arg.substring('--write-plan='.length).trim();
        if (raw.isEmpty) {
          stderr.writeln(
            'benchmark web-threshold-review --write-plan requires a non-empty path.',
          );
          _printBenchmarkWebThresholdReviewUsage();
          exit(2);
        }
        writePlanPath = _absolutePath(root, raw);
      } else if (arg.startsWith('--reviewed-by=')) {
        reviewedBy = arg.substring('--reviewed-by='.length).trim();
      } else if (arg.startsWith('--reviewed-at=')) {
        reviewedAt = arg.substring('--reviewed-at='.length).trim();
      } else if (arg.startsWith('--review-context=')) {
        reviewContext = arg.substring('--review-context='.length).trim();
      } else if (arg.startsWith('--review-context-hint=')) {
        reviewContextHint = arg
            .substring('--review-context-hint='.length)
            .trim();
      } else if (arg.startsWith('--review-note=')) {
        reviewNote = arg.substring('--review-note='.length).trim();
      } else if (arg.startsWith('--expect-input-fingerprint=')) {
        expectedInputFingerprint = arg
            .substring('--expect-input-fingerprint='.length)
            .trim();
        if (expectedInputFingerprint.isEmpty) {
          stderr.writeln(
            'benchmark web-threshold-review --expect-input-fingerprint requires a non-empty value.',
          );
          _printBenchmarkWebThresholdReviewUsage();
          exit(2);
        }
      } else if (arg == '--allow-over-budget-thresholds') {
        allowOverBudgetThresholds = true;
      } else if (arg.startsWith('--json-output=')) {
        final raw = arg.substring('--json-output='.length).trim();
        if (raw.isEmpty) {
          stderr.writeln(
            'benchmark web-threshold-review --json-output requires a non-empty path.',
          );
          _printBenchmarkWebThresholdReviewUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, raw);
      } else if (arg == '--json') {
        json = true;
      } else {
        stderr.writeln(
          'Unknown option for benchmark web-threshold-review: $arg',
        );
        _printBenchmarkWebThresholdReviewUsage();
        exit(2);
      }
    }

    if (inputPath == null || inputPath.isEmpty) {
      stderr.writeln('benchmark web-threshold-review requires --input=PATH');
      _printBenchmarkWebThresholdReviewUsage();
      exit(2);
    }
    final promote =
        writePlanPath == null ||
        outputPath != null ||
        reviewedBy != null ||
        reviewedAt != null ||
        reviewContext != null ||
        reviewNote != null ||
        json;
    if (promote && (outputPath == null || outputPath.isEmpty)) {
      stderr.writeln('benchmark web-threshold-review requires --output=PATH');
      _printBenchmarkWebThresholdReviewUsage();
      exit(2);
    }
    if (promote && (reviewedBy == null || reviewedBy.isEmpty)) {
      stderr.writeln(
        'benchmark web-threshold-review requires --reviewed-by=NAME',
      );
      _printBenchmarkWebThresholdReviewUsage();
      exit(2);
    }
    if (promote && (reviewContext == null || reviewContext.isEmpty)) {
      stderr.writeln(
        'benchmark web-threshold-review requires --review-context=TEXT',
      );
      _printBenchmarkWebThresholdReviewUsage();
      exit(2);
    }

    return _BenchmarkWebThresholdReviewOptions(
      inputPath: inputPath,
      outputPath: outputPath,
      writePlanPath: writePlanPath,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt == null || reviewedAt.isEmpty ? null : reviewedAt,
      reviewContext: reviewContext,
      reviewContextHint: reviewContextHint == null || reviewContextHint.isEmpty
          ? null
          : reviewContextHint,
      reviewNote: reviewNote == null || reviewNote.isEmpty ? null : reviewNote,
      expectedInputFingerprint:
          expectedInputFingerprint == null || expectedInputFingerprint.isEmpty
          ? null
          : expectedInputFingerprint,
      allowOverBudgetThresholds: allowOverBudgetThresholds,
      jsonOutputPath: jsonOutputPath,
      json: json,
    );
  }
}

final class _BenchmarkWebSemanticAuditOptions {
  const _BenchmarkWebSemanticAuditOptions({
    required this.inputDir,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.maxFallbackCells,
    required this.maxFallbackFramePercent,
    required this.maxFallbackViewportPercent,
    required this.json,
    required this.strict,
  });

  final String inputDir;
  final String? outputPath;
  final String? jsonOutputPath;
  final int? maxFallbackCells;
  final double? maxFallbackFramePercent;
  final double? maxFallbackViewportPercent;
  final bool json;
  final bool strict;

  static _BenchmarkWebSemanticAuditOptions parse(
    String root,
    List<String> args,
  ) {
    var inputDir = '$root/profiling/web';
    String? outputPath;
    String? jsonOutputPath;
    int? maxFallbackCells;
    double? maxFallbackFramePercent;
    double? maxFallbackViewportPercent;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebSemanticAuditUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputDir = _absolutePath(root, arg.substring('--input='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--json-output=')) {
        final rawPath = arg.substring('--json-output='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printBenchmarkWebSemanticAuditUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--max-fallback-cells=')) {
        maxFallbackCells = _nonNegativeCliInt(arg, '--max-fallback-cells=');
      } else if (arg.startsWith('--max-fallback-frame-percent=')) {
        maxFallbackFramePercent = _nonNegativeCliDouble(
          arg,
          '--max-fallback-frame-percent=',
        );
      } else if (arg.startsWith('--max-fallback-viewport-percent=')) {
        maxFallbackViewportPercent = _nonNegativeCliDouble(
          arg,
          '--max-fallback-viewport-percent=',
        );
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for benchmark web-semantic-audit: $arg');
        _printBenchmarkWebSemanticAuditUsage();
        exit(2);
      }
    }

    return _BenchmarkWebSemanticAuditOptions(
      inputDir: inputDir,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      maxFallbackCells: maxFallbackCells,
      maxFallbackFramePercent: maxFallbackFramePercent,
      maxFallbackViewportPercent: maxFallbackViewportPercent,
      json: json,
      strict: strict,
    );
  }
}

final class _BenchmarkWebManualValidationOptions {
  const _BenchmarkWebManualValidationOptions({
    required this.inputDir,
    required this.outputPath,
    required this.writePlanPath,
    required this.writeTemplatePath,
    required this.writeStarterPath,
    required this.starterTemplatePath,
    required this.updateProvenancePath,
    required this.updatePageSignalPath,
    required this.updateCheckPath,
    required this.reviewedBy,
    required this.capturedAt,
    required this.browserVersion,
    required this.signalId,
    required this.signalStatus,
    required this.observedValue,
    required this.signalNotes,
    required this.checkId,
    required this.checkStatus,
    required this.checkNotes,
    required this.entryStatus,
    required this.writeTemplatesDir,
    required this.templateTargetId,
    required this.jsonOutputPath,
    required this.targetPreset,
    required this.targetIds,
    required this.json,
    required this.strict,
  });

  final String inputDir;
  final String? outputPath;
  final String? writePlanPath;
  final String? writeTemplatePath;
  final String? writeStarterPath;
  final String? starterTemplatePath;
  final String? updateProvenancePath;
  final String? updatePageSignalPath;
  final String? updateCheckPath;
  final String? reviewedBy;
  final String? capturedAt;
  final String? browserVersion;
  final String? signalId;
  final String? signalStatus;
  final String? observedValue;
  final String? signalNotes;
  final String? checkId;
  final String? checkStatus;
  final String? checkNotes;
  final String? entryStatus;
  final String? writeTemplatesDir;
  final String? templateTargetId;
  final String? jsonOutputPath;
  final String targetPreset;
  final List<String> targetIds;
  final bool json;
  final bool strict;

  static _BenchmarkWebManualValidationOptions parse(
    String root,
    List<String> args,
  ) {
    var inputDir = '$root/profiling/web/manual';
    String? outputPath;
    String? writePlanPath;
    String? writeTemplatePath;
    String? writeStarterPath;
    String? starterTemplatePath;
    String? updateProvenancePath;
    String? updatePageSignalPath;
    String? updateCheckPath;
    String? reviewedBy;
    String? capturedAt;
    String? browserVersion;
    String? signalId;
    String? signalStatus;
    String? observedValue;
    String? signalNotes;
    String? checkId;
    String? checkStatus;
    String? checkNotes;
    String? entryStatus;
    String? writeTemplatesDir;
    String? templateTargetId;
    String? jsonOutputPath;
    var targetPreset = 'primary';
    final targetIds = <String>[];
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebManualValidationUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputDir = _absolutePath(root, arg.substring('--input='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--write-plan=')) {
        writePlanPath = _absolutePath(
          root,
          arg.substring('--write-plan='.length),
        );
      } else if (arg.startsWith('--write-template=')) {
        writeTemplatePath = _absolutePath(
          root,
          arg.substring('--write-template='.length),
        );
      } else if (arg.startsWith('--write-starter=')) {
        final rawPath = arg.substring('--write-starter='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--write-starter requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        writeStarterPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--starter-template=')) {
        final rawPath = arg.substring('--starter-template='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--starter-template requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        starterTemplatePath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--update-provenance=')) {
        final rawPath = arg.substring('--update-provenance='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--update-provenance requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        updateProvenancePath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--update-page-signal=')) {
        final rawPath = arg.substring('--update-page-signal='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--update-page-signal requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        updatePageSignalPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--update-check=')) {
        final rawPath = arg.substring('--update-check='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--update-check requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        updateCheckPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--reviewed-by=')) {
        reviewedBy = arg.substring('--reviewed-by='.length);
      } else if (arg.startsWith('--captured-at=')) {
        capturedAt = arg.substring('--captured-at='.length);
      } else if (arg.startsWith('--browser-version=')) {
        browserVersion = arg.substring('--browser-version='.length);
      } else if (arg.startsWith('--signal-id=')) {
        signalId = arg.substring('--signal-id='.length);
      } else if (arg.startsWith('--signal-status=')) {
        signalStatus = arg.substring('--signal-status='.length);
      } else if (arg.startsWith('--observed-value=')) {
        observedValue = arg.substring('--observed-value='.length);
      } else if (arg.startsWith('--signal-notes=')) {
        signalNotes = arg.substring('--signal-notes='.length);
      } else if (arg.startsWith('--check-id=')) {
        checkId = arg.substring('--check-id='.length);
      } else if (arg.startsWith('--check-status=')) {
        checkStatus = arg.substring('--check-status='.length);
      } else if (arg.startsWith('--check-notes=')) {
        checkNotes = arg.substring('--check-notes='.length);
      } else if (arg.startsWith('--entry-status=')) {
        entryStatus = arg.substring('--entry-status='.length);
      } else if (arg.startsWith('--write-templates=')) {
        final rawPath = arg.substring('--write-templates='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--write-templates requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        writeTemplatesDir = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--template-target=')) {
        templateTargetId = arg.substring('--template-target='.length);
      } else if (arg.startsWith('--json-output=')) {
        final rawPath = arg.substring('--json-output='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printBenchmarkWebManualValidationUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--target-preset=')) {
        targetPreset = arg.substring('--target-preset='.length);
      } else if (arg.startsWith('--target=')) {
        targetIds.add(arg.substring('--target='.length));
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln(
          'Unknown option for benchmark web-manual-validation: $arg',
        );
        _printBenchmarkWebManualValidationUsage();
        exit(2);
      }
    }

    return _BenchmarkWebManualValidationOptions(
      inputDir: inputDir,
      outputPath: outputPath,
      writePlanPath: writePlanPath,
      writeTemplatePath: writeTemplatePath,
      writeStarterPath: writeStarterPath,
      starterTemplatePath: starterTemplatePath,
      updateProvenancePath: updateProvenancePath,
      updatePageSignalPath: updatePageSignalPath,
      updateCheckPath: updateCheckPath,
      reviewedBy: reviewedBy,
      capturedAt: capturedAt,
      browserVersion: browserVersion,
      signalId: signalId,
      signalStatus: signalStatus,
      observedValue: observedValue,
      signalNotes: signalNotes,
      checkId: checkId,
      checkStatus: checkStatus,
      checkNotes: checkNotes,
      entryStatus: entryStatus,
      writeTemplatesDir: writeTemplatesDir,
      templateTargetId: templateTargetId,
      jsonOutputPath: jsonOutputPath,
      targetPreset: targetPreset,
      targetIds: List.unmodifiable(targetIds),
      json: json,
      strict: strict,
    );
  }
}

final class _BenchmarkWebReadinessOptions {
  const _BenchmarkWebReadinessOptions({
    required this.scoreboardPath,
    required this.semanticAuditPath,
    required this.manualAuditPath,
    required this.thresholdReviewPath,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.minScoreboardRuns,
    required this.requireComparableEnvironment,
    required this.requireScoreboardGates,
    required this.requireTotalFrameGate,
    required this.requireSemanticGates,
    required this.requireReviewedThresholdPolicy,
    required this.requireThresholdReviewSummary,
    required this.requireScenarioThresholds,
    required this.json,
    required this.strict,
  });

  final String scoreboardPath;
  final String semanticAuditPath;
  final String manualAuditPath;
  final String? thresholdReviewPath;
  final String? outputPath;
  final String? jsonOutputPath;
  final int minScoreboardRuns;
  final bool requireComparableEnvironment;
  final bool requireScoreboardGates;
  final bool requireTotalFrameGate;
  final bool requireSemanticGates;
  final bool requireReviewedThresholdPolicy;
  final bool requireThresholdReviewSummary;
  final bool requireScenarioThresholds;
  final bool json;
  final bool strict;

  static _BenchmarkWebReadinessOptions parse(String root, List<String> args) {
    var scoreboardPath =
        '$root/profiling/web/baselines/web-frame-scoreboard.json';
    var semanticAuditPath =
        '$root/profiling/web/baselines/web-semantic-coverage.json';
    var manualAuditPath =
        '$root/profiling/web/manual/manual-validation-audit.json';
    String? thresholdReviewPath;
    String? outputPath;
    String? jsonOutputPath;
    var minScoreboardRuns = 3;
    var requireComparableEnvironment = true;
    var requireScoreboardGates = true;
    var requireTotalFrameGate = true;
    var requireSemanticGates = true;
    var requireReviewedThresholdPolicy = true;
    var requireThresholdReviewSummary = true;
    var requireScenarioThresholds = true;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebReadinessUsage();
        exit(0);
      } else if (arg.startsWith('--scoreboard=')) {
        scoreboardPath = _absolutePath(
          root,
          arg.substring('--scoreboard='.length),
        );
      } else if (arg.startsWith('--semantic-audit=')) {
        semanticAuditPath = _absolutePath(
          root,
          arg.substring('--semantic-audit='.length),
        );
      } else if (arg.startsWith('--manual-audit=')) {
        manualAuditPath = _absolutePath(
          root,
          arg.substring('--manual-audit='.length),
        );
      } else if (arg.startsWith('--threshold-review=')) {
        final rawPath = arg.substring('--threshold-review='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--threshold-review requires a non-empty path.');
          _printBenchmarkWebReadinessUsage();
          exit(2);
        }
        thresholdReviewPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--json-output=')) {
        final rawPath = arg.substring('--json-output='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printBenchmarkWebReadinessUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--min-scoreboard-runs=')) {
        minScoreboardRuns = _positiveCliInt(arg, '--min-scoreboard-runs=');
      } else if (arg == '--no-require-comparable-environment') {
        requireComparableEnvironment = false;
      } else if (arg == '--no-require-scoreboard-gates') {
        requireScoreboardGates = false;
      } else if (arg == '--no-require-total-frame-gate') {
        requireTotalFrameGate = false;
      } else if (arg == '--no-require-semantic-gates') {
        requireSemanticGates = false;
      } else if (arg == '--no-require-reviewed-threshold-policy') {
        requireReviewedThresholdPolicy = false;
      } else if (arg == '--no-require-threshold-review-summary') {
        requireThresholdReviewSummary = false;
      } else if (arg == '--no-require-scenario-thresholds') {
        requireScenarioThresholds = false;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for benchmark web-readiness: $arg');
        _printBenchmarkWebReadinessUsage();
        exit(2);
      }
    }

    return _BenchmarkWebReadinessOptions(
      scoreboardPath: scoreboardPath,
      semanticAuditPath: semanticAuditPath,
      manualAuditPath: manualAuditPath,
      thresholdReviewPath: thresholdReviewPath,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      minScoreboardRuns: minScoreboardRuns,
      requireComparableEnvironment: requireComparableEnvironment,
      requireScoreboardGates: requireScoreboardGates,
      requireTotalFrameGate: requireTotalFrameGate,
      requireSemanticGates: requireSemanticGates,
      requireReviewedThresholdPolicy: requireReviewedThresholdPolicy,
      requireThresholdReviewSummary: requireThresholdReviewSummary,
      requireScenarioThresholds: requireScenarioThresholds,
      json: json,
      strict: strict,
    );
  }
}

final class _BenchmarkWebReadinessBundleOptions {
  const _BenchmarkWebReadinessBundleOptions({
    required this.verifyPath,
    required this.captureDir,
    required this.manualDir,
    required this.outputDir,
    required this.minRuns,
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
    required this.thresholdsPath,
    required this.thresholdReviewPath,
    required this.requireComparableRunEnvironment,
    required this.maxFallbackCells,
    required this.maxFallbackFramePercent,
    required this.maxFallbackViewportPercent,
    required this.targetPreset,
    required this.targetIds,
    required this.requireScoreboardGates,
    required this.requireTotalFrameGate,
    required this.requireSemanticGates,
    required this.requireReviewedThresholdPolicy,
    required this.requireThresholdReviewSummary,
    required this.requireScenarioThresholds,
    required this.writeDefaultPreflights,
    required this.completionAuditPath,
    required this.json,
    required this.strict,
  });

  final String? verifyPath;
  final String captureDir;
  final String manualDir;
  final String outputDir;
  final int minRuns;
  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;
  final String? thresholdsPath;
  final String? thresholdReviewPath;
  final bool requireComparableRunEnvironment;
  final int? maxFallbackCells;
  final double? maxFallbackFramePercent;
  final double? maxFallbackViewportPercent;
  final String targetPreset;
  final List<String> targetIds;
  final bool requireScoreboardGates;
  final bool requireTotalFrameGate;
  final bool requireSemanticGates;
  final bool requireReviewedThresholdPolicy;
  final bool requireThresholdReviewSummary;
  final bool requireScenarioThresholds;
  final bool writeDefaultPreflights;
  final String? completionAuditPath;
  final bool json;
  final bool strict;

  static _BenchmarkWebReadinessBundleOptions parse(
    String root,
    List<String> args,
  ) {
    String? verifyPath;
    var captureDir = '$root/profiling/web/baselines';
    var manualDir = '$root/profiling/web/manual';
    var outputDir = '$root/profiling/web/baselines/web-readiness-bundle';
    var minRuns = 3;
    double? maxTotalFrameP95Ms;
    double? maxDomApplyP95Ms;
    double? maxSemanticApplyP95Ms;
    double? maxOverBudgetPercent;
    double? maxSemanticUncoveredCells;
    String? thresholdsPath;
    String? thresholdReviewPath;
    var requireComparableRunEnvironment = true;
    int? maxFallbackCells;
    double? maxFallbackFramePercent;
    double? maxFallbackViewportPercent;
    var targetPreset = 'primary';
    final targetIds = <String>[];
    var requireScoreboardGates = true;
    var requireTotalFrameGate = true;
    var requireSemanticGates = true;
    var requireReviewedThresholdPolicy = true;
    var requireThresholdReviewSummary = true;
    var requireScenarioThresholds = true;
    var writeDefaultPreflights = false;
    String? completionAuditPath;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebReadinessBundleUsage();
        exit(0);
      } else if (arg.startsWith('--verify=')) {
        final rawPath = arg.substring('--verify='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--verify requires a non-empty path.');
          _printBenchmarkWebReadinessBundleUsage();
          exit(2);
        }
        verifyPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--captures=')) {
        captureDir = _absolutePath(root, arg.substring('--captures='.length));
      } else if (arg.startsWith('--manual=')) {
        manualDir = _absolutePath(root, arg.substring('--manual='.length));
      } else if (arg.startsWith('--output-dir=')) {
        outputDir = _absolutePath(root, arg.substring('--output-dir='.length));
      } else if (arg.startsWith('--min-runs=')) {
        minRuns = _positiveCliInt(arg, '--min-runs=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveCliDouble(
          arg,
          '--max-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveCliDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveCliDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeCliDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeCliDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg.startsWith('--thresholds=')) {
        thresholdsPath = _absolutePath(
          root,
          arg.substring('--thresholds='.length),
        );
      } else if (arg.startsWith('--threshold-review=')) {
        final rawPath = arg.substring('--threshold-review='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--threshold-review requires a non-empty path.');
          _printBenchmarkWebReadinessBundleUsage();
          exit(2);
        }
        thresholdReviewPath = _absolutePath(root, rawPath);
      } else if (arg == '--no-require-comparable-environment') {
        requireComparableRunEnvironment = false;
      } else if (arg.startsWith('--max-fallback-cells=')) {
        maxFallbackCells = _nonNegativeCliInt(arg, '--max-fallback-cells=');
      } else if (arg.startsWith('--max-fallback-frame-percent=')) {
        maxFallbackFramePercent = _nonNegativeCliDouble(
          arg,
          '--max-fallback-frame-percent=',
        );
      } else if (arg.startsWith('--max-fallback-viewport-percent=')) {
        maxFallbackViewportPercent = _nonNegativeCliDouble(
          arg,
          '--max-fallback-viewport-percent=',
        );
      } else if (arg.startsWith('--target-preset=')) {
        targetPreset = arg.substring('--target-preset='.length);
      } else if (arg.startsWith('--target=')) {
        targetIds.add(arg.substring('--target='.length));
      } else if (arg == '--no-require-scoreboard-gates') {
        requireScoreboardGates = false;
      } else if (arg == '--no-require-total-frame-gate') {
        requireTotalFrameGate = false;
      } else if (arg == '--no-require-semantic-gates') {
        requireSemanticGates = false;
      } else if (arg == '--no-require-reviewed-threshold-policy') {
        requireReviewedThresholdPolicy = false;
      } else if (arg == '--no-require-threshold-review-summary') {
        requireThresholdReviewSummary = false;
      } else if (arg == '--no-require-scenario-thresholds') {
        requireScenarioThresholds = false;
      } else if (arg == '--write-default-preflights') {
        writeDefaultPreflights = true;
      } else if (arg.startsWith('--completion-audit=')) {
        final rawPath = arg.substring('--completion-audit='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--completion-audit requires a non-empty path.');
          _printBenchmarkWebReadinessBundleUsage();
          exit(2);
        }
        completionAuditPath = _absolutePath(root, rawPath);
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln(
          'Unknown option for benchmark web-readiness-bundle: $arg',
        );
        _printBenchmarkWebReadinessBundleUsage();
        exit(2);
      }
    }

    return _BenchmarkWebReadinessBundleOptions(
      verifyPath: verifyPath,
      captureDir: captureDir,
      manualDir: manualDir,
      outputDir: outputDir,
      minRuns: minRuns,
      maxTotalFrameP95Ms: maxTotalFrameP95Ms,
      maxDomApplyP95Ms: maxDomApplyP95Ms,
      maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
      maxOverBudgetPercent: maxOverBudgetPercent,
      maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      thresholdsPath: thresholdsPath,
      thresholdReviewPath: thresholdReviewPath,
      requireComparableRunEnvironment: requireComparableRunEnvironment,
      maxFallbackCells: maxFallbackCells,
      maxFallbackFramePercent: maxFallbackFramePercent,
      maxFallbackViewportPercent: maxFallbackViewportPercent,
      targetPreset: targetPreset,
      targetIds: List.unmodifiable(targetIds),
      requireScoreboardGates: requireScoreboardGates,
      requireTotalFrameGate: requireTotalFrameGate,
      requireSemanticGates: requireSemanticGates,
      requireReviewedThresholdPolicy: requireReviewedThresholdPolicy,
      requireThresholdReviewSummary: requireThresholdReviewSummary,
      requireScenarioThresholds: requireScenarioThresholds,
      writeDefaultPreflights: writeDefaultPreflights,
      completionAuditPath: completionAuditPath,
      json: json,
      strict: strict,
    );
  }
}

final class _BenchmarkWebDefaultPreflightOptions {
  const _BenchmarkWebDefaultPreflightOptions({
    required this.readinessPath,
    required this.bundlePath,
    required this.automatedValidationPath,
    required this.target,
    required this.outputPath,
    required this.jsonOutputPath,
    required this.json,
    required this.strict,
    required this.allowUnbundled,
  });

  final String readinessPath;
  final String? bundlePath;
  final String? automatedValidationPath;
  final String target;
  final String? outputPath;
  final String? jsonOutputPath;
  final bool json;
  final bool strict;
  final bool allowUnbundled;

  static _BenchmarkWebDefaultPreflightOptions parse(
    String root,
    List<String> args,
  ) {
    var readinessPath =
        '$root/profiling/web/baselines/web-readiness-bundle/web-readiness.json';
    String? bundlePath;
    String? automatedValidationPath;
    var target = 'make-dom-default';
    String? outputPath;
    String? jsonOutputPath;
    var json = false;
    var strict = false;
    var allowUnbundled = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebDefaultPreflightUsage();
        exit(0);
      } else if (arg.startsWith('--readiness=')) {
        readinessPath = _absolutePath(
          root,
          arg.substring('--readiness='.length),
        );
      } else if (arg.startsWith('--bundle=')) {
        final rawPath = arg.substring('--bundle='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--bundle requires a non-empty path.');
          _printBenchmarkWebDefaultPreflightUsage();
          exit(2);
        }
        bundlePath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--automated-validation=')) {
        final rawPath = arg.substring('--automated-validation='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--automated-validation requires a non-empty path.');
          _printBenchmarkWebDefaultPreflightUsage();
          exit(2);
        }
        automatedValidationPath = _absolutePath(root, rawPath);
      } else if (arg.startsWith('--target=')) {
        target = arg.substring('--target='.length);
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--json-output=')) {
        final rawPath = arg.substring('--json-output='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printBenchmarkWebDefaultPreflightUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, rawPath);
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg == '--allow-unbundled') {
        allowUnbundled = true;
      } else {
        stderr.writeln(
          'Unknown option for benchmark web-default-preflight: $arg',
        );
        _printBenchmarkWebDefaultPreflightUsage();
        exit(2);
      }
    }

    final effectiveBundlePath =
        bundlePath ??
        (allowUnbundled ? null : _siblingReadinessBundlePath(readinessPath));
    final effectiveAutomatedValidationPath =
        automatedValidationPath ??
        (allowUnbundled
            ? null
            : _siblingWebAutomatedValidationPath(readinessPath));

    return _BenchmarkWebDefaultPreflightOptions(
      readinessPath: readinessPath,
      bundlePath: effectiveBundlePath,
      automatedValidationPath: effectiveAutomatedValidationPath,
      target: target,
      outputPath: outputPath,
      jsonOutputPath: jsonOutputPath,
      json: json,
      strict: strict,
      allowUnbundled: allowUnbundled,
    );
  }
}

final class _BenchmarkWebAutomatedValidationOptions {
  const _BenchmarkWebAutomatedValidationOptions({
    required this.jsonOutputPath,
    required this.json,
    required this.strict,
  });

  final String? jsonOutputPath;
  final bool json;
  final bool strict;

  static _BenchmarkWebAutomatedValidationOptions parse(
    String root,
    List<String> args,
  ) {
    String? jsonOutputPath;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebAutomatedValidationUsage();
        exit(0);
      } else if (arg.startsWith('--json-output=')) {
        final rawPath = arg.substring('--json-output='.length).trim();
        if (rawPath.isEmpty) {
          stderr.writeln('--json-output requires a non-empty path.');
          _printBenchmarkWebAutomatedValidationUsage();
          exit(2);
        }
        jsonOutputPath = _absolutePath(root, rawPath);
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln(
          'Unknown option for benchmark web-automated-validation: $arg',
        );
        _printBenchmarkWebAutomatedValidationUsage();
        exit(2);
      }
    }

    return _BenchmarkWebAutomatedValidationOptions(
      jsonOutputPath: jsonOutputPath,
      json: json,
      strict: strict,
    );
  }
}

String _siblingReadinessBundlePath(String readinessPath) {
  return '${File(readinessPath).parent.path}${Platform.pathSeparator}web-readiness-bundle.json';
}

String _siblingWebAutomatedValidationPath(String readinessPath) {
  return '${File(readinessPath).parent.path}${Platform.pathSeparator}web-automated-validation.json';
}

final class _BenchmarkWebReportOptions {
  const _BenchmarkWebReportOptions({
    required this.inputPath,
    required this.outputPath,
    required this.frameBudgetMs,
    required this.maxTotalFrameP95Ms,
    required this.maxDomApplyP95Ms,
    required this.maxSemanticApplyP95Ms,
    required this.maxOverBudgetPercent,
    required this.maxSemanticUncoveredCells,
    required this.json,
    required this.strict,
  });

  final String inputPath;
  final String? outputPath;
  final double frameBudgetMs;
  final double? maxTotalFrameP95Ms;
  final double? maxDomApplyP95Ms;
  final double? maxSemanticApplyP95Ms;
  final double? maxOverBudgetPercent;
  final double? maxSemanticUncoveredCells;
  final bool json;
  final bool strict;

  static _BenchmarkWebReportOptions parse(String root, List<String> args) {
    String? inputPath;
    String? outputPath;
    var frameBudgetMs = 16.67;
    double? maxTotalFrameP95Ms;
    double? maxDomApplyP95Ms;
    double? maxSemanticApplyP95Ms;
    double? maxOverBudgetPercent;
    double? maxSemanticUncoveredCells;
    var json = false;
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        _printBenchmarkWebReportUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputPath = _absolutePath(root, arg.substring('--input='.length));
      } else if (arg.startsWith('--output=')) {
        outputPath = _absolutePath(root, arg.substring('--output='.length));
      } else if (arg.startsWith('--budget-ms=')) {
        frameBudgetMs = _positiveCliDouble(arg, '--budget-ms=');
      } else if (arg.startsWith('--max-total-frame-p95-ms=')) {
        maxTotalFrameP95Ms = _positiveCliDouble(
          arg,
          '--max-total-frame-p95-ms=',
        );
      } else if (arg.startsWith('--max-dom-apply-p95-ms=')) {
        maxDomApplyP95Ms = _positiveCliDouble(arg, '--max-dom-apply-p95-ms=');
      } else if (arg.startsWith('--max-semantic-apply-p95-ms=')) {
        maxSemanticApplyP95Ms = _positiveCliDouble(
          arg,
          '--max-semantic-apply-p95-ms=',
        );
      } else if (arg.startsWith('--max-over-budget-percent=')) {
        maxOverBudgetPercent = _nonNegativeCliDouble(
          arg,
          '--max-over-budget-percent=',
        );
      } else if (arg.startsWith('--max-semantic-uncovered-cells=')) {
        maxSemanticUncoveredCells = _nonNegativeCliDouble(
          arg,
          '--max-semantic-uncovered-cells=',
        );
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else {
        stderr.writeln('Unknown option for benchmark web-report: $arg');
        _printBenchmarkWebReportUsage();
        exit(2);
      }
    }

    if (inputPath == null) {
      stderr.writeln('benchmark web-report requires --input=<path>.');
      _printBenchmarkWebReportUsage();
      exit(2);
    }

    return _BenchmarkWebReportOptions(
      inputPath: inputPath,
      outputPath: outputPath,
      frameBudgetMs: frameBudgetMs,
      maxTotalFrameP95Ms: maxTotalFrameP95Ms,
      maxDomApplyP95Ms: maxDomApplyP95Ms,
      maxSemanticApplyP95Ms: maxSemanticApplyP95Ms,
      maxOverBudgetPercent: maxOverBudgetPercent,
      maxSemanticUncoveredCells: maxSemanticUncoveredCells,
      json: json,
      strict: strict,
    );
  }
}

double _positiveCliDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value <= 0) {
    stderr.writeln('$prefix requires a positive number.');
    exit(2);
  }
  return value;
}

double _nonNegativeCliDouble(String arg, String prefix) {
  final value = double.tryParse(arg.substring(prefix.length));
  if (value == null || value < 0) {
    stderr.writeln('$prefix requires a non-negative number.');
    exit(2);
  }
  return value;
}

final class _TerminalMatrixOptions {
  const _TerminalMatrixOptions({
    required this.label,
    required this.outputPath,
    required this.probe,
    required this.probeTimeoutMs,
    required this.reviewNotes,
  });

  final String label;
  final String outputPath;
  final bool probe;
  final int probeTimeoutMs;
  final List<String> reviewNotes;

  static _TerminalMatrixOptions parse(String root, List<String> args) {
    var label = 'local-terminal';
    String? outputPath;
    var probe = true;
    var probeTimeoutMs = 150;
    final reviewNotes = <String>[];

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printTerminalMatrixUsage();
        exit(0);
      } else if (arg == '--no-probe') {
        probe = false;
      } else if (arg.startsWith('--label=')) {
        label = arg.substring('--label='.length).trim();
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
      } else if (arg.startsWith('--probe-timeout=')) {
        final value = int.tryParse(arg.substring('--probe-timeout='.length));
        if (value == null || value < 1) {
          stderr.writeln(
            '--probe-timeout must be a positive millisecond value.',
          );
          exit(2);
        }
        probeTimeoutMs = value;
      } else if (arg.startsWith('--review-note=')) {
        final value = arg.substring('--review-note='.length).trim();
        if (value.isEmpty) {
          stderr.writeln('--review-note must not be empty.');
          exit(2);
        }
        reviewNotes.add(value);
      } else {
        stderr.writeln('Unknown option for terminal-matrix: $arg');
        _printTerminalMatrixUsage();
        exit(2);
      }
    }

    if (label.isEmpty) label = 'local-terminal';
    final path =
        outputPath ??
        '$root/docs/implementation/terminal-matrix/'
            '${_timestampForFile(DateTime.now().toUtc())}-${_slug(label)}.json';
    return _TerminalMatrixOptions(
      label: label,
      outputPath: _absolutePath(root, path),
      probe: probe,
      probeTimeoutMs: probeTimeoutMs,
      reviewNotes: List<String>.unmodifiable(reviewNotes),
    );
  }
}

final class _TerminalMatrixAuditOptions {
  const _TerminalMatrixAuditOptions({
    required this.inputPath,
    required this.targets,
    required this.json,
    required this.strict,
    required this.writePlanPath,
    required this.writeReviewPath,
  });

  final String inputPath;
  final List<String> targets;
  final bool json;
  final bool strict;
  final String? writePlanPath;
  final String? writeReviewPath;

  static _TerminalMatrixAuditOptions parse(String root, List<String> args) {
    var inputPath = '$root/docs/implementation/terminal-matrix';
    var json = false;
    var strict = false;
    String? writePlanPath;
    String? writeReviewPath;
    final targets = <String>[];

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printTerminalMatrixAuditUsage();
        exit(0);
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--write-plan=')) {
        writePlanPath = arg.substring('--write-plan='.length).trim();
      } else if (arg.startsWith('--write-review=')) {
        writeReviewPath = arg.substring('--write-review='.length).trim();
      } else if (arg.startsWith('--target-preset=')) {
        final value = arg.substring('--target-preset='.length).trim();
        final preset = _terminalMatrixTargetPresets[value];
        if (preset == null) {
          stderr.writeln(
            'Unknown terminal matrix target preset: $value. '
            'Known presets: ${_terminalMatrixTargetPresets.keys.join(', ')}',
          );
          exit(2);
        }
        targets.addAll(preset);
      } else if (arg.startsWith('--target=')) {
        final value = arg.substring('--target='.length).trim();
        if (value.isNotEmpty) targets.add(value);
      } else {
        stderr.writeln('Unknown option for terminal-matrix-audit: $arg');
        _printTerminalMatrixAuditUsage();
        exit(2);
      }
    }

    return _TerminalMatrixAuditOptions(
      inputPath: _absolutePath(root, inputPath),
      targets: targets.isEmpty
          ? _defaultTerminalMatrixTargets
          : _dedupeStrings(targets),
      json: json,
      strict: strict,
      writePlanPath: writePlanPath == null || writePlanPath.isEmpty
          ? null
          : _absolutePath(root, writePlanPath),
      writeReviewPath: writeReviewPath == null || writeReviewPath.isEmpty
          ? null
          : _absolutePath(root, writeReviewPath),
    );
  }
}

final class _TerminalMatrixAcceptOptions {
  const _TerminalMatrixAcceptOptions({
    required this.inputPath,
    required this.label,
    required this.notes,
    required this.acceptedBy,
    required this.allowNonInteractive,
  });

  final String inputPath;
  final String label;
  final List<String> notes;
  final String? acceptedBy;
  final bool allowNonInteractive;

  static _TerminalMatrixAcceptOptions parse(String root, List<String> args) {
    var inputPath = '$root/docs/implementation/terminal-matrix';
    String? label;
    String? acceptedBy;
    var allowNonInteractive = false;
    final notes = <String>[];

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printTerminalMatrixAcceptUsage();
        exit(0);
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--label=')) {
        label = arg.substring('--label='.length).trim();
      } else if (arg.startsWith('--accepted-by=')) {
        acceptedBy = arg.substring('--accepted-by='.length).trim();
      } else if (arg.startsWith('--note=')) {
        final note = arg.substring('--note='.length).trim();
        if (note.isNotEmpty) notes.add(note);
      } else if (arg == '--allow-non-interactive') {
        allowNonInteractive = true;
      } else {
        stderr.writeln('Unknown option for terminal-matrix-accept: $arg');
        _printTerminalMatrixAcceptUsage();
        exit(2);
      }
    }

    if (label == null || label.isEmpty) {
      stderr.writeln('terminal-matrix-accept requires --label=<entry-label>.');
      exit(2);
    }
    if (notes.isEmpty) {
      stderr.writeln('terminal-matrix-accept requires at least one --note.');
      exit(2);
    }
    if (acceptedBy != null && acceptedBy.isEmpty) {
      acceptedBy = null;
    }

    return _TerminalMatrixAcceptOptions(
      inputPath: _absolutePath(root, inputPath),
      label: label,
      notes: List<String>.unmodifiable(notes),
      acceptedBy: acceptedBy,
      allowNonInteractive: allowNonInteractive,
    );
  }
}

final class _MvpReadinessOptions {
  const _MvpReadinessOptions({
    required this.inputPath,
    required this.json,
    required this.strict,
    required this.writeReportPath,
  });

  final String inputPath;
  final bool json;
  final bool strict;
  final String? writeReportPath;

  static _MvpReadinessOptions parse(String root, List<String> args) {
    var inputPath = '$root/docs/implementation/terminal-matrix';
    var json = false;
    var strict = false;
    String? writeReportPath;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printMvpReadinessUsage();
        exit(0);
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--write-report=')) {
        writeReportPath = arg.substring('--write-report='.length).trim();
      } else {
        stderr.writeln('Unknown option for mvp-readiness: $arg');
        _printMvpReadinessUsage();
        exit(2);
      }
    }

    return _MvpReadinessOptions(
      inputPath: _absolutePath(root, inputPath),
      json: json,
      strict: strict,
      writeReportPath: writeReportPath == null || writeReportPath.isEmpty
          ? null
          : _absolutePath(root, writeReportPath),
    );
  }
}

final class _MvpFinalGateOptions {
  const _MvpFinalGateOptions({
    required this.inputPath,
    required this.quick,
    required this.skipLocal,
    required this.writeReportPath,
  });

  final String inputPath;
  final bool quick;
  final bool skipLocal;
  final String? writeReportPath;

  static _MvpFinalGateOptions parse(String root, List<String> args) {
    var inputPath = '$root/docs/implementation/terminal-matrix';
    var quick = false;
    var skipLocal = false;
    String? writeReportPath;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printMvpFinalGateUsage();
        exit(0);
      } else if (arg == '--quick') {
        quick = true;
      } else if (arg == '--skip-local') {
        skipLocal = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--write-report=')) {
        writeReportPath = arg.substring('--write-report='.length).trim();
      } else {
        stderr.writeln('Unknown option for mvp-final-gate: $arg');
        _printMvpFinalGateUsage();
        exit(2);
      }
    }

    return _MvpFinalGateOptions(
      inputPath: _absolutePath(root, inputPath),
      quick: quick,
      skipLocal: skipLocal,
      writeReportPath: writeReportPath == null || writeReportPath.isEmpty
          ? null
          : _absolutePath(root, writeReportPath),
    );
  }
}

final class _MvpEvidenceRefreshOptions {
  const _MvpEvidenceRefreshOptions({
    required this.inputPath,
    required this.outputDir,
    required this.strict,
  });

  final String inputPath;
  final String outputDir;
  final bool strict;

  static _MvpEvidenceRefreshOptions parse(String root, List<String> args) {
    var inputPath = '$root/docs/implementation/terminal-matrix';
    var outputDir = '$root/docs/implementation';
    var strict = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help') {
        _printMvpEvidenceRefreshUsage();
        exit(0);
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length).trim();
      } else if (arg.startsWith('--output-dir=')) {
        outputDir = arg.substring('--output-dir='.length).trim();
      } else {
        stderr.writeln('Unknown option for mvp-evidence-refresh: $arg');
        _printMvpEvidenceRefreshUsage();
        exit(2);
      }
    }

    return _MvpEvidenceRefreshOptions(
      inputPath: _absolutePath(root, inputPath),
      outputDir: _absolutePath(root, outputDir),
      strict: strict,
    );
  }
}

const _defaultTerminalMatrixTargets = <String>['macos-terminal', 'tmux'];

const _windowsTerminalMatrixTargets = <String>[
  'windows-terminal',
  'windows-conhost',
  'windows-powershell',
  'windows-ide',
];

const _terminalMatrixTargetPresets = <String, List<String>>{
  'launch': _defaultTerminalMatrixTargets,
  'windows': _windowsTerminalMatrixTargets,
};

void _printTerminalMatrixUsage() {
  stdout.writeln('Usage: dart tool/fleury_dev.dart terminal-matrix [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --label=<name>          Human label for this terminal/session',
  );
  stdout.writeln('  --output=<path>         Output JSON path');
  stdout.writeln('  --probe-timeout=<ms>    Per-probe timeout, default 150');
  stdout.writeln('  --no-probe              Capture passive diagnose only');
  stdout.writeln(
    '  --review-note=<text>    Add reviewer context to the matrix entry',
  );
}

void _printTerminalMatrixAuditUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart terminal-matrix-audit [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=<dir>           Matrix directory, default docs/implementation/terminal-matrix',
  );
  stdout.writeln('  --target=<label>        Required ready label; may repeat');
  stdout.writeln(
    '  --target-preset=<name>  Add preset targets: launch, windows',
  );
  stdout.writeln('  --json                  Print machine-readable audit JSON');
  stdout.writeln(
    '  --write-plan=<path>     Write a Markdown capture/review checklist',
  );
  stdout.writeln(
    '  --write-review=<path>   Write a Markdown reviewer packet for entries',
  );
  stdout.writeln(
    '  --strict                Exit non-zero if targets are missing or entries are invalid',
  );
}

void _printTerminalMatrixAcceptUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart terminal-matrix-accept [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=<dir>           Matrix directory, default docs/implementation/terminal-matrix',
  );
  stdout.writeln('  --label=<label>         Entry label to accept');
  stdout.writeln('  --note=<text>           Reviewer note; may repeat');
  stdout.writeln('  --accepted-by=<name>    Reviewer identity');
  stdout.writeln(
    '  --allow-non-interactive Allow accepting a nonInteractive control entry',
  );
}

void _printMvpReadinessUsage() {
  stdout.writeln('Usage: dart tool/fleury_dev.dart mvp-readiness [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=<dir>           Matrix directory, default docs/implementation/terminal-matrix',
  );
  stdout.writeln('  --json                  Print machine-readable audit JSON');
  stdout.writeln('  --write-report=<path>   Write a Markdown readiness report');
  stdout.writeln(
    '  --strict                Exit non-zero until external evidence is ready',
  );
}

void _printMvpFinalGateUsage() {
  stdout.writeln('Usage: dart tool/fleury_dev.dart mvp-final-gate [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=<dir>           Matrix directory, default docs/implementation/terminal-matrix',
  );
  stdout.writeln('  --quick                 Use the quick local check gate');
  stdout.writeln(
    '  --skip-local            Skip local check; use only when it already ran',
  );
  stdout.writeln('  --write-report=<path>   Write a Markdown readiness report');
}

void _printMvpEvidenceRefreshUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart mvp-evidence-refresh [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=<dir>           Matrix directory, default docs/implementation/terminal-matrix',
  );
  stdout.writeln(
    '  --output-dir=<dir>      Generated docs directory, default docs/implementation',
  );
  stdout.writeln(
    '  --strict                Exit non-zero until external evidence is ready',
  );
}

void _printBenchmarkUsage() {
  stdout.writeln('Usage: dart tool/fleury_dev.dart benchmark <subcommand>');
  stdout.writeln('');
  stdout.writeln('Subcommands:');
  stdout.writeln(
    '  list [--json]           Show local scenarios, peer fixtures, and wire runs',
  );
  stdout.writeln(
    '  local <SB.id|all> [...] Run Fleury scenario benchmarks through package runners',
  );
  stdout.writeln(
    '  profile <SB.id> [...]    Run local benchmark under VM CPU/allocation profiler',
  );
  stdout.writeln(
    '  wire <scenario> [...]   Build/capture/analyze real PTY peer runs',
  );
  stdout.writeln('');
  stdout.writeln('Regression gates (pass --gate to fail on regression; see '
      'docs/implementation/perf-gates.md):');
  stdout.writeln(
    '  gates                   Run the fast gate suite + pass/fail summary',
  );
  stdout.writeln(
    '  wire-gate [...]         Terminal wire bytes (SB.1/6/9) vs baseline',
  );
  stdout.writeln(
    '  serve-wire-live [...]   Live serve socket bytes + input latency vs baseline',
  );
  stdout.writeln(
    '  serve-semantics-gate    Semantics wire anti-cliff (DEFLATE) invariant',
  );
  stdout.writeln(
    '  image-bench [--gate]    Inline-image encoder bytes/frame + dedup/zero',
  );
  stdout.writeln(
    '  bundle-size [--gate]    Served-browser first-load client raw + gzip',
  );
  stdout.writeln(
    '  alloc-gate [--gate]     Per-frame package:fleury allocation churn',
  );
  stdout.writeln(
    '  paint-gate [--gate]     Repaint-boundary counters (paint-walk pruning)',
  );
  stdout.writeln('');
  stdout.writeln(
    '  scoreboard [options]    Build the generated benchmark scoreboard',
  );
  stdout.writeln(
    '  web-capture [options]   Capture retained DOM browser frame metrics',
  );
  stdout.writeln(
    '  web-suite [options]     Run repeated retained DOM capture scenarios',
  );
  stdout.writeln(
    '  web-scoreboard [options] Aggregate retained DOM capture directories',
  );
  stdout.writeln(
    '  web-threshold-review [options] Promote candidate web thresholds after review',
  );
  stdout.writeln(
    '  web-semantic-audit [options] Audit retained DOM semantic fallback reliance',
  );
  stdout.writeln(
    '  web-manual-validation [options] Audit manual retained DOM web evidence',
  );
  stdout.writeln(
    '  web-readiness [options] Combine reviewed web release-gate artifacts',
  );
  stdout.writeln(
    '  web-readiness-bundle [options] Generate web readiness JSON artifacts',
  );
  stdout.writeln(
    '  web-automated-validation [options] Run retained DOM automated host tests',
  );
  stdout.writeln(
    '  web-default-preflight [options] Gate DOM default/retirement release actions',
  );
  stdout.writeln(
    '  web-report [options]    Summarize retained DOM web frame captures',
  );
  stdout.writeln(
    '  manifest [options]     Print the comparative benchmark contract',
  );
  stdout.writeln(
    '  result [options]       Validate and merge one peer benchmark run',
  );
  stdout.writeln(
    '  variance [options]     Summarize repeated peer benchmark runs',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  fleury benchmark list');
  stdout.writeln(
    '  fleury benchmark local SB.4 --warmup=1 --iterations=3 --json',
  );
  stdout.writeln(
    '  fleury benchmark profile SB.6 --warmup=1 --iterations=5 --save=profiling/caps/sb6-vm-profile.json',
  );
  stdout.writeln('  fleury benchmark local --list');
  stdout.writeln('  fleury benchmark wire sb2 --runs=3');
  stdout.writeln(
    '  fleury benchmark wire sb3 --peers=ratatui,opentui --runs=3',
  );
  stdout.writeln('  fleury benchmark wire sb4 --runs=3');
  stdout.writeln('  fleury benchmark wire sb5 --peer=ink --runs=3');
  stdout.writeln('  fleury benchmark wire-gate');
  stdout.writeln('  fleury benchmark wire-gate --update-baseline');
  stdout.writeln(
    '  fleury benchmark scoreboard --input=profiling/caps --output=profiling/caps/scoreboard.md',
  );
  stdout.writeln(
    '  fleury benchmark web-capture --scenario=normal-80x24 --output=profiling/web/baselines/normal-80x24.json',
  );
  stdout.writeln(
    '  fleury benchmark web-suite --scenarios=normal-80x24,large-160x50 --runs=3',
  );
  stdout.writeln(
    '  fleury benchmark web-scoreboard --input=profiling/web --output=profiling/web/scoreboard.md --json-output=profiling/web/scoreboard.json',
  );
  stdout.writeln(
    '  fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --output=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN --reviewed-by=REVIEWER --review-context="Chrome VERSION on PLATFORM, retained DOM product baseline" --allow-over-budget-thresholds --review-note="Explain any accepted over-budget thresholds."',
  );
  stdout.writeln(
    '  fleury benchmark web-semantic-audit --input=profiling/web --max-fallback-cells=0 --strict',
  );
  stdout.writeln(
    '  fleury benchmark web-manual-validation --write-plan=profiling/web/manual/plan.md',
  );
  stdout.writeln('  fleury benchmark web-readiness --strict --json');
  stdout.writeln(
    '  fleury benchmark web-readiness-bundle --captures=profiling/web/baselines/2026-06-08-dom-retained --manual=profiling/web/manual --output-dir=profiling/web/baselines/2026-06-08-dom-retained/readiness --thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --max-total-frame-p95-ms=16.67 --max-fallback-cells=0 --write-default-preflights --strict',
  );
  stdout.writeln(
    '  fleury benchmark web-automated-validation --json-output=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-automated-validation.json --strict',
  );
  stdout.writeln(
    '  fleury benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json --automated-validation=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-automated-validation.json --target=make-dom-default --strict',
  );
  stdout.writeln(
    '  fleury benchmark web-report --input=profiling/web/dom-frames.json --output=profiling/web/dom-frames.md',
  );
}

void _printBenchmarkListUsage() {
  stdout.writeln('Usage: dart tool/fleury_dev.dart benchmark list [--json]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --json                  Print machine-readable catalog JSON',
  );
}

void _printBenchmarkLocalUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark local <SB.id|all> [runner options]',
  );
  stdout.writeln('');
  stdout.writeln('Options are forwarded to the owning scenario runner.');
  stdout.writeln('Common options:');
  stdout.writeln(
    '  --list                  List scenarios from all local runners',
  );
  stdout.writeln('  --warmup=N              Warmup iterations');
  stdout.writeln('  --iterations=N          Measured iterations');
  stdout.writeln('  --json                  Print runner JSON');
  stdout.writeln(
    '  --save=PATH             Save runner JSON; relative to repo root',
  );
  stdout.writeln('  --size=COLSxROWS        Terminal size');
  stdout.writeln(
    '  --rows=N                Widget row count for widget scenarios',
  );
  stdout.writeln(
    '  --profile-memory        Add RSS phase profiling metrics where supported',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  fleury benchmark local SB.2 --text-chars=10000 --json');
  stdout.writeln(
    '  fleury benchmark local SB.4 --rows=10000 --warmup=1 --iterations=3',
  );
  stdout.writeln(
    '  fleury benchmark local SB.6 --profile-memory --json --save=profiling/caps/sb6-local-memory.json',
  );
  stdout.writeln('  fleury benchmark local all --warmup=1 --iterations=1');
}

void _printBenchmarkProfileUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark profile <SB.id> [options] [runner options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Runs a local scenario benchmark under the Dart VM service profiler.',
  );
  stdout.writeln('Profiler options:');
  stdout.writeln(
    '  --save=PATH             Save profile JSON; relative to repo root',
  );
  stdout.writeln('  --json                  Print profile JSON');
  stdout.writeln('  --cpu-top=N             CPU rows to keep');
  stdout.writeln('  --allocation-top=N      Allocation rows to keep');
  stdout.writeln('  --profile-period-us=N   CPU sample period');
  stdout.writeln('  --runner-json           Forward --json to the runner');
  stdout.writeln('  --runner-save=PATH      Forward --save to the runner');
  stdout.writeln('');
  stdout.writeln('Common runner options are forwarded:');
  stdout.writeln(
    '  --warmup=N --iterations=N --rows=N --size=COLSxROWS --sb12-phase=PHASE',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark profile SB.6 --warmup=1 --iterations=5 --save=profiling/caps/sb6-vm-profile.json',
  );
  stdout.writeln(
    '  fleury benchmark profile SB.12 --warmup=1 --iterations=20 --save=profiling/caps/sb12-vm-profile.json',
  );
  stdout.writeln(
    '  fleury benchmark profile SB.12 --sb12-phase=viewport --warmup=1 --iterations=10',
  );
}

void _printBenchmarkWireUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark wire <scenario> [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Bare scenario IDs run every configured primary peer. Use --peer/--peers',
  );
  stdout.writeln(
    'to narrow, or pass a concrete ID such as sb6-ratatui for one peer.',
  );
  stdout.writeln('');
  stdout.writeln('Scenario groups:');
  for (final entry in _wireScenarioGroups().entries) {
    stdout.writeln(
      '  ${entry.key.padRight(8)} ${entry.value.map((config) => config.peerId).join(', ')}',
    );
  }
  stdout.writeln('');
  stdout.writeln('Supported scenarios:');
  for (final entry in _wireScenarioConfigs.entries) {
    stdout.writeln(
      '  ${entry.key.padRight(24)} ${entry.value.scenarioName} '
      'vs ${entry.value.peerId} ${entry.value.uiMode}',
    );
  }
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --runs=N                Paired capture repetitions, default 1',
  );
  stdout.writeln('  --peer=ID               Run one peer; may be repeated');
  stdout.writeln(
    '  --peers=A,B             Comma-separated peer list; default all',
  );
  stdout.writeln(
    '  --list-peers            List peers configured for this scenario',
  );
  stdout.writeln('  --json                  With --list-peers, print JSON');
  stdout.writeln('  --rows=N                Scenario row/data-size override');
  stdout.writeln(
    '  --append=N              Append-count override for append scenarios',
  );
  stdout.writeln('  --steps=N               Scenario work-step override');
  stdout.writeln('  --interval-ms=N         Delay between steps override');
  stdout.writeln(
    '  --timeout=N             Capture timeout seconds, scenario-specific default',
  );
  stdout.writeln('  --cols=N                PTY columns, default 120');
  stdout.writeln('  --pty-rows=N            PTY rows, default 32');
  stdout.writeln(
    '  --out-dir=PATH          Capture directory, default profiling/caps',
  );
  stdout.writeln(
    '  --debug-capture         Write Fleury DebugCapture JSON beside each run',
  );
  stdout.writeln(
    '  --runtime-markers       Write Fleury runtime marker JSON beside each run',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  fleury benchmark wire sb6 --runs=3');
  stdout.writeln(
    '  fleury benchmark wire sb6 --peers=ratatui,opentui --runs=3',
  );
  stdout.writeln('  fleury benchmark wire sb6-ratatui --runs=3');
  stdout.writeln('  fleury benchmark wire sb6 --list-peers');
  stdout.writeln('  fleury benchmark wire sb6 --help');
}

void _printBenchmarkScoreboardUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark scoreboard [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Scans capture_pty outputs and writes a scenario-indexed Markdown scoreboard.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=PATH            Capture directory, default profiling/caps',
  );
  stdout.writeln(
    '  --output=PATH           Markdown output; omit to print to stdout',
  );
  stdout.writeln(
    '  --json                  Also print machine-readable scoreboard JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  fleury benchmark scoreboard');
  stdout.writeln(
    '  fleury benchmark scoreboard --input=profiling/caps/2026-06-05-baseline --output=profiling/caps/2026-06-05-baseline/scoreboard.md',
  );
}

void _printBenchmarkWebCaptureUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-capture [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Compiles the retained DOM benchmark page, runs it in Chrome, and writes frame capture JSON.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --scenario=ID           Scenario id, default normal-80x24');
  stdout.writeln('  --frames=N              Driven benchmark steps');
  stdout.writeln('  --warmup=N              Warmup frames, default 2');
  stdout.writeln('  --budget-ms=N           Frame budget, default 16.67');
  stdout.writeln(
    '  --output=PATH           Capture JSON output, default profiling/web/runs/<scenario>-<timestamp>.json',
  );
  stdout.writeln('  --chrome=PATH           Chrome/Chromium executable');
  stdout.writeln('  --timeout=N             Timeout seconds, default 30');
  stdout.writeln('  --headful               Launch Chrome visibly');
  stdout.writeln(
    '  --compile-only          Compile and print temp page directory',
  );
  stdout.writeln(
    '  --keep-temp             Keep generated temp page/profile files',
  );
  stdout.writeln(
    '  --json                  Print machine-readable result JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-capture --scenario=large-160x50 --frames=32',
  );
  stdout.writeln(
    '  fleury benchmark web-capture --scenario=stress-300x100 --output=profiling/web/baselines/stress.json',
  );
}

void _printBenchmarkWebScoreboardUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-scoreboard [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Aggregates retained DOM web frame captures into a scenario scoreboard.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=DIR             Capture directory, default profiling/web',
  );
  stdout.writeln('  --output=PATH           Markdown output path');
  stdout.writeln('  --json-output=PATH      JSON scoreboard output path');
  stdout.writeln(
    '  --min-runs=N            Required captures per scenario, default 1',
  );
  stdout.writeln('  --max-total-frame-p95-ms=N       Gate median total p95');
  stdout.writeln(
    '  --max-dom-apply-p95-ms=N         Gate median DOM apply p95',
  );
  stdout.writeln(
    '  --max-semantic-apply-p95-ms=N    Gate median semantic apply p95',
  );
  stdout.writeln(
    '  --max-over-budget-percent=N      Gate median percent over budget',
  );
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N Gate max uncovered semantic cells',
  );
  stdout.writeln(
    '  --thresholds=PATH       JSON threshold policy with defaults/scenarios',
  );
  stdout.writeln(
    '  --write-thresholds=PATH Write a candidate JSON threshold policy from observed aggregates',
  );
  stdout.writeln(
    '  --threshold-headroom-percent=N      Candidate threshold headroom, default 20',
  );
  stdout.writeln(
    '  --threshold-min-headroom-ms=N       Candidate minimum timing headroom, default 1',
  );
  stdout.writeln(
    '  --threshold-min-headroom-percent=N  Candidate minimum over-budget headroom, default 1',
  );
  stdout.writeln(
    '  --require-comparable-environment Require one complete run environment signature per scenario',
  );
  stdout.writeln(
    '  --strict                Exit non-zero if run count, supplied gates, or required environment checks fail',
  );
  stdout.writeln(
    '  --json                  Print machine-readable scoreboard JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-scoreboard --input=profiling/web --output=profiling/web/scoreboard.md --json-output=profiling/web/scoreboard.json',
  );
  stdout.writeln(
    '  fleury benchmark web-scoreboard --input=profiling/web --min-runs=3 --strict --json',
  );
}

void _printBenchmarkWebThresholdReviewUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-threshold-review [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Promotes a candidate retained DOM threshold policy to reviewed release-gate evidence.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --input=PATH        Candidate threshold policy JSON');
  stdout.writeln(
    '  --output=PATH       Reviewed threshold policy JSON to write',
  );
  stdout.writeln(
    '  --write-plan=PATH   Write a non-promoting Markdown review plan',
  );
  stdout.writeln('  --reviewed-by=NAME  Human reviewer name or handle');
  stdout.writeln(
    '  --reviewed-at=TIME  ISO-8601 review time, default current UTC time',
  );
  stdout.writeln(
    '  --review-context=TEXT Required product/browser/environment basis for approval',
  );
  stdout.writeln(
    '  --review-context-hint=TEXT Override or supply fallback review context for review plans',
  );
  stdout.writeln('  --review-note=TEXT  Optional review note');
  stdout.writeln(
    '  --expect-input-fingerprint=FNV Require the loaded candidate policy to match a review-plan fingerprint',
  );
  stdout.writeln(
    '  --allow-over-budget-thresholds  Required when any scenario threshold allows over-budget frames',
  );
  stdout.writeln(
    '  --json-output=PATH  Promotion summary JSON path; with --write-plan only, embed this path in the generated command',
  );
  stdout.writeln('  --json              Print machine-readable summary JSON');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --output=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN --reviewed-by=REVIEWER --review-context="Chrome VERSION on PLATFORM, retained DOM product baseline" --allow-over-budget-thresholds --review-note="Explain any accepted over-budget thresholds."',
  );
  stdout.writeln(
    '  fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --write-plan=profiling/web/baselines/2026-06-08-dom-retained/threshold-review-plan.md',
  );
}

void _printBenchmarkWebSuiteUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-suite [options]',
  );
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
  stdout.writeln('  --budget-ms=N           Frame budget, default 16.67');
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
  stdout.writeln('  --max-total-frame-p95-ms=N       Gate median total p95');
  stdout.writeln(
    '  --max-dom-apply-p95-ms=N         Gate median DOM apply p95',
  );
  stdout.writeln(
    '  --max-semantic-apply-p95-ms=N    Gate median semantic apply p95',
  );
  stdout.writeln(
    '  --max-over-budget-percent=N      Gate median percent over budget',
  );
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N Gate max uncovered semantic cells',
  );
  stdout.writeln(
    '  --thresholds=PATH       JSON threshold policy with defaults/scenarios',
  );
  stdout.writeln(
    '  --write-thresholds=PATH Write a candidate JSON threshold policy after captures',
  );
  stdout.writeln(
    '  --threshold-headroom-percent=N      Candidate threshold headroom, default 20',
  );
  stdout.writeln(
    '  --threshold-min-headroom-ms=N       Candidate minimum timing headroom, default 1',
  );
  stdout.writeln(
    '  --threshold-min-headroom-percent=N  Candidate minimum over-budget headroom, default 1',
  );
  stdout.writeln(
    '  --no-strict             Do not strict-gate scoreboard min runs or supplied gates',
  );
  stdout.writeln(
    '  --no-require-comparable-environment Do not require identical run environment metadata',
  );
  stdout.writeln(
    '  --no-compile-once     Compile benchmark JS separately for each capture',
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
    '  --json                  Print machine-readable suite plan before running',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-suite --scenarios=normal-80x24,large-160x50 --runs=3',
  );
  stdout.writeln(
    '  fleury benchmark web-suite --runs=5 --output-dir=profiling/web/baselines/2026-06-08-baseline',
  );
}

void _printBenchmarkWebSemanticAuditUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-semantic-audit [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Audits retained DOM captures for semantic text fallback reliance.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=DIR                         Capture directory, default profiling/web',
  );
  stdout.writeln('  --output=PATH                       Markdown output path');
  stdout.writeln(
    '  --json-output=PATH                  JSON audit output path',
  );
  stdout.writeln(
    '  --max-fallback-cells=N              Gate max fallback cells in any frame',
  );
  stdout.writeln(
    '  --max-fallback-frame-percent=N      Gate percent of frames needing fallback',
  );
  stdout.writeln(
    '  --max-fallback-viewport-percent=N   Gate fallback cells as percent of viewport cells',
  );
  stdout.writeln(
    '  --strict                            Exit non-zero if any gate fails',
  );
  stdout.writeln(
    '  --json                              Print machine-readable audit JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-semantic-audit --input=profiling/web/baselines/2026-06-08-dom-retained --output=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.md --json-output=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.json',
  );
  stdout.writeln(
    '  fleury benchmark web-semantic-audit --input=profiling/web --max-fallback-cells=0 --strict --json',
  );
}

void _printBenchmarkWebManualValidationUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-manual-validation [options]',
  );
  stdout.writeln('');
  stdout.writeln('Generates and audits manual retained DOM web evidence.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=DIR                  Manual evidence directory, default profiling/web/manual',
  );
  stdout.writeln('  --output=PATH                Markdown audit output path');
  stdout.writeln(
    '  --write-plan=PATH            Write manual validation plan Markdown',
  );
  stdout.writeln(
    '  --write-template=PATH        Write a JSON evidence template',
  );
  stdout.writeln(
    '  --write-starter=PATH         Write a no-overwrite starter evidence file',
  );
  stdout.writeln(
    '  --starter-template=PATH      Template source for --write-starter',
  );
  stdout.writeln(
    '  --update-provenance=PATH     Update provenance fields on an evidence file',
  );
  stdout.writeln(
    '  --update-page-signal=PATH    Update one required page signal in an evidence file',
  );
  stdout.writeln(
    '  --update-check=PATH          Update one required check in an evidence file',
  );
  stdout.writeln(
    '  --reviewed-by=NAME           Reviewer value for --update-provenance',
  );
  stdout.writeln(
    '  --captured-at=ISO|now        Capture time for --update-provenance',
  );
  stdout.writeln(
    '  --browser-version=VERSION    Browser version for --update-provenance',
  );
  stdout.writeln(
    '  --signal-id=ID               Required page signal to update',
  );
  stdout.writeln(
    '  --signal-status=STATUS       pass, fail, blocked, or needsReview',
  );
  stdout.writeln('  --observed-value=VALUE       Observed page signal value');
  stdout.writeln(
    '  --signal-notes=TEXT          Reviewer observation notes for the page signal',
  );
  stdout.writeln('  --check-id=ID                Required check to update');
  stdout.writeln(
    '  --check-status=STATUS        pass, fail, blocked, or needsReview',
  );
  stdout.writeln(
    '  --check-notes=TEXT           Reviewer observation notes for the check',
  );
  stdout.writeln(
    '  --entry-status=STATUS        Set top-level evidence status',
  );
  stdout.writeln(
    '  --write-templates=DIR        Write selected target templates into DIR',
  );
  stdout.writeln(
    '  --template-target=ID         Target for template generation',
  );
  stdout.writeln('  --json-output=PATH           JSON audit output path');
  stdout.writeln(
    '  --target-preset=v1|primary|all  Target preset, default primary',
  );
  stdout.writeln('  --target=ID                  Restrict audit to a target');
  stdout.writeln(
    '  --strict                     Exit non-zero unless targets pass',
  );
  stdout.writeln(
    '  --json                       Print machine-readable audit JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-manual-validation --write-plan=profiling/web/manual/plan.md',
  );
  stdout.writeln(
    '  fleury benchmark web-manual-validation --write-template=profiling/web/manual/chrome-ime-macos.json --template-target=chrome-ime-macos',
  );
  stdout.writeln(
    '  fleury benchmark web-manual-validation --write-templates=profiling/web/manual/templates --target-preset=v1',
  );
  stdout.writeln(
    "  fleury benchmark web-manual-validation --update-provenance=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version>'",
  );
  stdout.writeln(
    "  fleury benchmark web-manual-validation --update-page-signal=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos --signal-id=retained-dom-ready --signal-status=pass --observed-value=ready '--signal-notes=<reviewer observation>'",
  );
  stdout.writeln(
    "  fleury benchmark web-manual-validation --update-check=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos --check-id=composition-end-commits-once --check-status=pass '--check-notes=<reviewer observation>'",
  );
  stdout.writeln(
    '  fleury benchmark web-manual-validation --input=profiling/web/manual --output=profiling/web/manual/review.md --json-output=profiling/web/manual/manual-validation-audit.json --strict',
  );
}

void _printBenchmarkWebReadinessUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-readiness [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Combines reviewed retained DOM web gate artifacts into the Phase 6 readiness audit.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --scoreboard=PATH                   Frame scoreboard JSON artifact',
  );
  stdout.writeln(
    '  --semantic-audit=PATH               Semantic coverage audit JSON artifact',
  );
  stdout.writeln(
    '  --manual-audit=PATH                 Manual validation audit JSON artifact',
  );
  stdout.writeln(
    '  --threshold-review=PATH             Threshold promotion summary JSON artifact',
  );
  stdout.writeln('  --output=PATH                       Markdown output path');
  stdout.writeln('  --json-output=PATH                  JSON output path');
  stdout.writeln(
    '  --min-scoreboard-runs=N             Minimum scoreboard minRuns, default 3',
  );
  stdout.writeln(
    '  --no-require-comparable-environment Do not require comparable run environments',
  );
  stdout.writeln(
    '  --no-require-scoreboard-gates       Do not require frame threshold gates',
  );
  stdout.writeln(
    '  --no-require-total-frame-gate       Do not require total-frame p95 gate',
  );
  stdout.writeln(
    '  --no-require-semantic-gates         Do not require semantic fallback gates',
  );
  stdout.writeln(
    '  --no-require-reviewed-threshold-policy Do not require reviewed threshold policy metadata',
  );
  stdout.writeln(
    '  --no-require-threshold-review-summary Do not require matching threshold-review JSON',
  );
  stdout.writeln(
    '  --no-require-scenario-thresholds    Do not require per-scenario threshold policy matches',
  );
  stdout.writeln(
    '  --strict                            Exit non-zero unless all checks pass',
  );
  stdout.writeln(
    '  --json                              Print machine-readable audit JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-readiness --scoreboard=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.json --semantic-audit=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.json --manual-audit=profiling/web/manual/manual-validation-audit.json --threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/web-readiness.json --strict',
  );
  stdout.writeln(
    '  fleury benchmark web-readiness --output=profiling/web/baselines/web-readiness.md --json',
  );
}

void _printBenchmarkWebReadinessBundleUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-readiness-bundle [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Generates the reviewed JSON artifact bundle consumed by web-readiness.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --captures=DIR                      Capture directory, default profiling/web/baselines',
  );
  stdout.writeln(
    '  --manual=DIR                        Manual evidence directory, default profiling/web/manual',
  );
  stdout.writeln(
    '  --output-dir=DIR                    Bundle output directory, default profiling/web/baselines/web-readiness-bundle',
  );
  stdout.writeln(
    '  --verify=PATH                       Verify artifact fingerprints in an existing web-readiness-bundle.json',
  );
  stdout.writeln(
    '  --min-runs=N                        Minimum runs, default 3',
  );
  stdout.writeln('  --max-total-frame-p95-ms=N          Frame gate');
  stdout.writeln('  --max-dom-apply-p95-ms=N            DOM apply gate');
  stdout.writeln('  --max-semantic-apply-p95-ms=N       Semantic apply gate');
  stdout.writeln('  --max-over-budget-percent=N         Over-budget gate');
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N    Semantic uncovered-cell gate',
  );
  stdout.writeln(
    '  --thresholds=PATH                   JSON threshold policy with defaults/scenarios',
  );
  stdout.writeln(
    '  --threshold-review=PATH             Threshold promotion summary JSON artifact',
  );
  stdout.writeln(
    '  --no-require-comparable-environment Do not require comparable run environments',
  );
  stdout.writeln(
    '  --max-fallback-cells=N              Semantic fallback gate',
  );
  stdout.writeln(
    '  --max-fallback-frame-percent=N      Semantic fallback gate',
  );
  stdout.writeln(
    '  --max-fallback-viewport-percent=N   Semantic fallback gate',
  );
  stdout.writeln('  --target-preset=v1|primary|all     Manual target preset');
  stdout.writeln(
    '  --target=ID                         Restrict manual target',
  );
  stdout.writeln('  --no-require-scoreboard-gates       Relax readiness gate');
  stdout.writeln('  --no-require-total-frame-gate       Relax readiness gate');
  stdout.writeln('  --no-require-semantic-gates         Relax readiness gate');
  stdout.writeln(
    '  --no-require-reviewed-threshold-policy Relax reviewed-threshold gate',
  );
  stdout.writeln(
    '  --no-require-threshold-review-summary Relax threshold-review summary gate',
  );
  stdout.writeln(
    '  --no-require-scenario-thresholds    Relax per-scenario threshold gate',
  );
  stdout.writeln(
    '  --write-default-preflights          Write default/retirement preflight artifacts',
  );
  stdout.writeln(
    '  --completion-audit=PATH             Write an RFC completion status audit JSON',
  );
  stdout.writeln(
    '  --strict                            Exit non-zero unless readiness passes',
  );
  stdout.writeln(
    '  --json                              Print machine-readable bundle JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-readiness-bundle --captures=profiling/web/baselines/2026-06-08-dom-retained --manual=profiling/web/manual --output-dir=profiling/web/baselines/2026-06-08-dom-retained/readiness --thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --max-total-frame-p95-ms=16.67 --max-fallback-cells=0 --write-default-preflights --strict',
  );
}

void _printBenchmarkWebDefaultPreflightUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-default-preflight [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Consumes a strict Phase 6 web-readiness JSON artifact before allowing',
  );
  stdout.writeln(
    'retained DOM default flips or temporary-path retirement claims.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --readiness=PATH  web-readiness JSON artifact, default profiling/web/baselines/web-readiness-bundle/web-readiness.json',
  );
  stdout.writeln(
    '  --bundle=PATH     web-readiness-bundle.json manifest to verify',
  );
  stdout.writeln(
    '                    Defaults to sibling web-readiness-bundle.json',
  );
  stdout.writeln('  --automated-validation=PATH');
  stdout.writeln(
    '                    web-automated-validation.json evidence to verify',
  );
  stdout.writeln(
    '                    Defaults to sibling web-automated-validation.json',
  );
  stdout.writeln(
    '  --allow-unbundled Permit readiness-only diagnostics; not a release gate',
  );
  stdout.writeln(
    '  --target=ID       make-dom-default or retire-temporary-paths',
  );
  stdout.writeln('  --output=PATH     Markdown output path');
  stdout.writeln('  --json-output=PATH Machine-readable JSON output path');
  stdout.writeln('  --strict          Exit non-zero unless preflight passes');
  stdout.writeln('  --json            Print machine-readable preflight JSON');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json --automated-validation=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-automated-validation.json --target=make-dom-default --strict',
  );
}

void _printBenchmarkWebAutomatedValidationUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-automated-validation [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Runs retained DOM browser and VM automated host tests and writes durable',
  );
  stdout.writeln(
    'web-automated-validation.json evidence for bundle-bound default preflights.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --json-output=PATH Machine-readable JSON output path');
  stdout.writeln('  --strict          Exit non-zero unless validation passes');
  stdout.writeln('  --json            Print machine-readable validation JSON');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-automated-validation --json-output=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-automated-validation.json --strict',
  );
}

void _printBenchmarkWebReportUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark web-report --input=<frames.json> [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Summarizes retained DOM web host frame instrumentation into JSON or Markdown.',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=PATH            JSON capture with a `frames` array',
  );
  stdout.writeln(
    '  --output=PATH           Markdown output, or JSON when PATH ends with .json',
  );
  stdout.writeln('  --budget-ms=N          Total-frame budget, default 16.67');
  stdout.writeln('  --max-total-frame-p95-ms=N       Gate total frame p95');
  stdout.writeln('  --max-dom-apply-p95-ms=N         Gate DOM apply p95');
  stdout.writeln('  --max-semantic-apply-p95-ms=N    Gate semantic apply p95');
  stdout.writeln(
    '  --max-over-budget-percent=N      Gate percent of frames over budget',
  );
  stdout.writeln(
    '  --max-semantic-uncovered-cells=N Gate max uncovered semantic cells',
  );
  stdout.writeln('  --strict                Exit non-zero if any gate fails');
  stdout.writeln(
    '  --json                  Also print machine-readable summary JSON',
  );
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  fleury benchmark web-report --input=profiling/web/dom-frames.json --output=profiling/web/dom-frames.md',
  );
  stdout.writeln(
    '  fleury benchmark web-report --input=profiling/web/dom-frames.json --json',
  );
  stdout.writeln(
    '  fleury benchmark web-report --input=profiling/web/dom-frames.json --max-total-frame-p95-ms=16.67 --strict',
  );
}

void _printBenchmarkWireScenarioUsage(String selector) {
  final entries = _wireScenarioEntriesForSelector(selector);
  final first = entries.first.value;
  final scenarioId = first.shortName;
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark wire $selector [options]',
  );
  stdout.writeln('');
  stdout.writeln(first.scenarioName);
  stdout.writeln('');
  stdout.writeln('Default command:');
  stdout.writeln('  fleury benchmark wire $scenarioId --runs=3');
  stdout.writeln('');
  stdout.writeln('Configured peers:');
  for (final entry in entries) {
    final config = entry.value;
    stdout.writeln(
      '  ${config.peerId.padRight(10)} ${entry.key.padRight(18)} '
      '${config.peerKind.padRight(6)} ${config.uiMode}',
    );
  }
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  fleury benchmark wire $scenarioId --runs=3');
  if (entries.length > 1) {
    final firstTwo = entries
        .take(2)
        .map((entry) => entry.value.peerId)
        .join(',');
    stdout.writeln(
      '  fleury benchmark wire $scenarioId --peers=$firstTwo --runs=3',
    );
  }
  stdout.writeln('  fleury benchmark wire ${entries.first.key} --runs=3');
  stdout.writeln('  fleury benchmark wire $scenarioId --list-peers');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --runs=N                Paired capture repetitions, default 1',
  );
  stdout.writeln('  --peer=ID               Run one peer; may be repeated');
  stdout.writeln(
    '  --peers=A,B             Comma-separated peer list; default all',
  );
  stdout.writeln(
    '  --list-peers            List peers configured for this scenario',
  );
  stdout.writeln('  --rows=N                Scenario row/data-size override');
  stdout.writeln(
    '  --append=N              Append-count override for append scenarios',
  );
  stdout.writeln('  --steps=N               Scenario work-step override');
  stdout.writeln('  --interval-ms=N         Delay between steps override');
  stdout.writeln(
    '  --timeout=N             Capture timeout seconds, scenario-specific default',
  );
  stdout.writeln('  --cols=N                PTY columns, default 120');
  stdout.writeln('  --pty-rows=N            PTY rows, default 32');
  stdout.writeln(
    '  --out-dir=PATH          Capture directory, default profiling/caps',
  );
  stdout.writeln(
    '  --debug-capture         Write Fleury DebugCapture JSON beside each run',
  );
  stdout.writeln(
    '  --runtime-markers       Write Fleury runtime marker JSON beside each run',
  );
}

void _printBenchmarkWireScenarioPeers(String selector, {required bool json}) {
  final entries = _wireScenarioEntriesForSelector(selector);
  final first = entries.first.value;
  if (json) {
    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(
      encoder.convert(<String, Object?>{
        'scenario': first.shortName,
        'name': first.scenarioName,
        'command': ['fleury', 'benchmark', 'wire', first.shortName, '--runs=3'],
        'peers': [
          for (final entry in entries)
            <String, Object?>{
              'id': entry.value.peerId,
              'wireScenario': entry.key,
              'kind': entry.value.peerKind,
              'uiMode': entry.value.uiMode,
            },
        ],
      }),
    );
    return;
  }

  stdout.writeln('${first.scenarioName} (${first.shortName})');
  stdout.writeln('');
  stdout.writeln('Configured peers:');
  for (final entry in entries) {
    final config = entry.value;
    stdout.writeln(
      '  ${config.peerId.padRight(10)} ${entry.key.padRight(18)} '
      '${config.peerKind.padRight(6)} ${config.uiMode}',
    );
  }
  stdout.writeln('');
  stdout.writeln('Run all:');
  stdout.writeln('  fleury benchmark wire ${first.shortName} --runs=3');
}

void _printBenchmarkCatalog(Map<String, Object?> catalog) {
  stdout.writeln('Fleury benchmark catalog');
  stdout.writeln('');
  stdout.writeln('Primary commands:');
  stdout.writeln('  fleury benchmark list');
  stdout.writeln('  fleury benchmark local <SB.id> [runner options]');
  stdout.writeln('  fleury benchmark wire <scenario> [options]');
  stdout.writeln('  fleury benchmark scoreboard [options]');
  stdout.writeln('  fleury benchmark manifest|result|variance [options]');
  stdout.writeln('');
  stdout.writeln('Local Fleury scenario runners:');
  for (final target in _localBenchmarkTargets) {
    stdout.writeln('  ${target.packagePath}: ${target.scenarios.join(', ')}');
  }
  stdout.writeln('');
  stdout.writeln('Wire scenario groups:');
  final wireScenarioGroups = catalog['wireScenarioGroups'] as List<Object?>;
  for (final item in wireScenarioGroups.cast<Map<String, Object?>>()) {
    final peers = (item['peers'] as List<Object?>).join(', ');
    stdout.writeln('  ${item['id']} -> ${item['scenario']} vs $peers');
  }
  stdout.writeln('');
  stdout.writeln('Concrete wire fixtures:');
  final wireScenarios = catalog['wireScenarios'] as List<Object?>;
  for (final item in wireScenarios.cast<Map<String, Object?>>()) {
    stdout.writeln(
      '  ${item['id']} -> ${item['scenario']} vs ${item['peer']} (${item['uiMode']})',
    );
  }
  stdout.writeln('');
  stdout.writeln('Peer fixture coverage:');
  final peerFixtures = catalog['peerFixtures'] as List<Object?>;
  for (final item in peerFixtures.cast<Map<String, Object?>>()) {
    final scenarios = (item['scenarios'] as List<Object?>).join(', ');
    final wire = (item['wire'] as List<Object?>).join(', ');
    stdout.writeln(
      '  ${item['peer'].toString().padRight(10)} scenarios: $scenarios'
      '${wire.isEmpty ? '' : ' | wire: $wire'}',
    );
  }
  stdout.writeln('');
  stdout.writeln('Docs:');
  for (final path in (catalog['docs'] as List<Object?>)) {
    stdout.writeln('  $path');
  }
}

void _printBenchmarkManifestUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark-manifest [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --input=<path>          Manifest JSON path, default docs/implementation/comparative-benchmark-manifest.json',
  );
  stdout.writeln('  --output=<path>         Write validated manifest JSON');
  stdout.writeln(
    '  --json                  Print machine-readable manifest JSON',
  );
}

void _printBenchmarkResultUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark-result --input=<path> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --manifest=<path>       Manifest JSON path, default docs/implementation/comparative-benchmark-manifest.json',
  );
  stdout.writeln(
    '  --input=<path>          Peer run artifact JSON with kind=fleuryPeerBenchmarkRun',
  );
  stdout.writeln(
    '  --output=<path>         Write a manifest copy with the peer run appended',
  );
  stdout.writeln(
    '  --json                  Print machine-readable summary JSON',
  );
}

void _printBenchmarkVarianceUsage() {
  stdout.writeln(
    'Usage: dart tool/fleury_dev.dart benchmark-variance --input=<path> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(
    '  --manifest=<path>       Manifest JSON path, default docs/implementation/comparative-benchmark-manifest.json',
  );
  stdout.writeln(
    '  --input=<path>          Peer run artifact JSON file or directory; may repeat',
  );
  stdout.writeln('  --output=<path>         Write a variance summary artifact');
  stdout.writeln(
    '  --min-runs=<count>      Minimum run count for strict readiness, default 3',
  );
  stdout.writeln(
    '  --strict                Exit non-zero unless repeated evidence is ready',
  );
  stdout.writeln(
    '  --json                  Print machine-readable summary JSON',
  );
}

String _absolutePath(String root, String path) {
  if (path.startsWith('/')) return path;
  return '$root/$path';
}

const _defaultWebBenchmarkScenarioIds = <String>[
  'normal-80x24',
  'large-160x50',
  'stress-300x100',
  'noop-160x50',
  'single-dirty-cell-160x50',
  'dirty-row-160x50',
  'full-frame-churn-160x50',
  'scroll-row-churn-160x50',
  'cursor-blink-80x24',
  'text-input-burst-80x24',
  'resize-burst',
];

List<String> _csvOption(String value) {
  return [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

String _relativePath(String root, String path) {
  if (path == root) return '.';
  if (path.startsWith('$root/')) return path.substring(root.length + 1);
  return path;
}

String _relativeFilePath({
  required String fromDirectory,
  required String toPath,
}) {
  final fromParts = Directory(fromDirectory).absolute.path
      .split(Platform.pathSeparator)
      .where((part) => part.isNotEmpty)
      .toList();
  final toParts = File(toPath).absolute.path
      .split(Platform.pathSeparator)
      .where((part) => part.isNotEmpty)
      .toList();
  var common = 0;
  while (common < fromParts.length &&
      common < toParts.length &&
      fromParts[common] == toParts[common]) {
    common++;
  }
  final up = List<String>.filled(fromParts.length - common, '..');
  final down = toParts.sublist(common);
  final parts = [...up, ...down];
  return parts.isEmpty ? '.' : parts.join('/');
}

String _fileStem(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

String _timestampForFile(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  String six(int n) => n.toString().padLeft(6, '0');
  final micros = value.millisecond * 1000 + value.microsecond;
  return '${value.year}-${two(value.month)}-${two(value.day)}T'
      '${two(value.hour)}-${two(value.minute)}-${two(value.second)}'
      '-${six(micros)}Z';
}

String _slug(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  var lastWasDash = false;
  for (final codeUnit in lower.codeUnits) {
    final alpha = codeUnit >= 97 && codeUnit <= 122;
    final digit = codeUnit >= 48 && codeUnit <= 57;
    if (alpha || digit) {
      buffer.writeCharCode(codeUnit);
      lastWasDash = false;
    } else if (!lastWasDash) {
      buffer.write('-');
      lastWasDash = true;
    }
  }
  final slug = buffer.toString().replaceAll(RegExp('^-+|-+\$'), '');
  return slug.isEmpty ? 'terminal' : slug;
}

List<String> _dedupeStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    if (value.isEmpty || !seen.add(value)) continue;
    result.add(value);
  }
  return List<String>.unmodifiable(result);
}

Map<String, Object?> _buildTerminalMatrixEntry({
  required String label,
  required DateTime capturedAt,
  required List<String> command,
  required Map<String, Object?> diagnosis,
  List<String> reviewNotes = const <String>[],
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryTerminalMatrixEntry',
    'label': label,
    'capturedAt': capturedAt.toIso8601String(),
    'command': command,
    'summary': _terminalMatrixSummary(diagnosis),
    'review': _terminalMatrixReview(diagnosis, additionalNotes: reviewNotes),
    'diagnosis': diagnosis,
  };
}

Map<String, Object?> _buildTerminalMatrixAudit({
  required String root,
  required String inputPath,
  required List<String> targets,
}) {
  final inputDirectory = Directory(inputPath);
  final entries = <Map<String, Object?>>[];
  final invalidEntries = <Map<String, Object?>>[];
  if (inputDirectory.existsSync()) {
    final files =
        inputDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        final entry = _object(decoded);
        if (entry['kind'] != 'fleuryTerminalMatrixEntry') {
          invalidEntries.add(<String, Object?>{
            'path': _relativePath(root, file.path),
            'issue': 'not a Fleury terminal matrix entry',
          });
          continue;
        }
        entries.add(_terminalMatrixAuditEntry(root, file.path, entry));
      } on Object catch (error) {
        invalidEntries.add(<String, Object?>{
          'path': _relativePath(root, file.path),
          'issue': error.toString(),
        });
      }
    }
  }

  final reviewStatusCounts = <String, int>{};
  final platformCounts = <String, int>{};
  for (final entry in entries) {
    final reviewStatus = entry['reviewStatus']?.toString() ?? 'unknown';
    reviewStatusCounts[reviewStatus] =
        (reviewStatusCounts[reviewStatus] ?? 0) + 1;
    final platform = entry['operatingSystem']?.toString() ?? 'unknown';
    platformCounts[platform] = (platformCounts[platform] ?? 0) + 1;
  }

  final targetReports = <Map<String, Object?>>[
    for (final target in targets)
      _terminalMatrixTargetReport(target: target, entries: entries),
  ];
  final missingTargets = <String>[
    for (final target in targetReports)
      if (target['covered'] != true) target['target']!.toString(),
  ];
  final targetsNeedingReview = <String>[
    for (final target in targetReports)
      if (target['covered'] != true &&
          (target['nonReadyEntryCount'] as int? ?? 0) > 0)
        target['target']!.toString(),
  ];
  final readyTargetCount = targetReports
      .where((target) => target['covered'] == true)
      .length;
  final collectionPlan = <Map<String, Object?>>[
    for (final target in targetReports)
      if (target['covered'] != true)
        _terminalMatrixCollectionPlanItem(target['target']!.toString()),
  ];
  final strictPass = missingTargets.isEmpty && invalidEntries.isEmpty;

  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryTerminalMatrixAudit',
    'directory': _relativePath(root, inputPath),
    'directoryExists': inputDirectory.existsSync(),
    'entryCount': entries.length,
    'invalidEntryCount': invalidEntries.length,
    'targetCount': targetReports.length,
    'readyTargetCount': readyTargetCount,
    'missingTargetCount': missingTargets.length,
    'nonReadyTargetCount': targetsNeedingReview.length,
    'strictPass': strictPass,
    'reviewStatusCounts': reviewStatusCounts,
    'platformCounts': platformCounts,
    'targets': targetReports,
    'missingTargets': missingTargets,
    'targetsNeedingReview': targetsNeedingReview,
    'collectionPlan': collectionPlan,
    'entries': entries,
    'invalidEntries': invalidEntries,
  };
}

Map<String, Object?> _buildMvpReadinessAudit({
  required String root,
  required String inputPath,
}) {
  final launchAudit = _buildTerminalMatrixAudit(
    root: root,
    inputPath: inputPath,
    targets: _defaultTerminalMatrixTargets,
  );
  final windowsAudit = _buildTerminalMatrixAudit(
    root: root,
    inputPath: inputPath,
    targets: _windowsTerminalMatrixTargets,
  );
  final blockers = <String>[];
  if (!_terminalMatrixAuditStrictPass(launchAudit)) {
    blockers.add(
      'M2.10 reviewed real-terminal matrix coverage is incomplete '
      '(${launchAudit['readyTargetCount']}/${launchAudit['targetCount']} ready).',
    );
  }
  const deferred = <String>[
    'Dune/dune_cli flagship integration',
    'fleury_acp package and ACP-specific widgets',
    'extended terminal matrix coverage for iTerm2, Kitty, Ghostty, Alacritty, WezTerm, and SSH',
    'real Windows validation across Windows Terminal, conhost, PowerShell, and IDE terminals',
    'public adoption/release collateral until API freeze',
    'full replay/shareable replay artifacts and browser/devtools protocol',
    'expanded peer benchmarks and public superiority comparison copy',
  ];
  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryMvpReadinessAudit',
    'strictPass': blockers.isEmpty,
    'directory': _relativePath(root, inputPath),
    'localImplementationEvidence': <String, Object?>{
      'status': 'documentedLocalRcGate',
      'auditPath': 'docs/implementation/mvp-completion-audit.md',
      'note':
          'This command audits external evidence readiness. Run `dart tool/fleury_dev.dart check` separately for a fresh local RC gate.',
    },
    'launchTerminalEvidence': _mvpReadinessMatrixSummary(launchAudit),
    'windowsValidationEvidence': <String, Object?>{
      ..._mvpReadinessMatrixSummary(windowsAudit),
      'requiredForMvp': false,
      'mvpStatus': 'deferred',
    },
    'remainingBlockers': blockers,
    'deferredOutOfMvp': deferred,
    'launchTerminalAudit': launchAudit,
    'windowsValidationAudit': windowsAudit,
  };
}

Map<String, Object?> _mvpReadinessMatrixSummary(Map<String, Object?> audit) {
  return <String, Object?>{
    'strictPass': audit['strictPass'],
    'targetCount': audit['targetCount'],
    'readyTargetCount': audit['readyTargetCount'],
    'missingTargetCount': audit['missingTargetCount'],
    'nonReadyTargetCount': audit['nonReadyTargetCount'],
    'missingTargets': audit['missingTargets'],
    'targetsNeedingReview': audit['targetsNeedingReview'],
  };
}

Map<String, Object?> _terminalMatrixAuditEntry(
  String root,
  String path,
  Map<String, Object?> entry,
) {
  final review = _object(entry['review']);
  final summary = _object(entry['summary']);
  final platform = _object(summary['platform']);
  final terminal = _object(summary['terminal']);
  final diagnostics = _object(summary['diagnostics']);
  final activeProbes = _object(summary['activeProbes']);
  final compatibility = _object(summary['compatibility']);
  final label = entry['label']?.toString() ?? _fileStem(path);
  return <String, Object?>{
    'path': _relativePath(root, path),
    'label': label,
    'labelSlug': _slug(label),
    'reviewStatus': review['status'] ?? 'unknown',
    'issues': _list(review['issues']),
    'notes': _list(review['notes']),
    'operatingSystem': platform['operatingSystem'],
    'dartVersion': platform['dartVersion'],
    'term': terminal['term'],
    'termProgram': terminal['termProgram'],
    'isInteractive': terminal['isInteractive'],
    'stdinIsTerminal': terminal['stdinIsTerminal'],
    'stdoutIsTerminal': terminal['stdoutIsTerminal'],
    'tmux': terminal['tmux'],
    'ssh': terminal['ssh'],
    'fallbackCount': diagnostics['fallbackCount'],
    'warningCount': diagnostics['warningCount'],
    'unsupportedFeatureCount': diagnostics['unsupportedFeatureCount'],
    'fallbackCodes': _list(diagnostics['fallbackCodes']),
    'warningCodes': _list(diagnostics['warningCodes']),
    'unsupportedFeatures': _list(diagnostics['unsupportedFeatures']),
    'activeProbeSummary': activeProbes['summary'],
    'compatibilitySummary': compatibility['summary'],
  };
}

Map<String, Object?> _terminalMatrixTargetReport({
  required String target,
  required List<Map<String, Object?>> entries,
}) {
  final targetSlug = _slug(target);
  final matches = <Map<String, Object?>>[];
  for (final entry in entries) {
    final labelSlug = entry['labelSlug']?.toString() ?? '';
    final matchKind = _terminalMatrixTargetMatchKind(
      targetSlug: targetSlug,
      labelSlug: labelSlug,
    );
    if (matchKind == null) continue;
    matches.add(<String, Object?>{...entry, 'matchKind': matchKind});
  }
  final readyMatches = matches
      .where(
        (entry) => _terminalMatrixReviewStatusIsReady(entry['reviewStatus']),
      )
      .toList();
  final nonReadyMatches = matches
      .where(
        (entry) => !_terminalMatrixReviewStatusIsReady(entry['reviewStatus']),
      )
      .toList();
  final nonReadyStatuses = <String>{
    for (final entry in nonReadyMatches)
      entry['reviewStatus']?.toString() ?? 'unknown',
  }.toList()..sort();
  final collectionPlan = _terminalMatrixCollectionPlanItem(target);
  final covered = readyMatches.isNotEmpty;
  return <String, Object?>{
    'target': target,
    'targetSlug': targetSlug,
    'covered': covered,
    'readyEntryCount': readyMatches.length,
    'nonReadyEntryCount': nonReadyMatches.length,
    'nonReadyReviewStatuses': nonReadyStatuses,
    'nextAction': covered
        ? 'complete'
        : nonReadyMatches.isNotEmpty
        ? 'review-or-recapture'
        : 'capture',
    'suggestedLabel': collectionPlan['suggestedLabel'],
    'suggestedCaptureCommand': collectionPlan['suggestedCaptureCommand'],
    if (collectionPlan['note'] != null)
      'collectionNote': collectionPlan['note'],
    'matchedEntries': <Object?>[
      for (final entry in matches)
        <String, Object?>{
          'label': entry['label'],
          'path': entry['path'],
          'reviewStatus': entry['reviewStatus'],
          'matchKind': entry['matchKind'],
        },
    ],
  };
}

bool _terminalMatrixReviewStatusIsReady(Object? status) {
  return status == 'readyForReview' || status == 'acceptedForLaunch';
}

Map<String, Object?> _terminalMatrixCollectionPlanItem(String target) {
  final targetSlug = _slug(target);
  final suggestedLabel = switch (targetSlug) {
    'tmux' => 'tmux-terminal',
    'ssh' => 'ssh-terminal',
    _ => target,
  };
  final note = switch (targetSlug) {
    'tmux' => 'Run from inside tmux and keep the context first in the label.',
    'ssh' => 'Run over SSH and keep the context first in the label.',
    'windows-terminal' =>
      'Run on a real Windows host inside Windows Terminal and add profile/shell/version context with --review-note.',
    'windows-conhost' =>
      'Run in classic Windows Console Host/conhost, not Windows Terminal.',
    'windows-powershell' =>
      'Run from a PowerShell host on Windows and note whether the wrapper is Windows Terminal, conhost, or an IDE.',
    'windows-ide' =>
      'Run from a Windows IDE integrated terminal and include IDE/version context with --review-note.',
    _ => null,
  };
  return <String, Object?>{
    'target': target,
    'suggestedLabel': suggestedLabel,
    'suggestedCaptureCommand': <String>[
      'dart',
      'tool/fleury_dev.dart',
      'terminal-matrix',
      '--label=$suggestedLabel',
    ],
    if (note != null) 'note': note,
  };
}

String? _terminalMatrixTargetMatchKind({
  required String targetSlug,
  required String labelSlug,
}) {
  if (labelSlug == targetSlug) return 'exact';

  // The tmux and SSH launch targets are context checks rather than clean
  // terminal brands. Labels like `tmux-kitty` and `ssh-iterm2` should cover
  // those targets with context-specific evidence rather than being reported as
  // generic clean target-prefix matches.
  if (targetSlug == 'tmux' || targetSlug == 'ssh') {
    final token = '-$targetSlug';
    if (labelSlug.startsWith('$targetSlug-') ||
        labelSlug.endsWith(token) ||
        labelSlug.contains('$token-')) {
      return 'contextToken';
    }
  }

  // Clean terminal captures often include a version/profile suffix, such as
  // `iterm2-3-5` or `windows-terminal-pwsh`. Do not let context-prefixed
  // labels such as `tmux-iterm2` satisfy the clean terminal target.
  if (labelSlug.startsWith('$targetSlug-')) return 'targetPrefix';

  return null;
}

void _printTerminalMatrixAudit(Map<String, Object?> audit) {
  final entryCount = audit['entryCount'];
  final invalidEntryCount = audit['invalidEntryCount'];
  final reviewStatusCounts = _object(audit['reviewStatusCounts']);
  final platformCounts = _object(audit['platformCounts']);
  final missingTargets = _list(audit['missingTargets']);
  final targetsNeedingReview = _list(audit['targetsNeedingReview']);
  final targets = _list(audit['targets']);
  final entries = _list(audit['entries']);
  final coveredTargets = targets.where((target) {
    return target is Map<String, Object?> && target['covered'] == true;
  }).length;
  final fallbackCount = _sumEntryInt(entries, 'fallbackCount');
  final warningCount = _sumEntryInt(entries, 'warningCount');
  final unsupportedFeatureCount = _sumEntryInt(
    entries,
    'unsupportedFeatureCount',
  );

  stdout.writeln('Terminal matrix audit: ${audit['directory']}');
  stdout.writeln(
    'Entries: $entryCount '
    '(invalid: $invalidEntryCount, review: $reviewStatusCounts)',
  );
  if (platformCounts.isNotEmpty) {
    stdout.writeln('Platforms: $platformCounts');
  }
  if (entries.isNotEmpty) {
    stdout.writeln(
      'Diagnostics: $fallbackCount fallbacks, $warningCount warnings, '
      '$unsupportedFeatureCount unsupported features',
    );
  }
  stdout.writeln('Targets ready: $coveredTargets/${targets.length}');
  final readyDescriptions = <String>[];
  for (final target in targets) {
    if (target is! Map<String, Object?> || target['covered'] != true) {
      continue;
    }
    final targetName = target['target'];
    final readyMatches = _list(target['matchedEntries'])
        .where((match) {
          return match is Map<String, Object?> &&
              _terminalMatrixReviewStatusIsReady(match['reviewStatus']);
        })
        .cast<Map<String, Object?>>()
        .toList();
    if (readyMatches.isEmpty) continue;
    final first = readyMatches.first;
    readyDescriptions.add(
      '$targetName -> ${first['label']} (${first['matchKind']})',
    );
  }
  if (readyDescriptions.isNotEmpty) {
    stdout.writeln('Ready target entries: ${readyDescriptions.join(', ')}');
  }
  if (targetsNeedingReview.isNotEmpty) {
    stdout.writeln(
      'Targets with non-ready captures: ${targetsNeedingReview.join(', ')}',
    );
    for (final target in targets) {
      if (target is! Map<String, Object?> ||
          target['covered'] == true ||
          (target['nonReadyEntryCount'] as int? ?? 0) == 0) {
        continue;
      }
      stdout.writeln(
        '  ${target['target']}: review existing ${target['nonReadyEntryCount']} '
        'capture(s) or recapture with '
        '${_displayCommand(_list(target['suggestedCaptureCommand']))}',
      );
    }
  }
  if (missingTargets.isNotEmpty) {
    stdout.writeln('Missing ready targets: ${missingTargets.join(', ')}');
    stdout.writeln('Suggested missing-target captures:');
    for (final item in _list(audit['collectionPlan'])) {
      if (item is! Map<String, Object?>) continue;
      stdout.writeln(
        '  ${item['target']}: '
        '${_displayCommand(_list(item['suggestedCaptureCommand']))}',
      );
      if (item['note'] case final note?) {
        stdout.writeln('    note: $note');
      }
    }
  }

  for (final invalid in _list(audit['invalidEntries'])) {
    if (invalid is! Map<String, Object?>) continue;
    stdout.writeln('Invalid: ${invalid['path']} - ${invalid['issue']}');
  }
}

String _terminalMatrixAuditPlanMarkdown(Map<String, Object?> audit) {
  final buffer = StringBuffer()
    ..writeln('# Terminal Matrix Collection Plan')
    ..writeln()
    ..writeln('**Directory:** ${audit['directory']}')
    ..writeln(
      '**Targets ready:** ${audit['readyTargetCount']}/${audit['targetCount']}',
    )
    ..writeln(
      '**Entries:** ${audit['entryCount']} '
      '(invalid: ${audit['invalidEntryCount']})',
    )
    ..writeln();

  buffer
    ..writeln(
      'Run each capture command from the actual terminal, tmux session,',
    )
    ..writeln(
      'SSH session, or Windows host named by the target. Do not collect',
    )
    ..writeln('launch evidence from an IDE output panel, CI pipe, or non-TTY')
    ..writeln('wrapper unless the entry is intentionally a control case.')
    ..writeln();

  final invalidEntries = _list(audit['invalidEntries']);
  if (invalidEntries.isNotEmpty) {
    buffer
      ..writeln('## Invalid Entries')
      ..writeln();
    for (final invalid in invalidEntries) {
      if (invalid is! Map<String, Object?>) continue;
      buffer.writeln('- `${invalid['path']}`: ${invalid['issue']}');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Targets')
    ..writeln();

  for (final target in _list(audit['targets'])) {
    if (target is! Map<String, Object?>) continue;
    final name = target['target'];
    final nextAction = target['nextAction'];
    final command = _displayCommand(_list(target['suggestedCaptureCommand']));
    buffer
      ..writeln('### $name')
      ..writeln()
      ..writeln(
        '- Status: ${target['covered'] == true ? 'ready' : 'not ready'}',
      )
      ..writeln('- Next action: $nextAction');
    if (nextAction == 'capture') {
      buffer.writeln('- Capture: `$command`');
    } else if (nextAction == 'review-or-recapture') {
      buffer.writeln('- Recapture if review cannot clear issues: `$command`');
    }
    if (target['collectionNote'] case final note?) {
      buffer.writeln('- Note: $note');
    }
    final matchedEntries = _list(target['matchedEntries']);
    if (matchedEntries.isNotEmpty) {
      buffer.writeln('- Matched entries:');
      for (final match in matchedEntries) {
        if (match is! Map<String, Object?>) continue;
        buffer.writeln(
          '  - `${match['label']}` (${match['reviewStatus']}, '
          '${match['matchKind']}): ${match['path']}',
        );
      }
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Review Checklist')
    ..writeln()
    ..writeln('- Entry was captured in the named terminal.')
    ..writeln('- `review.status` is `readyForReview` or `acceptedForLaunch`.')
    ..writeln(
      '- `stdinIsTerminal` and `stdoutIsTerminal` are true for interactive entries.',
    )
    ..writeln('- Active probes are not skipped for interactive entries.')
    ..writeln('- Unexpected passive-unverified findings are reviewed.')
    ..writeln('- Accepted entries preserve reviewer notes and original issues.')
    ..writeln('- tmux and SSH entries keep the context first in the label.')
    ..writeln();

  return buffer.toString();
}

String _terminalMatrixAuditReviewMarkdown(Map<String, Object?> audit) {
  final buffer = StringBuffer()
    ..writeln('# Terminal Matrix Review Packet')
    ..writeln()
    ..writeln('**Directory:** ${audit['directory']}')
    ..writeln(
      '**Targets ready:** ${audit['readyTargetCount']}/${audit['targetCount']}',
    )
    ..writeln(
      '**Entries:** ${audit['entryCount']} '
      '(invalid: ${audit['invalidEntryCount']})',
    )
    ..writeln('**Strict pass:** ${audit['strictPass']}')
    ..writeln();

  buffer
    ..writeln(
      'Use this packet to review collected terminal evidence target by target.',
    )
    ..writeln(
      'It is generated from the same audit model as the strict gate; do not',
    )
    ..writeln(
      'treat an entry as launch evidence until the source JSON review status',
    )
    ..writeln('is ready and the checklist item below has been reviewed.')
    ..writeln();

  final invalidEntries = _list(audit['invalidEntries']);
  if (invalidEntries.isNotEmpty) {
    buffer
      ..writeln('## Invalid Entries')
      ..writeln();
    for (final invalid in invalidEntries) {
      if (invalid is! Map<String, Object?>) continue;
      buffer.writeln('- [ ] `${invalid['path']}`: ${invalid['issue']}');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Target Review')
    ..writeln();

  final matchedEntryPaths = <String>{};
  for (final target in _list(audit['targets'])) {
    if (target is! Map<String, Object?>) continue;
    final targetName = target['target'];
    final nextAction = target['nextAction'];
    final command = _displayCommand(_list(target['suggestedCaptureCommand']));
    buffer
      ..writeln('### $targetName')
      ..writeln()
      ..writeln(
        '- Status: ${target['covered'] == true ? 'ready' : 'not ready'}',
      )
      ..writeln('- Next action: $nextAction');
    if (nextAction == 'capture') {
      buffer.writeln('- Capture: `$command`');
    } else if (nextAction == 'review-or-recapture') {
      buffer.writeln('- Recapture if review cannot clear issues: `$command`');
    }
    if (target['collectionNote'] case final note?) {
      buffer.writeln('- Note: $note');
    }

    final matchedEntries = _list(target['matchedEntries']);
    if (matchedEntries.isEmpty) {
      buffer.writeln();
      continue;
    }

    buffer
      ..writeln()
      ..writeln('Matched entries:');
    for (final match in matchedEntries) {
      if (match is! Map<String, Object?>) continue;
      final entry = _terminalMatrixAuditEntryForMatch(audit, match);
      final path = match['path']?.toString();
      if (path != null) matchedEntryPaths.add(path);
      _writeTerminalMatrixReviewEntry(
        buffer,
        match: match,
        entry: entry,
        indent: '  ',
      );
    }
    buffer.writeln();
  }

  final unmatchedEntries = <Map<String, Object?>>[];
  for (final entry in _list(audit['entries'])) {
    if (entry is! Map<String, Object?>) continue;
    final path = entry['path']?.toString();
    if (path == null || matchedEntryPaths.contains(path)) continue;
    unmatchedEntries.add(entry);
  }
  if (unmatchedEntries.isNotEmpty) {
    buffer
      ..writeln('## Unmatched Entries')
      ..writeln();
    for (final entry in unmatchedEntries) {
      _writeTerminalMatrixReviewEntry(
        buffer,
        match: entry,
        entry: entry,
        indent: '',
      );
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Review Checklist')
    ..writeln()
    ..writeln('- [ ] Entry labels match the actual terminal/session context.')
    ..writeln('- [ ] Accepted entries preserve reviewer notes and original')
    ..writeln('      issues in `review.acceptanceNotes` / `review.issues`.')
    ..writeln('- [ ] `stdinIsTerminal` and `stdoutIsTerminal` are true for')
    ..writeln('      interactive launch evidence.')
    ..writeln('- [ ] Active probes are not skipped for interactive entries.')
    ..writeln('- [ ] Unexpected passive-unverified, fallback, warning, and')
    ..writeln('      unsupported-feature findings are explained.')
    ..writeln('- [ ] tmux and SSH entries keep the context first in the label.')
    ..writeln(
      '- [ ] Non-ready entries were either recaptured or explicitly kept as',
    )
    ..writeln('      control/degradation evidence, not launch coverage.')
    ..writeln();

  return buffer.toString();
}

void _printMvpReadinessAudit(Map<String, Object?> readiness) {
  final launch = _object(readiness['launchTerminalEvidence']);
  final windows = _object(readiness['windowsValidationEvidence']);
  final blockers = _list(readiness['remainingBlockers']);
  stdout.writeln(
    'Fleury MVP readiness: ${readiness['strictPass'] == true ? 'ready' : 'not ready'}',
  );
  stdout.writeln('Matrix directory: ${readiness['directory']}');
  stdout.writeln(
    'Launch terminal evidence: ${launch['readyTargetCount']}/${launch['targetCount']} ready',
  );
  stdout.writeln(
    'Post-MVP Windows validation evidence: ${windows['readyTargetCount']}/${windows['targetCount']} ready',
  );
  if (blockers.isNotEmpty) {
    stdout.writeln('Remaining blockers:');
    for (final blocker in blockers) {
      stdout.writeln('  - $blocker');
    }
  }
  final deferred = _list(readiness['deferredOutOfMvp']);
  if (deferred.isNotEmpty) {
    stdout.writeln('Deferred out of MVP:');
    for (final item in deferred) {
      stdout.writeln('  - $item');
    }
  }
}

String _mvpReadinessAuditMarkdown(Map<String, Object?> readiness) {
  final launch = _object(readiness['launchTerminalEvidence']);
  final windows = _object(readiness['windowsValidationEvidence']);
  final local = _object(readiness['localImplementationEvidence']);
  final launchMissingTargets = _list(launch['missingTargets']);
  final windowsMissingTargets = _list(windows['missingTargets']);
  final buffer = StringBuffer()
    ..writeln('# Fleury MVP Readiness Audit')
    ..writeln()
    ..writeln('**Directory:** ${readiness['directory']}')
    ..writeln('**Strict pass:** ${readiness['strictPass']}')
    ..writeln(
      '**Launch terminal targets ready:** '
      '${launch['readyTargetCount']}/${launch['targetCount']}',
    )
    ..writeln(
      '**Post-MVP Windows validation targets ready:** '
      '${windows['readyTargetCount']}/${windows['targetCount']}',
    )
    ..writeln('**Windows validation MVP status:** ${windows['mvpStatus']}')
    ..writeln()
    ..writeln('## Local Implementation Evidence')
    ..writeln()
    ..writeln('- Status: ${local['status']}')
    ..writeln('- Audit: ${local['auditPath']}')
    ..writeln('- Note: ${local['note']}')
    ..writeln()
    ..writeln('## Remaining Blockers')
    ..writeln();

  final blockers = _list(readiness['remainingBlockers']);
  if (blockers.isEmpty) {
    buffer.writeln('- None.');
  } else {
    for (final blocker in blockers) {
      buffer.writeln('- [ ] $blocker');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Evidence Gates')
    ..writeln()
    ..writeln('- Final MVP gate: `dart tool/fleury_dev.dart mvp-final-gate`')
    ..writeln(
      '- Launch terminal strict gate: '
      '`dart tool/fleury_dev.dart terminal-matrix-audit --strict`',
    )
    ..writeln('- Local RC gate: `dart tool/fleury_dev.dart check`')
    ..writeln()
    ..writeln('## Missing Targets')
    ..writeln()
    ..writeln(
      '- Launch terminal matrix: '
      '${launchMissingTargets.isEmpty ? 'None.' : launchMissingTargets.join(', ')}',
    )
    ..writeln()
    ..writeln('## Post-MVP Windows Validation')
    ..writeln()
    ..writeln(
      '- Status: deferred out of MVP; current evidence '
      '${windows['readyTargetCount']}/${windows['targetCount']} ready.',
    )
    ..writeln(
      '- Strict gate for the later Windows pass: '
      '`dart tool/fleury_dev.dart terminal-matrix-audit --target-preset=windows --strict`',
    )
    ..writeln(
      '- Missing Windows targets: '
      '${windowsMissingTargets.isEmpty ? 'None.' : windowsMissingTargets.join(', ')}',
    )
    ..writeln()
    ..writeln('## Deferred Out Of MVP')
    ..writeln();

  for (final item in _list(readiness['deferredOutOfMvp'])) {
    buffer.writeln('- $item');
  }
  buffer.writeln();

  return buffer.toString();
}

Map<String, Object?>? _terminalMatrixAuditEntryForMatch(
  Map<String, Object?> audit,
  Map<String, Object?> match,
) {
  final path = match['path']?.toString();
  final label = match['label']?.toString();
  for (final entry in _list(audit['entries'])) {
    if (entry is! Map<String, Object?>) continue;
    if (path != null && entry['path']?.toString() == path) return entry;
    if (label != null && entry['label']?.toString() == label) return entry;
  }
  return null;
}

void _writeTerminalMatrixReviewEntry(
  StringBuffer buffer, {
  required Map<String, Object?> match,
  required Map<String, Object?>? entry,
  required String indent,
}) {
  final label = match['label'] ?? entry?['label'] ?? '(unknown)';
  final reviewStatus =
      match['reviewStatus'] ?? entry?['reviewStatus'] ?? 'unknown';
  final matchKind = match['matchKind'];
  final matchSuffix = matchKind == null ? '' : ', $matchKind';
  buffer.writeln('$indent- [ ] `$label` (`$reviewStatus`$matchSuffix)');

  final detail = entry ?? match;
  void writeDetail(String key, Object? value) {
    if (value == null) return;
    if (value is String && value.isEmpty) return;
    buffer.writeln('$indent  - $key: $value');
  }

  writeDetail('Path', detail['path']);
  writeDetail('Platform', detail['operatingSystem']);
  writeDetail('Dart', detail['dartVersion']);
  writeDetail(
    'Terminal',
    [
      detail['term'],
      detail['termProgram'],
    ].where((value) => value != null && value.toString().isNotEmpty).join(' '),
  );
  writeDetail('Interactive', detail['isInteractive']);
  writeDetail(
    'stdin/stdout',
    '${detail['stdinIsTerminal']}/${detail['stdoutIsTerminal']}',
  );
  writeDetail('tmux/ssh', '${detail['tmux']}/${detail['ssh']}');
  writeDetail('Active probes', detail['activeProbeSummary']);
  writeDetail('Compatibility', detail['compatibilitySummary']);
  writeDetail('Fallbacks', detail['fallbackCount']);
  writeDetail('Warnings', detail['warningCount']);
  writeDetail('Unsupported features', detail['unsupportedFeatureCount']);

  final issueValues = _list(detail['issues']);
  if (issueValues.isNotEmpty) {
    buffer.writeln('$indent  - Issues:');
    for (final issue in issueValues) {
      buffer.writeln('$indent    - $issue');
    }
  }
  final noteValues = _list(detail['notes']);
  if (noteValues.isNotEmpty) {
    buffer.writeln('$indent  - Notes:');
    for (final note in noteValues) {
      buffer.writeln('$indent    - $note');
    }
  }
}

int _sumEntryInt(List<Object?> entries, String key) {
  var sum = 0;
  for (final entry in entries) {
    if (entry is! Map<String, Object?>) continue;
    final value = entry[key];
    if (value is int) {
      sum += value;
    } else if (value is num) {
      sum += value.toInt();
    }
  }
  return sum;
}

bool _terminalMatrixAuditStrictPass(Map<String, Object?> audit) {
  final strictPass = audit['strictPass'];
  if (strictPass is bool) return strictPass;
  return _list(audit['missingTargets']).isEmpty &&
      (audit['invalidEntryCount'] == 0);
}

String _displayCommand(List<Object?> command) {
  return command
      .map((part) {
        final text = part.toString();
        return text.contains(' ') ? '"$text"' : text;
      })
      .join(' ');
}

Map<String, Object?> _readBenchmarkManifest(
  String text, {
  required String source,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    stderr.writeln('Benchmark manifest is not valid JSON: $error');
    exit(1);
  }
  final manifest = _object(decoded);
  final errors = _benchmarkManifestErrors(manifest);
  if (errors.isNotEmpty) {
    stderr.writeln('Benchmark manifest is invalid: $source');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    exit(1);
  }
  return manifest;
}

List<String> _benchmarkManifestErrors(Map<String, Object?> manifest) {
  final errors = <String>[];
  if (manifest['kind'] != 'fleuryComparativeBenchmarkManifest') {
    errors.add('kind must be fleuryComparativeBenchmarkManifest');
  }
  if (manifest['schemaVersion'] != 1) {
    errors.add('schemaVersion must be 1');
  }

  final peers = _list(manifest['peers']);
  if (peers.isEmpty) errors.add('peers must not be empty');
  final peerIds = <String>{};
  for (final peer in peers) {
    final object = _object(peer);
    final id = object['id']?.toString() ?? '';
    if (id.isEmpty) {
      errors.add('peer is missing id');
    } else if (!peerIds.add(id)) {
      errors.add('duplicate peer id: $id');
    }
    if ((object['name']?.toString() ?? '').isEmpty) {
      errors.add('peer $id is missing name');
    }
  }

  final scenarios = _list(manifest['scenarios']);
  if (scenarios.isEmpty) errors.add('scenarios must not be empty');
  final scenarioIds = <String>{};
  for (final scenario in scenarios) {
    final object = _object(scenario);
    final id = object['id']?.toString() ?? '';
    if (id.isEmpty) {
      errors.add('scenario is missing id');
      continue;
    }
    if (!scenarioIds.add(id)) errors.add('duplicate scenario id: $id');
    if ((object['name']?.toString() ?? '').isEmpty) {
      errors.add('scenario $id is missing name');
    }
    final local = _object(object['local']);
    if ((local['workingDirectory']?.toString() ?? '').isEmpty) {
      errors.add('scenario $id local.workingDirectory is missing');
    }
    if (_list(local['command']).isEmpty) {
      errors.add('scenario $id local.command must not be empty');
    }
    final peerTargets = _list(
      object['peerTargets'],
    ).map((target) => target.toString()).toList(growable: false);
    if (peerTargets.isEmpty) {
      errors.add('scenario $id peerTargets must not be empty');
    }
    for (final target in peerTargets) {
      if (!peerIds.contains(target)) {
        errors.add('scenario $id targets unknown peer: $target');
      }
    }
    if (_list(object['contract']).isEmpty) {
      errors.add('scenario $id contract must not be empty');
    }
    if (_list(object['requiredMetrics']).isEmpty) {
      errors.add('scenario $id requiredMetrics must not be empty');
    }
    if (_list(object['claimGates']).isEmpty) {
      errors.add('scenario $id claimGates must not be empty');
    }
  }

  return errors;
}

void _printBenchmarkManifest(Map<String, Object?> manifest) {
  final peers = _list(manifest['peers']);
  final scenarios = _list(manifest['scenarios']);
  stdout.writeln('Comparative benchmark manifest');
  stdout.writeln('Status: ${manifest['status']}');
  stdout.writeln('Last source refresh: ${manifest['lastSourceRefresh']}');
  stdout.writeln('Peers: ${peers.length}');
  stdout.writeln('Scenarios: ${scenarios.length}');
  stdout.writeln('');
  for (final scenario in scenarios) {
    final object = _object(scenario);
    final local = _object(object['local']);
    final id = object['id'];
    final name = object['name'];
    final workingDirectory = local['workingDirectory'];
    final command = _displayCommand(_list(local['command']));
    stdout.writeln('$id $name');
    stdout.writeln('  local: ($workingDirectory) $command');
    stdout.writeln('  peers: ${_list(object['peerTargets']).join(', ')}');
  }
}

Map<String, Object?> _readBenchmarkPeerRun(
  String text, {
  required Map<String, Object?> manifest,
  required String source,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    stderr.writeln('Benchmark peer run is not valid JSON: $error');
    exit(1);
  }
  final peerRun = _object(decoded);
  final errors = _benchmarkPeerRunErrors(peerRun, manifest);
  if (errors.isNotEmpty) {
    stderr.writeln('Benchmark peer run is invalid: $source');
    for (final error in errors) {
      stderr.writeln('  - $error');
    }
    exit(1);
  }
  return _normalizedBenchmarkPeerRun(peerRun);
}

List<String> _benchmarkPeerRunErrors(
  Map<String, Object?> peerRun,
  Map<String, Object?> manifest,
) {
  final errors = <String>[];
  if (peerRun['kind'] != 'fleuryPeerBenchmarkRun') {
    errors.add('kind must be fleuryPeerBenchmarkRun');
  }
  if (peerRun['schemaVersion'] != 1) {
    errors.add('schemaVersion must be 1');
  }

  final runId = (peerRun['runId'] ?? '').toString();
  final peerId = (peerRun['peerId'] ?? '').toString();
  final scenarioId = (peerRun['scenarioId'] ?? '').toString();
  final capturedAt = (peerRun['capturedAt'] ?? '').toString();
  if (runId.isEmpty) errors.add('runId is missing');
  if (peerId.isEmpty) errors.add('peerId is missing');
  if (scenarioId.isEmpty) errors.add('scenarioId is missing');
  if (capturedAt.isEmpty) {
    errors.add('capturedAt is missing');
  } else if (DateTime.tryParse(capturedAt) == null) {
    errors.add('capturedAt must be an ISO-8601 timestamp');
  }

  final peerIds = _benchmarkPeerIds(manifest);
  if (peerId.isNotEmpty && !peerIds.contains(peerId)) {
    errors.add('unknown peerId: $peerId');
  }
  final scenario = _benchmarkScenario(manifest, scenarioId);
  if (scenarioId.isNotEmpty && scenario == null) {
    errors.add('unknown scenarioId: $scenarioId');
  }
  if (scenario != null && peerId.isNotEmpty) {
    final peerTargets = _stringList(scenario['peerTargets']);
    if (!peerTargets.contains(peerId)) {
      errors.add('peer $peerId is not a target for scenario $scenarioId');
    }
  }

  final source = _object(peerRun['source']);
  if ((source['name'] ?? '').toString().isEmpty) {
    errors.add('source.name is missing');
  }
  if ((source['version'] ?? '').toString().isEmpty) {
    errors.add('source.version is missing');
  }
  if ((source['url'] ?? '').toString().isEmpty) {
    errors.add('source.url is missing');
  }

  final environment = _object(peerRun['environment']);
  for (final field in [
    'machine',
    'operatingSystem',
    'runtime',
    'terminalMode',
  ]) {
    if ((environment[field] ?? '').toString().isEmpty) {
      errors.add('environment.$field is missing');
    }
  }
  final terminalSize = _object(environment['terminalSize']);
  if (terminalSize['columns'] is! num || terminalSize['rows'] is! num) {
    errors.add('environment.terminalSize.columns/rows are required');
  }

  final fixture = _object(peerRun['fixture']);
  if ((fixture['workingDirectory'] ?? '').toString().isEmpty) {
    errors.add('fixture.workingDirectory is missing');
  }
  if (_list(fixture['command']).isEmpty) {
    errors.add('fixture.command must not be empty');
  }
  if (fixture['warmupIterations'] is! num) {
    errors.add('fixture.warmupIterations is missing');
  }
  if (fixture['measuredIterations'] is! num) {
    errors.add('fixture.measuredIterations is missing');
  }

  final metrics = _object(peerRun['metrics']);
  if (metrics.isEmpty) errors.add('metrics must not be empty');
  if (scenario != null) {
    for (final metric in _stringList(scenario['requiredMetrics'])) {
      if (!metrics.containsKey(metric)) {
        errors.add('missing required metric for $scenarioId: $metric');
      }
    }
  }

  final correctness = _list(peerRun['correctness']);
  if (correctness.isEmpty) {
    errors.add('correctness must not be empty');
  }
  final gates = <String, bool>{};
  for (final entry in correctness) {
    final object = _object(entry);
    final gate = (object['gate'] ?? '').toString();
    if (gate.isEmpty) {
      errors.add('correctness entry is missing gate');
      continue;
    }
    final pass = object['pass'];
    if (pass is! bool) {
      errors.add('correctness gate $gate is missing boolean pass');
      continue;
    }
    gates[gate] = pass;
  }
  if (scenario != null) {
    for (final gate in _stringList(scenario['claimGates'])) {
      if (!gates.containsKey(gate)) {
        errors.add('missing claim gate for $scenarioId: $gate');
      } else if (gates[gate] != true) {
        errors.add('claim gate did not pass for $scenarioId: $gate');
      }
    }
  }

  return errors;
}

Map<String, Object?> _normalizedBenchmarkPeerRun(Map<String, Object?> peerRun) {
  final result = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryPeerBenchmarkRun',
    'runId': peerRun['runId'],
    'peerId': peerRun['peerId'],
    'scenarioId': peerRun['scenarioId'],
    'capturedAt': peerRun['capturedAt'],
    'source': _object(peerRun['source']),
    'environment': _object(peerRun['environment']),
    'fixture': _object(peerRun['fixture']),
    'metrics': _object(peerRun['metrics']),
    'correctness': _list(peerRun['correctness']),
    'pass': true,
  };
  final ergonomics = _object(peerRun['ergonomics']);
  if (ergonomics.isNotEmpty) result['ergonomics'] = ergonomics;
  final artifacts = _list(peerRun['artifacts']);
  if (artifacts.isNotEmpty) result['artifacts'] = artifacts;
  final notes = _list(peerRun['notes']);
  if (notes.isNotEmpty) result['notes'] = notes;
  return result;
}

Map<String, Object?> _mergeBenchmarkPeerRun(
  Map<String, Object?> manifest,
  Map<String, Object?> peerRun,
) {
  final scenarioId = peerRun['scenarioId'].toString();
  final runId = peerRun['runId'].toString();
  final scenarios = <Object?>[];
  for (final scenario in _list(manifest['scenarios'])) {
    final object = Map<String, Object?>.of(_object(scenario));
    if (object['id']?.toString() == scenarioId) {
      object['peerRuns'] = <Object?>[
        for (final existing in _list(object['peerRuns']))
          if (_object(existing)['runId']?.toString() != runId) existing,
        peerRun,
      ];
    }
    scenarios.add(object);
  }
  return <String, Object?>{...manifest, 'scenarios': scenarios};
}

Map<String, Object?> _benchmarkPeerRunSummary(
  Map<String, Object?> manifest,
  Map<String, Object?> peerRun, {
  String? outputPath,
}) {
  final scenario = _benchmarkScenario(
    manifest,
    peerRun['scenarioId'].toString(),
  );
  final requiredMetrics = scenario == null
      ? const <String>[]
      : _stringList(scenario['requiredMetrics']);
  final claimGates = scenario == null
      ? const <String>[]
      : _stringList(scenario['claimGates']);
  return <String, Object?>{
    'accepted': true,
    'runId': peerRun['runId'],
    'peerId': peerRun['peerId'],
    'scenarioId': peerRun['scenarioId'],
    if (scenario != null) 'scenarioName': scenario['name'],
    'requiredMetricCount': requiredMetrics.length,
    'claimGateCount': claimGates.length,
    if (outputPath != null) 'outputPath': outputPath,
  };
}

void _printBenchmarkPeerRunSummary(Map<String, Object?> summary) {
  stdout.writeln('Benchmark peer run accepted');
  stdout.writeln('Run: ${summary['runId']}');
  stdout.writeln('Peer: ${summary['peerId']}');
  stdout.writeln(
    'Scenario: ${summary['scenarioId']} ${summary['scenarioName'] ?? ''}',
  );
  stdout.writeln('Required metrics: ${summary['requiredMetricCount']}');
  stdout.writeln('Claim gates: ${summary['claimGateCount']}');
  if (summary['outputPath'] != null) {
    stdout.writeln('Wrote ${summary['outputPath']}');
  }
}

List<File> _benchmarkVarianceInputFiles({
  required String root,
  required List<String> inputPaths,
}) {
  final files = <File>[];
  final seen = <String>{};
  for (final inputPath in inputPaths) {
    final type = FileSystemEntity.typeSync(inputPath, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        if (inputPath.endsWith('.json') && seen.add(inputPath)) {
          files.add(File(inputPath));
        }
      case FileSystemEntityType.directory:
        final directory = Directory(inputPath);
        final directoryFiles =
            directory
                .listSync(followLinks: false)
                .whereType<File>()
                .where((file) => file.path.endsWith('.json'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in directoryFiles) {
          if (seen.add(file.path)) files.add(file);
        }
      case FileSystemEntityType.notFound:
        stderr.writeln(
          'Benchmark variance input not found: ${_relativePath(root, inputPath)}',
        );
        exit(1);
      default:
        stderr.writeln(
          'Benchmark variance input is not a file or directory: '
          '${_relativePath(root, inputPath)}',
        );
        exit(1);
    }
  }
  return files;
}

Map<String, Object?> _buildBenchmarkVariance({
  required Map<String, Object?> manifest,
  required List<Map<String, Object?>> peerRuns,
  required List<String> runPaths,
  required int minRuns,
}) {
  final errors = <String>[];
  final peerIds = _uniqueBenchmarkValues(peerRuns, 'peerId');
  final scenarioIds = _uniqueBenchmarkValues(peerRuns, 'scenarioId');
  if (peerRuns.isEmpty) {
    errors.add('at least one peer run is required');
  }
  if (peerIds.length > 1) {
    errors.add('all peer runs must share one peerId: ${peerIds.join(', ')}');
  }
  if (scenarioIds.length > 1) {
    errors.add(
      'all peer runs must share one scenarioId: ${scenarioIds.join(', ')}',
    );
  }

  final peerId = peerIds.isEmpty ? 'unknown' : peerIds.single;
  final scenarioId = scenarioIds.isEmpty ? 'unknown' : scenarioIds.single;
  final scenario = scenarioIds.length == 1
      ? _benchmarkScenario(manifest, scenarioId)
      : null;
  final requiredMetrics = scenario == null
      ? const <String>[]
      : _stringList(scenario['requiredMetrics']);

  final sourceVersions = _benchmarkNestedValues(peerRuns, [
    'source',
    'version',
  ]);
  final terminalModes = _benchmarkNestedValues(peerRuns, [
    'environment',
    'terminalMode',
  ]);
  final terminalSizes = <String>{
    for (final run in peerRuns) _benchmarkTerminalSizeKey(run),
  }.where((value) => value.isNotEmpty).toList(growable: false);
  final fixtureDirectories = _benchmarkNestedValues(peerRuns, [
    'fixture',
    'workingDirectory',
  ]);
  final fixtureCommands = <String>{
    for (final run in peerRuns)
      _displayCommand(_list(_object(run['fixture'])['command'])),
  }.where((value) => value.isNotEmpty).toList(growable: false);

  final comparableIssues = <String>[];
  void checkComparable(String name, List<String> values) {
    if (values.length > 1) {
      comparableIssues.add('$name differs: ${values.join(' | ')}');
    }
  }

  checkComparable('source.version', sourceVersions);
  checkComparable('environment.terminalMode', terminalModes);
  checkComparable('environment.terminalSize', terminalSizes);
  checkComparable('fixture.workingDirectory', fixtureDirectories);
  checkComparable('fixture.command', fixtureCommands);
  final comparable = comparableIssues.isEmpty && errors.isEmpty;
  final sufficientRunCount = peerRuns.length >= minRuns;
  if (!sufficientRunCount) {
    errors.add('runCount ${peerRuns.length} is below minRuns $minRuns');
  }

  final metricReports = <String, Object?>{};
  for (final metric in requiredMetrics) {
    final values = <double>[];
    String? primaryPath;
    for (final run in peerRuns) {
      final metrics = _object(run['metrics']);
      final primary = _benchmarkMetricPrimary(metrics[metric]);
      if (primary == null) {
        errors.add(
          'metric $metric does not have a numeric scalar, p95, median, max, '
          'or value field in run ${run['runId']}',
        );
        continue;
      }
      primaryPath ??= primary.key;
      if (primaryPath != primary.key) {
        errors.add(
          'metric $metric uses inconsistent primary value paths: '
          '$primaryPath and ${primary.key}',
        );
      }
      values.add(primary.value);
    }
    if (values.isNotEmpty) {
      metricReports[metric] = <String, Object?>{
        'primaryValue': primaryPath,
        ..._benchmarkNumberStats(values),
      };
    }
  }

  final gateCounts = <String, Map<String, int>>{};
  for (final run in peerRuns) {
    for (final entry in _list(run['correctness'])) {
      final object = _object(entry);
      final gate = object['gate']?.toString() ?? '';
      if (gate.isEmpty) continue;
      final counts = gateCounts.putIfAbsent(
        gate,
        () => <String, int>{'pass': 0, 'fail': 0},
      );
      if (object['pass'] == true) {
        counts['pass'] = counts['pass']! + 1;
      } else {
        counts['fail'] = counts['fail']! + 1;
      }
    }
  }
  final correctness = <String, Object?>{
    'allRunsPass': gateCounts.values.every((counts) => counts['fail'] == 0),
    'gates': <String, Object?>{
      for (final entry in gateCounts.entries)
        entry.key: <String, Object?>{
          'passCount': entry.value['pass'],
          'failCount': entry.value['fail'],
        },
    },
  };

  final warmupIterations = <double>[];
  final measuredIterations = <double>[];
  for (final run in peerRuns) {
    final fixture = _object(run['fixture']);
    if (fixture['warmupIterations'] case final num value) {
      warmupIterations.add(value.toDouble());
    }
    if (fixture['measuredIterations'] case final num value) {
      measuredIterations.add(value.toDouble());
    }
  }

  final strictPass =
      comparable &&
      sufficientRunCount &&
      errors.where((error) => !error.startsWith('runCount ')).isEmpty &&
      _object(correctness)['allRunsPass'] == true;

  return <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryBenchmarkVariance',
    'peerId': peerId,
    'scenarioId': scenarioId,
    if (scenario != null) 'scenarioName': scenario['name'],
    'runCount': peerRuns.length,
    'minRuns': minRuns,
    'sufficientRunCount': sufficientRunCount,
    'comparable': comparable,
    'strictPass': strictPass,
    'errors': errors,
    'comparableIssues': comparableIssues,
    'source': <String, Object?>{
      'versions': sourceVersions,
      'urls': _benchmarkNestedValues(peerRuns, ['source', 'url']),
    },
    'environment': <String, Object?>{
      'machines': _benchmarkNestedValues(peerRuns, ['environment', 'machine']),
      'operatingSystems': _benchmarkNestedValues(peerRuns, [
        'environment',
        'operatingSystem',
      ]),
      'runtimes': _benchmarkNestedValues(peerRuns, ['environment', 'runtime']),
      'terminalModes': terminalModes,
      'terminalSizes': terminalSizes,
    },
    'fixture': <String, Object?>{
      'workingDirectories': fixtureDirectories,
      'commands': fixtureCommands,
      'warmupIterations': _benchmarkNumberStats(warmupIterations),
      'measuredIterations': _benchmarkNumberStats(measuredIterations),
    },
    'runs': <Object?>[
      for (var index = 0; index < peerRuns.length; index += 1)
        <String, Object?>{
          'runId': peerRuns[index]['runId'],
          'capturedAt': peerRuns[index]['capturedAt'],
          'path': runPaths[index],
        },
    ],
    'metrics': metricReports,
    'correctness': correctness,
    'notes': <String>[
      'Metric variance uses each run artifact primary value: scalar metrics use the scalar value; metric maps prefer p95, then median, max, and value.',
      'strictPass is false unless run count, scenario/peer identity, source version, terminal mode, terminal size, fixture command, fixture directory, and correctness gates are comparable.',
    ],
  };
}

void _printBenchmarkVariance(Map<String, Object?> summary) {
  stdout.writeln('Benchmark variance summary');
  stdout.writeln('Peer: ${summary['peerId']}');
  stdout.writeln(
    'Scenario: ${summary['scenarioId']} ${summary['scenarioName'] ?? ''}',
  );
  stdout.writeln(
    'Runs: ${summary['runCount']} '
    '(min: ${summary['minRuns']}, sufficient: ${summary['sufficientRunCount']})',
  );
  stdout.writeln('Comparable: ${summary['comparable']}');
  stdout.writeln('Strict pass: ${summary['strictPass']}');
  for (final issue in _list(summary['comparableIssues'])) {
    stdout.writeln('Comparable issue: $issue');
  }
  for (final error in _list(summary['errors'])) {
    stdout.writeln('Error: $error');
  }

  final metrics = _object(summary['metrics']);
  if (metrics.isEmpty) return;
  stdout.writeln('Metrics:');
  for (final entry in metrics.entries) {
    final metric = _object(entry.value);
    stdout.writeln(
      '  ${entry.key} (${metric['primaryValue']}): '
      'median ${_formatCompactNumber(metric['median'])}, '
      'min ${_formatCompactNumber(metric['min'])}, '
      'max ${_formatCompactNumber(metric['max'])}, '
      'spread ${_formatCompactNumber(metric['relativeSpreadPercent'])}%',
    );
  }
}

List<String> _uniqueBenchmarkValues(
  List<Map<String, Object?>> peerRuns,
  String key,
) {
  return <String>{
    for (final run in peerRuns)
      if ((run[key] ?? '').toString().isNotEmpty) run[key]!.toString(),
  }.toList(growable: false);
}

List<String> _benchmarkNestedValues(
  List<Map<String, Object?>> peerRuns,
  List<String> path,
) {
  return <String>{
    for (final run in peerRuns)
      if (_benchmarkNestedValue(run, path).isNotEmpty)
        _benchmarkNestedValue(run, path),
  }.toList(growable: false);
}

String _benchmarkNestedValue(Map<String, Object?> run, List<String> path) {
  Object? value = run;
  for (final segment in path) {
    value = _object(value)[segment];
  }
  return value?.toString() ?? '';
}

String _benchmarkTerminalSizeKey(Map<String, Object?> run) {
  final environment = _object(run['environment']);
  final size = _object(environment['terminalSize']);
  final columns = size['columns'];
  final rows = size['rows'];
  if (columns == null || rows == null) return '';
  return '${columns}x$rows';
}

MapEntry<String, double>? _benchmarkMetricPrimary(Object? metric) {
  if (metric is num) return MapEntry('value', metric.toDouble());
  final object = _object(metric);
  for (final key in ['p95', 'median', 'max', 'value']) {
    final value = object[key];
    if (value is num) return MapEntry(key, value.toDouble());
  }
  return null;
}

Map<String, Object?> _benchmarkNumberStats(List<double> values) {
  if (values.isEmpty) {
    return <String, Object?>{
      'samples': 0,
      'min': null,
      'median': null,
      'mean': null,
      'max': null,
      'standardDeviation': null,
      'relativeSpreadPercent': null,
      'values': const <Object?>[],
    };
  }
  final sorted = [...values]..sort();
  final min = sorted.first;
  final max = sorted.last;
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[(sorted.length ~/ 2) - 1] + sorted[sorted.length ~/ 2]) / 2;
  final variance =
      sorted
          .map((value) {
            final delta = value - mean;
            return delta * delta;
          })
          .reduce((a, b) => a + b) /
      sorted.length;
  final relativeSpreadPercent = median == 0
      ? null
      : ((max - min) / median) * 100;
  return <String, Object?>{
    'samples': sorted.length,
    'min': _compactNumber(min),
    'median': _compactNumber(median),
    'mean': _compactNumber(mean),
    'max': _compactNumber(max),
    'standardDeviation': _compactNumber(math.sqrt(variance)),
    'relativeSpreadPercent': relativeSpreadPercent == null
        ? null
        : _compactNumber(relativeSpreadPercent),
    'values': <Object?>[for (final value in values) _compactNumber(value)],
  };
}

num _compactNumber(double value) {
  if (value.isFinite && value.roundToDouble() == value) return value.round();
  return double.parse(value.toStringAsFixed(3));
}

String _formatCompactNumber(Object? value) {
  if (value == null) return 'n/a';
  return value.toString();
}

Set<String> _benchmarkPeerIds(Map<String, Object?> manifest) {
  return <String>{
    for (final peer in _list(manifest['peers']))
      if ((_object(peer)['id'] ?? '').toString().isNotEmpty)
        _object(peer)['id'].toString(),
  };
}

Map<String, Object?>? _benchmarkScenario(
  Map<String, Object?> manifest,
  String id,
) {
  for (final scenario in _list(manifest['scenarios'])) {
    final object = _object(scenario);
    if (object['id']?.toString() == id) return object;
  }
  return null;
}

Map<String, Object?> _terminalMatrixSummary(Map<String, Object?> diagnosis) {
  final terminal = _object(diagnosis['terminal']);
  final environment = _object(diagnosis['environment']);
  final platform = _object(diagnosis['platform']);
  final capabilities = _object(diagnosis['capabilities']);
  final activeProbes = _object(diagnosis['activeProbes']);
  final compatibility = _object(diagnosis['compatibility']);
  final fallbacks = _list(diagnosis['fallbacks']);
  final warnings = _list(diagnosis['warnings']);
  final unsupportedFeatures = _list(diagnosis['unsupportedFeatures']);
  return <String, Object?>{
    if (platform.isNotEmpty)
      'platform': <String, Object?>{
        'operatingSystem': platform['operatingSystem'],
        'operatingSystemVersion': platform['operatingSystemVersion'],
        'dartVersion': platform['dartVersion'],
      },
    'terminal': <String, Object?>{
      'term': terminal['term'],
      'termProgram': terminal['termProgram'],
      'termProgramVersion': terminal['termProgramVersion'],
      'columns': terminal['columns'],
      'rows': terminal['rows'],
      'isInteractive': terminal['isInteractive'],
      'stdinIsTerminal': terminal['stdinIsTerminal'],
      'stdoutIsTerminal': terminal['stdoutIsTerminal'],
      'tmux': environment['tmux'],
      'ssh': environment['ssh'],
    },
    'capabilities': <String, Object?>{
      'colorMode': capabilities['colorMode'],
      'imageProtocol': capabilities['imageProtocol'],
      'alternateScreen': capabilities['alternateScreen'],
      'hideCursor': capabilities['hideCursor'],
      'tmuxPassthrough': capabilities['tmuxPassthrough'],
    },
    'diagnostics': <String, Object?>{
      'fallbackCount': fallbacks.length,
      'warningCount': warnings.length,
      'unsupportedFeatureCount': unsupportedFeatures.length,
      'fallbackCodes': _diagnosticMessageCodes(fallbacks),
      'warningCodes': _diagnosticMessageCodes(warnings),
      'unsupportedFeatures': unsupportedFeatures,
    },
    if (activeProbes.isNotEmpty)
      'activeProbes': <String, Object?>{
        'skippedReason': activeProbes['skippedReason'],
        'confirmedFeatures': activeProbes['confirmedFeatures'],
        'summary': activeProbes['summary'],
        'probeStatuses': <String, Object?>{
          for (final probe in _list(activeProbes['probes']))
            if (probe is Map<String, Object?>)
              probe['id'].toString(): probe['status'],
        },
      },
    if (compatibility.isNotEmpty)
      'compatibility': <String, Object?>{
        'skippedReason': compatibility['skippedReason'],
        'summary': compatibility['summary'],
        'findings': <Object?>[
          for (final finding in _list(compatibility['findings']))
            if (finding is Map<String, Object?>)
              <String, Object?>{
                'feature': finding['feature'],
                'status': finding['status'],
                'passiveSupported': finding['passiveSupported'],
                'activeStatus': finding['activeStatus'],
              },
        ],
      },
  };
}

List<String> _diagnosticMessageCodes(List<Object?> messages) {
  return <String>[
    for (final message in messages)
      if (message is Map<String, Object?> && message['code'] != null)
        message['code'].toString(),
  ];
}

Map<String, Object?> _terminalMatrixReview(
  Map<String, Object?> diagnosis, {
  List<String> additionalNotes = const <String>[],
}) {
  final terminal = _object(diagnosis['terminal']);
  final environment = _object(diagnosis['environment']);
  final activeProbes = _object(diagnosis['activeProbes']);
  final compatibility = _object(diagnosis['compatibility']);
  final issues = <String>[];
  final notes = <String>[];

  final stdinIsTerminal = terminal['stdinIsTerminal'] == true;
  final stdoutIsTerminal = terminal['stdoutIsTerminal'] == true;
  if (!stdinIsTerminal || !stdoutIsTerminal) {
    issues.add('stdin/stdout are not both terminals');
  }
  if (terminal['isInteractive'] != true) {
    issues.add('terminal is not interactive');
  }
  if (environment['tmux'] == true) {
    notes.add('captured inside tmux');
  }
  if (environment['ssh'] == true) {
    notes.add('captured over ssh');
  }

  if (activeProbes.isEmpty) {
    issues.add('active probe evidence missing');
  } else if (activeProbes['skippedReason'] case final reason?) {
    issues.add('active probes skipped: $reason');
  }

  if (compatibility.isEmpty) {
    issues.add('compatibility report missing');
  } else {
    for (final finding in _list(compatibility['findings'])) {
      if (finding is! Map<String, Object?>) continue;
      final feature = finding['feature'] ?? 'unknown';
      final status = finding['status'];
      switch (status) {
        case 'passiveUnverified':
          issues.add('$feature passive support was not confirmed by probes');
        case 'inconclusive':
          issues.add('$feature compatibility is inconclusive');
        case 'activeConfirmed':
          notes.add('$feature was confirmed only by active probing');
      }
    }
  }
  notes.addAll(additionalNotes);

  final status = issues.isEmpty
      ? 'readyForReview'
      : (!stdinIsTerminal || !stdoutIsTerminal)
      ? 'nonInteractive'
      : 'needsAttention';
  return <String, Object?>{'status': status, 'issues': issues, 'notes': notes};
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const <Object?>[];
}

List<String> _stringList(Object? value) {
  return <String>[for (final item in _list(value)) item.toString()];
}
