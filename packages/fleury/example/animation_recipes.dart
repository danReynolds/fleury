// Animation recipes — a gallery of common TUI animation patterns, each
// a small self-contained widget. The point is to show the texture of
// the API across real scenarios, not to be exhaustive.
//
// Run:
//   cd packages/fleury
//   dart run example/animation_recipes.dart
//
//   ↑/↓  move selection      space  toggle panel
//   +/-  change the counter  n      new item (badge flash + toast)
//   Ctrl+C exits.

import 'package:fleury/fleury.dart';

// ---------------------------------------------------------------------------
// 1. Value-tracks-state: a number that animates to its target.
//    AnimationBuilder owns the Animation, retargets when `value` changes,
//    and disposes itself — no StatefulWidget, no didUpdateWidget, no
//    dispose. This is the dominant case and it's one widget.
// ---------------------------------------------------------------------------

class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({required this.value, super.key});
  final int value;

  @override
  Widget build(BuildContext context) =>
      AnimationBuilder<int>(value, builder: (context, v) => Text('$v'));
}

// ---------------------------------------------------------------------------
// 2. Interruptible: a panel that springs open/closed. Toggle rapidly
//    and it stays smooth — each retarget continues from the live
//    width AND velocity, so no jarring restart. This is the whole
//    reason the default engine is a spring.
// ---------------------------------------------------------------------------

class ExpandablePanel extends StatelessWidget {
  const ExpandablePanel({required this.open, required this.child, super.key});
  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimationBuilder<int>(
    open ? 30 : 0,
    spring: Spring.snappy,
    builder: (context, width) => SizedBox(width: width, child: child),
  );
}

// ---------------------------------------------------------------------------
// 3. One driver, many props: a single 0..1 "selectedness" Animation
//    drives indent, weight, and color together (the Compose
//    updateTransition pattern). Add a derived property by reading the
//    same value — the choreography comes free.
// ---------------------------------------------------------------------------

