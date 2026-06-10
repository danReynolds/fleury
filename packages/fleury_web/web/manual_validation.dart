import 'dart:async';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  unawaited(_run());
}

Future<void> _run() async {
  await runManualValidation();
}

Future<TuiSurfaceHost> runManualValidation({
  web.Element? hostElement,
  FrameFlushScheduler? flushScheduler,
}) async {
  final host = hostElement ?? _hostElement();
  _applyHostStyle(host);
  final provenance = _ManualValidationProvenance.capture();
  provenance.applyToBody();
  final instrumentation = _ReadyMarkerInstrumentation();
  final surfaceHost = await runTuiWebDom(
    () => _ManualValidationApp(provenance: provenance),
    hostElement: host,
    flushScheduler: flushScheduler,
    instrumentation: instrumentation,
  );
  web.document.body?.setAttribute('data-fleury-manual-validation', 'mounted');
  instrumentation.firstFrame.then((_) {
    web.document.body?.setAttribute('data-fleury-manual-validation', 'ready');
  });
  return surfaceHost;
}

web.Element _hostElement() {
  final existing = web.document.querySelector('#fleury-app');
  if (existing != null) return existing;
  final element = web.document.createElement('div');
  element.id = 'fleury-app';
  web.document.body?.appendChild(element);
  return element;
}

void _applyHostStyle(web.Element host) {
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;width:96ch;height:420px;'
        'font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;'
        'font-size:16px;line-height:18px;overflow:hidden;'
        'background:#050505;color:#f5f5f5;padding:8px;',
  );
}

final class _ManualValidationProvenance {
  const _ManualValidationProvenance({
    required this.browserVersion,
    required this.platform,
    required this.userAgent,
    required this.page,
  });

  factory _ManualValidationProvenance.capture() {
    final navigator = web.window.navigator;
    final userAgent = navigator.userAgent;
    return _ManualValidationProvenance(
      browserVersion: _browserVersionFromUserAgent(userAgent),
      platform: navigator.platform,
      userAgent: userAgent,
      page: 'manual_validation.html',
    );
  }

  final String browserVersion;
  final String platform;
  final String userAgent;
  final String page;

  void applyToBody() {
    final body = web.document.body;
    if (body == null) return;
    body
      ..setAttribute('data-fleury-manual-browser-version', browserVersion)
      ..setAttribute('data-fleury-manual-platform', platform)
      ..setAttribute('data-fleury-manual-user-agent', userAgent)
      ..setAttribute('data-fleury-manual-page', page);
  }
}

String _browserVersionFromUserAgent(String userAgent) {
  final browserMatch = RegExp(
    r'(HeadlessChrome|Chrome|Chromium|CriOS|Edg)/[^\s]+',
  ).firstMatch(userAgent);
  if (browserMatch != null) return browserMatch.group(0)!;
  return userAgent.trim().isEmpty ? 'unknown' : userAgent;
}

final class _ReadyMarkerInstrumentation implements WebHostInstrumentation {
  final Completer<void> _firstFrame = Completer<void>();

  Future<void> get firstFrame => _firstFrame.future;

  @override
  void recordFrame(WebFrameInstrumentation frame) {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }
}

final class _ManualValidationApp extends StatefulWidget {
  const _ManualValidationApp({required this.provenance});

  final _ManualValidationProvenance provenance;

  @override
  State<_ManualValidationApp> createState() => _ManualValidationAppState();
}

final class _ManualValidationAppState extends State<_ManualValidationApp> {
  final _controller = TextEditingController(text: 'type with IME here');
  var _lastAction = 'none';
  var _submitCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      id: const SemanticNodeId('manual-validation-root'),
      role: SemanticRole.app,
      label: 'Fleury web manual validation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fleury retained DOM manual validation',
            style: CellStyle(bold: true, foreground: AnsiColor(4)),
          ),
          const Text(''),
          const Text('IME field:'),
          TextInput(
            controller: _controller,
            autofocus: true,
            placeholder: 'IME command',
            onSubmit: (value) {
              setState(() {
                _submitCount += 1;
                _lastAction = 'submitted "$value"';
              });
            },
          ),
          const Text(''),
          Semantics(
            id: const SemanticNodeId('manual-validation-action'),
            role: SemanticRole.button,
            label: 'Run sample action',
            actions: const {SemanticAction.activate},
            onAction: (action) {
              setState(() => _lastAction = 'semantic ${action.name}');
            },
            child: const Text('[ Run sample action ]'),
          ),
          Semantics(
            id: const SemanticNodeId('manual-validation-link'),
            role: SemanticRole.link,
            label: 'Fleury project link',
            value: 'https://github.com/',
            actions: const {SemanticAction.open},
            state: const SemanticState({
              'linkUrl': 'https://github.com/',
              'safeLinkScheme': true,
            }),
            child: const Text('Link: https://github.com/'),
          ),
          const Text(''),
          Semantics(
            id: const SemanticNodeId('manual-validation-status'),
            role: SemanticRole.status,
            label: 'Manual validation status',
            value: 'Last action $_lastAction, submissions $_submitCount',
            child: Text(
              'status: last action $_lastAction | submissions $_submitCount',
            ),
          ),
          const Text(''),
          Semantics(
            id: const SemanticNodeId('manual-validation-provenance'),
            role: SemanticRole.status,
            label: 'Manual validation evidence metadata',
            value:
                'Browser ${widget.provenance.browserVersion}, platform '
                '${widget.provenance.platform}, page ${widget.provenance.page}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Evidence browser: ${widget.provenance.browserVersion}'),
                Text('Evidence platform: ${widget.provenance.platform}'),
                Text('Evidence page: ${widget.provenance.page}'),
              ],
            ),
          ),
          const Text(''),
          const Text(
            'Expected: visual grid is hidden from AT, semantic DOM exposes the '
            'focused textbox, action, link, and status without reading every '
            'visual row as a live terminal log.',
            style: CellStyle(dim: true),
          ),
        ],
      ),
    );
  }
}
