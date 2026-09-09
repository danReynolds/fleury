import '../foundation/mouse_cursor.dart';

// https://sw.kovidgoyal.net/kitty/pointer-shapes/
// A DA1 sentinel bounds the exchange using the existing query runner/parser.
const pointerShapesQuery =
    '\x1b]22;?default,pointer,text,ew-resize,ns-resize\x1b\\\x1b[c';
const pushPointerShape = '\x1b]22;>default\x1b\\';
const popPointerShape = '\x1b]22;<\x1b\\';

/// Accept only the exact affirmative response for our fixed shape set.
bool parsePointerShapesReply(List<int> bytes) => RegExp(
  r'\x1b\]22;1,1,1,1,1(?:\x1b\\|\x07)',
).hasMatch(String.fromCharCodes(bytes));

/// Only enum-owned names reach the terminal; no application text is encoded.
String pointerShapeSequence(MouseCursor cursor) {
  final name = switch (cursor) {
    MouseCursor.basic => 'default',
    MouseCursor.pointer => 'pointer',
    MouseCursor.text => 'text',
    MouseCursor.resizeLeftRight => 'ew-resize',
    MouseCursor.resizeUpDown => 'ns-resize',
  };
  return '\x1b]22;$name\x1b\\';
}
