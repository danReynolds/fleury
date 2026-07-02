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
