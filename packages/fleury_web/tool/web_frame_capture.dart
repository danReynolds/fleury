import 'dart:async';
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
  if (options.list) {
    _printScenarioList(json: options.json);
    return;
  }

  final scenario = webBenchmarkScenarioById(options.scenarioId);
  if (scenario == null) {
    stderr.writeln('Unknown web benchmark scenario: ${options.scenarioId}');
    _printScenarioList(json: false);
    exit(2);
  }

  final runner = _CaptureRunner(options: options, scenario: scenario);
  await runner.run();
}

final class _CaptureRunner {
  const _CaptureRunner({required this.options, required this.scenario});

  final _Options options;
  final WebBenchmarkScenario scenario;

  Future<void> run() async {
    final packageRoot = Directory.current.absolute.path;
    final buildDir = options.pageDir == null
        ? Directory.systemTemp.createTempSync('fleury_web_frame_capture_')
        : Directory(options.pageDir!);
    final ownsBuildDir = options.pageDir == null;
    final outputPath = options.outputPath ?? _defaultOutputPath(scenario.id);

    _ChromeProcess? chrome;
    _StaticServer? server;
    try {
      if (options.compileOnly || ownsBuildDir) {
        buildDir.createSync(recursive: true);
        await _compileBenchmarkEntrypoint(
          packageRoot: packageRoot,
          outputPath: '${buildDir.path}/benchmark_capture.dart.js',
          minify: !options.heapProfile,
        );
        _writeBenchmarkPage(buildDir);
      } else {
        _validateBenchmarkPageDir(buildDir);
      }
      if (options.compileOnly) {
        _printCompileOnlyResult(buildDir.path, json: options.json);
        return;
      }

      server = await _StaticServer.start(buildDir);
      chrome = await _ChromeProcess.start(options);
      final page = await chrome.openPage(
        server.uri(
          scenario: scenario,
          frames: options.frames ?? scenario.defaultFrames,
          warmupFrames: options.warmupFrames,
          frameBudgetMs: options.frameBudgetMs,
          timeoutSeconds: options.timeoutSeconds,
          semanticsEnabled: !options.disableSemantics,
        ),
      );

      if (options.heapProfile) await page.startHeapSampling();
      if (options.traceFrames) await page.startFrameTracing();
      final captureJson = await page.waitForCapture(
        Duration(seconds: options.timeoutSeconds),
      );
      Map<String, Object?>? heapProfileJson;
      if (options.heapProfile) {
        heapProfileJson = await page.stopHeapSampling();
      }
      Map<String, Object?>? browserFrameTiming;
      if (options.traceFrames) {
        final events = await page.stopFrameTracing(
          Duration(seconds: options.timeoutSeconds),
        );
        browserFrameTiming = _analyzeFrameTrace(events);
      }
      final capture = jsonDecode(captureJson);
      if (capture is! Map<String, Object?>) {
        throw const FormatException('Browser capture root was not an object.');
      }
      final browserMetrics = await page.captureBrowserMetrics();
      if (browserMetrics.isNotEmpty) {
        capture['browserMetrics'] = browserMetrics;
      }
      if (browserFrameTiming != null) {
        capture['browserFrameTiming'] = browserFrameTiming;
      }
      capture['runEnvironment'] = chrome.runEnvironmentJson(
        options: options,
        requestedFrames: options.frames ?? scenario.defaultFrames,
      );
      final output = File(outputPath);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(capture)}\n',
      );
      if (heapProfileJson != null) {
        File(
          '$outputPath.heap.json',
        ).writeAsStringSync('${jsonEncode(heapProfileJson)}\n');
        stderr.writeln('heap profile written to $outputPath.heap.json');
      }
      await page.close();
      _printCaptureResult(capture, output.path, json: options.json);
    } finally {
      await chrome?.dispose();
      await server?.close();
      if (ownsBuildDir && !options.keepTemp && !options.compileOnly) {
        try {
          buildDir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup only.
        }
      }
    }
  }
}

