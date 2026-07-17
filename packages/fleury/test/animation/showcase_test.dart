// Animation capability showcase.
//
// This file is a verified showcase: each "demo" is a small widget
// pattern that exercises the animation infrastructure end-to-end,
// with goldens captured at multiple frames so the visual progress
// is pinned against regression.
//
// Patterns demonstrated:
//
//   1. Typewriter text — discrete-lane FrameTicker reveals one
//      grapheme per tick.
//   2. Progress bar fill — a continuous-lane Animation<int> animating
//      on appear, painted as a hash-fill row.
//   3. Pulsing border — a looping Animation<RgbColor> threaded into a
//      Container's BoxBorder.cellStyle.
//   4. Marquee text — FrameTicker stepping a horizontal offset
//      across a fixed-width window.
//   5. Two animations on one widget — typewriter + progress bar
//      composed; verifies the scheduler coalesces multiple
//      independent animations behind one timer.
//
// Update goldens with:
//
//     FLEURY_UPDATE_GOLDENS=1 dart test test/animation/showcase_test.dart

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Demo 1: typewriter text
// ---------------------------------------------------------------------------

/// Reveals [text] one character per [interval]. Stops when fully
/// revealed; further ticks become no-ops.
class _Typewriter extends StatelessWidget {
  const _Typewriter({
    required this.text,
    this.interval = const Duration(milliseconds: 100),
  });

  final String text;
  final Duration interval;

