// Tests for FrameBuilder, Spinner, and BlinkingCursor.
// FakeClock-driven; includes golden-style snapshot assertions for
// the public spinner/cursor widgets per RFC §21.2.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

String _rowContent(CellBuffer buffer, int row) {
  final buf = StringBuffer();
  for (var col = 0; col < buffer.size.cols; col++) {
    final cell = buffer.atColRow(col, row);
    switch (cell.role) {
      case CellRole.empty:
        buf.write('·');
      case CellRole.leading:
        buf.write(cell.grapheme);
      case CellRole.continuation:
      case CellRole.protocolAnchor:
      case CellRole.protocolCovered:
        break;
    }
  }
  return buf.toString();
}

({BuildOwner owner, Element root, FakeTickerScheduler scheduler}) _mount(
  Widget app,
) {
  final clock = FakeClock();
  final scheduler = FakeTickerScheduler(clock: clock);
  final binding = TuiBinding(tickerScheduler: scheduler);
  final owner = BuildOwner();
  final root = owner.mountRoot(TuiBindingScope(binding: binding, child: app));
  return (owner: owner, root: root, scheduler: scheduler);
}

void main() {
  group('FrameBuilder', () {
    test('builder receives advancing frame counter', () {
      final receivedFrames = <int>[];
      final m = _mount(
        FrameBuilder(
          interval: const Duration(milliseconds: 100),
          builder: (ctx, frame, elapsed, delta) {
            receivedFrames.add(frame);
            return const Text('hi');
          },
        ),
      );

      // First build sees frame 0.
      expect(receivedFrames, [0]);

      m.scheduler.advance(const Duration(milliseconds: 100));
      m.owner.flushBuild();
      expect(receivedFrames.last, 1);

      m.scheduler.advance(const Duration(milliseconds: 100));
      m.owner.flushBuild();
      expect(receivedFrames.last, 2);
    });

    test('enabled: false stops the ticker', () {
      final receivedFrames = <int>[];
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: FrameBuilder(
            interval: const Duration(milliseconds: 100),
            enabled: false,
            builder: (ctx, frame, elapsed, delta) {
              receivedFrames.add(frame);
              return const Text('hi');
            },
          ),
        ),
      );
      expect(receivedFrames, [0]);

      scheduler.advance(const Duration(milliseconds: 500));
      owner.flushBuild();
      expect(receivedFrames, [
        0,
      ], reason: 'no frames advance while enabled is false');

      // Re-enable by swapping the widget.
      owner.updateRoot(
        root,
        TuiBindingScope(
          binding: binding,
          child: FrameBuilder(
            interval: const Duration(milliseconds: 100),
            enabled: true,
            builder: (ctx, frame, elapsed, delta) {
              receivedFrames.add(frame);
              return const Text('hi');
            },
          ),
        ),
      );
      scheduler.advance(const Duration(milliseconds: 100));
      owner.flushBuild();
      expect(receivedFrames.last, 1);
    });

    test('FrameBuilder under TickerMode(enabled: false) mutes', () {
      final receivedFrames = <int>[];
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: TickerMode(
            enabled: false,
            child: FrameBuilder(
              interval: const Duration(milliseconds: 100),
              builder: (ctx, frame, elapsed, delta) {
                receivedFrames.add(frame);
                return const Text('hi');
              },
            ),
          ),
        ),
      );
      scheduler.advance(const Duration(milliseconds: 300));
      owner.flushBuild();
      // Frame counter advances internally (so re-enabling lands at
      // the right frame), but no notifications => no rebuilds.
      expect(receivedFrames, [0]);
    });
  });

  group('Spinner golden snapshots (braille)', () {
    test('cycles through all 10 braille frames at default 80ms', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const Spinner()),
      );
      const expected = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
      for (var i = 0; i < expected.length; i++) {
        final buffer = CellBuffer(const CellSize(1, 1));
        owner.renderFrame(root, buffer);
        expect(
          _rowContent(buffer, 0),
          expected[i],
          reason: 'frame $i should be ${expected[i]}',
        );
        scheduler.advance(const Duration(milliseconds: 80));
        owner.flushBuild();
      }
    });

    test('label renders after the glyph', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: const Spinner(label: 'Loading'),
        ),
      );
      final buffer = CellBuffer(const CellSize(12, 1));
      owner.renderFrame(root, buffer);
      expect(_rowContent(buffer, 0), '⠋ Loading···');
    });
  });

  group('Spinner golden snapshots (ascii)', () {
    test('cycles through |/-\\ at default 80ms', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(
          binding: binding,
          child: const Spinner(style: SpinnerStyle.ascii),
        ),
      );
      const expected = ['|', '/', '-', r'\'];
      for (var i = 0; i < expected.length; i++) {
        final buffer = CellBuffer(const CellSize(1, 1));
        owner.renderFrame(root, buffer);
        expect(_rowContent(buffer, 0), expected[i]);
        scheduler.advance(const Duration(milliseconds: 80));
        owner.flushBuild();
      }
    });
  });

  group('BlinkingCursor golden snapshot', () {
    test('alternates between glyph and space at 500ms', () {
      final clock = FakeClock();
      final scheduler = FakeTickerScheduler(clock: clock);
      final binding = TuiBinding(tickerScheduler: scheduler);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        TuiBindingScope(binding: binding, child: const BlinkingCursor()),
      );

      // Frame 0: visible.
      var buffer = CellBuffer(const CellSize(1, 1));
      owner.renderFrame(root, buffer);
      expect(_rowContent(buffer, 0), '█');

      // Advance to frame 1: hidden (rendered as a space character,
      // which paints a leading cell with grapheme ' ' rather than
      // leaving the cell empty — important for stacked-cursor
      // semantics on top of bordered Containers).
      scheduler.advance(const Duration(milliseconds: 500));
      owner.flushBuild();
      buffer = CellBuffer(const CellSize(1, 1));
      owner.renderFrame(root, buffer);
      expect(
        _rowContent(buffer, 0),
        ' ',
        reason: 'odd frame: visible space, preserves layout',
      );

      // Frame 2: visible again.
      scheduler.advance(const Duration(milliseconds: 500));
      owner.flushBuild();
      buffer = CellBuffer(const CellSize(1, 1));
      owner.renderFrame(root, buffer);
      expect(_rowContent(buffer, 0), '█');
    });
  });
}
