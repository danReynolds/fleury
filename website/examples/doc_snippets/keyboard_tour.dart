// Compile-checked source behind the Key handling guide.
//
// The public API patterns in
// `website/src/content/docs/guides/focus-and-keyboard.mdx` have compile-checked
// counterparts here, so the guide cannot drift to APIs that no longer exist.

import 'package:fleury/fleury.dart';

// ---------------------------------------------------------------------------
// 1. Commands — the common case.
// ---------------------------------------------------------------------------

class CommandsExample extends StatelessWidget {
  const CommandsExample({super.key, required this.child});

  final Widget child;

  void _save() {}
  void _quit() {}
  void _gotoTop() {}
  void _findFile() {}

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [
      KeyBinding(.ctrl.s, label: 'Save', onTrigger: (_) => _save()),
      KeyBinding(.q, label: 'Quit', onTrigger: (_) => _quit()),
      // Multi-step sequences: vim's `gg`, emacs' `C-x C-s`, a Space leader.
      KeyBinding(.g.g, label: 'Top', onTrigger: (_) => _gotoTop()),
      KeyBinding(.space.f, label: 'Find file', onTrigger: (_) => _findFile()),
    ],
    child: child,
  );
}

// ---------------------------------------------------------------------------
// 2. Aliases, repeats, and letting a key keep going.
// ---------------------------------------------------------------------------

class BindingOptionsExample extends StatelessWidget {
  const BindingOptionsExample({super.key, required this.child});

  final Widget child;

  void _moveDown() {}
  bool _close() => false;

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [
      // One command, several keys — one row in the hint bar, not three.
      KeyBinding(
        .j,
        aliases: [.down],
        label: 'Down',
        // Movement is the repeat-reliant class: holding the key should keep
        // moving. Everything else fires once per physical press.
        includeRepeats: true,
        onTrigger: (_) => _moveDown(),
      ),
      // A handler always receives the event, so it can decline: bubble() hands
      // the key to an ancestor binding instead of consuming it.
      KeyBinding(
        KeyCode.escape,
        label: 'Close',
        onTrigger: (event) {
          if (!_close()) event.bubble(); // not ours after all
        },
      ),
    ],
    child: child,
  );
}

// ---------------------------------------------------------------------------
// 3. A key boundary — a dialog that keeps the app's keys out.
// ---------------------------------------------------------------------------

class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({super.key, required this.onAnswer});

  final void Function(bool confirmed) onAnswer;

  @override
  Widget build(BuildContext context) => KeyBindings(
    // Nothing below this scope reaches the app's own bindings while the
    // dialog is up — so Ctrl+S cannot save behind a confirmation prompt.
    modal: true,
    bindings: [
      KeyBinding(KeyCode.y, label: 'Yes', onTrigger: (_) => onAnswer(true)),
      KeyBinding(KeyCode.n, label: 'No', onTrigger: (_) => onAnswer(false)),
      KeyBinding(
        KeyCode.escape,
        label: 'Cancel',
        onTrigger: (_) => onAnswer(false),
      ),
    ],
    child: const Focus(autofocus: true, child: Text('Delete this file? y/n')),
  );
}

// ---------------------------------------------------------------------------
// 4. Sampled state — a game loop reads keys, it does not react to them.
// ---------------------------------------------------------------------------

class ShipControls extends StatefulWidget {
  const ShipControls({super.key});

  @override
  State<ShipControls> createState() => _ShipControlsState();
}

