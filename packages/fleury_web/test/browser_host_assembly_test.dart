// The anti-drift oracle for the browser host assembly: every frame source
// receives the SAME component set from BrowserPresentationHost.assemble().
// The serve client historically lacked focus coordination, clipboard, and
// caret sync because it hand-assembled its own stack — this test makes
// that class of gap structurally impossible: a source can't lack a
// component, because the host built it before the source ever ran.

@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// Records the component set without starting a session.
final class _RecordingSource implements BrowserFrameSource {
  BrowserHostComponents? components;

  @override
  Future<MountedApp> start(BrowserHostComponents components) {
    this.components = components;
    throw _Recorded();
  }
}

final class _Recorded implements Exception {}

void main() {
  test('the host assembles the full component set for any source', () async {
    final into = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(into);
    addTearDown(() => into.remove());

    final host = BrowserPresentationHost(into: into);
    final source = _RecordingSource();
    await expectLater(host.attach(source), throwsA(isA<_Recorded>()));

    final components = source.components!;
    expect(components.surface, isNotNull, reason: 'DOM grid surface');
    expect(components.metrics, isNotNull, reason: 'cell metrics');
    expect(components.inputSource, isNotNull, reason: 'DOM input');
    expect(
      components.semanticPresenter,
      isNotNull,
      reason: 'semantic DOM mirror is on by default',
    );
    expect(components.focusCoordinator, isNotNull, reason: 'focus');
    expect(components.clipboard, isNotNull, reason: 'clipboard');
    expect(components.instrumentation, isNotNull, reason: 'instrumentation');

    // Failure path removed the generated roots.
    expect(into.children.length, 0, reason: 'generated roots cleaned up');
  });

  test('mountApp and a direct attach produce identical assemblies', () async {
    final intoA = web.document.createElement('div') as web.HTMLElement;
    final intoB = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(intoA);
    web.document.body!.appendChild(intoB);
    addTearDown(() => intoA.remove());
    addTearDown(() => intoB.remove());

    // mountApp path.
    final appA = await mountApp(() => const Text('assembly A'), into: intoA);
    addTearDown(appA.dispose);

    // Direct host + local source path (what the web render backend and the
    // serve client ride).
    final appB = await BrowserPresentationHost(
      into: intoB,
    ).attach(LocalRuntimeFrameSource(() => const Text('assembly B')));
    addTearDown(appB.dispose);

    String shape(web.HTMLElement el) => [
      for (var i = 0; i < el.children.length; i++)
        (el.children.item(i)! as web.HTMLElement).tagName,
    ].join(',');

    // Both paths mount the same DOM shape (surface root, semantic root,
    // and the input source's keyboard-capture element), in the same order.
    expect(shape(intoA), shape(intoB));
    expect(intoA.children.length, intoB.children.length);
    expect(
      intoA.children.length,
      greaterThanOrEqualTo(2),
      reason: 'surface root + semantic root at minimum',
    );

    // Both sessions render and answer semantic idles — the full stack is
    // live in each.
    await appA.awaitSemanticIdle();
    await appB.awaitSemanticIdle();
  });

  test('semanticsEnabled: false requires the diagnostics opt-in', () {
    final into = web.document.createElement('div') as web.HTMLElement;
    expect(
      () => BrowserPresentationHost(
        into: into,
        semanticsEnabled: false,
      ).assemble(),
      throwsStateError,
    );
  });
}
