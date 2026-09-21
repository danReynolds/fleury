import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _ObservedController extends ListController {
  final notifications = <({int first, int last})?>[];
  void Function()? onNotification;
  bool beforeSuper = true;
  bool deliver = true;

  @override
  void notifyListeners() {
    notifications.add(visibleRange);
    if (!deliver) return;
    if (beforeSuper) onNotification?.call();
    super.notifyListeners();
    if (!beforeSuper) onNotification?.call();
  }
}

class _RedirectingController extends ListController {
  bool redirected = false;

  @override
  void notifyListeners() {
    if (visibleRange?.first == 20 && !redirected) {
      redirected = true;
      jumpToIndex(60);
      return; // The nested command already notified listeners.
    }
    super.notifyListeners();
  }
}

void main() {
  testWidgets(
    'reported viewport metrics do not schedule a second list build',
    (tester) {
      final controller = ListController();
      addTearDown(controller.dispose);
      var builds = 0;
      final metrics = <({int first, int last})?>[];
      controller.addListener(() => metrics.add(controller.visibleRange));
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (context, index, highlighted) {
            builds++;
            return Text('row $index');
          },
        ),
      );
      controller.jumpToIndex(40);
      tester.pump();
      expect(controller.visibleRange, (first: 40, last: 43));
      expect(metrics.last, (first: 40, last: 43));
      expect(tester.owner.hasScheduledBuilds, isFalse);
      final before = builds;
      tester.pump();
      expect(builds, before);
      expect(tester.renderToString().trim(), 'row 40\nrow 41\nrow 42\nrow 43');
    },
    viewportSize: const CellSize(16, 4),
  );

  testWidgets(
    'subclass content changes during metrics still rebuild the rows',
    (tester) {
      final controller = _ObservedController();
      addTearDown(controller.dispose);
      var label = 'before';
      controller.onNotification = () {
        if (controller.visibleRange?.first == 40) label = 'after';
      };
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, index, highlighted) => Text('$label $index'),
        ),
      );
      controller.jumpToIndex(40);
      tester.pump();
      expect(label, 'after');
      expect(tester.owner.hasScheduledBuilds, isTrue);
      tester.pump();
      expect(tester.renderToString(), contains('after 40'));
      expect(tester.owner.hasScheduledBuilds, isFalse);
    },
    viewportSize: const CellSize(16, 4),
  );

  testWidgets(
    'a redirecting override can suppress the outer metrics notification',
    (tester) {
      final controller = _RedirectingController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, index, highlighted) => Text('row $index'),
        ),
      );
      controller.jumpToIndex(20);
      tester.pump();
      expect(controller.redirected, isTrue);
      expect(tester.owner.hasScheduledBuilds, isTrue);
      tester.pump();
      expect(controller.visibleRange, (first: 60, last: 63));
      tester.pump();
      expect(tester.renderToString(), contains('row 60'));
      expect(tester.owner.hasScheduledBuilds, isFalse);
    },
    viewportSize: const CellSize(16, 4),
  );

  testWidgets(
    'controller subclasses observe the completed viewport',
    (tester) {
      final controller = _ObservedController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, index, highlighted) => Text('row $index'),
        ),
      );
      controller.notifications.clear();
      controller.jumpToIndex(40);
      tester.pump();
      expect(controller.notifications.last, (first: 40, last: 43));
      // A subclass can change visible data in its override; keep its refresh.
      expect(tester.owner.hasScheduledBuilds, isTrue);
      tester.pump();
      expect(tester.owner.hasScheduledBuilds, isFalse);
    },
    viewportSize: const CellSize(16, 4),
  );

  for (final beforeSuper in [true, false]) {
    testWidgets(
      'commands from a metrics override still render: beforeSuper=$beforeSuper',
      (tester) {
        final controller = _ObservedController()..beforeSuper = beforeSuper;
        addTearDown(controller.dispose);
        var redirected = false;
        controller.onNotification = () {
          if (controller.visibleRange?.first == 20 && !redirected) {
            redirected = true;
            controller.jumpToIndex(60);
          }
        };
        tester.pumpWidget(
          ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, index, highlighted) => Text('row $index'),
          ),
        );
        controller.jumpToIndex(20);
        tester.pump();
        expect(redirected, isTrue);
        tester.pump();
        expect(controller.visibleRange, (first: 60, last: 63));
        expect(tester.renderToString(), contains('row 60'));
        tester.pump();
        expect(tester.owner.hasScheduledBuilds, isFalse);
      },
      viewportSize: const CellSize(16, 4),
    );
  }

  testWidgets(
    'a subclass suppressing metrics does not suppress a later refresh',
    (tester) {
      final controller = _ObservedController();
      addTearDown(controller.dispose);
      var label = 'before';
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 100,
          itemBuilder: (_, index, highlighted) => Text('$label $index'),
        ),
      );
      controller.jumpToIndex(40);
      controller.deliver = false;
      tester.pump();
      expect(controller.visibleRange, (first: 40, last: 43));
      label = 'after';
      controller.deliver = true;
      controller.notify();
      tester.pump();
      expect(tester.renderToString(), contains('after 40'));
    },
    viewportSize: const CellSize(16, 4),
  );

  for (final beforeMount in [true, false]) {
    testWidgets(
      'commands from a metrics listener still render: early=$beforeMount',
      (tester) {
        final controller = ListController();
        addTearDown(controller.dispose);
        var redirected = false;
        void react() {
          if (controller.visibleRange?.first == 20 && !redirected) {
            redirected = true;
            controller.jumpToIndex(60);
          }
        }

        if (beforeMount) controller.addListener(react);
        tester.pumpWidget(
          ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, index, highlighted) => Text('row $index'),
          ),
        );
        if (!beforeMount) controller.addListener(react);
        controller.jumpToIndex(20);
        tester.pump();
        expect(redirected, isTrue);
        tester.pump();
        expect(controller.visibleRange, (first: 60, last: 63));
        expect(tester.renderToString(), contains('row 60'));
        expect(tester.owner.hasScheduledBuilds, isFalse);
      },
      viewportSize: const CellSize(16, 4),
    );
  }

  testWidgets(
    'explicit notifications still refresh visible content',
    (tester) {
      final controller = ListController();
      addTearDown(controller.dispose);
      var label = 'before';
      tester.pumpWidget(
        ListView.builder(
          controller: controller,
          itemCount: 10,
          itemBuilder: (_, index, highlighted) => Text('$label $index'),
        ),
      );
      label = 'after';
      controller.notify();
      tester.pump();
      expect(tester.renderToString(), contains('after 0'));
    },
    viewportSize: const CellSize(16, 4),
  );

  for (final beforeMount in [true, false]) {
    testWidgets(
      'explicit refresh during metric delivery still renders: early=$beforeMount',
      (tester) {
        final controller = ListController();
        addTearDown(controller.dispose);
        var label = 'before';
        void refresh() {
          if (controller.visibleRange?.first == 40 && label == 'before') {
            label = 'after';
            controller.notify();
          }
        }

        if (beforeMount) controller.addListener(refresh);
        tester.pumpWidget(
          ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, index, highlighted) => Text('$label $index'),
          ),
        );
        if (!beforeMount) controller.addListener(refresh);
        controller.jumpToIndex(40);
        tester.pump();
        tester.pump();
        expect(tester.renderToString(), contains('after 40'));
        expect(tester.owner.hasScheduledBuilds, isFalse);
      },
      viewportSize: const CellSize(16, 4),
    );
  }
}
