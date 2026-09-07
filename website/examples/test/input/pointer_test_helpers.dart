import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';

void pointer(
  FleuryTester tester,
  MouseEventKind kind,
  int col,
  int row, {
  MouseButton button = MouseButton.left,
}) {
  tester.sendMouse(MouseEvent(kind: kind, button: button, col: col, row: row));
  tester.pump();
}
