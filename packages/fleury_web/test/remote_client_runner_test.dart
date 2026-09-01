// The serve entrypoint's connect step must surface a failed initial connect
// (stale/wrong token, server down, rejected upgrade) to the page instead of
// leaving it stuck at "connecting…" forever — the failure only reachable via
// the devtools console.

@TestOn('browser')
library;

import 'dart:async';

import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// A frame source whose start() rejects the way WireFrameSource does when the
/// socket closes before it ever opens (WireFrameSource._failOpen).
final class _FailingFrameSource implements BrowserFrameSource {
  @override
  Future<MountedApp> start(BrowserHostComponents components) async {
    throw StateError(
      'fleury serve connection closed before it opened: ws://x/',
    );
  }
}

/// A frame source that starts cleanly, returning a wire-style mounted session.
final class _SucceedingFrameSource implements BrowserFrameSource {
  _SucceedingFrameSource({this.startInput = false});

  /// Starts the DOM input listeners the way WireFrameSource._onOpen does.
  final bool startInput;

  @override
  Future<MountedApp> start(BrowserHostComponents components) async {
    if (startInput) components.inputSource.start((_) {});
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
    final app = await connectRemoteClient(
      host: host,
      source: _FailingFrameSource(),
    );
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

  test(
    'a successful connect marks the page connected with no error banner',
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
    },
  );

  test('a click on the served page chrome takes keyboard capture back', () {
    // The served page IS the app: its `#status` line sits outside the host,
    // and the host has chrome (a padding ring) the grid does not cover.
    // Clicking either blurs the hidden capture textarea — which sweeps held
    // keys and clears the focus coordinator — and every keystroke is dead for
    // the rest of the session with no cue. The serve entrypoint therefore
    // assembles the host with document-wide capture recovery.
    final status = web.document.createElement('div')..id = 'status';
    final elsewhere =
        web.document.createElement('input') as web.HTMLInputElement;
    web.document.body!.appendChild(status);
    web.document.body!.appendChild(elsewhere);
    addTearDown(() {
      status.remove();
      elsewhere.remove();
    });

    MountedApp? app;
    unawaited(
      connectRemoteClient(
        host: host,
        source: _SucceedingFrameSource(startInput: true),
      ).then((mounted) => app = mounted),
    );
    addTearDown(() async => app?.dispose());

    final textArea = host.querySelector('textarea');
    expect(textArea, isNotNull, reason: 'the client injects a capture area');
    expect(web.document.activeElement, same(textArea));

    elsewhere.focus();
    expect(web.document.activeElement, same(elsewhere));

    status.dispatchEvent(
      web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          pointerId: 9,
          clientX: 1,
          clientY: 1,
          button: 0,
          buttons: 1,
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    expect(web.document.activeElement, same(textArea));
  });
}
