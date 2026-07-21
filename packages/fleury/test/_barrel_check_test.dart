import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
void main() {
  test('public barrel exposes the binding surface', () {
    final KeySequence seq = KeySequence.ctrl.char('+');
    final b = KeyBinding(KeyCode.enter, onTrigger: () {});
    final PendingKeySequence p = KeySequence.ctrl;
    expect(seq.hintLabel, 'Ctrl++');
    expect(b.displayLabel, 'Enter');
    expect(p, isNotNull);
    // The '+' round-trip:
    print('roundtrip Ctrl++ : ${KeySequence.tryParse(seq.hintLabel)} == $seq ? ${KeySequence.tryParse(seq.hintLabel) == seq}');
  });
}
