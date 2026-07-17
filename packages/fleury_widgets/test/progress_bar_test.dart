import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _bar(FleuryTester tester, {int cols = 10}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    sb.write(buf.atColRow(c, 0).grapheme ?? ' ');
  }
  return sb.toString();
}

void main() {
  testWidgets('fills proportionally with a track behind', (tester) {
    tester.pumpWidget(const ProgressBar(value: 0.5));
    expect(_bar(tester), '█████░░░░░');
  });

  testWidgets('indeterminate (null value) sweeps a block across the track', (
    tester,
  ) {
    tester.pumpWidget(const ProgressBar(value: null));
    final f0 = _bar(tester);
    expect(f0.contains('█'), isTrue);
    expect(f0.contains('░'), isTrue, reason: 'a partial block, not full/empty');
    tester.pump(const Duration(milliseconds: 300)); // advance the marquee
    expect(_bar(tester), isNot(f0), reason: 'the lit block moved');
  });

  testWidgets('full and empty extremes', (tester) {
    tester.pumpWidget(const ProgressBar(value: 1));
    expect(_bar(tester), '██████████');
    tester.pumpWidget(const ProgressBar(value: 0));
    expect(_bar(tester), '░░░░░░░░░░');
  });

  testWidgets('value updates repaint without relayout', (tester) {
    tester.pumpWidget(const ProgressBar(value: 0.2));
    tester.render(size: const CellSize(10, 1));

    tester.pumpWidget(const ProgressBar(value: 0.8));
    RenderLayoutDebugStats.beginFrame(enabled: true);
    final buf = tester.render(size: const CellSize(10, 1));
    final stats = RenderLayoutDebugStats.takeFrameStats();

    final row = StringBuffer();
    for (var c = 0; c < 10; c++) {
      row.write(buf.atColRow(c, 0).grapheme ?? ' ');
    }
    expect(row.toString(), '████████░░');
    expect(stats.performedCount, 0);
    expect(stats.skippedCount, greaterThan(0));
  });

  testWidgets('renders a partial block for sub-cell precision', (tester) {
    // 0.45 * 10 = 4.5 cells → 4 full + a half block + 5 track.
    tester.pumpWidget(const ProgressBar(value: 0.45));
    expect(_bar(tester), '████▌░░░░░');
  });

  testWidgets('uses ASCII glyphs under ASCII glyph tier', (tester) {
    tester.pumpWidget(const ProgressBar(value: 0.45));
    expect(_bar(tester), '####+.....');
  }, glyphTier: GlyphTier.ascii);

  testWidgets('clamps out-of-range values', (tester) {
    tester.pumpWidget(const ProgressBar(value: 1.5));
    expect(_bar(tester), '██████████');
    tester.pumpWidget(const ProgressBar(value: -0.3));
    expect(_bar(tester), '░░░░░░░░░░');
  });

  testWidgets('fills the bounded width it is given', (tester) {
    tester.pumpWidget(const SizedBox(width: 4, child: ProgressBar(value: 0.5)));
    expect(_bar(tester, cols: 4), '██░░'); // 4-wide bar, half filled
  });

  testWidgets('exposes progress semantics', (tester) {
    tester.pumpWidget(const ProgressBar(value: 0.45));

    final node = tester.semantics().single(role: SemanticRole.progress);
    expect(node.label, 'Progress');
    expect(node.value, 0.45);
    expect(node.state.progressCurrent, 0.45);
    expect(node.state.progressTotal, 1.0);
    expect(node.state.progressLabel, '45%');
  });

  testWidgets('accepts a custom semantic label', (tester) {
    tester.pumpWidget(
      const ProgressBar(value: 0.45, semanticLabel: 'Download progress'),
    );

    final node = tester.semantics().single(role: SemanticRole.progress);
    expect(node.label, 'Download progress');
  });
}
