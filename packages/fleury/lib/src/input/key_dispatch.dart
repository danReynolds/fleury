// The ambient dispatch-frame stack behind `KeyEvent.consume()` (RFC 0020
// §17.2).
//
// Entitlement to consume is a property of the DISPATCH CONTEXT, never of the
// event object: const canonicalization makes equal key events the identical
// instance, and the sequence engine re-dispatches held instances on replay,
// so any instance-keyed liveness state would be wrong twice over (the
// assumption-challenge review's F6/F4). The input dispatcher pushes a frame
// around each synchronous delivery; `consume()` acts on the top frame if and
// only if the current consumer is entitled (detector callbacks — P4).
// Nested synchronous dispatch pushes nested frames; replayed events re-enter
// liveness naturally because each replay is its own frame.

/// One live synchronous key delivery.
final class KeyDispatchFrame {
  KeyDispatchFrame({required this.entitled});

  /// Whether the consumer currently being invoked may consume (a
  /// `KeyDetector` callback). Observation-lane deliveries and binding
  /// handlers push non-entitled frames — bindings control propagation via
  /// `KeyBindingEvent.bubble()`, never `consume()`.
  final bool entitled;

  bool _consumed = false;

  /// Whether some entitled consumer consumed during this frame.
  bool get consumed => _consumed;

  /// Marks the frame consumed. Framework-internal; reached via
  /// [KeyDispatchContext.consumeCurrent].
  void markConsumed() => _consumed = true;
}

/// Process-ambient dispatch stack. Dart's single-threaded synchronous
/// dispatch makes stack discipline sound; an `await` inside a handler ends
/// its synchronous window, which is exactly the liveness contract.
abstract final class KeyDispatchContext {
  static final List<KeyDispatchFrame> _stack = [];

  /// The innermost live frame, or null outside any dispatch.
  static KeyDispatchFrame? get current =>
      _stack.isEmpty ? null : _stack.last;

  /// Runs [body] inside a new dispatch frame and reports whether an
  /// entitled consumer consumed within it.
  static bool run(void Function() body, {required bool entitled}) {
    final frame = KeyDispatchFrame(entitled: entitled);
    _stack.add(frame);
    try {
      body();
    } finally {
      final popped = _stack.removeLast();
      assert(identical(popped, frame), 'dispatch frame stack imbalance');
    }
    return frame.consumed;
  }

  /// `KeyEvent.consume()`'s target. Valid only during a live synchronous
  /// dispatch to an entitled consumer; a call from anywhere else —
  /// observation, stored events, after an `await` — is a debug-mode error
  /// and a release-mode no-op (§17.2).
  static void consumeCurrent() {
    final frame = current;
    assert(
      frame != null,
      'KeyEvent.consume() called outside a live key dispatch — consumption '
      'is only valid synchronously inside a KeyDetector onKey callback '
      '(after an await, the dispatch has moved on).',
    );
    assert(
      frame == null || frame.entitled,
      'This consumer cannot consume: observation and binding handlers are '
      'not entitled (bindings use KeyBindingEvent.bubble() instead).',
    );
    if (frame != null && frame.entitled) frame.markConsumed();
  }
}
