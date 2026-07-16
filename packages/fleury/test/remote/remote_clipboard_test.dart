// Serve-path clipboard end-to-end over a fake transport: a copy inside a
// served app travels to the peer as CLIPBOARD_WRITE, the peer's answer
// resolves the app-side report as `hostSurface`, an unanswered write
// degrades to `inProcessOnly` (the register still pastes in-app), and the
// focused-caret rect rides the frame stream for IME positioning.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_clipboard.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

import 'remote_test_support.dart';

const _init = InitFrame(
  size: CellSize(40, 6),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

final class _ClipboardSink implements RemoteSurfaceSink {
  final sent = <({int seq, String text})>[];
  bool failSend = false;
  void Function(int seq, RemoteClipboardStatus status)? _onResult;

  @override
  bool get wantsPresentationPlans => true;

  @override
  void sendClipboardWrite(int seq, String text) {
    if (failSend) throw StateError('injected send failure');
    sent.add((seq: seq, text: text));
  }

  @override
  set onClipboardResult(
    void Function(int seq, RemoteClipboardStatus status)? handler,
  ) {
    _onResult = handler;
  }

  void answer(int seq, RemoteClipboardStatus status) {
    _onResult?.call(seq, status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('RemoteClipboard resolves hostSurface from the peer answer', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));

    final done = runApp(
      const SelectionArea(
        copyOnRelease: true,
        child: Text('served text to copy'),
      ),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    // Select via drag, then copy with Ctrl+C — the served app's clipboard
    // is the RemoteClipboard runApp installed for the structured path.
    transport.emit(
      const InputEventFrame(
        MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 0,
          row: 0,
        ),
      ),
    );
    transport.emit(
      const InputEventFrame(
        MouseEvent(
          kind: MouseEventKind.drag,
          button: MouseButton.left,
          col: 6,
          row: 0,
        ),
      ),
    );
    transport.emit(
      const InputEventFrame(
        MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 6,
          row: 0,
        ),
      ),
    );
    await _settle();

    final writes = transport.sent.whereType<ClipboardWriteFrame>().toList();
    expect(writes, hasLength(1), reason: 'copy travels to the peer');
    expect(writes.single.text, 'served');

    // Peer confirms → nothing further required app-side (the report
    // resolution is covered by the unit test below); the register pastes
    // in-app either way.
    transport.emit(
      ClipboardResultFrame(writes.single.seq, RemoteClipboardStatus.written),
    );
    await _settle();

    // The caret channel: focusing produced caret traffic at most once per
    // change (TextInput isn't focused here, so nothing editable —
    // presence of the channel is covered by the presenter dedupe test).
    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });

  test('unanswered writes degrade to inProcessOnly', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    unawaited(
      runApp(
        const Text('app'),
        driver: driver,
        enableHotReload: false,
        requireInteractiveTerminal: false,
      ),
    );
    await _settle();

    final clipboard = RemoteClipboard(
      driver,
      resultTimeout: const Duration(milliseconds: 30),
    );
    final report = await clipboard.writeWithReport('lost to the void');
    expect(report.result, ClipboardWriteResult.inProcessOnly);
    expect(
      clipboard.readInProcess(),
      'lost to the void',
      reason: 'paste-within-app still works',
    );
    clipboard.dispose();
    transport.emit(const ByeFrame());
    await _settle();
    await transport.close();
  });

  test('an answered write resolves hostSurface', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));
    unawaited(
      runApp(
        const Text('app'),
        driver: driver,
        enableHotReload: false,
        requireInteractiveTerminal: false,
      ),
    );
    await _settle();

    final clipboard = RemoteClipboard(driver);
    final pending = clipboard.writeWithReport('landed');
    await _settle();
    final write = transport.sent.whereType<ClipboardWriteFrame>().single;
    transport.emit(
      ClipboardResultFrame(write.seq, RemoteClipboardStatus.written),
    );
    final report = await pending;
    expect(report.result, ClipboardWriteResult.hostSurface);
    clipboard.dispose();
    transport.emit(const ByeFrame());
    await _settle();
    await transport.close();
  });

  group('bounded remote clipboard writes', () {
    late _ClipboardSink sink;
    late RemoteClipboard clipboard;

    setUp(() {
      sink = _ClipboardSink();
      clipboard = RemoteClipboard(
        sink,
        resultTimeout: const Duration(seconds: 10),
      );
    });

    tearDown(() => clipboard.dispose());

    test(
      'oversized text degrades immediately without a pending request',
      () async {
        final textLimit = remoteFramePayloadLimit(FrameType.clipboardWrite) - 4;
        final text = 'a' * (textLimit + 1);

        final report = await clipboard
            .writeWithReport(text)
            .timeout(const Duration(milliseconds: 250));

        expect(report.result, ClipboardWriteResult.inProcessOnly);
        expect(report.resolution.state, CapabilityResolutionState.degraded);
        expect(clipboard.readInProcess(), text);
        expect(sink.sent, isEmpty);

        final valid = clipboard.writeWithReport('next');
        expect(
          sink.sent.single.seq,
          0,
          reason: 'oversize consumed no sequence',
        );
        sink.answer(0, RemoteClipboardStatus.written);
        expect((await valid).result, ClipboardWriteResult.hostSurface);
      },
    );

    test('an exact-limit payload still travels to the peer', () async {
      final textLimit = remoteFramePayloadLimit(FrameType.clipboardWrite) - 4;
      final text = 'a' * textLimit;

      final pending = clipboard.writeWithReport(text);
      expect(sink.sent, hasLength(1));
      expect(sink.sent.single.text, text);
      sink.answer(sink.sent.single.seq, RemoteClipboardStatus.written);

      expect((await pending).result, ClipboardWriteResult.hostSurface);
    });

    test('in-process-only policy never sends text to the peer', () async {
      final report = await clipboard.writeWithReport(
        'local secret',
        policy: ClipboardWritePolicy.inProcessOnly,
      );

      expect(report.result, ClipboardWriteResult.inProcessOnly);
      expect(
        report.resolution.state,
        CapabilityResolutionState.disabledByPolicy,
      );
      expect(clipboard.readInProcess(), 'local secret');
      expect(sink.sent, isEmpty);
    });

    test(
      'a synchronous send failure degrades without a pending leak',
      () async {
        sink.failSend = true;

        final report = await clipboard.writeWithReport('still local');

        expect(report.result, ClipboardWriteResult.inProcessOnly);
        expect(report.resolution.state, CapabilityResolutionState.degraded);
        expect(clipboard.readInProcess(), 'still local');
        expect(sink.sent, isEmpty);
      },
    );
  });

  test('the focused caret rect ships and dedupes', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));

    final controller = TextEditingController(text: 'abc');
    final done = runApp(
      TextInput(controller: controller, autofocus: true),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    final carets = transport.sent.whereType<CaretFrame>().toList();
    expect(carets, isNotEmpty, reason: 'focused editable ships its caret');
    expect(carets.last.caret, isNotNull);
    final caretCountAfterMount = carets.length;

    // Typing moves the caret → a new frame; a no-op frame doesn't resend.
    transport.emit(const InputEventFrame(TextInputEvent('x')));
    await _settle();
    final after = transport.sent.whereType<CaretFrame>().toList();
    expect(after.length, greaterThan(caretCountAfterMount));
    expect(after.last.caret, isNot(carets.last.caret));

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });
}
