// Entry point for the docs example bundle. Compiled to JS with:
//   dart compile js web/main.dart -o <site>/public/fleury-examples.js
//
// It scans the page for `<div data-fleury-example="<id>">` hosts and mounts the
// matching example into each, fully client-side. It also exposes
// `window.fleuryMountExamples()` so the docs site can re-scan after Astro
// client-side navigations (the dart2js `main` only runs on the first load).
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

// `window.fleuryMountExamples()` — re-scan the page after client-side
// navigations (the dart2js `main` only runs once).
@JS('fleuryMountExamples')
external set _fleuryMountExamples(JSFunction value);

// `window.fleuryMountInto(hostElement, id)` — mount one example into a given
// element (used by the fullscreen overlay) and return a `{ dispose }` handle so
// the caller can tear it down (and stop any ticker) on close.
@JS('fleuryMountInto')
external set _fleuryMountInto(JSFunction value);

void main() {
  _fleuryMountExamples = (() => _mountAll()).toJS;
  _fleuryMountInto =
      ((web.Element host, String id) => _mountInto(host, id)).toJS;
  _mountAll();
}

JSObject _mountInto(web.Element host, String id) {
  final builder = examples[id];
  TuiSurfaceHost? surface;
  var disposed = false;
  if (builder != null) {
    unawaited(runTuiWebDom(builder, hostElement: host).then((h) {
      if (disposed) {
        h.dispose();
      } else {
        surface = h;
      }
    }));
  }
  final handle = JSObject();
  handle['dispose'] = (() {
    disposed = true;
    surface?.dispose();
    surface = null;
  }).toJS;
  return handle;
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
