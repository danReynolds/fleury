import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_web/src/benchmark/web_benchmark_scenarios.dart';
import 'package:web/web.dart' as web;

void main() {
  unawaited(_run());
}

Future<void> _run() async {
  final options = _BrowserCaptureOptions.fromLocation();
  _publishStatus('running');
  try {
    final scenario = webBenchmarkScenarioById(options.scenarioId);
    if (scenario == null) {
      throw StateError('Unknown web benchmark scenario: ${options.scenarioId}');
    }

    final hostElement = _hostElement();
    _applyHostSize(hostElement, scenario.cols, scenario.rows);
    final instrumentation = RecordingWebHostInstrumentation();
    final key = GlobalKey<_BenchmarkAppState>();
    final host = await mountApp(
      () => _BenchmarkApp(
        key: key,
        scenario: scenario,
        textInputController: TextEditingController(),
      ),
      into: hostElement,
      instrumentation: instrumentation,
      semanticsEnabled: options.semanticsEnabled,
      allowInaccessibleDiagnostics: !options.semanticsEnabled,
    );

    await _waitForFrameCount(instrumentation, 1, timeout: options.timeout);
    await _waitForFrameQuiescence(instrumentation, timeout: options.timeout);
    await host.awaitSemanticIdle();
    for (var index = 0; index < options.warmupFrames; index++) {
      final previousFrameCount = instrumentation.frames.length;
      _driveStep(
        scenario: scenario,
        step: index + 1,
        host: host,
        appState: key.currentState,
        hostElement: hostElement,
      );
      await _waitForFrameCount(
        instrumentation,
        previousFrameCount + 1,
        timeout: options.timeout,
      );
      await _waitForFrameQuiescence(instrumentation, timeout: options.timeout);
      await host.awaitSemanticIdle();
    }

    instrumentation.clear();
    for (var index = 0; index < options.frames; index++) {
      final previousFrameCount = instrumentation.frames.length;
      _driveStep(
        scenario: scenario,
        step: options.warmupFrames + index + 1,
        host: host,
        appState: key.currentState,
        hostElement: hostElement,
      );
      await _waitForFrameCount(
        instrumentation,
        previousFrameCount + 1,
        timeout: options.timeout,
      );
      await _waitForFrameQuiescence(instrumentation, timeout: options.timeout);
      await host.awaitSemanticIdle();
    }

    final capture = instrumentation.toJson(
      frameBudgetMs: options.frameBudgetMs,
    );
    final capturedFrameCount = instrumentation.frames.length;
    capture.addAll(<String, Object?>{
      'scenario': scenario.toJson(),
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'requestedFrames': options.frames,
      'requestedSteps': options.frames,
      'capturedFrameCount': capturedFrameCount,
      'extraFrameCount': capturedFrameCount - options.frames,
      'framesPerStep': options.frames == 0
          ? 0
          : capturedFrameCount / options.frames,
      'warmupFrames': options.warmupFrames,
      'semanticsEnabled': options.semanticsEnabled,
      'captureMode': options.semanticsEnabled
          ? 'product-semantics'
          : 'diagnostic-visual-only',
      'browser': <String, Object?>{
        'userAgent': web.window.navigator.userAgent,
        'devicePixelRatio': web.window.devicePixelRatio,
      },
    });
    await host.dispose();
    _publishDone(capture);
  } catch (error, stack) {
    _publishError(error, stack);
  }
}

web.Element _hostElement() {
  final existing = web.document.querySelector('#fleury-app');
  if (existing != null) return existing;
  final element = web.document.createElement('div');
  element.id = 'fleury-app';
  web.document.body?.appendChild(element);
  return element;
}

void _applyHostSize(web.Element host, int cols, int rows) {
  const lineHeight = 16;
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;'
        'width:${cols}ch;height:${rows * lineHeight}px;'
        'font-family:monospace;font-size:16px;line-height:${lineHeight}px;'
        'overflow:hidden;background:#050505;color:#f5f5f5;',
  );
}

void _driveStep({
  required WebBenchmarkScenario scenario,
  required int step,
  required MountedApp host,
  required _BenchmarkAppState? appState,
  required web.Element hostElement,
}) {
  switch (scenario.kind) {
    case WebBenchmarkScenarioKind.noOp:
      host.requestFrame('benchmark:noop');
    case WebBenchmarkScenarioKind.textInputBurst:
      _dispatchTextInput(_burstText(step));
    case WebBenchmarkScenarioKind.resizeBurst:
      final cols = step.isEven ? 160 : 80;
      final rows = step.isEven ? 50 : 24;
      _applyHostSize(hostElement, cols, rows);
      host.requestFrame('benchmark:resize');
      appState?.advance(step);
    case WebBenchmarkScenarioKind.normal:
    case WebBenchmarkScenarioKind.singleDirtyCell:
    case WebBenchmarkScenarioKind.dirtyRow:
    case WebBenchmarkScenarioKind.fullFrameChurn:
    case WebBenchmarkScenarioKind.scrollRowChurn:
    case WebBenchmarkScenarioKind.scrollKeyed:
    case WebBenchmarkScenarioKind.scatteredRows:
    case WebBenchmarkScenarioKind.cursorBlink:
      appState?.advance(step);
  }
}

