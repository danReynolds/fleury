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
  testWidgets(
    'jumping pauses following without changing its policy or selection',
    (tester) {
      final controller = MessageListController(
        selectedIndex: 2,
        followTail: true,
      );
      tester.pumpWidget(
        MessageList(controller: controller, messages: _messages),
      );
      expect(controller.isFollowing, isTrue);
      controller.jumpToIndex(0);
      tester.pump();
      expect(controller.followTail, isTrue);
      expect(controller.isFollowing, isFalse);
      expect(controller.selectedIndex, 2);
      controller.scrollToBottom();
      tester.pump();
      expect(controller.isFollowing, isTrue);
      expect(controller.selectedIndex, 2);
    },
    viewportSize: const CellSize(40, 1),
  );
}
