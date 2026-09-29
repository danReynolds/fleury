import '../foundation/geometry.dart';
import '../rendering/ansi_render_target.dart';

/// Geometry and escape generation for one full-width main-buffer allocation.
/// The driver serializes queries and lifecycle transitions around this state.
final class InlineTerminalRegion {
  InlineTerminalRegion(int rows) : _requestedRows = _validateRows(rows);

  static int _validateRows(int rows) {
    if (rows < 1) throw ArgumentError.value(rows, 'rows', 'must be positive');
    return rows;
  }

  static void _validateCursor(CellSize terminal, CellOffset cursor) {
    if (cursor.col < 0 ||
        cursor.col >= terminal.cols ||
        cursor.row < 0 ||
        cursor.row >= terminal.rows) {
      throw StateError('Inline cursor must be inside the terminal viewport.');
    }
  }

  int _requestedRows;
  int get requestedRows => _requestedRows;
  void requestRows(int rows) => _requestedRows = _validateRows(rows);
  CellSize _terminalSize = CellSize.zero;
  CellSize get terminalSize => _terminalSize;
  CellSize _size = CellSize.zero;
  CellSize get size => _size;
  int _top = 0;
  CellOffset _cursor = CellOffset.zero;
  bool _allocated = false;
  bool get isAllocated => _allocated;
  AnsiRenderTarget get target => AnsiRenderTarget.inline(top: _top);

  /// The presenter reports the final hardware cursor, including an IME caret.
  /// This lets a cursor report after resize recover the region's new origin.
  void recordCursor(CellOffset local) => _cursor = local;

  CellOffset get terminalCursor => target.toTerminal(_cursor);

  String acquire(CellSize terminal, CellOffset cursor) {
    if (terminal.isEmpty) {
      throw StateError('Inline viewport needs a nonempty terminal.');
    }
    _validateCursor(terminal, cursor);
    if (_allocated) throw StateError('Inline region is already allocated.');
    final bytes = StringBuffer();
    var start = cursor.row;
    // Preserve an existing partial line (e.g. output without a final newline).
    if (cursor.col > 0) {
      bytes.write('\r\n');
      start = (start + 1).clamp(0, terminal.rows - 1);
    }
    bytes.write(_reserve(terminal, start));
    return bytes.toString();
  }

  String resize(CellSize terminal, CellOffset cursor, {int? rows}) {
    if (terminal.isEmpty) {
      throw StateError('Inline viewport needs a nonempty terminal.');
    }
    _validateCursor(terminal, cursor);
    if (rows != null) _requestedRows = _validateRows(rows);
    if (!_allocated) return acquire(terminal, cursor);
    // Preserve the cursor's relative row when the terminal moved its buffer
    // during resize. Full-width rows are rendered with autowrap disabled.
    final top = terminal == _terminalSize
        ? _top
        : (cursor.row - _cursor.row).clamp(0, terminal.rows - 1);
    final visibleRows = _size.rows.clamp(0, terminal.rows - top);
    final bytes = StringBuffer(
      AnsiRenderTarget.inline(
        top: top,
      ).clearSequence(CellSize(terminal.cols, visibleRows)),
    );
    bytes.write('\x1B[${top + 1};1H');
    bytes.write(_reserve(terminal, top));
    return bytes.toString();
  }

  String _reserve(CellSize terminal, int start) {
    final height = _requestedRows.clamp(1, terminal.rows);
    _terminalSize = terminal;
    _size = CellSize(terminal.cols, height);
    _top = start.clamp(0, terminal.rows - height);
    _cursor = CellOffset(0, height - 1);
    _allocated = true;
    // Explicit newlines allocate rows and move old shell output into normal
    // scrollback as needed. No ED, SU, or alternate-screen operations.
    return '\r${'\n' * (height - 1)}';
  }

  /// Release once, parking at the start for the shell/next command output.
  /// A fresh [cursor] report can locate the surviving rows after a physical
  /// resize without allocating or repainting another region. Without that
  /// evidence, a newline is safer than erasing unknown shell rows.
  String release(CellSize terminal, {CellOffset? cursor}) {
    if (!_allocated) return '';
    if (cursor != null) _validateCursor(terminal, cursor);
    _allocated = false;
    if (terminal == _terminalSize) {
      return '${target.clearSequence(_size)}\x1B[${_top + 1};1H';
    }
    if (cursor == null) return '\r\n';
    final top = (cursor.row - _cursor.row).clamp(0, terminal.rows - 1);
    final visibleRows = _size.rows.clamp(0, terminal.rows - top);
    final recovered = AnsiRenderTarget.inline(top: top);
    return '${recovered.clearSequence(CellSize(terminal.cols, visibleRows))}'
        '\x1B[${top + 1};1H';
  }
}
