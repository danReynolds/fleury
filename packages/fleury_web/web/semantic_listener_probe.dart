// Live native listener counts for the shared semantic DOM presenter.
// Compile this as benchmark_capture.dart.js in a capture page directory, then
// use tool/web_frame_capture.dart --page-dir=... --frames=64 (passive labels).
// The presenter remains mounted until the capture process closes so Chrome's
// Memory.getDOMCounters observes its live listeners, not a disposed snapshot.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:web/web.dart' as web;

void main() {
  final labels = int.parse(Uri.base.queryParameters['frames'] ?? '64');
  final root = web.document.createElement('div');
  web.document.body!.appendChild(root);
  final presenter = SemanticDomPresenter(root: root);
  final requests = <String>[];
  presenter.onSemanticActionRequest = (id, action) {
    requests.add('${id.value}:${action.name}');
  };
  final tree = SemanticTree(
    root: SemanticNode(
      id: const SemanticNodeId('root'),
      role: SemanticRole.app,
      actions: const {SemanticAction.activate},
      children: [
        for (var i = 0; i < labels; i++)
          SemanticNode(
            id: SemanticNodeId('label-$i'),
            role: SemanticRole.text,
            label: 'Service $i ready',
          ),
        const SemanticNode(
          id: SemanticNodeId('run'),
          role: SemanticRole.button,
          label: 'Run',
          actions: {SemanticAction.activate},
        ),
        const SemanticNode(
          id: SemanticNodeId('stop'),
          role: SemanticRole.button,
          label: 'Stop',
          actions: {SemanticAction.activate},
        ),
        const SemanticNode(
          id: SemanticNodeId('disabled'),
          role: SemanticRole.text,
          label: 'Unavailable',
          enabled: false,
        ),
      ],
    ),
  );
  presenter.present(tree);
  bool click(String id) {
    final event = web.Event(
      'click',
      web.EventInit(bubbles: true, cancelable: true),
    );
    root.querySelector('[data-fleury-semantic-id="$id"]')!.dispatchEvent(event);
    return event.defaultPrevented;
  }

  final prevented = [click('run'), click('label-0'), click('disabled')];
  if (requests.join(',') != 'run:activate,root:activate' ||
      prevented.any((value) => !value)) {
    throw StateError('Semantic action or disabled-node behavior changed');
  }
  var fingerprint = 0x811c9dc5;
  for (final unit in (root.outerHTML as JSString).toDart.codeUnits) {
    fingerprint = ((fingerprint ^ unit) * 0x01000193) & 0xffffffff;
  }
  final capture = {
    'kind': 'fleurySemanticListenerProbe',
    'passiveLabels': labels,
    'semanticNodes': tree.nodeCount,
    'fingerprint': fingerprint,
    'requests': requests,
    'defaultPrevented': prevented,
    'summary': {'frameCount': 1},
  };
  globalContext.setProperty('__fleuryWebBenchmarkError'.toJS, ''.toJS);
  globalContext.setProperty(
    '__fleuryWebBenchmarkCaptureJson'.toJS,
    jsonEncode(capture).toJS,
  );
  globalContext.setProperty('__fleuryWebBenchmarkDone'.toJS, true.toJS);
}
