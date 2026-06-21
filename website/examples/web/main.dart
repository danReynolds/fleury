// Entry point for the docs example bundle. Compiled to JS with:
//   dart compile js web/main.dart -o <site>/public/fleury-examples.js
//
// It scans the page for `<div data-fleury-example="<id>">` hosts and mounts the
// matching example into each, fully client-side. It also exposes
// `window.fleuryMountExamples()` so the docs site can re-scan after Astro
// client-side navigations (the dart2js `main` only runs on the first load).
import 'dart:async';
import 'dart:js_interop';

import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

// Exposes `window.fleuryMountExamples()` for the docs site to call after
// client-side navigations.
@JS('fleuryMountExamples')
external set _fleuryMountExamples(JSFunction value);

void main() {
  _fleuryMountExamples = (() => _mountAll()).toJS;
  _mountAll();
}

void _mountAll() {
  final hosts = web.document.querySelectorAll('[data-fleury-example]');
  for (var i = 0; i < hosts.length; i++) {
    final node = hosts.item(i);
    if (node is! web.Element) continue;
    if (node.getAttribute('data-fleury-state') != null) continue; // mounted
    mountExample(node);
  }
}

/// Mounts the example named by `data-fleury-example` into [host].
void mountExample(web.Element host) {
  final id = host.getAttribute('data-fleury-example');
  final builder = id == null ? null : examples[id];
  if (builder == null) {
    host.textContent = 'Unknown Fleury example: $id';
    return;
  }
  host.setAttribute('data-fleury-state', 'mounting');
  unawaited(
    runTuiWebDom(builder, hostElement: host).then(
      (_) => host.setAttribute('data-fleury-state', 'ready'),
    ),
  );
}