Future<void> _compileBenchmarkEntrypoint({
  required String packageRoot,
  required String outputPath,
  bool minify = true,
}) async {
  final result = await Process.run('dart', [
    'compile',
    'js',
    'web/benchmark_capture.dart',
    '-O2',
    // Heap-profiling builds keep readable names so allocation stacks map
    // back to Dart functions.
    if (!minify) '--no-minify',
    '-o',
    outputPath,
  ], workingDirectory: packageRoot);
  final stdoutText = result.stdout.toString();
  final stderrText = result.stderr.toString();
  if (stdoutText.isNotEmpty) stderr.write(stdoutText);
  if (stderrText.isNotEmpty) stderr.write(stderrText);
  if (result.exitCode != 0) {
    stderr.writeln('dart compile js failed with exit code ${result.exitCode}.');
    exit(result.exitCode);
  }
}

void _writeBenchmarkPage(Directory buildDir) {
  File('${buildDir.path}/index.html').writeAsStringSync('''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Fleury Web Frame Capture</title>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: #050505;
      color: #f5f5f5;
      font-family: monospace;
    }
    #fleury-capture-json, #fleury-capture-error {
      position: absolute;
      left: -10000px;
      top: -10000px;
    }
  </style>
</head>
<body>
  <div id="fleury-app"></div>
  <script defer src="benchmark_capture.dart.js"></script>
</body>
</html>
''');
}

void _validateBenchmarkPageDir(Directory buildDir) {
  if (!buildDir.existsSync()) {
    throw StateError(
      'Frame capture page directory does not exist: ${buildDir.path}',
    );
  }
  final index = File('${buildDir.path}/index.html');
  if (!index.existsSync()) {
    throw StateError(
      'Frame capture page directory is missing index.html: ${buildDir.path}',
    );
  }
  final script = File('${buildDir.path}/benchmark_capture.dart.js');
  if (!script.existsSync()) {
    throw StateError(
      'Frame capture page directory is missing benchmark_capture.dart.js: ${buildDir.path}',
    );
  }
}

void _printCaptureResult(
  Map<String, Object?> capture,
  String outputPath, {
  required bool json,
}) {
  final summary = capture['summary'] as Map<String, Object?>?;
  final result = <String, Object?>{
    'kind': 'fleuryWebFrameCaptureResult',
    'outputPath': outputPath,
    'scenario': capture['scenario'],
    'frameCount': summary?['frameCount'],
    'overBudgetFrameCount': summary?['overBudgetFrameCount'],
    'overBudgetPercent': summary?['overBudgetPercent'],
    'dominantP95Slice': summary?['dominantP95Slice'],
    'semanticsEnabled': capture['semanticsEnabled'],
    if (capture['browserMetrics'] != null)
      'browserMetrics': capture['browserMetrics'],
  };
  if (json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return;
  }
  stdout.writeln('wrote $outputPath');
  stdout.writeln(
    'frames ${result['frameCount']} | '
    'over budget ${result['overBudgetFrameCount']} | '
    'dominant ${result['dominantP95Slice']}',
  );
}

void _printCompileOnlyResult(String pageDir, {required bool json}) {
  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'kind': 'fleuryWebFrameCompileResult',
        'pageDir': pageDir,
        'indexPath': '$pageDir/index.html',
        'javascriptPath': '$pageDir/benchmark_capture.dart.js',
      }),
    );
    return;
  }
  stdout.writeln(pageDir);
}

final class _StaticServer {
  _StaticServer._(this._server, this._root);

  final HttpServer _server;
  final Directory _root;