void _dispatchTextInput(String text) {
  final textarea = web.document.querySelector('textarea');
  if (textarea is! web.HTMLTextAreaElement) return;
  textarea.focus();
  textarea.dispatchEvent(
    web.InputEvent(
      'input',
      web.InputEventInit(
        data: text,
        inputType: 'insertText',
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
}

String _burstText(int step) {
  const chunks = <String>['a', 'b', 'c', 'd', 'e', 'f', '0', '1'];
  return chunks[step % chunks.length];
}

Future<void> _waitForFrameCount(
  RecordingWebHostInstrumentation instrumentation,
  int count, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (instrumentation.frames.length < count) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Timed out waiting for $count web frames; '
        'captured ${instrumentation.frames.length}.',
        timeout,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 4));
  }
}

Future<void> _waitForFrameQuiescence(
  RecordingWebHostInstrumentation instrumentation, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastCount = instrumentation.frames.length;
  var stablePolls = 0;
  while (stablePolls < 2) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Timed out waiting for web frame quiescence; '
        'captured ${instrumentation.frames.length}.',
        timeout,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final currentCount = instrumentation.frames.length;
    if (currentCount == lastCount) {
      stablePolls++;
    } else {
      lastCount = currentCount;
      stablePolls = 0;
    }
  }
}

void _publishStatus(String status) {
  web.document.body?.setAttribute('data-fleury-web-benchmark-status', status);
  globalContext.setProperty('__fleuryWebBenchmarkDone'.toJS, false.toJS);
  globalContext.setProperty('__fleuryWebBenchmarkError'.toJS, ''.toJS);
}

void _publishDone(Map<String, Object?> capture) {
  final encoded = const JsonEncoder.withIndent('  ').convert(capture);
  globalContext.setProperty(
    '__fleuryWebBenchmarkCaptureJson'.toJS,
    encoded.toJS,
  );
  globalContext.setProperty('__fleuryWebBenchmarkDone'.toJS, true.toJS);
  web.document.body?.setAttribute('data-fleury-web-benchmark-status', 'done');
  final output =
      web.document.querySelector('#fleury-capture-json') ??
      web.document.createElement('pre');
  output.id = 'fleury-capture-json';
  output.textContent = encoded;
  if (output.parentNode == null) web.document.body?.appendChild(output);
}

void _publishError(Object error, StackTrace stack) {
  final message = '$error\n$stack';
  globalContext.setProperty('__fleuryWebBenchmarkError'.toJS, message.toJS);
  globalContext.setProperty('__fleuryWebBenchmarkDone'.toJS, true.toJS);
  web.document.body?.setAttribute('data-fleury-web-benchmark-status', 'error');
  final output =
      web.document.querySelector('#fleury-capture-error') ??
      web.document.createElement('pre');
  output.id = 'fleury-capture-error';
  output.textContent = message;
  if (output.parentNode == null) web.document.body?.appendChild(output);
}

final class _BrowserCaptureOptions {
  const _BrowserCaptureOptions({
    required this.scenarioId,
    required this.frames,
    required this.warmupFrames,
    required this.frameBudgetMs,
    required this.timeout,
    required this.semanticsEnabled,
  });

  factory _BrowserCaptureOptions.fromLocation() {
    final query = web.window.location.search;
    final params = web.URLSearchParams(query.toJS);
    final scenarioId = params.get('scenario') ?? 'normal-80x24';
    final scenario = webBenchmarkScenarioById(scenarioId);
    return _BrowserCaptureOptions(
      scenarioId: scenarioId,
      frames: _intParam(params, 'frames') ?? scenario?.defaultFrames ?? 24,
      warmupFrames: _intParam(params, 'warmup') ?? 2,
      frameBudgetMs:
          _doubleParam(params, 'budgetMs') ?? defaultWebFrameBudgetMs,
      timeout: Duration(seconds: _intParam(params, 'timeout') ?? 30),
      semanticsEnabled: _boolParam(params, 'semantics') ?? true,
    );
  }

  final String scenarioId;
  final int frames;
  final int warmupFrames;
  final double frameBudgetMs;
  final Duration timeout;
  final bool semanticsEnabled;
}

int? _intParam(web.URLSearchParams params, String name) {
  final raw = params.get(name);
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw);
}

double? _doubleParam(web.URLSearchParams params, String name) {
  final raw = params.get(name);
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw);
}

bool? _boolParam(web.URLSearchParams params, String name) {
  final raw = params.get(name)?.toLowerCase();
  if (raw == null || raw.isEmpty) return null;
  return switch (raw) {
    '1' || 'true' || 'on' || 'yes' => true,
    '0' || 'false' || 'off' || 'no' => false,
    _ => null,
  };
}

final class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp({
    super.key,
    required this.scenario,
    required this.textInputController,
  });

  final WebBenchmarkScenario scenario;
  final TextEditingController textInputController;

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

final class _BenchmarkAppState extends State<_BenchmarkApp> {
  final _scenarioKey = GlobalKey<DrivenWebBenchmarkScenarioState>();

  void advance(int step) {
    _scenarioKey.currentState?.advance(step);
  }

  @override
  Widget build(BuildContext context) {
    return DrivenWebBenchmarkScenario(
      key: _scenarioKey,
      scenario: widget.scenario,
      textInputController: widget.textInputController,
    );
  }
}