class SelectableRow extends StatelessWidget {
  const SelectableRow({required this.label, required this.selected, super.key});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimationBuilder<double>(
    selected ? 1.0 : 0.0,
    spring: Spring.snappy,
    builder: (context, t) {
      final indent = (t * 2).round(); // 0..2 cells
      final bold = t > 0.5; // cell-quantized: weight is a bool
      final fg = rgbColorLerp(
        const RgbColor(120, 120, 120),
        const RgbColor(255, 255, 255),
        t,
      );
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: Text(
          '${t > 0.5 ? '› ' : '  '}$label',
          style: CellStyle(foreground: fg, bold: bold),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// 4. Loop: a pulsing "recording" dot. loop(mirror) ping-pongs between
//    two colors forever — nothing to start, stop, or dispose-and-
//    restart. Settles to nothing when off-screen (no ticker).
// ---------------------------------------------------------------------------

class RecordingDot extends StatefulWidget {
  const RecordingDot({super.key});

  @override
  State<RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<RecordingDot> {
  late final Animation<RgbColor> _c = Animation(const RgbColor(120, 0, 0))
    ..loop(
      between: (const RgbColor(120, 0, 0), const RgbColor(255, 60, 60)),
      period: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
    );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text('●', style: CellStyle(foreground: _c.value));
}

// ---------------------------------------------------------------------------
// 5. Sequence + await: a toast that slides in, holds, slides out, then
//    calls onDismissed. The entire lifecycle is one run([...]); the
//    returned future fires when it finishes. run() before the widget
//    is on screen is deferred and plays on first display.
// ---------------------------------------------------------------------------

class Toast extends StatefulWidget {
  const Toast({required this.message, required this.onDismissed, super.key});
  final String message;
  final void Function() onDismissed;

  @override
  State<Toast> createState() => _ToastState();
}

class _ToastState extends State<Toast> {
  static const _hidden = 28;
  late final Animation<int> _x = Animation(_hidden);

  @override
  void initState() {
    super.initState();
    _x
        .run([
          AnimationStep.to(0, spring: Spring.snappy),
          const AnimationStep.hold(Duration(seconds: 2)),
          AnimationStep.to(
            _hidden,
            curve: Curves.easeIn,
            duration: const Duration(milliseconds: 200),
          ),
        ])
        .then((_) => widget.onDismissed());
  }

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: _x.value),
    child: Text(
      widget.message,
      style: const CellStyle(foreground: RgbColor(120, 200, 255)),
    ),
  );
}

// ---------------------------------------------------------------------------
// 6. Emphasis: a count badge that flashes when it changes, then
//    settles back. A two-step run on a color Animation.
// ---------------------------------------------------------------------------

class BadgeFlash extends StatefulWidget {
  const BadgeFlash({required this.count, super.key});
  final int count;

  @override
  State<BadgeFlash> createState() => _BadgeFlashState();
}

class _BadgeFlashState extends State<BadgeFlash> {
  static const _base = RgbColor(70, 70, 80);
  static const _flash = RgbColor(255, 220, 90);
  late final Animation<RgbColor> _bg = Animation(_base);

  @override
  void didUpdateWidget(BadgeFlash old) {
    super.didUpdateWidget(old);
    if (widget.count != old.count) {
      _bg.run([
        AnimationStep.to(
          _flash,
          curve: Curves.easeOut,
          duration: const Duration(milliseconds: 120),
        ),
        AnimationStep.to(
          _base,
          curve: Curves.easeIn,
          duration: const Duration(milliseconds: 450),
        ),
      ]);
    }
  }

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    ' ${widget.count} ',
    style: CellStyle(
      background: _bg.value,
      foreground: const RgbColor(0, 0, 0),
    ),
  );
}

// ---------------------------------------------------------------------------
// 7. Color tracks a value: combine Lerp (to pick the target color from
//    a 0..1 health) with Animation (to glide there). green = healthy,
//    red = bad.
// ---------------------------------------------------------------------------

class HealthDot extends StatelessWidget {
  const HealthDot({required this.health, super.key}); // 0 bad .. 1 good
  final double health;

  static const _bad = RgbColor(220, 60, 60);
  static const _good = RgbColor(80, 220, 120);

  @override
  Widget build(BuildContext context) => AnimationBuilder<RgbColor>(
    rgbColorLerp(_bad, _good, health.clamp(0, 1)),
    builder: (context, c) => Text('■', style: CellStyle(foreground: c)),
  );
}

// ---------------------------------------------------------------------------
// Runnable gallery wiring it together with key bindings.
// ---------------------------------------------------------------------------

Future<void> main() async {
  await runApp(
    const _Gallery(),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.code.character == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

class _Gallery extends StatefulWidget {
  const _Gallery();

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _selected = 0;
  int _counter = 0;
  bool _panelOpen = false;
  int _items = 0;
  final List<Widget> _toasts = [];

  static const _rows = ['Inbox', 'Drafts', 'Sent', 'Archive'];

  void _newItem() {
    setState(() {
      _items++;
      final id = _items;
      late final Widget toast;
      toast = Toast(
        message: '✓ item $id added',
        onDismissed: () => setState(() => _toasts.remove(toast)),
      );
      _toasts.add(toast);
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.key(KeyCode.arrowDown),
          onEvent: (_) =>
              setState(() => _selected = (_selected + 1) % _rows.length),
        ),
        KeyBinding(
          KeyChord.key(KeyCode.arrowUp),
          onEvent: (_) => setState(
            () => _selected = (_selected - 1 + _rows.length) % _rows.length,
          ),
        ),
        KeyBinding(
          KeyChord.char(' '),
          onEvent: (_) => setState(() => _panelOpen = !_panelOpen),
        ),
        KeyBinding(
          KeyChord.char('+'),
          onEvent: (_) => setState(() => _counter += 10),
        ),
        KeyBinding(
          KeyChord.char('-'),
          onEvent: (_) => setState(() => _counter -= 10),
        ),
        KeyBinding(KeyChord.char('n'), onEvent: (_) => _newItem()),
      ],
      child: Container(
        border: const BoxBorder(style: BorderStyle.rounded),
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              ' Animation recipes ',
              style: CellStyle(bold: true, foreground: AnsiColor(14)),
            ),
            const Text(''),
            Row(
              children: [
                const SizedBox(width: 14, child: Text(' recording')),
                const RecordingDot(),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 14, child: Text(' counter (+/-)')),
                AnimatedCounter(value: _counter),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 14, child: Text(' badge (n)')),
                BadgeFlash(count: _items),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 14, child: Text(' health')),
                HealthDot(health: (_counter % 100) / 100),
              ],
            ),
            const Text(''),
            const Text(' list (↑/↓):'),
            for (var i = 0; i < _rows.length; i++)
              SelectableRow(label: _rows[i], selected: i == _selected),
            const Text(''),
            Row(
              children: [
                const SizedBox(width: 14, child: Text(' panel (space)')),
                ExpandablePanel(
                  open: _panelOpen,
                  child: const Text(
                    '────────── details ──────────',
                    softWrap: false,
                  ),
                ),
              ],
            ),
            const Text(''),
            ..._toasts,
            const Text(' Ctrl+C exits.', style: CellStyle(dim: true)),
          ],
        ),
      ),
    );
  }
}
