import 'package:fleury_peer_nocterm_sb1_counter/counter_app.dart';
import 'package:nocterm/nocterm.dart';
import 'package:nocterm/nocterm_test.dart';
import 'package:test/test.dart' hide isEmpty;

void main() {
  test('space increments the counter through Nocterm tester input', () async {
    await testNocterm('SB.1 Nocterm counter fixture', (tester) async {
      await tester.pumpComponent(const Sb1Counter());
      expect(tester.terminalState, containsText('Count: 0'));

      await tester.sendKey(LogicalKey.space);
      expect(tester.terminalState, containsText('Count: 1'));
    });
  });
}