  static Future<_StaticServer> start(Directory root) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final staticServer = _StaticServer._(server, root);
    server.listen(staticServer._handle);
    return staticServer;
  }

  Uri uri({
    required WebBenchmarkScenario scenario,
    required int frames,
    required int warmupFrames,
    required double frameBudgetMs,
    required int timeoutSeconds,
    required bool semanticsEnabled,
  }) {
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server.port,
      path: '/',
      queryParameters: <String, String>{
        'scenario': scenario.id,
        'frames': '$frames',
        'warmup': '$warmupFrames',
        'budgetMs': '$frameBudgetMs',
        'timeout': '$timeoutSeconds',
        'semantics': semanticsEnabled ? 'on' : 'off',
      },
    );
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final file = resolveFrameCaptureStaticFile(_root, request.uri);
    if (file == null || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (file.path.endsWith('.js')) {
      request.response.headers.contentType = ContentType(
        'application',
        'javascript',
        charset: 'utf-8',
      );
    } else if (file.path.endsWith('.html')) {
      request.response.headers.contentType = ContentType.html;
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
}

/// Resolves static files served by the frame-capture loopback server.
///
/// The benchmark page server should only expose files generated under [root].
/// Reject traversal-like segments and encoded path separators before joining
/// so a browser request cannot escape the generated page directory.
File? resolveFrameCaptureStaticFile(Directory root, Uri requestUri) {
  final segments = requestUri.path == '/'
      ? const <String>['index.html']
      : requestUri.pathSegments;
  if (segments.isEmpty) return File('${root.path}/index.html');

  final safeSegments = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') return null;
    if (segment.contains('/') || segment.contains(r'\')) return null;
    safeSegments.add(segment);
  }
  return File([root.path, ...safeSegments].join(Platform.pathSeparator));
}

/// Aggregates devtools.timeline events into per-rAF browser-side frame
/// timings.
///
/// Buckets main-thread rendering work (style recalc, layout, pre-paint,
/// paint, layerize, compositing commit) between consecutive
/// `FireAnimationFrame` events, which is the browser-side half of each
/// Fleury frame: the part a Dart-side stopwatch cannot see.
Map<String, Object?> _analyzeFrameTrace(List<Map<String, Object?>> events) {
  const renderingNames = {
    'UpdateLayoutTree': 'styleUs',
    'Layout': 'layoutUs',
    'PrePaint': 'paintUs',
    'Paint': 'paintUs',
    'Layerize': 'paintUs',
    'Commit': 'paintUs',
  };
  // Find the main thread: the one that fires animation frames.
  int? mainTid;
  for (final event in events) {
    if (event['name'] == 'FireAnimationFrame') {
      final tid = event['tid'];
      if (tid is int) mainTid = tid;
      break;
    }
  }
  final frameStarts = <int>[];
  final completes = <(int ts, int dur, String bucket)>[];
  for (final event in events) {
    if (event['tid'] != mainTid) continue;
    final name = event['name'];
    final ts = event['ts'];
    if (ts is! int) continue;
    if (name == 'FireAnimationFrame') {
      frameStarts.add(ts);
      continue;
    }
    final bucket = renderingNames[name];
    if (bucket == null) continue;
    final dur = event['dur'];
    if (event['ph'] == 'X' && dur is int) {
      completes.add((ts, dur, bucket));
    }
  }
  frameStarts.sort();
  if (frameStarts.isEmpty) {
    return {'frameCount': 0, 'note': 'no FireAnimationFrame events traced'};
  }
  final perFrame = List.generate(
    frameStarts.length,
    (_) => <String, int>{'styleUs': 0, 'layoutUs': 0, 'paintUs': 0},
  );
  for (final (ts, dur, bucket) in completes) {
    // Frame index: last frame start at or before this event.
    var lo = 0, hi = frameStarts.length - 1, index = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (frameStarts[mid] <= ts) {
        index = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (index < 0) continue;
    perFrame[index][bucket] = perFrame[index][bucket]! + dur;
  }
  final totals = [
    for (final frame in perFrame)
      frame['styleUs']! + frame['layoutUs']! + frame['paintUs']!,
  ]..sort();
  double percentile(List<int> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final index = (sorted.length * p).round().clamp(1, sorted.length) - 1;
    return sorted[index] / 1000.0;
  }

  return {
    'frameCount': perFrame.length,
    'frames': [
      for (final frame in perFrame)
        {
          'styleUs': frame['styleUs'],
          'layoutUs': frame['layoutUs'],
          'paintUs': frame['paintUs'],
        },
    ],
    'browserSideMs': {
      'p50': percentile(totals, 0.50),
      'p95': percentile(totals, 0.95),
      'max': totals.isEmpty ? 0 : totals.last / 1000.0,
    },
  };
}

/// Pins Chrome to the HOST architecture on Apple Silicon.
///
/// An x64 (Rosetta) parent process spawns universal binaries as their x64
/// slice, which puts V8's JIT under Rosetta translation — benchmarks then
/// show multi-hundred-ms whole-process stalls as freshly emitted code pages
/// get translated. Launching through `arch -arm64` keeps the renderer
/// native regardless of the Dart SDK's architecture.
Future<({String executable, List<String> prefixArgs})> _nativeArchLaunch(
  String chromePath,
) async {
  if (!Platform.isMacOS) {
    return (executable: chromePath, prefixArgs: const <String>[]);
  }
  try {
    final result = await Process.run('sysctl', ['-n', 'hw.optional.arm64']);
    if (result.exitCode == 0 && result.stdout.toString().trim() == '1') {
      return (
        executable: '/usr/bin/arch',
        prefixArgs: <String>['-arm64', chromePath],
      );
    }
  } on Object {
    // Fall through to a direct launch.
  }
  return (executable: chromePath, prefixArgs: const <String>[]);
}

final class _ChromeProcess {
  _ChromeProcess._({
    required this.process,
    required this.executablePath,
    required this.debugPort,
    required this.profileDir,
    required this.stderrBuffer,
    required this.stdoutSubscription,
    required this.stderrSubscription,
    required this.versionInfo,
  });

  final Process process;
  final String executablePath;
  final int debugPort;
  final Directory profileDir;
  final StringBuffer stderrBuffer;
  final StreamSubscription<List<int>> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;
  final Map<String, Object?> versionInfo;

  static Future<_ChromeProcess> start(_Options options) async {
    final chromePath = options.chromePath ?? _findChromeExecutable();
    final launch = await _nativeArchLaunch(chromePath);
    final debugPort = await _reservePort();
    final profileDir = Directory.systemTemp.createTempSync(
      'fleury_web_chrome_profile_',
    );
    final stderrBuffer = StringBuffer();
    late final Process process;
    try {
      process = await Process.start(launch.executable, [
        ...launch.prefixArgs,
        if (options.headless) '--headless=new',
        '--disable-background-networking',
        // Benchmark fidelity: never deprioritize the page's renderer. The
        // page is CDP-driven and effectively occluded, which otherwise
        // invites timer/raf throttling and renderer backgrounding that show
        // up as multi-hundred-ms stalls inside synchronous script sections.
        '--disable-renderer-backgrounding',
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows',
        '--disable-gpu',
        '--disable-search-engine-choice-screen',
        '--no-default-browser-check',
        '--no-first-run',
        '--remote-debugging-port=$debugPort',
        '--user-data-dir=${profileDir.path}',
        'about:blank',
      ]);
    } catch (_) {
      try {
        profileDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup only.
      }
      rethrow;
    }
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write, onError: (_) {});
    final stdoutSubscription = process.stdout.listen((_) {}, onError: (_) {});
    final chrome = _ChromeProcess._(
      process: process,
      executablePath: chromePath,
      debugPort: debugPort,
      profileDir: profileDir,
      stderrBuffer: stderrBuffer,
      stdoutSubscription: stdoutSubscription,
      stderrSubscription: stderrSubscription,
      versionInfo: const <String, Object?>{},
    );
    try {
      final versionInfo = await chrome._waitForProtocol(
        Duration(seconds: options.timeoutSeconds),
      );
      return _ChromeProcess._(
        process: process,
        executablePath: chromePath,
        debugPort: debugPort,
        profileDir: profileDir,
        stderrBuffer: stderrBuffer,
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
        versionInfo: versionInfo,
      );
    } catch (_) {
      await chrome.dispose();
      rethrow;
    }
  }

  Future<_CdpPage> openPage(Uri uri) async {
    final target = await _readJson(
      Uri.parse('http://127.0.0.1:$debugPort/json/new?about%3Ablank'),
      method: 'PUT',
    );
    final webSocketUrl = target['webSocketDebuggerUrl'];
    if (webSocketUrl is! String || webSocketUrl.isEmpty) {
      throw StateError('Chrome did not return a page debugger URL: $target');
    }
    final client = await _CdpClient.connect(webSocketUrl);
    await client.call('Runtime.enable');
    await client.call('Page.enable');
    await _tryCdpCall(client, 'Performance.enable');
    await client.call('Page.navigate', {'url': uri.toString()});
    return _CdpPage(client);
  }

  Future<void> dispose() async {
    if (!await _processExited) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // Keep cleanup best-effort. The capture artifact has already been
          // written by the time dispose runs, so an uncooperative browser
          // process should not hold the Dart tool open indefinitely.
        }
      }
    }
    await _cancelProcessStreams();
    try {
      profileDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup only.
    }
  }

  Map<String, Object?> runEnvironmentJson({
    required _Options options,
    required int requestedFrames,
  }) {
    return <String, Object?>{
      'schemaVersion': 1,
      'chromeExecutable': executablePath,
      'chromeBrowser': versionInfo['Browser'],
      'chromeUserAgent': versionInfo['User-Agent'],
      'devtoolsProtocolVersion': versionInfo['Protocol-Version'],
      'v8Version': versionInfo['V8-Version'],
      'webkitVersion': versionInfo['WebKit-Version'],
      'dartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystem,
      'operatingSystemVersion': Platform.operatingSystemVersion,
      'headless': options.headless,
      'requestedFrames': requestedFrames,
      'requestedSteps': requestedFrames,
      'warmupFrames': options.warmupFrames,
      'frameBudgetMs': options.frameBudgetMs,
      'semanticsEnabled': !options.disableSemantics,
    };
  }

  Future<Map<String, Object?>> _waitForProtocol(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      if (await _processExited) {
        throw StateError(
          'Chrome exited before DevTools became available.\n'
          '${stderrBuffer.toString()}',
        );
      }
      try {
        return await _readJson(
          Uri.parse('http://127.0.0.1:$debugPort/json/version'),
        );
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw TimeoutException(
      'Timed out waiting for Chrome DevTools: $lastError\n'
      '${stderrBuffer.toString()}',
      timeout,
    );
  }

  Future<bool> get _processExited async {
    try {
      await process.exitCode.timeout(Duration.zero);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _cancelProcessStreams() async {
    await Future.wait<void>([
      stdoutSubscription.cancel(),
      stderrSubscription.cancel(),
    ]).timeout(const Duration(seconds: 2), onTimeout: () => const <void>[]);
  }
}

Future<void> _tryCdpCall(
  _CdpClient client,
  String method, [
  Map<String, Object?>? params,
]) async {
  try {
    await client.call(method, params);
  } on Object {
    // Optional CDP domains vary by browser/version. Missing metrics should not
    // make the frame capture itself unusable.
  }
}

final class _CdpPage {
  const _CdpPage(this._client);

  final _CdpClient _client;

  Future<String> waitForCapture(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastEvaluationError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final error = await _evaluateString(
          'globalThis.__fleuryWebBenchmarkError || ""',
        );
        if (error.isNotEmpty) {
          throw StateError('Browser benchmark failed:\n$error');
        }
        final done = await _evaluateBool(
          'globalThis.__fleuryWebBenchmarkDone === true',
        );
        if (done) {
          final capture = await _evaluateString(
            'globalThis.__fleuryWebBenchmarkCaptureJson || ""',
          );
          if (capture.isNotEmpty) return capture;
        }
        lastEvaluationError = null;
      } on StateError catch (error) {
        if (error.message.startsWith('Browser benchmark failed:')) rethrow;
        lastEvaluationError = error;
      } on Object catch (error) {
        lastEvaluationError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final suffix = lastEvaluationError == null
        ? ''
        : ' Last CDP evaluation error: $lastEvaluationError';
    throw TimeoutException(
      'Timed out waiting for browser capture.$suffix',
      timeout,
    );
  }

  /// Collected devtools.timeline trace events while tracing is active.
  static final List<Map<String, Object?>> _traceEvents = [];
  static Completer<void>? _tracingComplete;

  Future<void> startFrameTracing() async {
    _traceEvents.clear();
    _tracingComplete = Completer<void>();
    _client.on('Tracing.dataCollected', (params) {
      final value = params['value'];
      if (value is List) {
        _traceEvents.addAll(value.whereType<Map<String, Object?>>());
      }
    });
    _client.on('Tracing.tracingComplete', (_) {
      final completer = _tracingComplete;
      if (completer != null && !completer.isCompleted) completer.complete();
    });
    await _client.call('Tracing.start', {
      'traceConfig': {
        'includedCategories': ['devtools.timeline'],
      },
      'transferMode': 'ReportEvents',
    });
  }

  Future<List<Map<String, Object?>>> stopFrameTracing(Duration timeout) async {
    await _client.call('Tracing.end');
    final completer = _tracingComplete;
    if (completer != null) {
      await completer.future.timeout(timeout, onTimeout: () {});
    }
    return List.of(_traceEvents);
  }

  Future<void> startHeapSampling() async {
    await _client.call('HeapProfiler.enable', {});
    // 8KiB sampling interval: fine enough to rank per-frame allocators
    // without measurably perturbing the run.
    await _client.call('HeapProfiler.startSampling', {
      'samplingInterval': 8192,
    });
  }

  Future<Map<String, Object?>> stopHeapSampling() async {
    final response = await _client.call('HeapProfiler.stopSampling', {});
    final profile = response['profile'];
    return profile is Map<String, Object?> ? profile : <String, Object?>{};
  }

  Future<Map<String, Object?>> captureBrowserMetrics() async {
    final performance = await _performanceMetrics();
    final domCounters = await _domCounters();
    final heapUsage = await _heapUsage();
    return WebBrowserPerformanceMetrics(
      layoutDurationMs: _secondsToMillis(performance['LayoutDuration']),
      recalcStyleDurationMs: _secondsToMillis(
        performance['RecalcStyleDuration'],
      ),
      scriptDurationMs: _secondsToMillis(performance['ScriptDuration']),
      taskDurationMs: _secondsToMillis(performance['TaskDuration']),
      jsHeapUsedBytes: heapUsage['usedSize'] ?? performance['JSHeapUsedSize'],
      jsHeapTotalBytes:
          heapUsage['totalSize'] ?? performance['JSHeapTotalSize'],
      domDocumentCount:
          domCounters['documents'] ?? _optionalInt(performance['Documents']),
      domNodeCount: domCounters['nodes'] ?? _optionalInt(performance['Nodes']),
      jsEventListenerCount:
          domCounters['jsEventListeners'] ??
          _optionalInt(performance['JSEventListeners']),
    ).toJson();
  }

  Future<void> close() => _client.close();

  Future<Map<String, double>> _performanceMetrics() async {
    try {
      final response = await _client.call('Performance.getMetrics');
      final metrics = response['metrics'];
      if (metrics is! List) return const <String, double>{};
      return <String, double>{
        for (final metric in metrics)
          if (metric is Map &&
              metric['name'] is String &&
              metric['value'] is num)
            metric['name'] as String: (metric['value'] as num).toDouble(),
      };
    } on Object {
      return const <String, double>{};
    }
  }

  Future<Map<String, int>> _domCounters() async {
    try {
      final response = await _client.call('Memory.getDOMCounters');
      return <String, int>{
        for (final key in const ['documents', 'nodes', 'jsEventListeners'])
          if (response[key] is num) key: (response[key] as num).toInt(),
      };
    } on Object {
      return const <String, int>{};
    }
  }

  Future<Map<String, double>> _heapUsage() async {
    try {
      final response = await _client.call('Runtime.getHeapUsage');
      return <String, double>{
        for (final key in const ['usedSize', 'totalSize'])
          if (response[key] is num) key: (response[key] as num).toDouble(),
      };
    } on Object {
      return const <String, double>{};
    }
  }

  Future<bool> _evaluateBool(String expression) async {
    final value = await _evaluate(expression);
    return value == true;
  }

  Future<String> _evaluateString(String expression) async {
    final value = await _evaluate(expression);
    return value is String ? value : '';
  }

  Future<Object?> _evaluate(String expression) async {
    final response = await _client.call('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
    });
    final result = response['result'] as Map<String, Object?>?;
    final exception = response['exceptionDetails'];
    if (exception != null) {
      throw StateError('CDP evaluation failed: $exception');
    }
    return result?['value'];
  }
}

double? _secondsToMillis(double? value) => value == null ? null : value * 1000;

int? _optionalInt(double? value) => value == null ? null : value.round();

final class _CdpClient {
  _CdpClient._(this._socket) {
    _subscription = _socket.listen(
      _handleMessage,
      onError: _failAll,
      onDone: () => _failAll(StateError('CDP socket closed.')),
    );
  }

  final WebSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final Map<String, List<void Function(Map<String, Object?>)>> _eventListeners =
      {};
  var _nextId = 1;

  /// Registers [handler] for CDP events named [method].
  void on(String method, void Function(Map<String, Object?> params) handler) {
    _eventListeners.putIfAbsent(method, () => []).add(handler);
  }

  static Future<_CdpClient> connect(String webSocketUrl) async {
    final socket = await WebSocket.connect(webSocketUrl);
    return _CdpClient._(socket);
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?>? params,
  ]) {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode(<String, Object?>{
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      }),
    );
    return completer.future;
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
  }

  void _handleMessage(dynamic data) {
    final decoded = jsonDecode(data as String) as Map<String, Object?>;
    final id = decoded['id'];
    if (id is! int) {
      final method = decoded['method'];
      final listeners = method is String ? _eventListeners[method] : null;
      if (listeners != null) {
        final params = decoded['params'];
        final eventParams = params is Map<String, Object?>
            ? params
            : <String, Object?>{};
        for (final listener in listeners) {
          listener(eventParams);
        }
      }
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = decoded['error'];
    if (error != null) {
      completer.completeError(StateError('CDP command failed: $error'));
      return;
    }
    final result = decoded['result'];
    completer.complete(
      result is Map<String, Object?> ? result : <String, Object?>{},
    );
  }

  void _failAll(Object error) {
    final pending = Map<int, Completer<Map<String, Object?>>>.of(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }
}

Future<Map<String, Object?>> _readJson(Uri uri, {String method = 'GET'}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $text', uri: uri);
    }
    return (jsonDecode(text) as Map).cast<String, Object?>();
  } finally {
    client.close(force: true);
  }
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

