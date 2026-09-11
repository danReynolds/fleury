// Lock test: RenderText's single-line fast path never consults maxLines.
// Short text with no newlines takes that path whenever it fits (or softWrap
// is false / width is unbounded), so `maxLines: 0` is silently ignored and
// the glyph still paints — while the same maxLines: 0 on a wrapping or
// multi-paragraph string correctly yields zero lines. Docs say maxLines caps
// the number of lines; zero must mean zero on every path.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  testWidgets(
    'maxLines: 0 suppresses a short single-line Text on the fast path',
    (tester) {
      tester.pumpWidget(const Text('hello', maxLines: 0));
      final out = tester.renderToString(size: const CellSize(10, 3));
      expect(
        out.replaceAll(RegExp(r'\s'), ''),
        isEmpty,
        reason:
            'maxLines: 0 must suppress all lines even when the single-line '
            'fast path would otherwise paint the full string',
      );
    },
  );

  testWidgets('maxLines: 0 with softWrap: false also suppresses short text', (
    tester,
  ) {
    tester.pumpWidget(
      const SizedBox(
        width: 20,
        height: 2,
        child: Text('hello', softWrap: false, maxLines: 0),
      ),
    );
    final out = tester.renderToString(size: const CellSize(20, 2));
    expect(
      out.replaceAll(RegExp(r'\s'), ''),
      isEmpty,
      reason:
          'softWrap: false still hits the single-line fast path; maxLines: 0 '
          'must not be skipped there either',
    );
  });

  testWidgets('maxLines: 0 is consistent across short and wrapping inputs', (
    tester,
  ) {
    // Control: wrapping path already honors maxLines: 0.
    tester.pumpWidget(
      const SizedBox(width: 4, height: 3, child: Text('abcdefgh', maxLines: 0)),
    );
    final wrapped = tester.renderToString(size: const CellSize(10, 3));
    expect(wrapped.replaceAll(RegExp(r'\s'), ''), isEmpty);

    tester.pumpWidget(const Text('ab', maxLines: 0));
    final short = tester.renderToString(size: const CellSize(10, 3));
    expect(
      short.replaceAll(RegExp(r'\s'), ''),
      isEmpty,
      reason:
          'short text must match the wrapping-path empty result under '
          'maxLines: 0 — today the fast path paints "ab"',
    );
  });
}
