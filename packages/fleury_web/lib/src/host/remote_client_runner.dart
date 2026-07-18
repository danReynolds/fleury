// The serve entrypoint's connect step, factored out of web/remote_client.dart
// so the failure-surfacing is unit-testable (the entrypoint itself is a bare
// dart2js `main`). Attaches a frame source to a fresh BrowserPresentationHost
// and reports the outcome to the page.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'browser_presentation_host.dart';
import '../run_tui_surface.dart' show MountedApp;

/// The `data-fleury-remote-client` value the serve page's #status observer
/// swaps in for "connecting…" once the session is live.
const String _connectedStatus = 'connected';

/// Shown when the connection never opens. The browser deliberately hides WHY a
/// WebSocket upgrade failed (a 401 from a stale/wrong `?token=` and a refused
/// connection from a down/restarting server are indistinguishable to script),
/// so the message names both likely causes rather than guessing one.
const String _failedStatus =
    'Connection failed — check the token, or that fleury serve is running.';

/// Attaches [source] to a [BrowserPresentationHost] rendering into [host] and
/// surfaces the outcome on the page.
///
/// On success the `data-fleury-remote-client` attribute is set to `connected`
/// and the mounted session is returned. On a pre-open connection failure —
/// stale/wrong token, server down or restarting, or a rejected upgrade, all of
/// which close the socket before it opens and reject [BrowserFrameSource.start]
/// — the failure is surfaced (see [_surfaceConnectionFailure]) and null is
/// returned, instead of leaving the page stuck at "connecting…" forever with
/// the error visible only in the devtools console.
Future<MountedApp?> connectRemoteClient({
  required web.Element host,
  required BrowserFrameSource source,
  web.Document? document,
}) async {
  final doc = document ?? web.document;
  try {
    final app = await BrowserPresentationHost(into: host).attach(source);
    doc.body?.setAttribute('data-fleury-remote-client', _connectedStatus);
    return app;
  } catch (error) {
    web.console.error(
      'fleury: remote client failed to connect: $error'.toJS,
    );
    _surfaceConnectionFailure(host, doc);
    return null;
  }
}

/// Surfaces a failed initial connect on the page: drives the #status observer
/// off "connecting…" and shows a click-to-retry banner over the (now
/// torn-down) grid, so the user sees an auth/server error instead of a page
/// that appears to hang forever.
void _surfaceConnectionFailure(web.Element host, web.Document doc) {
  // Setting the attribute the serve page's MutationObserver watches replaces
  // the corner "connecting…" text with the failure message.
  doc.body?.setAttribute('data-fleury-remote-client', _failedStatus);

  // Idempotent: a caller that retries into the same host must not stack banners.
  if (host.querySelector('[data-fleury-connection-error]') != null) return;
  final banner = doc.createElement('div') as web.HTMLElement;
  banner.setAttribute('data-fleury-connection-error', '');
  banner.textContent = '⚠ $_failedStatus  Click to retry.';
  final style = banner.style;
  style.setProperty('position', 'fixed');
  style.setProperty('left', '0');
  style.setProperty('right', '0');
  style.setProperty('top', '0');
  style.setProperty('padding', '8px 12px');
  style.setProperty('background', 'rgba(120, 18, 18, 0.95)');
  style.setProperty('color', '#fff');
  style.setProperty('font', '13px ui-monospace, monospace');
  style.setProperty('text-align', 'center');
  style.setProperty('cursor', 'pointer');
  style.setProperty('z-index', '2147483647');
  // A reload re-runs the entrypoint — the retry — matching the mid-session
  // disconnect banner's behavior.
  banner.addEventListener(
    'click',
    ((web.Event _) => web.window.location.reload()).toJS,
  );
  host.appendChild(banner);
}