String _findChromeExecutable() {
  final candidates = <String>[
    if (Platform.isMacOS)
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    if (Platform.isMacOS)
      '${Platform.environment['HOME']}/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    if (Platform.isLinux) '/usr/bin/google-chrome',
    if (Platform.isLinux) '/usr/bin/google-chrome-stable',
    if (Platform.isLinux) '/usr/bin/chromium',
    if (Platform.isWindows)
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    if (Platform.isWindows)
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
  ];
  for (final candidate in candidates) {
    if (candidate.contains('null')) continue;
    if (File(candidate).existsSync()) return candidate;
  }
  final fromPath = _which(Platform.isWindows ? 'chrome.exe' : 'google-chrome');
  if (fromPath != null) return fromPath;
  final chromium = _which(Platform.isWindows ? 'chromium.exe' : 'chromium');
  if (chromium != null) return chromium;
  throw StateError(
    'Could not find Chrome. Pass --chrome=/absolute/path/to/chrome.',
  );
}

String? _which(String executable) {
  final path = Platform.environment['PATH'];
  if (path == null) return null;
  for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
    final candidate = File(
      '$dir/${Platform.isWindows ? executable : executable}',
    );
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

String _defaultOutputPath(String scenarioId) {
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  return File('../../profiling/web/runs/$scenarioId-$stamp.json').absolute.path;
}

final class _Options {
  const _Options({
    required this.help,
    required this.list,
    required this.json,
    required this.scenarioId,
    required this.frames,
    required this.warmupFrames,
    required this.frameBudgetMs,
    required this.outputPath,
    required this.pageDir,
    required this.chromePath,
    required this.timeoutSeconds,
    required this.headless,
    required this.keepTemp,
    required this.heapProfile,
    required this.traceFrames,
    required this.compileOnly,
    required this.disableSemantics,
  });

  final bool help;
  final bool list;
  final bool json;
  final String scenarioId;
  final int? frames;
  final int warmupFrames;
  final double frameBudgetMs;
  final String? outputPath;
  final String? pageDir;
  final String? chromePath;
  final int timeoutSeconds;
  final bool headless;
  final bool keepTemp;

  /// Compile unminified and record a CDP allocation-sampling profile next to
  /// the capture (`<output>.heap.json`).
  final bool heapProfile;

  /// Record a devtools.timeline trace and merge per-frame browser-side
  /// style/layout/paint timings into the capture
  /// (`browserFrameTiming` section).
  final bool traceFrames;
  final bool compileOnly;
  final bool disableSemantics;

  static _Options parse(List<String> args) {
    var help = false;
    var list = false;
    var json = false;
    var scenarioId = 'normal-80x24';
    int? frames;
    var warmupFrames = 2;
    var frameBudgetMs = defaultWebFrameBudgetMs;
    String? outputPath;
    String? pageDir;
    String? chromePath;
    var timeoutSeconds = 30;
    var headless = true;
    var keepTemp = false;
    var compileOnly = false;
    var heapProfile = false;
    var traceFrames = false;
    var disableSemantics = false;

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg == '--list') {
        list = true;
      } else if (arg == '--json') {
        json = true;
      } else if (arg.startsWith('--scenario=')) {
        scenarioId = arg.substring('--scenario='.length).trim();
      } else if (arg.startsWith('--frames=')) {
        frames = _positiveInt(arg, '--frames=');
      } else if (arg.startsWith('--warmup=')) {
        warmupFrames = _nonNegativeInt(arg, '--warmup=');
      } else if (arg.startsWith('--budget-ms=')) {
        frameBudgetMs = _positiveDouble(arg, '--budget-ms=');
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length).trim();
      } else if (arg.startsWith('--page-dir=')) {
        pageDir = arg.substring('--page-dir='.length).trim();
        if (pageDir.isEmpty) {
          stderr.writeln('--page-dir requires a non-empty path.');
          exit(2);
        }
      } else if (arg.startsWith('--chrome=')) {
        chromePath = arg.substring('--chrome='.length).trim();
      } else if (arg.startsWith('--timeout=')) {
        timeoutSeconds = _positiveInt(arg, '--timeout=');
      } else if (arg == '--headful') {
        headless = false;
      } else if (arg == '--heap-profile') {
        heapProfile = true;
      } else if (arg == '--trace-frames') {
        traceFrames = true;
      } else if (arg == '--keep-temp') {
        keepTemp = true;
      } else if (arg == '--compile-only') {
        compileOnly = true;
      } else if (arg == '--disable-semantics') {
        disableSemantics = true;
      } else {
        stderr.writeln('Unknown option for web_frame_capture: $arg');
        _printUsage();
        exit(2);
      }
    }

    return _Options(
      help: help,
      list: list,
      json: json,
      scenarioId: scenarioId,
      frames: frames,
      warmupFrames: warmupFrames,
      frameBudgetMs: frameBudgetMs,
      outputPath: outputPath == null || outputPath.isEmpty
          ? null
          : File(outputPath).absolute.path,
      pageDir: pageDir == null || pageDir.isEmpty
          ? null
          : Directory(pageDir).absolute.path,
      chromePath: chromePath == null || chromePath.isEmpty
          ? null
          : File(chromePath).absolute.path,
      timeoutSeconds: timeoutSeconds,
      headless: headless,
      keepTemp: keepTemp,
      heapProfile: heapProfile,
      traceFrames: traceFrames,
      compileOnly: compileOnly,
      disableSemantics: disableSemantics,
    );
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

