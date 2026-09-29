import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  test('view-change listeners can detach after controller disposal', () {
    final list = ListController();
    void listener() {}
    final changes = list.viewChanges;
    changes.addListener(listener);
    list.dispose();
    expect(identical(list.viewChanges, changes), isTrue);
    list.viewChanges.removeListener(listener);
    expect(() => changes.addListener(listener), throwsStateError);
  });

  test('a view listener can dispose its controller during notification', () {
    final list = ListController();
    var deliveredAfterDispose = false;
    list.viewChanges.addListener(list.dispose);
    list.addListener(() => deliveredAfterDispose = true);
    expect(list.notify, returnsNormally);
    expect(deliveredAfterDispose, isFalse);
    expect(list.notify, throwsStateError);
  });

  testWidgets(
    'view changes exclude completed metrics but retain explicit refresh',
    (tester) {
      final list = ListController();
      addTearDown(list.dispose);
      var viewChanges = 0;
      var allChanges = 0;
      list.viewChanges.addListener(() => viewChanges++);
      list.addListener(() => allChanges++);
      tester.pumpWidget(
        SizedBox(
          height: 4,
          child: ListView.builder(
            controller: list,
            itemCount: 100,
            itemBuilder: (_, index, _) => Text('row $index'),
          ),
        ),
      );
      tester.pump();
      tester.pump();
      viewChanges = 0;
      allChanges = 0;
      list.jumpToIndex(20);
      expect(viewChanges, 1);
      tester.pump();
      tester.pump();
      expect(viewChanges, 1);
      expect(allChanges, greaterThan(viewChanges));
      expect(list.visibleRange!.first, 20);
      list.notify();
      expect(viewChanges, 2);
      list.currentIndex = 30;
      expect(viewChanges, 3);
    },
  );

  testWidgets(
    'nested explicit refresh during metric delivery stays a view change',
    (tester) {
      final list = ListController();
      addTearDown(list.dispose);
      var views = 0;
      var refresh = false;
      list.viewChanges.addListener(() => views++);
      list.addListener(() {
        if (refresh) {
          refresh = false;
          list.notify();
        }
      });
      tester.pumpWidget(
        SizedBox(
          height: 3,
          child: ListView.builder(
            controller: list,
            itemCount: 30,
            itemBuilder: (_, i, _) => Text('$i'),
          ),
        ),
      );
      tester.pump();
      tester.pump();
      list.jumpToIndex(10);
      views = 0;
      refresh = true;
      tester.pump();
      tester.pump();
      expect(views, 1);
    },
  );
}
