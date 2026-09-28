import 'package:fleury/fleury_host.dart';
import 'package:test/test.dart';

void main() {
  test('semantic coverage leaves fully covered visible text unchanged', () {
    final buffer = CellBuffer(const CellSize(8, 1))
      ..writeText(const CellOffset(0, 0), 'covered');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('text'),
            role: SemanticRole.text,
            label: 'covered',
            value: 'covered',
            bounds: CellRect.fromLTWH(0, 0, 7, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(tree: tree, buffer: buffer);

    expect(result.tree, same(tree));
    expect(result.audit.uncoveredCellCount, 0);
    expect(result.audit.fallbackNodeCount, 0);
  });

  test('semantic coverage leaves fully covered viewport unchanged', () {
    final buffer = CellBuffer(const CellSize(8, 2))
      ..writeText(const CellOffset(0, 0), 'row zero')
      ..writeText(const CellOffset(0, 1), 'row one');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('row-zero'),
            role: SemanticRole.text,
            label: 'row zero',
            value: 'row zero',
            bounds: CellRect.fromLTWH(0, 0, 8, 1),
          ),
          SemanticNode(
            id: const SemanticNodeId('row-one'),
            role: SemanticRole.text,
            label: 'row one',
            value: 'row one',
            bounds: CellRect.fromLTWH(0, 1, 8, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(tree: tree, buffer: buffer);

    expect(result.tree, same(tree));
    expect(result.audit.uncoveredCellCount, 0);
    expect(result.audit.fallbackNodeCount, 0);
  });

  test('semantic coverage accepts adjacent readable dirty-row bounds', () {
    final buffer = CellBuffer(const CellSize(8, 1))
      ..writeText(const CellOffset(0, 0), 'abcdefgh');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('left'),
            role: SemanticRole.text,
            label: 'abcd',
            value: 'abcd',
            bounds: CellRect.fromLTWH(0, 0, 4, 1),
          ),
          SemanticNode(
            id: const SemanticNodeId('right'),
            role: SemanticRole.text,
            label: 'efgh',
            value: 'efgh',
            bounds: CellRect.fromLTWH(4, 0, 4, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(
      tree: tree,
      buffer: buffer,
      dirtyRows: TuiDirtyRows.range(0, 1, rowCount: 1),
      previousAudit: SemanticCoverageAudit.empty,
    );

    expect(result.tree, same(tree));
    expect(result.audit.uncoveredCellCount, 0);
    expect(result.audit.fallbackNodeCount, 0);
  });

  test(
    'semantic coverage appends fallback nodes for uncovered visible text',
    () {
      final buffer = CellBuffer(const CellSize(8, 1))
        ..writeText(const CellOffset(0, 0), 'raw');
      const tree = SemanticTree(
        root: SemanticNode(id: SemanticNodeId('root'), role: SemanticRole.app),
      );

      final result = applySemanticTextFallback(tree: tree, buffer: buffer);
      final fallback = result.tree.single(
        id: const SemanticNodeId('__fleury_text_fallback_0_0'),
      );

      expect(result.audit.uncoveredCellCount, 3);
      expect(result.audit.fallbackNodeCount, 1);
      expect(fallback.role, SemanticRole.text);
      expect(fallback.label, 'raw');
      expect(fallback.value, 'raw');
      expect(fallback.bounds, CellRect.fromLTWH(0, 0, 3, 1));
      expect(fallback.state['semanticFallback'], isTrue);
    },
  );

  test('semantic coverage only falls back uncovered runs', () {
    final buffer = CellBuffer(const CellSize(8, 1))
      ..writeText(const CellOffset(0, 0), 'abc def');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('covered'),
            role: SemanticRole.text,
            label: 'abc',
            value: 'abc',
            bounds: CellRect.fromLTWH(0, 0, 3, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(tree: tree, buffer: buffer);
    final fallback = result.tree.single(
      id: const SemanticNodeId('__fleury_text_fallback_0_4'),
    );

    expect(result.audit.uncoveredCellCount, 3);
    expect(result.audit.fallbackNodeCount, 1);
    expect(fallback.label, 'def');
    expect(fallback.bounds, CellRect.fromLTWH(4, 0, 3, 1));
  });

  test('semantic coverage scopes clean follow-up audit to dirty rows', () {
    final buffer = CellBuffer(const CellSize(8, 2))
      ..writeText(const CellOffset(0, 0), 'stable')
      ..writeText(const CellOffset(0, 1), 'raw');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('stable'),
            role: SemanticRole.text,
            label: 'stable',
            value: 'stable',
            bounds: CellRect.fromLTWH(0, 0, 6, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(
      tree: tree,
      buffer: buffer,
      dirtyRows: TuiDirtyRows.range(1, 2, rowCount: 2),
      previousAudit: SemanticCoverageAudit.empty,
    );

    expect(result.audit.uncoveredCellCount, 3);
    expect(result.audit.fallbackNodeCount, 1);
    expect(
      result.tree
          .single(id: const SemanticNodeId('__fleury_text_fallback_1_0'))
          .label,
      'raw',
    );
  });

  test('semantic coverage full scans after previous fallback reliance', () {
    final buffer = CellBuffer(const CellSize(8, 2))
      ..writeText(const CellOffset(0, 0), 'raw')
      ..writeText(const CellOffset(0, 1), 'covered');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('covered'),
            role: SemanticRole.text,
            label: 'covered',
            value: 'covered',
            bounds: CellRect.fromLTWH(0, 1, 7, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(
      tree: tree,
      buffer: buffer,
      dirtyRows: TuiDirtyRows.range(1, 2, rowCount: 2),
      previousAudit: const SemanticCoverageAudit(
        uncoveredCellCount: 3,
        fallbackNodeCount: 1,
      ),
    );

    expect(result.audit.uncoveredCellCount, 3);
    expect(result.audit.fallbackNodeCount, 1);
    expect(
      result.tree
          .single(id: const SemanticNodeId('__fleury_text_fallback_0_0'))
          .label,
      'raw',
    );
  });

  test('structural semantic bounds do not suppress text fallback', () {
    final buffer = CellBuffer(const CellSize(8, 1))
      ..writeText(const CellOffset(0, 0), 'raw');
    final tree = SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('route'),
            role: SemanticRole.route,
            label: 'RawRoute',
            bounds: CellRect.fromLTWH(0, 0, 8, 1),
          ),
        ],
      ),
    );

    final result = applySemanticTextFallback(tree: tree, buffer: buffer);

    expect(result.audit.uncoveredCellCount, 3);
    expect(result.audit.fallbackNodeCount, 1);
    expect(
      result.tree
          .single(id: const SemanticNodeId('__fleury_text_fallback_0_0'))
          .label,
      'raw',
    );
  });

  group('drawing glyphs are not text', () {
    // A panel's frame, a gauge's bar, a plot's dots: read aloud, each is a
    // run of glyph names, and counting them as uncovered text kept every
    // framed app on the semantics pipeline's slow path.
    SemanticTree regionAround(List<SemanticNode> children) => SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: const SemanticNodeId('panel'),
            role: SemanticRole.region,
            label: 'Services',
            bounds: CellRect.fromLTWH(0, 0, 9, 3),
            children: children,
          ),
        ],
      ),
    );

    CellBuffer framed(String inside) => CellBuffer(const CellSize(9, 3))
      ..writeText(const CellOffset(0, 0), '╭───────╮')
      ..writeText(const CellOffset(0, 1), '│$inside│')
      ..writeText(const CellOffset(0, 2), '╰───────╯');

    test('a frame around covered text leaves nothing uncovered', () {
      final tree = regionAround([
        SemanticNode(
          id: const SemanticNodeId('text'),
          role: SemanticRole.text,
          label: 'hello',
          value: 'hello',
          bounds: CellRect.fromLTWH(1, 1, 5, 1),
        ),
      ]);

      final result = applySemanticTextFallback(
        tree: tree,
        buffer: framed('hello  '),
      );

      expect(result.audit.hasUncoveredText, isFalse);
      expect(result.audit.fallbackNodeCount, 0);
    });

    test('text inside a frame falls back without the frame', () {
      final result = applySemanticTextFallback(
        tree: regionAround(const []),
        buffer: framed('hello  '),
      );

      final fallback = result.tree.nodes
          .where((node) => node.state['semanticFallback'] == true)
          .toList();
      expect(fallback.map((node) => node.label), ['hello']);
      expect(fallback.single.bounds, CellRect.fromLTWH(1, 1, 5, 1));
      expect(result.audit.uncoveredCellCount, 5);
    });

    test('bars, braille plots and sextants are not text', () {
      final buffer = CellBuffer(const CellSize(8, 3))
        ..writeText(const CellOffset(0, 0), '▁▂▃▅▇█░▒')
        ..writeText(const CellOffset(0, 1), '⣀⣤⣶⣿⡇⢸⠉⠒')
        ..writeText(const CellOffset(0, 2), '🬀🬁🬂🬃🬄🬅🬆🬇');

      final result = applySemanticTextFallback(
        tree: const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
          ),
        ),
        buffer: buffer,
      );

      expect(result.audit.hasUncoveredText, isFalse);
      expect(result.audit.fallbackNodeCount, 0);
    });
  });
}
