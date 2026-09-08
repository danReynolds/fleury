import 'dart:io';
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('NumberInput seed survives rebuilds and a new key resets it', (
    t,
  ) async {
    Widget field(int seed, {Key? key}) =>
        NumberInput(key: key, initialValue: seed, semanticLabel: 'Amount');
    t.pumpWidget(field(1));
    await t.field('Amount').fill('7');
    t.pumpWidget(field(9));
    expect(t.field('Amount'), hasValue('7'));
    t.pumpWidget(field(9, key: const ValueKey('reset')));
    expect(t.field('Amount'), hasValue('9'));
  });

  testWidgets(
    'NumberInput controller updates stay quiet; accepted edits notify once',
    (t) async {
      final controller = TextEditingController(text: '1');
      final events = <num?>[];
      t.pumpWidget(
        NumberInput(
          controller: controller,
          semanticLabel: 'Amount',
          onChanged: events.add,
        ),
      );
      controller.text = '9';
      t.pump();
      expect(events, isEmpty);
      expect(t.field('Amount'), hasValue('9'));
      await t.field('Amount').fill('bad');
      expect(events, isEmpty);
      expect(t.field('Amount'), hasValue('9'));
      await t.field('Amount').fill('4');
      expect(events, [4]);
    },
  );

  testWidgets(
    'file directory seed, navigation command and replacement have separate contracts',
    (t) {
      final root = Directory.systemTemp.createTempSync('fleury-ownership-');
      addTearDown(() => root.deleteSync(recursive: true));
      final a = Directory('${root.path}/a')..createSync();
      final b = Directory('${root.path}/b')..createSync();
      for (var i = 0; i < 5; i++) {
        File('${a.path}/alpha$i').writeAsStringSync('');
      }
      File('${b.path}/beta').writeAsStringSync('');
      final first = FileBrowserController(initialIndex: 2);
      final events = <String>[];
      Widget browser(String seed, FileBrowserController c) => FileBrowser(
        initialDirectory: seed,
        controller: c,
        onDirectoryChanged: events.add,
      );
      t.pumpWidget(browser(a.path, first));
      expect(first.currentIndex, 2);
      t.pumpWidget(browser(b.path, first));
      expect(first.currentDirectory, a.path);
      expect(t.renderToString(), contains('alpha2'));
      final second = FileBrowserController(initialIndex: 4);
      t.pumpWidget(browser(b.path, second));
      expect(second.currentIndex, 4);
      expect(first.currentDirectory, isNull);
      expect(() => first.openDirectory(b.path), throwsStateError);
      var changes = 0;
      second.addListener(() => changes++);
      second.openDirectory(b.path);
      t.pump();
      expect(second.currentDirectory, b.path);
      expect(t.renderToString(), contains('beta'));
      expect(second.currentIndex, 0);
      expect(changes, greaterThan(0));
      expect(events, isEmpty);
    },
  );

  testWidgets('SearchPanel preserves supplied cursor including explicit null', (
    t,
  ) {
    const results = [
      SearchResult(title: 'Alpha'),
      SearchResult(title: 'Beta'),
      SearchResult(title: 'Gamma'),
    ];
    final first = ListController(initialIndex: 2);
    t.pumpWidget(SearchPanel(results: results, controller: first));
    expect(first.currentIndex, 2);
    final second = ListController(initialIndex: null);
    t.pumpWidget(SearchPanel(results: results, controller: second));
    expect(second.currentIndex, isNull);
    final third = ListController(initialIndex: 99);
    t.pumpWidget(SearchPanel(results: results, controller: third));
    expect(third.currentIndex, 2);
  });

  testWidgets(
    'JSON expansion default stays live while explicit overrides win',
    (t) {
      final controller = JsonViewController(collapsedPointers: ['/parent']);
      Widget json(int depth) => JsonView(
        value: {
          'parent': {'leaf': 1},
        },
        controller: controller,
        defaultExpandedDepth: depth,
      );
      t.pumpWidget(json(0));
      t.pumpWidget(json(3));
      expect(t.renderToString(), isNot(contains('leaf')));
      controller.expand('/parent');
      t.pump();
      expect(t.renderToString(), contains('leaf'));
    },
  );

  test('every row controller preserves an explicit null seed', () {
    final controllers = <dynamic>[
      CodeViewController(initialIndex: null),
      ContextPanelController(initialIndex: null),
      ConversationNavigatorController(initialIndex: null),
      DiffViewController(initialIndex: null),
      FileBrowserController(initialIndex: null),
      FileMentionPickerController(initialIndex: null),
      JsonViewController(initialIndex: null),
      LogRegionController(initialIndex: null),
      MarkdownViewController(initialIndex: null),
      MessageListController(initialIndex: null),
      PatchReviewController(initialIndex: null),
      TableController(initialIndex: null),
      TaskGraphController(initialIndex: null),
      TraceTimelineController(initialIndex: null),
      TreeTableController(initialIndex: null),
    ];
    for (final controller in controllers) {
      expect(
        controller.currentIndex,
        isNull,
        reason: '${controller.runtimeType}',
      );
      controller.dispose();
    }
  });

  testWidgets(
    'Table honors no cursor and uses the same default with an external controller',
    (t) {
      Widget table(TableController? controller) => Table(
        controller: controller,
        selectable: true,
        rows: const [
          [Text('A')],
          [Text('B')],
        ],
      );
      final empty = TableController(initialIndex: null);
      t.pumpWidget(table(empty));
      expect(empty.currentIndex, isNull);
      final controller = TableController();
      t.pumpWidget(table(controller));
      expect(controller.currentIndex, 0);
    },
  );

  for (final kind in ['table', 'tabs', 'data table']) {
    testWidgets('$kind rejects a second owner and reattaches', (t) {
      final dynamic controller = switch (kind) {
        'table' => TableController(initialIndex: 1),
        'tabs' => TabController(initialIndex: 1),
        _ => DataTableController(initialRowIndex: 1),
      };
      Widget view([int count = 2]) => switch (kind) {
        'table' => Table(
          controller: controller as TableController,
          rows: [
            for (var i = 0; i < count; i++) [Text('$i')],
          ],
        ),
        'tabs' => Tabs(
          controller: controller as TabController,
          tabs: [
            for (var i = 0; i < count; i++)
              TabItem(label: '$i', content: Text('$i')),
          ],
        ),
        _ => DataTable(
          controller: controller as DataTableController,
          columns: const [DataTableColumn(id: 'name', title: 'Name')],
          rowCount: count,
          cellBuilder: (row, col) => '$row',
        ),
      };
      t.pumpWidget(view());
      final other = FleuryTester();
      addTearDown(other.dispose);
      expect(() => other.pumpWidget(view()), throwsStateError);
      t.pumpWidget(const Text('unmounted'));
      // A detached controller must not clamp against its previous host's size.
      if (kind == 'tabs') {
        controller.index = 4;
      } else if (kind == 'data table') {
        controller.currentRowIndex = 4;
      } else {
        controller.currentIndex = 4;
      }
      t.pumpWidget(view(6));
      expect(
        kind == 'tabs'
            ? controller.index
            : kind == 'data table'
            ? controller.currentRowIndex
            : controller.currentIndex,
        4,
      );
    });
  }
}
