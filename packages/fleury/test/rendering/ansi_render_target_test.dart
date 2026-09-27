import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/rendering/ansi_render_target.dart';
import 'package:test/test.dart';

void main() {
  test('inline clear erases only the allocated rows with default style', () {
    const target = AnsiRenderTarget.inline(top: 5);
    expect(
      target.clearSequence(const CellSize(80, 2)),
      '\x1B[0m\x1B[6;1H\x1B[2K\x1B[7;1H\x1B[2K',
    );
    expect(target.clearSequence(CellSize.zero), isEmpty);
    expect(target.clearSequence(const CellSize(0, 2)), isEmpty);
  });

  test('an inline region at row zero does not acquire the whole screen', () {
    const target = AnsiRenderTarget.inline(top: 0);
    expect(
      target.clearSequence(const CellSize(80, 1)),
      '\x1B[0m\x1B[1;1H\x1B[2K',
    );
    expect(target, isNot(const AnsiRenderTarget.fullScreen()));
  });

  test('pointer coordinates outside the region stay outside', () {
    const target = AnsiRenderTarget.inline(top: 5);
    expect(target.toLocal(const CellOffset(3, 5)), const CellOffset(3, 0));
    expect(target.toLocal(const CellOffset(3, 4)), const CellOffset(3, -1));
    expect(target.toLocal(const CellOffset(-1, 15)), const CellOffset(-1, 10));
    for (final point in [const CellOffset(3, 8), const CellOffset(0, -1)]) {
      expect(target.toLocal(target.toTerminal(point)), point);
    }
  });
}
