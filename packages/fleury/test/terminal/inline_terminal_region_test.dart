import 'package:fleury/src/foundation/geometry.dart';
import 'package:fleury/src/terminal/inline_terminal_region.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reserves only the requested rows and accounts for bottom scrolling',
    () {
      final region = InlineTerminalRegion(4);
      expect(
        region.acquire(const CellSize(80, 24), const CellOffset(0, 22)),
        '\r\n\n\n',
      );
      expect(region.target.top, 20);
      expect(region.size, const CellSize(80, 4));
      expect(region.terminalCursor, const CellOffset(0, 23));
    },
  );

  test('preserves a partial line before starting its allocation', () {
    final region = InlineTerminalRegion(3);
    expect(
      region.acquire(const CellSize(80, 24), const CellOffset(7, 4)),
      '\r\n\r\n\n',
    );
    expect(region.target.top, 5);
  });

  test('clamps height, clears once, and parks where a summary can print', () {
    final region = InlineTerminalRegion(30);
    region.acquire(const CellSize(80, 3), const CellOffset(0, 2));
    expect(region.size, const CellSize(80, 3));
    expect(region.target.top, 0);
    final release = region.release(const CellSize(80, 3));
    expect(release, endsWith('\x1B[1;1H'));
    expect(RegExp(r'\x1b\[2K').allMatches(release).length, 3);
    expect(release, isNot(contains('\x1B[2J')));
    expect(region.release(const CellSize(80, 3)), isEmpty);
  });

  test('height shrink clears the old tail before reserving fewer rows', () {
    final region = InlineTerminalRegion(5);
    region.acquire(const CellSize(80, 24), const CellOffset(0, 10));
    final bytes = region.resize(
      const CellSize(80, 24),
      region.terminalCursor,
      rows: 2,
    );
    expect(RegExp(r'\x1b\[2K').allMatches(bytes).length, 5);
    expect(region.target.top, 10);
    expect(region.size, const CellSize(80, 2));
  });

  test('resize reanchors from the actual cursor and its last local row', () {
    final region = InlineTerminalRegion(4);
    region.acquire(const CellSize(80, 24), const CellOffset(0, 20));
    region.recordCursor(const CellOffset(3, 1));
    region.resize(const CellSize(60, 10), const CellOffset(3, 7));
    expect(region.target.top, 6);
    expect(region.size, const CellSize(60, 4));
  });

  test('unobserved resize on release never clears at stale coordinates', () {
    final region = InlineTerminalRegion(4);
    region.acquire(const CellSize(80, 24), const CellOffset(0, 20));
    expect(region.release(const CellSize(40, 10)), '\r\n');
  });

  test('invalid heights fail in release builds too', () {
    expect(() => InlineTerminalRegion(0), throwsArgumentError);
    final region = InlineTerminalRegion(2);
    expect(() => region.requestRows(-1), throwsArgumentError);
    expect(region.requestedRows, 2);
  });
}
