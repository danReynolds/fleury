import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

void main() {
  for (final mode in ['eager', 'builder', 'separated']) {
    for (final boundaries in [false, true]) {
      testWidgets(
        '$mode rows keep semantic targets across reorder and scroll, boundaries=$boundaries',
        (tester) async {
          final items = ['a', 'b', 'c', 'd', 'e'];
          final calls = <String>[];
          final controller = ListController();
          addTearDown(controller.dispose);
          Widget row(String value) => Container(
            // Eager lists take identity from child keys. Lazy lists deliberately
            // have no keyed widget: itemKeyBuilder alone identifies each row.
            key: mode == 'eager' ? ValueKey(value) : null,
            child: Semantics(
              role: SemanticRole.button,
              label: value,
              actions: const {SemanticAction.activate},
              onAction: (_) => calls.add(value),
              child: Text(value),
            ),
          );
          Widget app() => SizedBox(
            height: 3,
            child: switch (mode) {
              'eager' => ListView(
                controller: controller,
                addRepaintBoundaries: boundaries,
                children: items.map(row).toList(),
              ),
              'builder' => ListView.builder(
                controller: controller,
                addRepaintBoundaries: boundaries,
                itemCount: items.length,
                itemKeyBuilder: (i) => items[i],
                itemBuilder: (_, i, _) => row(items[i]),
              ),
              _ => ListView.separated(
                controller: controller,
                addRepaintBoundaries: boundaries,
                itemCount: items.length,
                itemKeyBuilder: (i) => items[i],
                itemBuilder: (_, i, _) => row(items[i]),
                separatorBuilder: (_, _) => null,
              ),
            },
          );
          tester.pumpWidget(app());
          final id = tester
              .semantics()
              .single(role: SemanticRole.button, label: 'b')
              .id;
          // Keep the anchored first row in place so b remains visible.
          items.setAll(0, ['a', 'c', 'b', 'd', 'e']);
          tester.pumpWidget(app());
          expect(
            tester.semantics().single(role: SemanticRole.button, label: 'b').id,
            id,
          );
          expect(
            (await tester.invokeSemanticAction(
              SemanticAction.activate,
              id: id,
            )).completed,
            isTrue,
          );
          expect(calls, ['b']);
          controller.jumpToIndex(4);
          tester.pump();
          controller.jumpToIndex(0);
          tester.pump();
          expect(
            tester.semantics().single(role: SemanticRole.button, label: 'b').id,
            id,
          );
          expect(
            (await tester.invokeSemanticAction(
              SemanticAction.activate,
              id: id,
            )).completed,
            isTrue,
          );
          expect(calls, ['b', 'b']);
        },
      );
    }
  }

  testWidgets('identical item keys in separate lazy lists stay distinct', (
    tester,
  ) {
    Widget list(String label) => SizedBox(
      height: 2,
      child: ListView.builder(
        itemCount: 1,
        itemKeyBuilder: (_) => 'same',
        itemBuilder: (_, _, _) => Semantics(
          role: SemanticRole.button,
          label: label,
          child: Text(label),
        ),
      ),
    );
    tester.pumpWidget(Row(children: [list('Recent'), list('All')]));
    final tree = tester.semantics();
    expect(
      tree.single(role: SemanticRole.button, label: 'Recent').id,
      isNot(tree.single(role: SemanticRole.button, label: 'All').id),
    );
  });
}
