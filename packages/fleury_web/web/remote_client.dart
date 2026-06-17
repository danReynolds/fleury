// dart2js entrypoint for the structured serve client. `fleury serve`
// embeds the compiled output and serves it in place of the xterm.js page;
// it renders a remote session through the retained DOM surface.

import 'dart:async';

import 'package:fleury_web/src/remote_client/remote_surface_client.dart';
import 'package:web/web.dart' as web;

void main() {
  unawaited(_run());
}

Future<void> _run() async {
  final host = _hostElement();
  final url = _socketUrl();
  final client = RemoteSurfaceClient(hostElement: host, url: url);
  await client.start();
  web.document.body?.setAttribute('data-fleury-remote-client', 'connected');
}

web.Element _hostElement() {
  final existing = web.document.querySelector('#fleury-remote');
  if (existing != null) return existing;
  final element = web.document.createElement('div');
  element.id = 'fleury-remote';
  web.document.body?.appendChild(element);
  return element;
}

/// The serve page is served same-origin, so the WebSocket lives at the
/// same host with the ws(s) scheme.
String _socketUrl() {
  final loc = web.window.location;
  final scheme = loc.protocol == 'https:' ? 'wss' : 'ws';
  return '$scheme://${loc.host}/ws';
}
