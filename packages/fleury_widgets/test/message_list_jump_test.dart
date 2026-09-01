import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _messages = [
  MessageEntry(id: 'm1', role: MessageRole.user, text: 'one'),
  MessageEntry(id: 'm2', role: MessageRole.assistant, text: 'two'),
  MessageEntry(id: 'm3', role: MessageRole.assistant, text: 'three'),
];

void main() {
  testWidgets('jumpToIndex leaves follow to the coupling — no false→true '
      'flap on a jump to the tail', (tester) {
    // Follow is owned by the selection coupling: a non-tail index disengages
    // it, the tail index engages it. An explicit `followTail = false` before
    // the jump was dead for a non-tail index and, for the tail, a flap —
    // listeners saw false, then true — the same dead pattern 8.e removed.
    final controller = MessageListController(
      selectedIndex: 0,
      followTail: true,
    );
    tester.pumpWidget(MessageList(controller: controller, messages: _messages));
    tester.render(size: const CellSize(40, 6));

    final seen = <bool>[];
    controller.addListener(() => seen.add(controller.followTail));

    controller.jumpToIndex(2);
    expect(controller.followTail, isTrue, reason: 'the tail engages follow');
    expect(seen, isNot(contains(false)), reason: 'no intermediate false');

    controller.jumpToIndex(0);
    expect(
      controller.followTail,
      isFalse,
      reason: 'a non-tail index disengages',
    );
  });
}
