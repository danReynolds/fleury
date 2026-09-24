// A frame requested from inside a frame must yield to the event loop before
// the next frame runs — through the REAL runtime and the REAL scheduler.
//
// Regression test for an isolate freeze: with the default
// `frameInterval: Duration.zero` the flush was a microtask, and a frame
// requested from the post-frame drain (a post-frame callback that
// re-registers itself; every chunk of a chunked paste) scheduled the next
// flush as another microtask. Dart drains the microtask queue to empty
// before any timer, I/O, or signal runs, so the whole chain executed as one
// unbroken sequence: a 512 KiB paste held the isolate for ~12 s with no
// input, no Ctrl+C (raw mode delivers it on stdin) and no SIGINT/SIGTERM
// delivery; a self-re-registering post-frame callback pinned it forever.
//
// The probe in both tests is a 1 ms periodic Timer. A timer cannot fire
// while microtasks are pending, so "the timer ticked while the chain was in
// flight" is exactly "the event loop turned between frames".
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// Re-registers a post-frame callback on every frame until [target] frames
/// have run — the Flutter "run something every frame" idiom, and the shape
/// of the paste chunker.
class _Chain extends StatefulWidget {
  const _Chain({required this.target, required this.onFrame});
  final int target;
  final void Function(int frame) onFrame;

  @override
  State<_Chain> createState() => _ChainState();
}

class _ChainState extends State<_Chain> {
  var _frames = 0;

  @override
  Widget build(BuildContext context) {
    if (_frames < widget.target) {
      TuiBinding.of(context).addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _frames++);
        widget.onFrame(_frames);
      });
    }
    return Text('frame $_frames');
  }
}

/// Queues a `setState` from a microtask on every build — the shape of
/// `Future.value(x).then(...)` or an async loop over completed futures.
class _MicrotaskChain extends StatefulWidget {
  const _MicrotaskChain({required this.target, required this.onFrame});
  final int target;
  final void Function(int frame) onFrame;

  @override
  State<_MicrotaskChain> createState() => _MicrotaskChainState();
}

class _MicrotaskChainState extends State<_MicrotaskChain> {
  var _frames = 0;

  @override
  Widget build(BuildContext context) {
    widget.onFrame(_frames);
    if (_frames < widget.target) {
      scheduleMicrotask(() {
        if (mounted) setState(() => _frames++);
      });
    }
    return Text('frame $_frames');
  }
}

/// Runs the app [chain] builds until it has rendered [_chainFrames] frames,
/// and expects the 1 ms beacon to have ticked while the chain ran: ticks
/// from frame 1's render to the last frame's. Startup ticks don't count.
Future<void> _expectChainYields(
  Widget Function(int target, void Function(int frame) onFrame) chain,
) async {
  final driver = FakeTerminalDriver();
  var ticks = 0;
  final ticksAtFrame = <int, int>{};
  final done = Completer<void>();
  final beacon = Timer.periodic(const Duration(milliseconds: 1), (_) {
    ticks++;
  });

  final app = runApp(
    chain(_chainFrames, (frame) {
      ticksAtFrame[frame] = ticks;
      if (frame == _chainFrames && !done.isCompleted) done.complete();
    }),
    driver: driver,
    requireInteractiveTerminal: false,
  );

  await done.future.timeout(const Duration(seconds: 20));
  beacon.cancel();
  requestExit();
  await app.timeout(const Duration(seconds: 8));

  expect(
    ticksAtFrame[_chainFrames]! - ticksAtFrame[1]!,
    greaterThan(0),
    reason:
        'the 1 ms beacon never fired across ${_chainFrames - 1} frames: the '
        'chain ran as one microtask sequence and starved the event loop',
  );
}

const _chainFrames = 150;

void main() {
  test(
    'a setState queued as a microtask by build yields to timers between frames',
    () => _expectChainYields(
      (target, onFrame) => _MicrotaskChain(target: target, onFrame: onFrame),
    ),
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a self-re-registering post-frame callback yields to timers between frames',
    () => _expectChainYields(
      (target, onFrame) => FleuryApp(
        title: 'chain',
        home: _Chain(target: target, onFrame: onFrame),
      ),
    ),
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a chunked paste is observable mid-flight from a timer',
    () async {
      final driver = FakeTerminalDriver();
      final controller = TextEditingController();
      // 24 chunks at the default 2 KiB chunk size — ~150 ms of rendering
      // before the fix, during which nothing else ran.
      final text = 'a' * (48 * 1024);
      final samples = <int>[];
      final done = Completer<void>();

      final app = runApp(
        FleuryApp(
          title: 'paste',
          home: TextInput(controller: controller, autofocus: true),
        ),
        driver: driver,
        requireInteractiveTerminal: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final beacon = Timer.periodic(const Duration(milliseconds: 1), (t) {
        final n = controller.text.length;
        samples.add(n);
        if (n == text.length && !done.isCompleted) {
          t.cancel();
          done.complete();
        }
      });
      driver.enqueue(PasteEvent(text));

      await done.future.timeout(const Duration(seconds: 20));
      beacon.cancel();
      requestExit();
      await app.timeout(const Duration(seconds: 8));

      expect(controller.text, text, reason: 'the paste still lands intact');
      expect(
        samples.any((n) => n > 0 && n < text.length),
        isTrue,
        reason:
            'the beacon only ever saw 0 then ${text.length}: no event-loop turn '
            'happened between the first chunk and the last (samples: '
            '${samples.toSet().toList()..sort()})',
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
