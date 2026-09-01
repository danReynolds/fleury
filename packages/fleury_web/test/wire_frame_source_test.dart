// The serve client's handling of the v3 parity frames, driven directly
// (no socket): CLIPBOARD_WRITE lands on the host-assembled clipboard and
// answers with CLIPBOARD_RESULT; CARET positions the IME capture element
// without error; a failed action result logs rather than throws.

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

final class _RecordingClipboard extends Clipboard {
  final writes = <String>[];
  var deny = false;

  @override
  String? readInProcess() => writes.isEmpty ? null : writes.last;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    writes.add(text);
    return ClipboardWriteReport(
      result: deny
          ? ClipboardWriteResult.inProcessOnly
          : ClipboardWriteResult.platformTool,
      resolution: resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.clipboardWrite,
          level: CapabilityLevel.preferred,
        ),
        const CapabilityTruth(
          feature: TerminalFeature.clipboardWrite,
          support: CapabilitySupport.supported,
          enablement: CapabilityEnablement.notApplicable,
          delivery: CapabilityDelivery.delivered,
          evidence: <CapabilityEvidence>[
            CapabilityEvidence(
              source: CapabilityEvidenceSource.operationResult,
              detail: 'Test clipboard acknowledged the write.',
            ),
          ],
        ),
      ),
      policy: policy,
      payloadBytes: text.length,
      osc52EncodedLength: 0,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }
}

List<RemoteFrame> _decodeAll(List<Uint8List> wire) {
  final decoder = FrameDecoder();
  for (final bytes in wire) {
    decoder.feed(bytes);
  }
  return decoder.drain().toList();
}

InitFrame _appInit(int protocolVersion) => InitFrame(
  size: const CellSize(80, 24),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
  protocolVersion: protocolVersion,
);

/// Hand-builds one wire frame: `[typeByte][4-byte big-endian length][payload]`.
/// Used to synthesize a framed-but-malformed frame — a VALID length header the
/// decoder consumes, followed by a payload `_decode` rejects (a RECOVERABLE
/// decode error, framing intact).
Uint8List _framedRaw(int typeByte, List<int> payload) {
  final len = payload.length;
  return Uint8List.fromList([
    typeByte,
    (len >> 24) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 8) & 0xFF,
    len & 0xFF,
    ...payload,
  ]);
}

