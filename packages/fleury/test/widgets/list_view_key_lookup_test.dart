import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _Key {
  const _Key(this.id);
  final int id;
  static int hashes = 0;

  @override
  bool operator ==(Object other) => other is _Key && other.id == id;

  @override
  int get hashCode {
    hashes++;
    return id.hashCode;
  }
}

class _Row extends StatefulWidget {
  const _Row(this.id);
  final int id;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final initialId = widget.id;

  @override
  Widget build(BuildContext context) => Text('${widget.id}:$initialId');
}

void main() {
  for (final separated in [false, true]) {
    testWidgets(
      'equal fresh keys reuse the lookup and update rows: separated=$separated',
      (tester) {
        final controller = ListController();
        addTearDown(controller.dispose);
        var label = 'before';
        var keyCalls = 0;
        Widget app() {
          Object keyAt(int i) {
            keyCalls++;
            // New equal objects and a new callback on every build.
            return _Key(i);
          }

          Widget row(BuildContext context, int i, bool highlighted) =>
              Text('$label $i');
          return SizedBox(
            width: 20,
            height: 3,
            child: separated
                ? ListView.separated(
                    controller: controller,
                    itemCount: 1000,
                    itemKeyBuilder: keyAt,
                    itemBuilder: row,
                    separatorBuilder: (_, _) => null,
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: 1000,
                    itemKeyBuilder: keyAt,
                    itemBuilder: row,
                  ),
          );
        }

        tester.pumpWidget(app());
        label = 'after';
        _Key.hashes = keyCalls = 0;
        tester.pumpWidget(app());
        expect(keyCalls, 1000, reason: 'must inspect mutable callback data');
        expect(
          _Key.hashes,
          lessThan(100),
          reason: 'no full reverse-map rebuild',
        );
        expect(tester.renderToString(), contains('after 0'));
        controller.jumpToIndex(500);
        tester.pump();
        expect(tester.renderToString(), contains('after 500'));
        expect(
          keyCalls,
          1000,
          reason: 'navigation already reuses the snapshot',
        );
      },
    );
  }

  testWidgets('offscreen changes survive reuse and later scrolling', (tester) {
    final items = List.generate(100, (i) => i);
    final controller = ListController(initialIndex: 50);
    addTearDown(controller.dispose);
    var reads = 0;
    Object keyAt(int i) {
      reads++;
      return items[i];
    }

    Widget app() => SizedBox(
      width: 20,
      height: 3,
      child: ListView.builder(
        controller: controller,
        itemCount: items.length,
        itemKeyBuilder: keyAt,
        itemBuilder: (_, i, _) => _Row(items[i]),
      ),
    );
    tester.pumpWidget(app());
    tester.pumpWidget(app());
    reads = 0;
    items[98] = 999;
    tester.pumpWidget(app());
    expect(reads, 100, reason: 'each callback is evaluated exactly once');
    expect(controller.currentIndex, 50);
    controller.currentIndex = 98;
    tester.pump();
    expect(tester.renderToString(), contains('999:999'));
    // The changed offscreen identity must now follow a same-size reorder.
    items[98] = items[1];
    items[1] = 999;
    tester.pumpWidget(app());
    expect(controller.currentIndex, 1);
    controller.jumpToIndex(1);
    tester.pump();
    expect(tester.renderToString(), contains('999:999'));
  });

  testWidgets(
    'offscreen duplicates fail; failed captures leave old keys valid',
    (tester) {
      final items = List.generate(100, (i) => i);
      final controller = ListController(initialIndex: 1);
      addTearDown(controller.dispose);
      int? throwAt;
      Widget app() => SizedBox(
        width: 20,
        height: 3,
        child: ListView.builder(
          controller: controller,
          itemCount: items.length,
          itemKeyBuilder: (i) {
            if (i == throwAt) throw StateError('interrupted capture');
            return items[i];
          },
          itemBuilder: (_, i, _) => _Row(items[i]),
        ),
      );
      tester.pumpWidget(app());
      items[99] = 98;
      expect(() => tester.pumpWidget(app()), throwsStateError);
      items[99] = 99;
      tester.pumpWidget(app());
      expect(controller.currentIndex, 1);

      items[0] = 100;
      throwAt = 50;
      expect(() => tester.pumpWidget(app()), throwsStateError);
      throwAt = null;
      items[0] = 1;
      items[1] = 0;
      tester.pumpWidget(app());
      expect(controller.currentIndex, 0);
      controller.jumpToIndex(0);
      tester.pump();
      expect(tester.renderToString().trim(), '1:1\n0:0\n2:2');
    },
  );

  testWidgets('seeded updates match an identity oracle', (tester) {
    var seed = 71;
    int next(int max) {
      seed = (seed * 1664525 + 1013904223) & 0xffffffff;
      return seed % max;
    }

    var items = List.generate(80, (i) => i);
    var nextId = 80;
    final controller = ListController(initialIndex: 40);
    addTearDown(controller.dispose);
    Object keyAt(int i) => items[i];
    Widget app() => SizedBox(
      width: 20,
      height: 4,
      child: ListView.builder(
        controller: controller,
        itemCount: items.length,
        itemKeyBuilder: keyAt,
        itemBuilder: (_, i, _) => _Row(items[i]),
      ),
    );
    tester.pumpWidget(app());
    for (var update = 0; update < 200; update++) {
      final oldIndex = controller.currentIndex!;
      final oldKey = items[oldIndex];
      switch (update % 6) {
        case 0:
          break; // ordinary unchanged parent rebuild
        case 1:
          final a = next(items.length), b = next(items.length);
          final key = items[a];
          items[a] = items[b];
          items[b] = key;
        case 2:
          items.insert(0, nextId++);
        case 3:
          items.removeAt(next(items.length));
        case 4:
          items[next(items.length)] = nextId++;
        case 5:
          items = items.reversed.toList();
      }
      final newIndex = items.indexOf(oldKey);
      tester.pumpWidget(app());
      expect(
        controller.currentIndex,
        newIndex >= 0 ? newIndex : oldIndex.clamp(0, items.length - 1),
      );
      final text = tester.renderToString();
      for (final match in RegExp(r'(\d+):(\d+)').allMatches(text)) {
        expect(match[1], match[2], reason: 'row State must follow its key');
      }
      // Vary the current item and viewport for the next mutation.
      controller.currentIndex = next(items.length);
      tester.pump();
    }
  });
}
