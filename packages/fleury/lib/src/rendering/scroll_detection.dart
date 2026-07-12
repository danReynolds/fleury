/// Shared scroll-up detection for diffing presenters.
///
/// The ANSI renderer uses this to emit an `SU` scroll instead of repainting
/// the moved region; the DOM presenter uses the same detection to MOVE
/// retained row elements instead of rebuilding every row's spans. Keeping one
/// implementation keeps the two targets' scroll behavior in lockstep.
library;

import 'cell.dart';
import 'cell_buffer.dart';

/// Whole-screen diff stats used as the scroll-detection baseline.
({int dirtyCells, bool hasOverlayCells}) screenDiffStats(
  CellBuffer previous,
  CellBuffer next,
) {
  final size = previous.size;
  var dirty = 0;
  var hasOverlayCells = false;
  for (var row = 0; row < size.rows; row++) {
    for (var col = 0; col < size.cols; col++) {
      final previousCell = previous.atColRow(col, row);
      final nextCell = next.atColRow(col, row);
      if (previousCell != nextCell) dirty++;
      hasOverlayCells =
          hasOverlayCells ||
          previousCell.role == CellRole.overlay ||
          nextCell.role == CellRole.overlay;
    }
  }
  return (dirtyCells: dirty, hasOverlayCells: hasOverlayCells);
}

/// Returns the upward shift (in rows) that minimizes residual dirty cells,
/// or null when no shift beats a plain diff.
///
/// A shift of `n` means `next.row(r) == previous.row(r + n)` for most rows:
/// the presenter can move/scroll the retained region up by `n` and only
/// repaint the residual rows. Overlay (inline-image) cells disable
/// detection — their painted pixels are not row-relocatable.
int? detectBeneficialScrollUp(
  CellBuffer previous,
  CellBuffer next,
  ({int dirtyCells, bool hasOverlayCells}) stats,
) {
  final size = previous.size;
  if (size != next.size || size.rows < 2) return null;

  if (stats.hasOverlayCells) return null;
  final normalDirty = stats.dirtyCells;
  var bestShift = 0;
  var bestDirty = normalDirty;
  for (var shift = 1; shift < size.rows; shift++) {
    if (!scrollShiftPassesEntryGuards(previous, next, shift)) continue;
    var shiftedDirty = 0;
    var abandoned = false;
    for (var row = 1; row < size.rows - shift; row++) {
      for (var col = 0; col < size.cols; col++) {
        final oldCell = previous.atColRow(col, row + shift);
        final newCell = next.atColRow(col, row);
        if (oldCell != newCell) {
          shiftedDirty++;
          if (shiftedDirty >= bestDirty) {
            abandoned = true;
            break;
          }
        }
      }
      if (abandoned) break;
    }
    if (abandoned) continue;
    for (var row = size.rows - shift; row < size.rows; row++) {
      for (var col = 0; col < size.cols; col++) {
        if (next.atColRow(col, row) != const Cell.empty()) {
          shiftedDirty++;
          if (shiftedDirty >= bestDirty) {
            abandoned = true;
            break;
          }
        }
      }
      if (abandoned) break;
    }
    if (!abandoned && shiftedDirty < bestDirty) {
      bestShift = shift;
      bestDirty = shiftedDirty;
    }
  }
  return bestShift == 0 ? null : bestShift;
}

/// Whether [shift] passes [detectBeneficialScrollUp]'s entry guards: the
/// retained `previous` row is non-empty and equals `next`'s first row.
///
/// This is the detector's OWN per-shift admission test — a shift failing it
/// can never be selected. Callers that prefilter (the remote plan builder
/// skips the detector's whole-screen stats scan when no shift passes) share
/// this predicate so "no candidate ⟹ detector returns null" holds
/// structurally: a future guard change lands in both places by construction.
bool scrollShiftPassesEntryGuards(
  CellBuffer previous,
  CellBuffer next,
  int shift,
) =>
    rowHasNonEmptyCells(previous, shift) && rowsEqual(previous, shift, next, 0);

/// Whether row [previousRow] of [previous] equals row [nextRow] of [next].
bool rowsEqual(
  CellBuffer previous,
  int previousRow,
  CellBuffer next,
  int nextRow,
) {
  final size = previous.size;
  for (var col = 0; col < size.cols; col++) {
    if (previous.atColRow(col, previousRow) != next.atColRow(col, nextRow)) {
      return false;
    }
  }
  return true;
}

/// Whether [row] contains any non-empty cell.
bool rowHasNonEmptyCells(CellBuffer buffer, int row) {
  final size = buffer.size;
  for (var col = 0; col < size.cols; col++) {
    if (buffer.atColRow(col, row) != const Cell.empty()) return true;
  }
  return false;
}
