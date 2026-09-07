import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';
import '../../lib/input/contact_fields.dart';
import 'pointer_test_helpers.dart';

void main() {
  testWidgets('click places the caret; Tab reaches the next field', (tester) {
    tester.pumpWidget(const FleuryApp(title: 'Contact', home: ContactFields()));
    pointer(tester, MouseEventKind.down, 3, 1);
    pointer(tester, MouseEventKind.up, 3, 1);
    tester.type('!');
    expect(tester.field('Name'), hasValue('Ada! Lovelace'));
    tester.press(KeySequence.tab);
    expect(tester.field('Note'), isFocused);
  });
}
