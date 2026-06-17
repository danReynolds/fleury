import 'dart:async';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  unawaited(_run());
}

Future<void> _run() async {
  await runDomDemo();
}

Future<TuiSurfaceHost> runDomDemo({
  web.Element? hostElement,
  FrameFlushScheduler? flushScheduler,
}) async {
  final host = hostElement ?? _hostElement();
  final instrumentation = _ReadyMarkerInstrumentation();
  final surfaceHost = await runTuiWebDom(
    () => const _DomDemoApp(),
    hostElement: host,
    flushScheduler: flushScheduler,
    instrumentation: instrumentation,
  );
  web.document.body?.setAttribute('data-fleury-dom-demo', 'mounted');
  instrumentation.firstFrame.then((_) {
    web.document.body?.setAttribute('data-fleury-dom-demo', 'ready');
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

final class _ReadyMarkerInstrumentation implements WebHostInstrumentation {
  final Completer<void> _firstFrame = Completer<void>();

  Future<void> get firstFrame => _firstFrame.future;

  @override
  void recordFrame(WebFrameInstrumentation frame) {
    if (!_firstFrame.isCompleted) _firstFrame.complete();
  }

  @override
  void recordSemanticFlush(WebSemanticFlushInstrumentation flush) {}
}

final class _DomDemoApp extends StatefulWidget {
  const _DomDemoApp();

  @override
  State<_DomDemoApp> createState() => _DomDemoAppState();
}

final class _DomDemoAppState extends State<_DomDemoApp> {
  final _controller = TextEditingController();
  var _count = 0;
  var _lastSubmit = 'none';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    setState(() {
      _count += 1;
      _lastSubmit = value.isEmpty ? 'empty' : value;
      _controller.clear();
    });
  }

  void _incrementFromSemantics(SemanticAction action) {
    if (action != SemanticAction.activate) return;
    setState(() {
      _count += 1;
      _lastSubmit = 'semantic action';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      id: const SemanticNodeId('dom-demo-root'),
      role: SemanticRole.app,
      label: 'Fleury retained DOM demo',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fleury retained DOM',
              style: CellStyle(bold: true, foreground: AnsiColor(6)),
            ),
            const Text(''),
            Semantics(
              id: const SemanticNodeId('dom-demo-counter'),
              role: SemanticRole.status,
              label: 'Counter',
              value: '$_count',
              child: Text(
                'counter  $_count',
                style: const CellStyle(bold: true, foreground: AnsiColor(2)),
              ),
            ),
            const Text(''),
            const Text('Entry'),
            TextInput(
              controller: _controller,
              autofocus: true,
              placeholder: 'submit text',
              onSubmit: _submit,
            ),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, child) {
                final text = _controller.text;
                return Text(
                  'draft length  ${text.length}',
                  style: const CellStyle(dim: true),
                );
              },
            ),
            const Text(''),
            Semantics(
              id: const SemanticNodeId('dom-demo-action'),
              role: SemanticRole.button,
              label: 'Increment counter',
              actions: const {SemanticAction.activate},
              onAction: _incrementFromSemantics,
              child: const Text('[ increment ]'),
            ),
            const Text(''),
            Semantics(
              id: const SemanticNodeId('dom-demo-status'),
              role: SemanticRole.status,
              label: 'Last submitted value',
              value: _lastSubmit,
              child: Text('last submit  $_lastSubmit'),
            ),
          ],
        ),
      ),
    );
  }
}
