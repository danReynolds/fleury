import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

Future<void> fill(FleuryTester tester, String label, String value) async {
  await tester.invokeSemanticAction(
    SemanticAction.setValue,
    label: label,
    payload: value,
  );
}

void main() {
  for (final multiline in [false, true]) {
    testWidgets(
      'editing callbacks belong to the originating ${multiline ? 'area' : 'input'}',
      (t) async {
        final controller = TextEditingController();
        final left = <String>[];
        final right = <String>[];
        var observations = 0;
        controller.addListener(() => observations++);
        Widget field(String label, List<String> events) => multiline
            ? TextArea(
                controller: controller,
                semanticLabel: label,
                onChanged: events.add,
              )
            : TextInput(
                controller: controller,
                semanticLabel: label,
                onChanged: events.add,
              );
        t.pumpWidget(
          Column(children: [field('Left', left), field('Right', right)]),
        );
        controller.text = 'model';
        controller.insert(' update');
        t.pump();
        expect(observations, greaterThan(0));
        expect(left, isEmpty);
        expect(right, isEmpty);
        await fill(t, 'Left', 'edit');
        expect(left, ['edit']);
        expect(right, isEmpty);
        expect(t.semantics().single(label: 'Right').value, 'edit');
        await fill(t, 'Right', 'other');
        expect(left, ['edit']);
        expect(right, ['other']);
      },
    );

    testWidgets(
      'callback writeback does not echo for ${multiline ? 'area' : 'input'}',
      (t) async {
        final controller = TextEditingController();
        final events = <String>[];
        void changed(String value) {
          events.add(value);
          controller.text = value.toUpperCase();
        }

        t.pumpWidget(
          multiline
              ? TextArea(
                  controller: controller,
                  semanticLabel: 'Draft',
                  onChanged: changed,
                )
              : TextInput(
                  controller: controller,
                  semanticLabel: 'Draft',
                  onChanged: changed,
                ),
        );
        await fill(t, 'Draft', 'hello');
        expect(events, ['hello']);
        expect(t.semantics().single(label: 'Draft').value, 'HELLO');
      },
    );
  }

  testWidgets(
    'initial list cursor reveals once and remains live across rebuilds',
    (t) {
      final controller = ListController(initialIndex: 24);
      final choices = <int>[];
      Widget list() => SizedBox(
        height: 4,
        child: ListView.builder(
          controller: controller,
          itemCount: 100,
          onSelect: choices.add,
          itemBuilder: (_, i, highlighted) => Text('Row $i'),
        ),
      );
      t.pumpWidget(list());
      expect(controller.currentIndex, 24);
      expect(t.renderToString(), contains('Row 24'));
      controller.currentIndex = 75;
      t.pumpWidget(list());
      expect(controller.currentIndex, 75);
      expect(t.renderToString(), contains('Row 75'));
      expect(choices, isEmpty);
    },
  );

  testWidgets('explicit null cursor survives empty data and later rows', (t) {
    final controller = ListController(initialIndex: null);
    Widget list(int count) => ListView.builder(
      controller: controller,
      itemCount: count,
      itemBuilder: (_, i, highlighted) => Text('$i'),
    );
    t.pumpWidget(list(0));
    t.pumpWidget(list(10));
    expect(controller.currentIndex, isNull);
    controller.currentIndex = 4;
    t.pumpWidget(list(2));
    expect(controller.currentIndex, 1);
  });

  testWidgets(
    'list controller rejects a second owner and supports reattachment',
    (t) {
      final controller = ListController(initialIndex: 2);
      Widget view(int count) => ListView.builder(
        controller: controller,
        itemCount: count,
        itemBuilder: (_, i, highlighted) => Text('$i'),
      );
      t.pumpWidget(view(4));
      final second = FleuryTester();
      addTearDown(second.dispose);
      expect(() => second.pumpWidget(view(100)), throwsStateError);
      expect(controller.itemCount, 4);
      t.pumpWidget(const Text('unmounted'));
      t.pumpWidget(view(10));
      expect(controller.itemCount, 10);
      expect(controller.currentIndex, 2);
    },
  );

  testWidgets(
    'scroll controller rejects a second owner and supports reattachment',
    (t) {
      final controller = ScrollController(initialOffset: 2);
      Widget view() => SizedBox(
        height: 3,
        child: ScrollView(
          controller: controller,
          child: Text(List.generate(20, (i) => 'Line $i').join('\n')),
        ),
      );
      t.pumpWidget(view());
      expect(controller.offset, 2);
      final second = FleuryTester();
      addTearDown(second.dispose);
      expect(() => second.pumpWidget(view()), throwsStateError);
      t.pumpWidget(const Text('unmounted'));
      t.pumpWidget(view());
      expect(controller.offset, 2);
    },
  );

  testWidgets(
    'a globally keyed list keeps its cursor and viewport when moved',
    (t) {
      final key = GlobalKey();
      final controller = ListController(initialIndex: 8);
      Widget app(bool right) {
        final list = ListView.builder(
          key: key,
          controller: controller,
          itemCount: 30,
          itemBuilder: (_, i, highlighted) => Text('Row $i'),
        );
        return SizedBox(
          height: 4,
          child: Row(
            children: [
              Expanded(child: right ? const Text('Left') : list),
              Expanded(child: right ? list : const Text('Right')),
            ],
          ),
        );
      }

      t.pumpWidget(app(false));
      controller.jumpToIndex(20);
      t.pump();
      final range = controller.visibleRange;
      t.pumpWidget(app(true));
      expect(controller.currentIndex, 8);
      expect(controller.visibleRange, range);
      controller.currentIndex = 24;
      t.pump();
      expect(t.renderToString(), contains('Row 24'));
    },
  );
}