void _printScenarioList({required bool json}) {
  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'kind': 'fleuryWebBenchmarkScenarios',
        'scenarios': [
          for (final scenario in webBenchmarkScenarios) scenario.toJson(),
        ],
      }),
    );
    return;
  }
  stdout.writeln('Web benchmark scenarios:');
  for (final scenario in webBenchmarkScenarios) {
    stdout.writeln(
      '  ${scenario.id.padRight(28)} '
      '${scenario.cols}x${scenario.rows} '
      '${scenario.description}',
    );
  }
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/web_frame_capture.dart [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --list                  List available scenarios');
  stdout.writeln('  --scenario=ID           Scenario id, default normal-80x24');
  stdout.writeln('  --frames=N              Driven benchmark steps');
  stdout.writeln('  --warmup=N              Warmup frames, default 2');
  stdout.writeln('  --budget-ms=N           Frame budget, default 16.67');
  stdout.writeln(
    '  --output=PATH           Capture JSON output path, default profiling/web/runs/<scenario>-<timestamp>.json',
  );
  stdout.writeln(
    '  --page-dir=DIR          Reuse or write a compiled benchmark page directory',
  );
  stdout.writeln('  --chrome=PATH           Chrome/Chromium executable');
  stdout.writeln('  --timeout=N             Timeout seconds, default 30');
  stdout.writeln('  --headful               Launch Chrome visibly');
  stdout.writeln(
    '  --compile-only          Compile and print temp page directory',
  );
  stdout.writeln(
    '  --disable-semantics     Diagnostics only: inaccessible visual-only run',
  );
  stdout.writeln(
    '  --keep-temp             Keep generated page/profile temp files',
  );
  stdout.writeln(
    '  --json                  Print machine-readable result or list',
  );
}
