// Implicit reactivity: reading animation.value during a build
// auto-subscribes that widget (no AnimationBuilder, no ListenableBuilder).

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// A widget that reads [animation] directly in build and paints the
/// value, with no explicit subscription wrapper.
class _Reader extends StatelessWidget {
  const _Reader(this.animation);
  final Animation<int> animation;

  @override
  Widget build(BuildContext context) => Text('${animation.value}');
}

/// Reads a double animation and renders a hash-fill bar.
class _Bar extends StatelessWidget {
  const _Bar(this.animation, {required this.width});
  final Animation<double> animation;
  final int width;

  @override
  Widget build(BuildContext context) {
    final cells = (animation.value * width).round();
    return Text('${'#' * cells}${'.' * (width - cells)}');
  }
}

void main() {
  group('implicit subscribe', () {
    testWidgets('reading value in build rebuilds on change — no '
        'builder widget', (tester) {
      final m = Animation(0);
      tester.pumpWidget(_Reader(m));
      expect(tester.renderToString(size: const CellSize(4, 1)), '0\n');

      m.to(
        10,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
      );
      tester.pump(const Duration(milliseconds: 100));
      expect(tester.renderToString(size: const CellSize(4, 1)), '10\n');
    });

    testWidgets('mid-animation snapshots track the curve', (tester) {
      final m = Animation(0.0);
      tester.pumpWidget(_Bar(m, width: 10));
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        '..........\n',
      );

      m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 200),
      );
      tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        '#####.....\n',
        reason: 'linear halfway',
      );
      tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        '##########\n',
      );
    });

    testWidgets('unmounting stops the animation from marking a dead '
        'element dirty', (tester) {
      final m = Animation(0);
      tester.pumpWidget(_Reader(m));
      m.to(10, spring: Spring.snappy);
      tester.pump(const Duration(milliseconds: 32));

      // Replace the reader with something that doesn't read the
      // animation. The old reader unmounts and should detach.
      tester.pumpWidget(const Text('gone'));
      // Continuing to animate must not throw (no dangling dependent).
      expect(() => tester.pump(const Duration(seconds: 1)), returnsNormally);
      expect(tester.renderToString(size: const CellSize(4, 1)), 'gone\n');
    });

    testWidgets('two widgets reading the same animation both update', (tester) {
      final m = Animation(0);
      tester.pumpWidget(Column(children: [_Reader(m), _Reader(m)]));
      m.snap(7);
      tester.pump();
      final out = tester.renderToString(size: const CellSize(4, 2));
      expect(out, '7\n7\n');
    });

    testWidgets('animate-on-appear: to() before display is deferred '
        'and runs on attach', (tester) {
      // The assign-and-animate idiom: a field that retargets at
      // construction, before any binding exists.
      final m = Animation(0)
        ..to(
          10,
          curve: Curves.linear,
          duration: const Duration(milliseconds: 100),
        );
      // Not on screen yet → still at the initial value.
      expect(m.value, 0);

      tester.pumpWidget(_Reader(m)); // attaches → deferred to() runs
      tester.pump(const Duration(milliseconds: 50));
      expect(m.value, inInclusiveRange(3, 7), reason: 'animating after attach');
      tester.pump(const Duration(milliseconds: 100));
      expect(m.value, 10);
    });

    testWidgets('disposed animation value reads stay renderable but do not '
        'reattach', (tester) {
      final m = Animation(7)..dispose();

      tester.pumpWidget(_Reader(m));

      expect(tester.renderToString(size: const CellSize(4, 1)), '7\n');
      expect(tester.scheduler.activeTickerCount, 0);
      expect(() => m.to(9), throwsStateError);
    });
  });
}
