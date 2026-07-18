import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../runtime/tui_frame_loop.dart';
import 'semantics.dart';

/// Result of applying the web semantic text fallback to a frame.
final class SemanticCoverageResult {
  const SemanticCoverageResult({required this.tree, required this.audit});

  final SemanticTree tree;
  final SemanticCoverageAudit audit;
}

/// Debug/audit data for semantic coverage of a visual frame.
final class SemanticCoverageAudit {
  const SemanticCoverageAudit({
    required this.uncoveredCellCount,
    required this.fallbackNodeCount,
  });

  static const empty = SemanticCoverageAudit(
    uncoveredCellCount: 0,
    fallbackNodeCount: 0,
  );

  final int uncoveredCellCount;
  final int fallbackNodeCount;

  bool get hasUncoveredText => uncoveredCellCount > 0;
}

/// Adds low-priority text fallback nodes for visible text not covered by
/// geometry-bearing semantic nodes.
///
/// The visual grid is `aria-hidden`, so visible painted text without semantics
/// would otherwise be unreachable to assistive technology. This bridge keeps
/// rich widget semantics authoritative where bounds exist and appends plain
/// text fallback nodes only for uncovered non-whitespace buffer text.
SemanticCoverageResult applySemanticTextFallback({
  required SemanticTree tree,
  required CellBuffer buffer,
  TuiDirtyRows? dirtyRows,
  SemanticCoverageAudit? previousAudit,
}) {
  if (buffer.size.isEmpty) {
    return SemanticCoverageResult(
      tree: tree,
      audit: SemanticCoverageAudit.empty,
    );
  }

  final scanRows = _semanticCoverageRows(buffer.size, dirtyRows, previousAudit);
  if (_scanRowsAreFullyCoveredByReadableSemantics(
    tree,
    buffer.size,
    scanRows,
  )) {
    return SemanticCoverageResult(
      tree: tree,
      audit: SemanticCoverageAudit.empty,
    );
  }

  final coverage = _coveredCells(tree, buffer.size, scanRows);
  if (coverage.isFullyCovered) {
    return SemanticCoverageResult(
      tree: tree,
      audit: SemanticCoverageAudit.empty,
    );
  }

  final fallbackNodes = <SemanticNode>[];
  var uncoveredCellCount = 0;

  for (final range in scanRows.ranges) {
    for (var row = range.startRow; row < range.endRow; row++) {
      var col = 0;
      while (col < buffer.size.cols) {
        final candidateWidth = _fallbackCandidateWidth(
          buffer,
          coverage.covered,
          col,
          row,
        );
        if (candidateWidth == 0) {
          col += 1;
          continue;
        }

        final startCol = col;
        col += candidateWidth;
        while (col < buffer.size.cols) {
          final width = _fallbackCandidateWidth(
            buffer,
            coverage.covered,
            col,
            row,
          );
          if (width == 0) break;
          col += width;
        }

        final rect = CellRect.fromLTWH(startCol, row, col - startCol, 1);
        final text = buffer.textInRange(rect).trimRight();
        if (text.isEmpty) continue;
        uncoveredCellCount += rect.size.cols;
        fallbackNodes.add(
          SemanticNode(
            id: SemanticNodeId('__fleury_text_fallback_${row}_$startCol'),
            role: SemanticRole.text,
            label: text,
            value: text,
            bounds: rect,
            state: const SemanticState({'semanticFallback': true}),
          ),
        );
      }
    }
  }

  if (fallbackNodes.isEmpty) {
    return SemanticCoverageResult(
      tree: tree,
      audit: const SemanticCoverageAudit(
        uncoveredCellCount: 0,
        fallbackNodeCount: 0,
      ),
    );
  }

  return SemanticCoverageResult(
    tree: SemanticTree(
      root: tree.root.copyWith(
        children: [...tree.root.children, ...fallbackNodes],
      ),
    ),
    audit: SemanticCoverageAudit(
      uncoveredCellCount: uncoveredCellCount,
      fallbackNodeCount: fallbackNodes.length,
    ),
  );
}

TuiDirtyRows _semanticCoverageRows(
  CellSize size,
  TuiDirtyRows? dirtyRows,
  SemanticCoverageAudit? previousAudit,
) {
  if (dirtyRows != null &&
      !dirtyRows.isEmpty &&
      !dirtyRows.isFull &&
      previousAudit != null &&
      !previousAudit.hasUncoveredText) {
    return dirtyRows;
  }
  return TuiDirtyRows.full(size.rows);
}

bool _scanRowsAreFullyCoveredByReadableSemantics(
  SemanticTree tree,
  CellSize size,
  TuiDirtyRows scanRows,
) {
  if (scanRows.isEmpty || size.cols <= 0) return true;
  final nodes = tree.nodes;
  for (final range in scanRows.ranges) {
    for (var row = range.startRow; row < range.endRow; row++) {
      if (!_rowIsFullyCoveredByReadableSemantics(nodes, size, row)) {
        return false;
      }
    }
  }
  return true;
}

