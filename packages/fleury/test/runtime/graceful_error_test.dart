// A throwing event handler — sync or async — must report and keep the session
// running (Flutter's posture), surfacing an error banner, instead of tearing
// the runApp session down. Drives runApp through the structured serve path and
// asserts the session survives and the banner appears.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

class _FakeTransport
    with SynchronousSendTransport
    implements RemoteFrameTransport {
  final _in = StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = [];
  bool closed = false;

  @override
  Stream<RemoteFrame> get incoming => _in.stream;

  @override
  void send(RemoteFrame frame) => sent.add(frame);

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void emit(RemoteFrame frame) {
    if (!_in.isClosed) _in.add(frame);
  }

  Future<void> disconnect() async {
    if (!_in.isClosed) await _in.close();
  }
}

const _init = InitFrame(
  size: CellSize(60, 16),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

String _planText(List<PlanFrame> frames) => frames
    .expand((f) => f.plan.patches)
    .expand((p) => p.runs)
    .map((run) => run.text)
    .join();

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('a throwing key handler is reported on screen, not fatal', () async {
    final transport = _FakeTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));

    var sessionError = false;
    final done = runApp(
      KeyBindings(
        bindings: [
          // Synchronous throw inside dispatch (caught by the event-loop guard).
          KeyBinding(
            KeyChord.key(KeyCode.f1),
            onEvent: (_) => throw StateError('boom-sync'),
          ),
          // Asynchronous throw (escapes to the zone guard).
          KeyBinding(
            KeyChord.key(KeyCode.f2),
            onEvent: (_) {
              unawaited(Future<void>(() => throw StateError('boom-async')));
            },
          ),
        ],
        child: const Text('app running'),
      ),
      driver: driver,
      requireInteractiveTerminal: false,
    ).then((_) {}, onError: (_) => sessionError = true);

    await _settle();
    final baseline = transport.sent.whereType<PlanFrame>().length;

    // Synchronous handler throw.
    transport.emit(const InputEventFrame(KeyEvent(keyCode: KeyCode.f1)));
    await _settle();
    final afterSync = transport.sent.whereType<PlanFrame>().toList();
    expect(
      _planText(afterSync.skip(baseline).toList()),
      contains('⚠'),
      reason: 'the error banner is painted',
    );
    expect(_planText(afterSync.skip(baseline).toList()), contains('boom-sync'));
    expect(sessionError, isFalse, reason: 'session survived the sync throw');

    // Asynchronous handler throw — escapes to the zone guard.
    transport.emit(const InputEventFrame(KeyEvent(keyCode: KeyCode.f2)));
    await _settle();
    expect(sessionError, isFalse, reason: 'session survived the async throw');

    // The app is still live and rendering.
    expect(driver.isActive, isTrue);

    await transport.disconnect();
    await done;
    expect(sessionError, isFalse, reason: 'clean shutdown, no error');
  });
}
