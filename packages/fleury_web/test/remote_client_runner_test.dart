// The serve entrypoint's connect step must surface a failed initial connect
// (stale/wrong token, server down, rejected upgrade) to the page instead of
// leaving it stuck at "connecting…" forever — the failure only reachable via
// the devtools console.

@TestOn('browser')
library;

import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// A frame source whose start() rejects the way WireFrameSource does when the
/// socket closes before it ever opens (WireFrameSource._failOpen).
final class _FailingFrameSource implements BrowserFrameSource {
  @override
  Future<MountedApp> start(BrowserHostComponents components) async {
    throw StateError('fleury serve connection closed before it opened: ws://x/');
  }
}

/// A frame source that starts cleanly, returning a wire-style mounted session.
final class _SucceedingFrameSource implements BrowserFrameSource {
  @override
  Future<MountedApp> start(BrowserHostComponents components) async {
    return MountedApp.forFrameSource(
      surface: components.surface,
      cellMetrics: components.metrics,
      inputSource: components.inputSource,
      semanticPresenter: components.semanticPresenter,
      semanticFlushScheduler: components.semanticFlushScheduler,
      disposeHostResources: components.removeGeneratedRoots,
    );
  }
}

void main() {
  late web.HTMLElement host;

  setUp(() {
    host = web.document.createElement('div') as web.HTMLElement;
    host.id = 'fleury-remote';
    web.document.body!.appendChild(host);
  });

  tearDown(() {
    host.remove();
    web.document.body!.removeAttribute('data-fleury-remote-client');
  });

  test('a failed connect surfaces an error and a retry affordance, not a stuck '
      '"connecting…"', () async {
    final app = await connectRemoteClient(host: host, source: _FailingFrameSource());
    expect(app, isNull);

    // The serve page's #status observer only leaves "connecting…" when this
    // attribute changes; on failure it must be driven to a visible error, not
    // left unset (which is the eternal-"connecting…" bug).
    final status = web.document.body!.getAttribute('data-fleury-remote-client');
    expect(status, isNotNull, reason: 'the status observer must be driven');
    expect(status, isNot('connected'));
    expect(status!.toLowerCase(), contains('failed'));

    // And a visible, clickable retry affordance over the (torn-down) grid.
    final banner = host.querySelector('[data-fleury-connection-error]');
    expect(banner, isNotNull, reason: 'a visible failure/retry banner');
    expect(banner!.textContent!.toLowerCase(), contains('retry'));
  });

  test('a successful connect marks the page connected with no error banner',
      () async {
    final app = await connectRemoteClient(
      host: host,
      source: _SucceedingFrameSource(),
    );
    addTearDown(() async => app?.dispose());

    expect(
      web.document.body!.getAttribute('data-fleury-remote-client'),
      'connected',
    );
    expect(host.querySelector('[data-fleury-connection-error]'), isNull);
  });
}
