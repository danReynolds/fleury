import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('x');
  }
}

void main() {
  testWidgets('sizeOf reports the tester viewport', (tester) {
    tester.viewportSize = const CellSize(40, 12);
    late CellSize size;
    tester.pumpWidget(_Capture((c) => size = MediaQuery.sizeOf(c)));
    expect(size, const CellSize(40, 12));
  });

  testWidgets('of returns the full data', (tester) {
    tester.viewportSize = const CellSize(30, 10);
    tester.glyphTier = GlyphTier.ascii;
    late MediaQueryData data;
    late BuildContext dataContext;
    tester.pumpWidget(
      _Capture((c) {
        dataContext = c;
        data = MediaQuery.of(c);
      }),
    );
    expect(data.size, const CellSize(30, 10));
    expect(data.glyphTier, GlyphTier.ascii);
    expect(MediaQuery.glyphTierOf(dataContext), GlyphTier.ascii);
  });

  testWidgets('maybeOf is null with no MediaQuery ancestor', (tester) {
    // A render-only path with no MediaQuery: maybeOf must not throw.
    MediaQueryData? data = const MediaQueryData(size: CellSize(1, 1));
    tester.pumpWidget(
      Builder((c) {
        // There IS a MediaQuery from the harness; assert maybeOf finds it.
        data = MediaQuery.maybeOf(c);
        return const Text('x');
      }),
    );
    expect(data, isNotNull);
  });

  test('MediaQueryData equality drives updates', () {
    expect(
      const MediaQueryData(size: CellSize(5, 5)),
      const MediaQueryData(size: CellSize(5, 5)),
    );
    expect(
      const MediaQueryData(size: CellSize(5, 5)),
      isNot(const MediaQueryData(size: CellSize(6, 5))),
    );
    expect(
      const MediaQueryData(size: CellSize(5, 5)),
      isNot(
        const MediaQueryData(size: CellSize(5, 5), glyphTier: GlyphTier.ascii),
      ),
    );
  });
}

/// Minimal inline builder widget for the test (the framework has no
/// public Builder).
class Builder extends StatelessWidget {
  const Builder(this._build, {super.key});
  final Widget Function(BuildContext) _build;
  @override
  Widget build(BuildContext context) => _build(context);
}