bool _rowIsFullyCoveredByReadableSemantics(
  Iterable<SemanticNode> nodes,
  CellSize size,
  int row,
) {
  var coveredUntil = 0;
  while (coveredUntil < size.cols) {
    var nextCoveredUntil = coveredUntil;
    for (final node in nodes) {
      final bounds = node.bounds;
      if (bounds == null) continue;
      if (!_providesReadableCoverage(node)) continue;
      if (row < bounds.top || row >= bounds.bottom) continue;
      final left = bounds.left.clamp(0, size.cols);
      final right = bounds.right.clamp(0, size.cols);
      if (left <= coveredUntil && right > nextCoveredUntil) {
        nextCoveredUntil = right;
      }
    }
    if (nextCoveredUntil == coveredUntil) return false;
    coveredUntil = nextCoveredUntil;
  }
  return true;
}

_CoverageMap _coveredCells(
  SemanticTree tree,
  CellSize size,
  TuiDirtyRows scanRows,
) {
  final covered = List<bool>.filled(size.cols * size.rows, false);
  var coveredCellCount = 0;
  for (final node in tree.nodes) {
    final bounds = node.bounds;
    if (bounds == null) continue;
    // An exclusion-shadow node (an excluding ExcludeSemantics) marks its region
    // covered WITHOUT exposing text: the subtree was intentionally hidden from
    // AT/agents, so its painted cells must not be re-minted as fallback nodes.
    if (!_isSemanticExclusion(node) && !_providesReadableCoverage(node)) {
      continue;
    }
    final left = bounds.left.clamp(0, size.cols);
    final right = bounds.right.clamp(0, size.cols);
    final top = bounds.top.clamp(0, size.rows);
    final bottom = bounds.bottom.clamp(0, size.rows);
    for (var row = top; row < bottom; row++) {
      if (!scanRows.isFull && !_containsRow(scanRows, row)) continue;
      for (var col = left; col < right; col++) {
        final index = row * size.cols + col;
        if (covered[index]) continue;
        covered[index] = true;
        coveredCellCount += 1;
      }
    }
  }
  return _CoverageMap(
    covered: covered,
    coveredCellCount: coveredCellCount,
    totalCellCount: size.cols * scanRows.dirtyRowCount,
  );
}

bool _containsRow(TuiDirtyRows rows, int row) {
  for (final range in rows.ranges) {
    if (range.contains(row)) return true;
  }
  return false;
}

final class _CoverageMap {
  const _CoverageMap({
    required this.covered,
    required this.coveredCellCount,
    required this.totalCellCount,
  });

  final List<bool> covered;
  final int coveredCellCount;
  final int totalCellCount;

  bool get isFullyCovered => coveredCellCount >= totalCellCount;
}

bool _isSemanticExclusion(SemanticNode node) =>
    node.state[semanticExcludedStateKey] == true;

bool _providesReadableCoverage(SemanticNode node) {
  return switch (node.role) {
    SemanticRole.app ||
    SemanticRole.screen ||
    SemanticRole.route ||
    SemanticRole.region ||
    SemanticRole.navigation ||
    SemanticRole.list ||
    SemanticRole.conversationNavigator ||
    SemanticRole.conversation ||
    SemanticRole.contextPanel ||
    SemanticRole.traceTimeline ||
    SemanticRole.patchReview ||
    SemanticRole.messageList ||
    SemanticRole.table ||
    SemanticRole.tableRow ||
    SemanticRole.fileMentionPicker ||
    SemanticRole.menu ||
    SemanticRole.commandPalette ||
    SemanticRole.dialog ||
    SemanticRole.form ||
    SemanticRole.taskGraph ||
    SemanticRole.tree ||
    SemanticRole.json ||
    SemanticRole.diff => false,
    _ => _hasReadableText(node) || node.actions.isNotEmpty,
  };
}

bool _hasReadableText(SemanticNode node) {
  final label = node.label;
  if (label != null && label.trim().isNotEmpty) return true;
  final value = node.value;
  if (value is String) return value.trim().isNotEmpty;
  return value != null;
}

int _fallbackCandidateWidth(
  CellBuffer buffer,
  List<bool> covered,
  int col,
  int row,
) {
  if (covered[row * buffer.size.cols + col]) return 0;
  final cell = buffer.atColRow(col, row);
  if (cell.role != CellRole.leading) return 0;
  final grapheme = cell.grapheme;
  if (grapheme == null || grapheme.trim().isEmpty) return 0;
  final nextCol = col + 1;
  if (nextCol < buffer.size.cols &&
      buffer.atColRow(nextCol, row).role == CellRole.continuation) {
    return 2;
  }
  return 1;
}
