// dart2js entrypoint for the structured serve client. `fleury serve`
// embeds the compiled output and serves it in place of a terminal-emulator
// page; it renders a remote session through the SAME browser presentation
// host the embed path uses — one assembly (surface, metrics, input,
// semantics mirror, focus, clipboard), with the wire as the frame source.

import 'dart:async';

import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  // connectRemoteClient surfaces a failed initial connect (stale/wrong token,
  // server down, rejected upgrade) on the page and swallows it, so the future
  // never rejects — unawaited is safe and cannot become a silent uncaught
  // promise rejection.
  unawaited(
    connectRemoteClient(
      host: _hostElement(),
      source: WireFrameSource(url: _socketUrl()),
    ),
  );
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
/// same host with the ws(s) scheme. When the page was opened with a
/// `?token=` (fleury serve --token=...), forward it so the upgrade
/// passes the server's auth check.
String _socketUrl() {
  final loc = web.window.location;
  final scheme = loc.protocol == 'https:' ? 'wss' : 'ws';
  final token = Uri.parse(loc.href).queryParameters['token'];
  final query = token == null || token.isEmpty
      ? ''
      : '?token=${Uri.encodeQueryComponent(token)}';
  return '$scheme://${loc.host}/ws$query';
}