class _ShipControlsState extends State<ShipControls>
    with SingleTickerProviderStateMixin {
  // Positions, not letters: the key left of E on QWERTY is the same physical
  // key on AZERTY, where it is capped Z.
  static const _thrust = KeyPosition.w;
  static const _left = KeyPosition.a;
  static const _right = KeyPosition.d;

  late final Keyboard _keyboard = Keyboard.of(context); // safe to cache
  late final Ticker _ticker = createTicker(_tick)..start();

  double _heading = 0;
  double get heading => _heading;

  void _tick(Duration elapsed) {
    // ONE immutable read for the whole frame, so every step below agrees
    // about what was held.
    final keys = _keyboard.snapshot;
    if (keys.isHeld(_left)) _heading -= 0.1;
    if (keys.isHeld(_right)) _heading += 0.1;
    if (keys.isHeld(_thrust)) _accelerate();
    // An EDGE, not a level: a tap that starts and ends between two frames is
    // still reported, so a quick shot is never swallowed.
    if (keys.wasPressed(KeyCode.space)) _fire();
  }

  void _accelerate() {}
  void _fire() {}

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Capability reads ARE reactive and legal in build: this rebuilds when a
    // terminal finishes negotiating, so the control scheme upgrades itself.
    final canHold = Keyboard.of(context).capabilities.supportsHeldState;
    return Focus(
      autofocus: true,
      child: Text(canHold ? 'hold W to thrust' : 'press W to toggle thrust'),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Hold — push-to-talk, hold-to-peek.
// ---------------------------------------------------------------------------

class PeekExample extends StatelessWidget {
  const PeekExample({super.key, required this.child, required this.onPeek});

  final Widget child;
  final void Function(bool showing) onPeek;

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [
      if (Keyboard.of(context).capabilities.supportsHeldState)
        KeyBinding.hold(
          KeyCode.space,
          label: 'Peek at logs',
          onHoldStart: (_) => onPeek(true),
          onHoldEnd: (_) => onPeek(false),
        ),
    ],
    child: child,
  );
}

/// A capability-driven control uses the richest behavior that was actually
/// delivered, while keeping the same command usable on press-only terminals.
class AdaptivePeekExample extends StatelessWidget {
  const AdaptivePeekExample({
    super.key,
    required this.child,
    required this.peeking,
    required this.onPeek,
  });

  final Widget child;
  final bool peeking;
  final void Function(bool showing) onPeek;

  @override
  Widget build(BuildContext context) {
    final canHold = Keyboard.of(context).capabilities.supportsHeldState;
    return KeyBindings(
      bindings: [
        if (canHold)
          KeyBinding.hold(
            .space,
            label: 'Peek (hold)',
            onHoldStart: (_) => onPeek(true),
            onHoldEnd: (_) => onPeek(false),
          )
        else
          KeyBinding(
            .space,
            label: 'Peek (toggle)',
            onTrigger: (_) => onPeek(!peeking),
          ),
      ],
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Awaiting one key — a rebind row, vim's `m<letter>`.
// ---------------------------------------------------------------------------

Future<void> rebind(
  BuildContext context,
  void Function(KeySelector selector) apply,
) async {
  final key = await Keyboard.nextKey(context);
  if (key == null) return; // the UI went away; nothing to apply to
  if (key.code == KeyCode.escape) return; // cancelled
  // A spatial control wants the SPOT; a mnemonic one wants the letter.
  apply(key.position ?? key.code);
}

// ---------------------------------------------------------------------------
// 7. The floor — conditional, widget-internal handling.
// ---------------------------------------------------------------------------

class ScrollRegion extends StatelessWidget {
  const ScrollRegion({super.key, required this.child, required this.canScroll});

  final Widget child;
  final bool Function(int delta) canScroll;

  @override
  Widget build(BuildContext context) => KeyDetector(
    // A detector PEEKS. Anything it does not consume keeps going, so
    // forgetting to consume is loud and local rather than silently starving
    // an ancestor's feature.
    onKey: (event) {
      final delta = switch (event.code) {
        KeyCode.arrowDown => 1,
        KeyCode.arrowUp => -1,
        _ => 0,
      };
      if (delta != 0 && canScroll(delta)) event.consume(); // mine
    },
    child: child,
  );
}

// ---------------------------------------------------------------------------
// 8. Focus, held explicitly.
// ---------------------------------------------------------------------------

class ExplicitFocusExample extends StatefulWidget {
  const ExplicitFocusExample({super.key});

  @override
  State<ExplicitFocusExample> createState() => _ExplicitFocusExampleState();
}

class _ExplicitFocusExampleState extends State<ExplicitFocusExample> {
  final FocusNode _node = FocusNode(debugLabel: 'editor');
  bool _active = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusDetector(
    // Fires when focus enters or leaves the subtree — pause a simulation, dim
    // a panel, stop a cursor blinking.
    onFocusChange: (hasFocus) => setState(() => _active = hasFocus),
    child: Focus(focusNode: _node, child: Text(_active ? 'editing' : 'idle')),
  );
}

/// The guide's "one game, two control schemes" snippet, compile-checked.
class DualSchemeControls extends StatefulWidget {
  const DualSchemeControls({super.key});
  @override
  State<DualSchemeControls> createState() => _DualSchemeControlsState();
}

class _DualSchemeControlsState extends State<DualSchemeControls> {
  final _nudges = <String, int>{};

  void _fire() {}

  void _nudgeThrust() => _nudges.update('w', (n) => n + 1, ifAbsent: () => 1);

  @override
  Widget build(BuildContext context) {
    final canHold = Keyboard.of(context).capabilities.supportsHeldState;
    return KeyBindings(
      bindings: [
        KeyBinding(KeyCode.space, label: 'Fire', onTrigger: (_) => _fire()),
        if (!canHold)
          KeyBinding(
            KeyPosition.w,
            aliases: [KeyCode.arrowUp],
            label: 'Thrust (tap)',
            includeRepeats: true,
            onTrigger: (_) => _nudgeThrust(),
          ),
      ],
      child: const Text('playfield'),
    );
  }
}