void main() {
  late web.HTMLElement into;
  late _RecordingClipboard clipboard;
  late BrowserHostComponents components;
  late WireFrameSource source;
  late MountedApp mounted;

  ({
    web.HTMLElement host,
    BrowserHostComponents components,
    WireFrameSource source,
  })
  attachUnnegotiated() {
    final host = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(host);
    final components = BrowserPresentationHost(into: host).assemble();
    final source = WireFrameSource(url: 'ws://unused-unnegotiated/');
    final mounted = source.attachComponentsForTest(components);
    addTearDown(() async {
      await mounted.dispose();
      host.remove();
    });
    return (host: host, components: components, source: source);
  }

  setUp(() {
    into = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(into);
    clipboard = _RecordingClipboard();
    components = BrowserPresentationHost(
      into: into,
      clipboard: clipboard,
    ).assemble();
    source = WireFrameSource(url: 'ws://unused/');
    mounted = source.attachComponentsForTest(components);
    source.handleFrameForTest(_appInit(remoteProtocolVersion));
    addTearDown(() async {
      await mounted.dispose();
      into.remove();
    });
  });

  test('an on-open setup failure rejects start and tears down partial browser '
      'resources', () async {
    final failedInto = web.document.createElement('div') as web.HTMLElement;
    web.document.body!.appendChild(failedInto);
    addTearDown(() => failedInto.remove());
    final bodyChildrenBeforeAttach = web.document.body!.children.length;
    final failure = StateError('injected on-open setup failure');
    final failingSource = WireFrameSource(
      url: 'ws://127.0.0.1:1/fleury-open-failure',
    )..openSetupHookForTest = () => throw failure;

    final start = BrowserPresentationHost(
      into: failedInto,
    ).attach(failingSource);
    // Drive the production WebSocket callback synchronously. The injected hook
    // throws after input has started, which used to escape to JavaScript and
    // leave BrowserPresentationHost.attach pending forever.
    failingSource.socketForTest!.dispatchEvent(web.Event('open'));

    await expectLater(
      start.timeout(const Duration(seconds: 1)),
      throwsA(same(failure)),
    );
    expect(failingSource.isClosedForTest, isTrue);
    expect(failingSource.bannerShownForTest, isFalse);
    expect(
      failedInto.children.length,
      0,
      reason: 'attach cleanup removed every generated partial-start root',
    );
    expect(
      web.document.body!.children.length,
      bodyChildrenBeforeAttach,
      reason: 'the partially-started metrics probe was removed',
    );
  });

  for (final failureCase
      in <({String label, web.Event Function() event, String message})>[
        (
          label: 'socket error',
          event: () => web.Event('error'),
          message: 'connection failed',
        ),
        (
          label: 'socket close',
          event: () => web.CloseEvent('close'),
          message: 'closed before it opened',
        ),
      ]) {
    test('a pre-open ${failureCase.label} rejects start and tears down the '
        'source and browser host', () async {
      final failedInto = web.document.createElement('div') as web.HTMLElement;
      web.document.body!.appendChild(failedInto);
      addTearDown(() => failedInto.remove());
      final bodyChildrenBeforeAttach = web.document.body!.children.length;
      final failingSource = WireFrameSource(
        url: 'ws://127.0.0.1:1/fleury-pre-open-failure',
      );

      final start = BrowserPresentationHost(
        into: failedInto,
      ).attach(failingSource);
      final socket = failingSource.socketForTest!;
      socket.dispatchEvent(failureCase.event());

      await expectLater(
        start.timeout(const Duration(seconds: 1)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(failureCase.message),
          ),
        ),
      );
      expect(failingSource.isClosedForTest, isTrue);
      expect(failingSource.socketForTest, isNull);
      expect(failingSource.bannerShownForTest, isFalse);
      expect(
        failedInto.children.length,
        0,
        reason: 'attach cleanup removed every generated root',
      );
      expect(
        web.document.body!.children.length,
        bodyChildrenBeforeAttach,
        reason: 'failed attachment removed the cell metrics probe',
      );
    });
  }

  test('CLIPBOARD_WRITE lands on the host clipboard and answers', () async {
    source.handleFrameForTest(const ClipboardWriteFrame(9, 'from the app'));
    await Future<void>.delayed(Duration.zero);

    expect(clipboard.writes, ['from the app']);
    final results = _decodeAll(
      source.sentForTest,
    ).whereType<ClipboardResultFrame>().toList();
    expect(results, hasLength(1));
    expect(results.single.seq, 9);
    expect(results.single.status, RemoteClipboardStatus.written);
  });

  test('a denied clipboard write answers denied', () async {
    clipboard.deny = true;
    source.handleFrameForTest(const ClipboardWriteFrame(3, 'nope'));
    await Future<void>.delayed(Duration.zero);

    final results = _decodeAll(
      source.sentForTest,
    ).whereType<ClipboardResultFrame>().toList();
    expect(results.single.seq, 3);
    expect(results.single.status, RemoteClipboardStatus.denied);
  });

  test('a wire-sized paste keeps its original single-frame encoding', () {
    const paste = PasteEvent('small\r\npaste 🌿');
    final expected = encodeFrame(const InputEventFrame(paste));

    source.sendInputForTest(paste);

    expect(source.sentForTest, hasLength(1));
    expect(source.sentForTest.single, orderedEquals(expected));
    final event =
        (_decodeAll(source.sentForTest).single as InputEventFrame).event;
    expect(event, paste);
  });

  test('oversized paste is segmented without splitting UTF-8 or newlines', () {
    final inputLimit = remoteFramePayloadLimit(FrameType.inputEvent);
    const segmentedOverhead = 1 + 4 + 1 + 4;
    final textBudget = inputLimit - segmentedOverhead;
    final text = '${'a' * (textBudget - 2)}😀${'b' * (textBudget - 5)}\r\nend';

    source.sendInputForTest(PasteEvent(text));

    final events = _decodeAll(source.sentForTest)
        .whereType<InputEventFrame>()
        .map((frame) => frame.event)
        .whereType<PasteEvent>()
        .toList();
    expect(events, hasLength(3));
    expect(events.map((event) => event.phase), [
      PasteEventPhase.start,
      PasteEventPhase.continuation,
      PasteEventPhase.end,
    ]);
    expect(events.map((event) => event.pasteId).toSet(), hasLength(1));
    expect(events.map((event) => event.text).join(), text);
    expect(events[1].text, startsWith('😀'));
    expect(events[1].text, isNot(endsWith('\r')));
    expect(events[2].text, startsWith('\r\n'));
    for (final wire in source.sentForTest) {
      final payloadLength = ByteData.sublistView(wire, 1, 5).getUint32(0);
      expect(payloadLength, lessThanOrEqualTo(inputLimit));
    }
  });

  test('paste above the bounded transaction cap is dropped whole', () {
    final text = 'a' * (defaultMaxRemoteFramePayloadLength + 1);

    source.sendInputForTest(PasteEvent(text));

    expect(source.sentForTest, isEmpty);
  });

  test('maximum accepted paste leaves startup control-frame headroom', () {
    final text = 'a' * source.maxPasteBytesForTest;

    source.sendInputForTest(PasteEvent(text));

    expect(source.sentForTest, isNotEmpty);
    final pasteWireBytes = source.sentForTest.fold<int>(
      0,
      (total, wire) => total + wire.length,
    );
    const frameHeaderBytes = 5;
    const queueCapacity = defaultMaxRemoteFramePayloadLength + frameHeaderBytes;
    expect(
      pasteWireBytes + maxRemoteControlFramePayloadLength + frameHeaderBytes,
      lessThanOrEqualTo(queueCapacity),
      reason: 'one queued INIT/control frame cannot make the paste overflow',
    );

    final initWire = encodeFrame(
      const InitFrame(
        size: CellSize(80, 24),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        images: InlineImageSupport.placements,
        hyperlinks: true,
      ),
    );
    expect(initWire.length + pasteWireBytes, lessThanOrEqualTo(queueCapacity));
  });

  test('CARET frames position the IME capture element without error', () {
    source.handleFrameForTest(CaretFrame(CellRect.fromLTWH(4, 2, 1, 1)));
    source.handleFrameForTest(const CaretFrame(null));
  });

  test('observed resize invalidates cached metrics, sends RESIZE, and '
      'repositions the last caret', () {
    into.setAttribute(
      'style',
      'position:absolute;left:10px;top:20px;width:160px;height:80px;'
          'padding:0;font-family:monospace;font-size:10px;line-height:10px;',
    );
    components.inputSource.start((_) {});
    source.handleObservedResizeForTest();
    source.handleFrameForTest(CaretFrame(CellRect.fromLTWH(4, 2, 1, 1)));

    final textArea = into.querySelector('textarea')!;
    final beforeLeft = textArea.getAttribute('data-fleury-caret-css-left');
    final beforeTop = textArea.getAttribute('data-fleury-caret-css-top');
    expect(textArea.getAttribute('data-fleury-caret-state'), 'positioned');
    expect(beforeLeft, isNotNull);
    expect(beforeTop, isNotNull);

    source.sentForTest.clear();
    into.setAttribute(
      'style',
      'position:absolute;left:40px;top:50px;width:640px;height:240px;'
          'padding-left:20px;font-family:monospace;font-size:20px;'
          'line-height:20px;',
    );
    source.handleObservedResizeForTest();

    final resizeFrames = _decodeAll(
      source.sentForTest,
    ).whereType<ResizeFrame>().toList();
    expect(resizeFrames, hasLength(1));
    expect(components.surface.size, resizeFrames.single.size);
    expect(
      textArea.getAttribute('data-fleury-caret-css-left'),
      isNot(beforeLeft),
    );
    expect(
      textArea.getAttribute('data-fleury-caret-css-top'),
      isNot(beforeTop),
    );
    expect(textArea.getAttribute('data-fleury-caret-state'), 'positioned');
  });

  test('production metrics observer routes host, font, and window signals '
      'through one refresh path', () async {
    into.setAttribute(
      'style',
      'position:absolute;left:10px;top:20px;width:320px;height:160px;'
          'padding:0;font-family:monospace;font-size:10px;line-height:10px;',
    );
    components.inputSource.start((_) {});
    source.handleObservedResizeForTest();
    source.handleFrameForTest(CaretFrame(CellRect.fromLTWH(4, 2, 1, 1)));
    source.sentForTest.clear();
    source.startObservingMetricsForTest();

    // Font readiness is not a host-size change. Changing the probe's font
    // pitch and dispatching the same signal a loaded webfont emits must still
    // remeasure, resize the surface, and tell the server.
    into.setAttribute(
      'style',
      'position:absolute;left:10px;top:20px;width:320px;height:160px;'
          'padding:0;font-family:monospace;font-size:20px;line-height:20px;',
    );
    web.document.fonts.dispatchEvent(web.Event('loadingdone'));

    var resizeFrames = _decodeAll(
      source.sentForTest,
    ).whereType<ResizeFrame>().toList();
    expect(resizeFrames, hasLength(1));
    expect(components.surface.size, resizeFrames.single.size);

    final textArea = into.querySelector('textarea')!;
    final beforeWindowLeft = textArea.getAttribute(
      'data-fleury-caret-css-left',
    );
    final beforeWindowTop = textArea.getAttribute('data-fleury-caret-css-top');
    source.sentForTest.clear();

    // Window resize is also the DPR/zoom invalidation signal. Keep the content
    // box and cell pitch fixed but move its viewport origin; no wire resize is
    // needed, while the hidden IME capture geometry must move.
    into.setAttribute(
      'style',
      'position:absolute;left:70px;top:90px;width:320px;height:160px;'
          'padding:0;font-family:monospace;font-size:20px;line-height:20px;',
    );
    web.window.dispatchEvent(web.Event('resize'));

    expect(_decodeAll(source.sentForTest).whereType<ResizeFrame>(), isEmpty);
    expect(
      textArea.getAttribute('data-fleury-caret-css-left'),
      isNot(beforeWindowLeft),
    );
    expect(
      textArea.getAttribute('data-fleury-caret-css-top'),
      isNot(beforeWindowTop),
    );
    source.sentForTest.clear();

    // The same CellMetrics observer also owns the host ResizeObserver. Its
    // callback is delivered on a browser rendering turn, so wait briefly for
    // the production callback rather than invoking the test seam.
    into.setAttribute(
      'style',
      'position:absolute;left:70px;top:90px;width:640px;height:240px;'
          'padding:0;font-family:monospace;font-size:20px;line-height:20px;',
    );
    for (var attempt = 0; attempt < 30; attempt++) {
      resizeFrames = _decodeAll(
        source.sentForTest,
      ).whereType<ResizeFrame>().toList();
      if (resizeFrames.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(resizeFrames, hasLength(1));
    expect(components.surface.size, resizeFrames.single.size);
  });

  test('a deliberate server close shows the reason the server gave', () {
    // `fleury serve` turns an over-cap browser away AFTER the WebSocket
    // upgrade precisely so the close can carry a code and a reason the page
    // can show. Overwriting it with the generic drop line throws that away —
    // the user hits the session cap and sees an unexplained disconnect.
    source.handleSocketCloseForTest(
      web.CloseEvent(
        'close',
        web.CloseEventInit(
          code: serveSessionLimitCloseCode,
          reason: 'session limit reached (1/1); raise with --max-sessions=<n>.',
        ),
      ),
    );

    expect(source.bannerShownForTest, isTrue);
    expect(into.textContent, contains('session limit reached'));
    expect(
      into.textContent,
      contains('reload to reconnect'),
      reason: 'the retry affordance stays',
    );
  });

  test('an ordinary drop keeps the generic disconnect message', () {
    source.handleSocketCloseForTest(web.CloseEvent('close'));

    expect(source.bannerShownForTest, isTrue);
    expect(into.textContent, contains('Disconnected from the fleury session'));
  });

  test(
    'disposing a disconnected session removes its reconnect banner',
    () async {
      source.handleFrameForTest(const ByeFrame());
      expect(source.bannerShownForTest, isTrue);
      expect(into.textContent, contains('reload to reconnect'));

      await mounted.dispose();

      expect(source.bannerShownForTest, isFalse);
      expect(into.children.length, 0);
      expect(into.parentNode, same(web.document.body));
    },
  );

  final earlyFrames = <({String label, RemoteFrame Function() build})>[
    (
      label: 'SEMANTICS',
      build: () {
        final encoder = SemanticsWireEncoder();
        return SemanticsFrame(
          encoder.encodeTree(
            const SemanticTree(
              root: SemanticNode(
                id: SemanticNodeId('early-root'),
                role: SemanticRole.app,
                children: [
                  SemanticNode(
                    id: SemanticNodeId('early-node'),
                    role: SemanticRole.text,
                    label: 'Must not present',
                  ),
                ],
              ),
            ),
          )!,
        );
      },
    ),
    (
      label: 'PLAN',
      build: () => const PlanFrame(
        RemotePlan(
          size: CellSize(2, 1),
          fullRepaint: true,
          styleTable: [],
          patches: [],
        ),
      ),
    ),
  ];
  for (final earlyFrame in earlyFrames) {
    test(
      '${earlyFrame.label} before echoed INIT tears down before presentation',
      () {
        final harness = attachUnnegotiated();
        harness.components.semanticPresenter!.present(
          const SemanticTree(
            root: SemanticNode(
              id: SemanticNodeId('retained-root'),
              role: SemanticRole.app,
              children: [
                SemanticNode(
                  id: SemanticNodeId('save'),
                  role: SemanticRole.button,
                  label: 'Save',
                  actions: {SemanticAction.activate},
                ),
              ],
            ),
          ),
        );
        final retainedButton = harness.host.querySelector(
          '[data-fleury-semantic-id="save"]',
        )!;
        var applyReached = false;
        harness.source.failApplyForTest = (_) {
          applyReached = true;
          return false;
        };

        harness.source.feedBytesForTest(encodeFrame(earlyFrame.build()));

        expect(harness.source.isClosedForTest, isTrue);
        expect(harness.source.bannerShownForTest, isTrue);
        expect(harness.host.textContent, contains('wire negotiation failed'));
        expect(
          applyReached,
          isFalse,
          reason: 'the negotiation gate runs before frame staging/apply',
        );
        expect(
          harness.host.querySelector('[data-fleury-semantic-id="early-node"]'),
          isNull,
          reason: 'pre-INIT semantics never reached the DOM presenter',
        );

        retainedButton.dispatchEvent(
          web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
        );
        harness.source.sendInputForTest(const TextInputEvent('x'));
        expect(
          harness.source.sentForTest,
          isEmpty,
          reason:
              'stable-id action and browser input stay inert after teardown',
        );
      },
    );
  }

  for (final appVersion in <int>[
    remoteProtocolVersion - 1,
    remoteProtocolVersion + 1,
  ]) {
    test('an echoed INIT at app v$appVersion rejects the browser v'
        '$remoteProtocolVersion session', () {
      source.handleFrameForTest(
        InitFrame(
          size: const CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: appVersion,
        ),
      );

      expect(source.isClosedForTest, isTrue);
      expect(source.bannerShownForTest, isTrue);
      expect(into.textContent, contains('wire protocol mismatch'));
      expect(into.textContent, contains('browser v$remoteProtocolVersion'));
      expect(into.textContent, contains('app v$appVersion'));
    });
  }

  test(
    'a future-version INIT cannot enable actions or present/send later frames',
    () {
      final encoder = SemanticsWireEncoder();
      SemanticTree tree({
        required String id,
        required String label,
        required String token,
      }) => SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId(id),
              role: SemanticRole.button,
              label: label,
              actions: const {SemanticAction.activate},
              actionTargetToken: token,
            ),
          ],
        ),
      );

      source.handleFrameForTest(
        SemanticsFrame(
          encoder.encodeTree(
            tree(id: 'element-7', label: 'Before skew', token: 'element.1'),
          )!,
        ),
      );
      final staleButton = into.querySelector(
        '[data-fleury-semantic-id="element-7"]',
      )!;
      source.sentForTest.clear();

      // Put the mismatch and a later semantic patch in one decoded batch. The
      // INIT must tear down synchronously, so the already-buffered patch is
      // never presented.
      final appVersion = remoteProtocolVersion + 1;
      final mismatch = encodeFrame(
        InitFrame(
          size: const CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: appVersion,
        ),
      );
      final lateSemantics = encodeFrame(
        SemanticsFrame(
          encoder.encodeTree(
            tree(id: 'element-8', label: 'After skew', token: 'element.2'),
          )!,
        ),
      );
      source.feedBytesForTest(
        Uint8List.fromList(<int>[...mismatch, ...lateSemantics]),
      );

      expect(source.isClosedForTest, isTrue);
      expect(source.bannerShownForTest, isTrue);
      expect(
        into.querySelector('[data-fleury-semantic-id="element-8"]'),
        isNull,
        reason: 'a frame queued after the rejected INIT was not presented',
      );

      // Existing retained DOM handles and browser input are inert after the
      // mismatch; in particular, v7 must not satisfy the old >=v6 check and
      // enable a positional action.
      staleButton.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      source.sendInputForTest(const TextInputEvent('x'));
      expect(
        source.sentForTest,
        isEmpty,
        reason: 'no semantic action or input was sent after teardown',
      );
    },
  );

  test('a failed action result is absorbed (logged), not thrown', () {
    source.handleFrameForTest(
      const SemanticActionResultFrame(
        SemanticNodeId('save'),
        SemanticAction.activate,
        SemanticActionInvocationStatus.failed,
      ),
    );
  });

  test('semantic actions echo the DOM target token', () {
    final encoder = SemanticsWireEncoder();
    final bytes = encoder.encodeTree(
      const SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('element-7'),
              role: SemanticRole.button,
              label: 'Save',
              actions: {SemanticAction.activate, SemanticAction.focus},
              actionTargetToken: 'element.1',
            ),
          ],
        ),
      ),
    );
    source.handleFrameForTest(SemanticsFrame(bytes!));
    source.handleFrameForTest(
      const InitFrame(
        size: CellSize(80, 24),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        protocolVersion: remoteProtocolVersion,
      ),
    );
    source.sentForTest.clear();

    final button = into.querySelector('[data-fleury-semantic-id="element-7"]')!;
    button.dispatchEvent(
      web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
    );

    final action = _decodeAll(
      source.sentForTest,
    ).whereType<SemanticActionFrame>().single;
    expect(action.id, const SemanticNodeId('element-7'));
    expect(action.action, SemanticAction.activate);
    expect(action.targetToken, 'element.1');
  });

  test(
    'a semantically identical recycled target detaches stale DOM handles',
    () {
      final encoder = SemanticsWireEncoder();
      SemanticTree tree(String token) => SemanticTree(
        root: SemanticNode(
          id: const SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: const SemanticNodeId('element-7'),
              role: SemanticRole.button,
              label: 'Delete',
              actions: const {SemanticAction.activate},
              actionTargetToken: token,
            ),
          ],
        ),
      );

      source.handleFrameForTest(
        SemanticsFrame(encoder.encodeTree(tree('element.1'))!),
      );
      source.handleFrameForTest(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          protocolVersion: remoteProtocolVersion,
        ),
      );
      final stale = into.querySelector(
        '[data-fleury-semantic-id="element-7"]',
      )!;

      source.handleFrameForTest(
        SemanticsFrame(encoder.encodeTree(tree('element.2'))!),
      );
      final replacement = into.querySelector(
        '[data-fleury-semantic-id="element-7"]',
      )!;
      expect(replacement, isNot(same(stale)));
      expect(stale.isConnected, isFalse);
      source.sentForTest.clear();

      stale.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      expect(
        _decodeAll(source.sentForTest).whereType<SemanticActionFrame>(),
        isEmpty,
      );

      replacement.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      final action = _decodeAll(
        source.sentForTest,
      ).whereType<SemanticActionFrame>().single;
      expect(action.targetToken, 'element.2');
    },
  );

  test(
    'outbound input and stable actions wait for INIT, then the latest resize '
    'is synchronized',
    () {
      final harness = attachUnnegotiated();
      harness.components.semanticPresenter!.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('save'),
                role: SemanticRole.button,
                label: 'Save',
                actions: {SemanticAction.activate},
              ),
            ],
          ),
        ),
      );
      final button = harness.host.querySelector(
        '[data-fleury-semantic-id="save"]',
      )!;

      harness.host.setAttribute(
        'style',
        'position:absolute;width:160px;height:80px;padding:0;'
            'font-family:monospace;font-size:10px;line-height:10px;',
      );
      harness.source.handleObservedResizeForTest();
      final firstSize = harness.components.surface.size;
      harness.host.setAttribute(
        'style',
        'position:absolute;width:640px;height:240px;padding:0;'
            'font-family:monospace;font-size:20px;line-height:20px;',
      );
      harness.source.handleObservedResizeForTest();
      final latestSize = harness.components.surface.size;
      expect(latestSize, isNot(firstSize));

      harness.source.sendInputForTest(const TextInputEvent('before'));
      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      expect(
        harness.source.sentForTest,
        isEmpty,
        reason: 'no non-INIT frame is legal before the exact app echo',
      );

      harness.source.handleFrameForTest(_appInit(remoteProtocolVersion));

      var sent = _decodeAll(harness.source.sentForTest);
      expect(sent, hasLength(1));
      expect(sent.single, isA<ResizeFrame>());
      expect((sent.single as ResizeFrame).size, latestSize);

      harness.source.sendInputForTest(const TextInputEvent('after'));
      button.dispatchEvent(
        web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
      );
      sent = _decodeAll(harness.source.sentForTest);
      expect(
        sent.whereType<InputEventFrame>().single.event,
        const TextInputEvent('after'),
      );
      expect(
        sent.whereType<SemanticActionFrame>().single.id,
        const SemanticNodeId('save'),
      );
    },
  );

  test('positional actions fail closed before the app echoes INIT', () {
    final harness = attachUnnegotiated();
    harness.components.semanticPresenter!.present(
      const SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('element-7'),
              role: SemanticRole.button,
              label: 'Save',
              actions: {SemanticAction.activate},
              actionTargetToken: 'element.1',
            ),
          ],
        ),
      ),
    );
    harness.source.sentForTest.clear();

    final button = harness.host.querySelector(
      '[data-fleury-semantic-id="element-7"]',
    )!;
    button.dispatchEvent(
      web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
    );

    expect(
      _decodeAll(harness.source.sentForTest).whereType<SemanticActionFrame>(),
      isEmpty,
    );
    expect(harness.source.isClosedForTest, isFalse);
  });

  test('stable-id actions keep the legacy payload on the current wire', () {
    final encoder = SemanticsWireEncoder();
    final bytes = encoder.encodeTree(
      const SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('save'),
              role: SemanticRole.button,
              label: 'Save',
              actions: {SemanticAction.activate},
            ),
          ],
        ),
      ),
    );
    source.handleFrameForTest(SemanticsFrame(bytes!));
    source.handleFrameForTest(
      const InitFrame(
        size: CellSize(80, 24),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        protocolVersion: remoteProtocolVersion,
      ),
    );
    source.sentForTest.clear();

    final button = into.querySelector('[data-fleury-semantic-id="save"]')!;
    button.dispatchEvent(
      web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
    );

    final action = _decodeAll(
      source.sentForTest,
    ).whereType<SemanticActionFrame>().single;
    expect(action.id, const SemanticNodeId('save'));
    expect(action.targetToken, isNull);
    expect(encodeSemanticAction(action.id, action.action), <int>[
      4,
      ...'save'.codeUnits,
      8,
      ...'activate'.codeUnits,
      0,
    ]);
  });

  test('a failed image plan does not lose sender-cached bytes', () {
    const image = ImagePlacement(
      id: 'image-b',
      col: 1,
      row: 1,
      cols: 2,
      rows: 1,
    );
    const imagePlan = RemotePlan(
      size: CellSize(80, 24),
      fullRepaint: false,
      styleTable: [],
      patches: [],
      placements: [image],
    );
    const emptyPlan = RemotePlan(
      size: CellSize(80, 24),
      fullRepaint: false,
      styleTable: [],
      patches: [],
    );

    source.feedBytesForTest(
      encodeFrame(InlineImageFrame('image-b', Uint8List.fromList([1, 2, 3]))),
    );
    var failFirstPlan = true;
    source.failApplyForTest = (frame) {
      if (frame is PlanFrame && failFirstPlan) {
        failFirstPlan = false;
        return true;
      }
      return false;
    };

    source.feedBytesForTest(encodeFrame(const PlanFrame(imagePlan)));
    expect(source.isClosedForTest, isFalse);
    expect(components.imageOverlay.pendingImageCount, 0);
    expect(components.imageOverlay.cachedImageCount, 1);

    source.failApplyForTest = null;
    source.feedBytesForTest(encodeFrame(const PlanFrame(emptyPlan)));
    source.feedBytesForTest(encodeFrame(const PlanFrame(imagePlan)));

    expect(components.imageOverlay.cachedImageCount, 1);
    expect(
      components.imageOverlay.imageElementCount,
      1,
      reason: 'image-b returns without a second InlineImageFrame',
    );
  });

  // F19: an unrecoverable stream desync must surface the reload banner
  // (and close the untrustworthy socket) instead of silently resyncing
  // forever against a mirror that can never advance — the "frozen, no
  // banner" hang. A single recoverable frame error still just resyncs.
  group('desync classification (F19)', () {
    // A frame the client decodes and applies as a clean no-op — used to drive
    // the apply path so the injected fault (not the frame) decides pass/fail.
    final benign = encodeFrame(
      const ClipboardResultFrame(1, RemoteClipboardStatus.written),
    );

    test('an oversized length prefix (framing lost) tears down with the '
        'reload banner — not a silent resync', () {
      // Byte 0 = type, bytes 1..4 = a 0xFFFFFFFF payload length, far past the
      // decoder cap: drain() clears the buffer and throws an UNRECOVERABLE
      // RemoteProtocolException (stream framing can never realign).
      source.feedBytesForTest(
        Uint8List.fromList([0x01, 0xFF, 0xFF, 0xFF, 0xFF]),
      );

      expect(source.isClosedForTest, isTrue, reason: 'socket closed');
      expect(source.bannerShownForTest, isTrue, reason: 'reload banner shown');
    });

    test(
      'a text WebSocket message tears down instead of escaping the callback',
      () {
        source.feedMessageDataForTest('not binary Fleury wire data'.toJS);

        expect(source.isClosedForTest, isTrue, reason: 'socket closed');
        expect(
          source.bannerShownForTest,
          isTrue,
          reason: 'reload banner shown',
        );
      },
    );

    test('a single recoverable apply error resyncs, keeping the socket open '
        'with no banner', () {
      source.failApplyForTest = (_) => true;
      source.feedBytesForTest(benign);

      expect(
        source.isClosedForTest,
        isFalse,
        reason: 'one bad frame is recoverable — socket stays open',
      );
      expect(source.bannerShownForTest, isFalse, reason: 'no banner');
    });

    test('N consecutive apply failures escalate to the banner; a success in '
        'between resets the counter', () {
      source.failApplyForTest = (_) => true;

      // Two failures — below the escalation threshold (3).
      source.feedBytesForTest(benign);
      source.feedBytesForTest(benign);
      expect(source.isClosedForTest, isFalse, reason: '2 < threshold');
      expect(source.bannerShownForTest, isFalse);

      // A successful apply clears the run.
      source.failApplyForTest = (_) => false;
      source.feedBytesForTest(benign);
      expect(source.isClosedForTest, isFalse);

      // Two more failures: only 2 since the reset, so still no escalation —
      // proving the counter reset rather than carrying the earlier two.
      source.failApplyForTest = (_) => true;
      source.feedBytesForTest(benign);
      source.feedBytesForTest(benign);
      expect(
        source.isClosedForTest,
        isFalse,
        reason: 'the success reset the counter, so 2+2 has not hit 3',
      );

      // The third consecutive failure crosses the threshold and escalates.
      source.feedBytesForTest(benign);
      expect(
        source.isClosedForTest,
        isTrue,
        reason: 'escalated: socket closed',
      );
      expect(source.bannerShownForTest, isTrue, reason: 'escalated: banner');
    });

    test('a clean ByeFrame still tears down through the existing path '
        '(not reclassified)', () {
      source.feedBytesForTest(encodeFrame(const ByeFrame()));

      expect(source.isClosedForTest, isTrue);
      expect(
        source.bannerShownForTest,
        isTrue,
        reason: 'normal end-of-session',
      );
    });

    test('a frame arriving after teardown is dropped before apply (no repaint '
        'over the banner)', () {
      // Tear down via a normal ByeFrame.
      source.feedBytesForTest(encodeFrame(const ByeFrame()));
      expect(source.isClosedForTest, isTrue);

      // Probe: the apply loop calls this predicate for every frame it reaches.
      var applyReached = false;
      source.failApplyForTest = (_) {
        applyReached = true;
        return false;
      };
      source.feedBytesForTest(benign);

      expect(
        applyReached,
        isFalse,
        reason: 'a post-teardown feed is dropped before the drain/apply loop',
      );
    });

    test('recoverable decode errors make forward progress (no infinite spin) '
        'and a later valid frame still applies', () {
      // Count clean applies via the same seam (never forcing a failure here).
      var appliesReached = 0;
      source.failApplyForTest = (_) {
        appliesReached++;
        return false;
      };

      // Feed several DISTINCT malformed-but-framed frames: a RESIZE payload
      // (type 0x03) with a valid length header but missing `cols`, so drain()
      // consumes the frame and then _decode throws a RECOVERABLE error.
      for (var i = 0; i < 5; i++) {
        source.feedBytesForTest(_framedRaw(0x03, 'rows=$i'.codeUnits));
      }
      expect(
        source.isClosedForTest,
        isFalse,
        reason: 'recoverable decode errors never tear down',
      );
      expect(source.bannerShownForTest, isFalse, reason: 'no banner');
      expect(
        appliesReached,
        0,
        reason: 'each malformed frame threw during DECODE, before any apply',
      );

      // A subsequent VALID frame decodes and applies cleanly — proving the
      // buffer drained past every malformed frame (no stuck bytes, no spin).
      source.feedBytesForTest(benign);
      expect(appliesReached, 1, reason: 'the valid frame reached apply');
      expect(source.isClosedForTest, isFalse);
      expect(source.bannerShownForTest, isFalse);
    });

    test('a valid frame trailing a recoverable decode error in the same '
        'message still applies immediately', () {
      var appliesReached = 0;
      source.failApplyForTest = (_) {
        appliesReached++;
        return false;
      };

      final malformed = _framedRaw(0x03, 'rows=7'.codeUnits);
      source.feedBytesForTest(
        Uint8List.fromList(<int>[...malformed, ...benign]),
      );

      expect(
        appliesReached,
        1,
        reason:
            'the valid trailing frame must not wait for another socket message',
      );
      expect(source.isClosedForTest, isFalse);
      expect(source.bannerShownForTest, isFalse);
    });
  });
}