  @override
  Widget build(BuildContext context) {
    return FrameBuilder(
      interval: interval,
      builder: (context, frame, elapsed, delta) {
        final visible = frame.clamp(0, text.length);
        return Text(text.substring(0, visible));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Demo 2: animated progress bar
// ---------------------------------------------------------------------------

/// Fills [width] cells over [duration]. An `Animation<int>` keeps the
/// visible cell count an exact integer at every frame (no
/// half-painted cells), and the "animate on appear" idiom kicks it
/// off: the field retargets at construction; it runs when the widget
/// first displays.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.width, required this.duration});
  final int width;
  final Duration duration;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  late final Animation<int> _filled = Animation(0)
    ..to(widget.width, curve: Curves.linear, duration: widget.duration);

  @override
  void dispose() {
    _filled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cells = _filled.value; // implicit subscribe + attach
    return Text('${'#' * cells}${'.' * (widget.width - cells)}');
  }
}

// ---------------------------------------------------------------------------
// Demo 3: pulsing border
// ---------------------------------------------------------------------------

/// A bordered container whose border color animates between [from]
/// and [to] over [duration], reversing forever. A looping
/// `Animation<RgbColor>` drives the border's CellStyle directly — read
/// `value` in build and you're subscribed.
class _PulsingBorder extends StatefulWidget {
  const _PulsingBorder({
    required this.child,
    required this.from,
    required this.to,
    required this.duration,
  });
  final Widget child;
  final RgbColor from;
  final RgbColor to;
  final Duration duration;

  @override
  State<_PulsingBorder> createState() => _PulsingBorderState();
}

class _PulsingBorderState extends State<_PulsingBorder> {
  late final Animation<RgbColor> _color = Animation(widget.from)
    ..loop(
      between: (widget.from, widget.to),
      period: widget.duration,
      curve: Curves.easeInOut,
    );

  @override
  void dispose() {
    _color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      border: BoxBorder(
        style: BorderStyle.rounded,
        cellStyle: CellStyle(foreground: _color.value),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// Demo 4: marquee
// ---------------------------------------------------------------------------

/// Scrolls [text] horizontally inside a [windowWidth]-cell viewport,
/// wrapping at the end. The visible substring changes by one cell
/// per [interval].
class _Marquee extends StatelessWidget {
  const _Marquee({
    required this.text,
    required this.windowWidth,
    this.interval = const Duration(milliseconds: 100),
  });
  final String text;
  final int windowWidth;
  final Duration interval;

  @override
  Widget build(BuildContext context) {
    // Pad with spaces so the wrap doesn't look glued.
    final padded = '$text   ';
    return FrameBuilder(
      interval: interval,
      builder: (context, frame, elapsed, delta) {
        final n = padded.length;
        final start = frame % n;
        final doubled = padded + padded;
        return Text(doubled.substring(start, start + windowWidth));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tests + goldens
// ---------------------------------------------------------------------------

void main() {
  group('1. Typewriter (discrete lane)', () {
    testWidgets('reveals one character per tick', (tester) {
      tester.pumpWidget(
        const _Typewriter(text: 'hello', interval: Duration(milliseconds: 100)),
      );

      // Frame 0: nothing visible yet (the FrameTicker only advances
      // once the interval has passed).
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        matchesGolden('showcase/typewriter_0.txt'),
      );

      tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        matchesGolden('showcase/typewriter_1.txt'),
      );

      tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        matchesGolden('showcase/typewriter_4.txt'),
      );

      tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        matchesGolden('showcase/typewriter_full.txt'),
        reason:
            'Past the last character — visible substring '
            'should pin at "hello" without growing further.',
      );
    });
  });

  group('2. Progress bar (continuous lane)', () {
    testWidgets('fills evenly from empty to full', (tester) {
      tester.pumpWidget(
        const _ProgressBar(width: 10, duration: Duration(milliseconds: 500)),
      );

      // Frame 0: just started, nothing painted yet beyond the
      // initial value (the controller has just been .forward()ed,
      // and a tick hasn't been delivered).
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        matchesGolden('showcase/progress_0pct.txt'),
      );

      tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        matchesGolden('showcase/progress_50pct.txt'),
      );

      tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        matchesGolden('showcase/progress_100pct.txt'),
      );

      // Past completion: stays at full.
      tester.pump(const Duration(milliseconds: 1000));
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        matchesGolden('showcase/progress_100pct.txt'),
      );
    });
  });

  group('3. Pulsing border (looping Animation<RgbColor>)', () {
    testWidgets('border foreground color cycles between two RGB '
        'endpoints', (tester) {
      tester.pumpWidget(
        _PulsingBorder(
          from: const RgbColor(255, 0, 0),
          to: const RgbColor(0, 255, 0),
          duration: const Duration(milliseconds: 400),
          child: const Text('hi'),
        ),
      );

      // Frame 0: the controller has just started; no tick has
      // landed yet, so the border color is still at `from`.
      _expectBorderColor(tester, const RgbColor(255, 0, 0));

      // Halfway through the easeInOut curve. Test by frame
      // sampling — exact value depends on the curve shape, so we
      // just assert it has moved off the start.
      tester.pump(const Duration(milliseconds: 200));
      final mid = _readBorderColor(tester);
      expect(mid, isNot(equals(const RgbColor(255, 0, 0))));
      expect(mid, isNot(equals(const RgbColor(0, 255, 0))));

      // End of the first half-cycle: at the `to` endpoint, modulo
      // sub-millisecond curve precision. easeInOut at t=1 is
      // exactly 1, so the value should be the to color.
      tester.pump(const Duration(milliseconds: 200));
      _expectBorderColor(tester, const RgbColor(0, 255, 0));

      // After repeat(reverse: true) flips the direction, by the
      // next half-cycle we should be back at the from color.
      tester.pump(const Duration(milliseconds: 400));
      _expectBorderColor(
        tester,
        const RgbColor(255, 0, 0),
        reason: 'reverse half-cycle returns to from',
      );
    });
  });

  group('4. Marquee (FrameTicker stepping)', () {
    testWidgets('scrolls text horizontally across a window', (tester) {
      tester.pumpWidget(
        const _Marquee(
          text: 'abcdef',
          windowWidth: 5,
          interval: Duration(milliseconds: 80),
        ),
      );

      // Position 0: shows the first 5 cells of the padded text.
      expect(
        tester.renderToString(size: const CellSize(5, 1)),
        matchesGolden('showcase/marquee_pos0.txt'),
      );

      tester.pump(const Duration(milliseconds: 80));
      expect(
        tester.renderToString(size: const CellSize(5, 1)),
        matchesGolden('showcase/marquee_pos1.txt'),
      );

      // After several ticks the window has rolled past the end.
      tester.pump(const Duration(milliseconds: 80 * 7));
      expect(
        tester.renderToString(size: const CellSize(5, 1)),
        matchesGolden('showcase/marquee_pos8.txt'),
      );
    });
  });

  group('5. Multiple animations share one timer', () {
    testWidgets('typewriter + progress bar in one tree register two '
        'tickers behind one scheduler timer', (tester) {
      tester.pumpWidget(
        const Column(
          children: [
            _Typewriter(text: 'loading'),
            _ProgressBar(width: 10, duration: Duration(milliseconds: 700)),
          ],
        ),
      );

      // Two independent animations (one discrete, one continuous)
      // → two active tickers, but the scheduler holds exactly one
      // Timer.periodic underneath. The FakeTickerScheduler's
      // `isActive` reflects whether the real-world Timer would
      // exist; the count of tickers reflects animation work.
      expect(tester.scheduler.activeTickerCount, 2);
      expect(tester.scheduler.isActive, isTrue);

      // Mid-animation snapshot pins both progressing together.
      tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.renderToString(size: const CellSize(10, 2)),
        matchesGolden('showcase/composite_mid.txt'),
      );
    });
  });

  group('6. AnimationPolicy.disabled snaps animations to their end', () {
    testWidgets('progress bar with disabled policy jumps straight to '
        'full', (tester) {
      tester.pumpWidget(
        const _ProgressBar(width: 10, duration: Duration(seconds: 5)),
      );

      // Without advancing time at all — the Animation's deferred to()
      // runs on attach, sees AnimationPolicy.disabled, and snaps to
      // the target. The bar paints fully even though zero ms
      // elapsed.
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        matchesGolden('showcase/progress_100pct.txt'),
      );
    }, animationPolicy: AnimationPolicy.disabled);
  });
}

/// Reads the foreground RGB color of the first border glyph in the
/// rendered cell buffer. The pulsing border wraps a small child,
/// so the top-left border cell is at (0, 0).
RgbColor _readBorderColor(FleuryTester tester) {
  final buffer = tester.render(size: const CellSize(8, 3));
  final fg = buffer.atColRow(0, 0).style.foreground;
  if (fg is! RgbColor) {
    throw StateError('Expected RgbColor at (0,0) border cell, got $fg');
  }
  return fg;
}

void _expectBorderColor(
  FleuryTester tester,
  RgbColor expected, {
  String? reason,
}) {
  expect(_readBorderColor(tester), expected, reason: reason);
}
