import '../foundation/geometry.dart';

/// Where a host has reserved space for one ANSI frame.
///
/// This is presentation state, not an app's requested height. The native host
/// must reserve the rows before painting, update [top] when the terminal
/// scrolls, and release the old region before resizing or handing off. Widgets
/// and frame buffers continue to use coordinates starting at (0, 0).
///
/// An inline target owns full-width rows, even when [top] is zero. It must
/// never use whole-screen clears or terminal scroll commands. Keeping that
/// ownership distinct from the offset prevents a top-anchored inline region
/// from accidentally taking over the screen.
final class AnsiRenderTarget {
  const AnsiRenderTarget.fullScreen() : top = 0, isInline = false;

  const AnsiRenderTarget.inline({required this.top})
    : assert(top >= 0),
      isInline = true;

  final int top;
  final bool isInline;

  /// Terminal coordinates to widget coordinates. Do not clamp: pointer
  /// capture needs to receive a drag/release that has left the viewport.
  CellOffset toLocal(CellOffset position) =>
      CellOffset(position.col, position.row - top);

  CellOffset toTerminal(CellOffset position) =>
      CellOffset(position.col, position.row + top);

  /// Clears exactly the current frame's rows, leaving surrounding shell
  /// output intact. The host owns autowrap and must disable it while painting.
  String clearSequence(CellSize size) {
    if (!isInline) return '\x1B[2J\x1B[H';
    if (size.isEmpty) return '';
    final bytes = StringBuffer('\x1B[0m');
    for (var row = 0; row < size.rows; row++) {
      bytes.write('\x1B[${top + row + 1};1H\x1B[2K');
    }
    return bytes.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is AnsiRenderTarget &&
      top == other.top &&
      isInline == other.isInline;

  @override
  int get hashCode => Object.hash(top, isInline);
}
