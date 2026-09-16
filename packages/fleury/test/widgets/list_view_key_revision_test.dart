import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _Row extends StatefulWidget {
  const _Row(this.id);
  final String id;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final initialId = widget.id;

  @override
  Widget build(BuildContext context) => Text('${widget.id}:$initialId');
}

void main() {
  testWidgets('a failed key capture cannot publish its revision', (tester) {
    var items = ['a', 'b', 'c'];
    var revision = 0;
    final controller = ListController(initialIndex: 2);
    addTearDown(controller.dispose);
    Widget app() => SizedBox(
      width: 12,
      height: 3,
      child: ListView.builder(
        controller: controller,
        itemCount: items.length,
        itemKeyBuilder: (i) => items[i],
        itemKeyRevision: revision,
        itemBuilder: (_, i, _) => Text(items[i]),
      ),
    );
    tester.pumpWidget(app());
    revision++;
    items = ['x', 'x', 'c'];
    expect(() => tester.pumpWidget(app()), throwsStateError);
    items = ['c', 'b', 'a'];
    // Retry the same requested revision with valid data. The old snapshot
    // must not masquerade as that revision after the failed capture.
    tester.pumpWidget(app());
    expect(controller.currentIndex, 0);
    expect(tester.renderToString().trim(), 'c\nb\na');
  });

  for (final separated in [false, true]) {
    testWidgets(
      'revision reuses keys but updates row content: separated=$separated',
      (tester) {
        final controller = ListController();
        addTearDown(controller.dispose);
        var keyCalls = 0;
        var rowCalls = 0;
        var label = 'before';
        Widget app() {
          // A new closure on every parent rebuild deliberately tests the
          // revision contract independently of callback identity.
          Object keyAt(int i) {
            keyCalls++;
            return i;
          }

          Widget rowAt(BuildContext context, int i, bool highlighted) {
            rowCalls++;
            return Text('$label $i');
          }

          return SizedBox(
            width: 20,
            height: 3,
            child: separated
                ? ListView.separated(
                    controller: controller,
                    itemCount: 100000,
                    itemKeyBuilder: keyAt,
                    itemKeyRevision: 0,
                    itemBuilder: rowAt,
                    separatorBuilder: (_, _) => null,
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: 100000,
                    itemKeyBuilder: keyAt,
                    itemKeyRevision: 0,
                    itemBuilder: rowAt,
                  ),
          );
        }

        tester.pumpWidget(app());
        expect(keyCalls, 100000);
        keyCalls = 0;
        rowCalls = 0;
        label = 'after';
        tester.pumpWidget(app());
        expect(tester.renderToString(), contains('after 0'));
        expect(
          keyCalls,
          0,
          reason: 'unchanged identities must not scan the collection',
        );
        expect(
          rowCalls,
          inInclusiveRange(1, 12),
          reason: 'visible rows still rebuild',
        );
        controller.jumpToIndex(50000);
        tester.pump();
        expect(tester.renderToString(), contains('after 50000'));
        expect(keyCalls, 0, reason: 'scrolling uses the retained snapshot');
      },
    );
  }

  testWidgets('a revised key order preserves cursor, viewport, and row state', (
    tester,
  ) {
    var items = ['a', 'b', 'c', 'd', 'e', 'f'];
    var revision = 0;
    final controller = ListController(initialIndex: 2);
    addTearDown(controller.dispose);
    Widget app() => SizedBox(
      width: 12,
      height: 3,
      child: ListView.builder(
        controller: controller,
        itemCount: items.length,
        itemKeyBuilder: (i) => items[i],
        itemKeyRevision: revision,
        itemBuilder: (_, i, _) => _Row(items[i]),
      ),
    );
    tester.pumpWidget(app());
    controller.jumpToIndex(2);
    tester.pump();
    expect(tester.renderToString().trim(), 'c:c\nd:d\ne:e');

    items = ['f', 'e', 'd', 'c', 'b', 'a'];
    revision++;
    tester.pumpWidget(app());
    expect(
      controller.currentIndex,
      3,
      reason: 'c moved from index 2 to index 3',
    );
    expect(tester.renderToString().trim(), 'c:c\nb:b\na:a');
    // Move back to a retained visible row; its State must follow its identity.
    controller.jumpToIndex(1);
    tester.pump();
    expect(tester.renderToString().trim(), 'e:e\nd:d\nc:c');
  });

  testWidgets('count and revision-mode changes refresh the snapshot', (tester) {
    var items = ['a', 'b', 'c'];
    Object? revision = 0;
    var keyed = true;
    var keyCalls = 0;
    Widget app() => SizedBox(
      width: 12,
      height: 3,
      child: ListView.builder(
        itemCount: items.length,
        itemKeyBuilder: keyed
            ? (i) {
                keyCalls++;
                return items[i];
              }
            : null,
        itemKeyRevision: keyed ? revision : null,
        itemBuilder: (_, i, _) => Text(items[i]),
      ),
    );
    tester.pumpWidget(app());
    keyCalls = 0;
    items = ['x', ...items];
    tester.pumpWidget(app());
    expect(
      keyCalls,
      4,
      reason: 'count changes refresh even with the same revision',
    );
    keyCalls = 0;
    revision = null;
    tester.pumpWidget(app());
    expect(keyCalls, 4, reason: 'leaving revision mode refreshes');
    keyCalls = 0;
    revision = 0;
    tester.pumpWidget(app());
    expect(keyCalls, 4, reason: 'entering revision mode refreshes');
    keyed = false;
    tester.pumpWidget(app());
    keyCalls = 0;
    keyed = true;
    tester.pumpWidget(app());
    expect(keyCalls, 4, reason: 're-entering keyed mode cannot reuse old keys');
  });

  testWidgets(
    'without a revision, one closure can observe same-size mutable data',
    (tester) {
      final items = ['a', 'b', 'c'];
      final controller = ListController(initialIndex: 1);
      addTearDown(controller.dispose);
      var keyCalls = 0;
      Object keyAt(int i) {
        keyCalls++;
        return items[i];
      }

      Widget app() => SizedBox(
        width: 12,
        height: 3,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: keyAt,
          itemBuilder: (_, i, _) => _Row(items[i]),
        ),
      );
      tester.pumpWidget(app());
      keyCalls = 0;
      items.setAll(0, ['b', 'c', 'a']);
      tester.pumpWidget(app());
      expect(keyCalls, 3);
      expect(controller.currentIndex, 0);
      expect(tester.renderToString().trim(), 'b:b\nc:c\na:a');
    },
  );
}
