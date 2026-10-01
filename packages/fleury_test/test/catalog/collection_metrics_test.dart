import 'dart:io';
import 'dart:collection';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('semantic snapshots do not scan the context collection', (
    tester,
  ) {
    final items = _CountingList([
      for (var i = 0; i < 500; i++)
        ContextItem(id: '$i', label: 'item $i', tokenCount: 1, pinned: true),
    ]);
    tester.pumpWidget(SizedBox(height: 10, child: ContextPanel(items: items)));
    tester.pump();
    tester.pump();
    items.reads = 0;
    final state = tester.semantics().single(label: 'Context').state;
    expect(state['contextTokenCount'], 500);
    expect(state['pinnedContextItemCount'], 500);
    expect(items.reads, lessThan(5));
  });

  testWidgets('initial tail cursor is read after list attachment', (tester) {
    tester.pumpWidget(
      SizedBox(
        height: 8,
        child: MessageList(
          semanticLabel: 'messages',
          messages: [
            for (var i = 0; i < 50; i++)
              MessageEntry(id: i, text: 'message $i'),
          ],
        ),
      ),
    );
    final state = tester.semantics().single(label: 'messages').state;
    expect(state['currentIndex'], 49);
    expect(state['selectedMessageId'], 49);
  });

  final panels = <String, Widget Function()>{
    'CodeView': () => CodeView(
      source: List.generate(200, (i) => 'line $i').join('\n'),
      semanticLabel: 'collection',
    ),
    'DiffView': () => DiffView(
      diff:
          '@@ -0,0 +1,200 @@\n${List.generate(200, (i) => '+line $i').join('\n')}',
      semanticLabel: 'collection',
    ),
    'FileBrowser': () {
      final dir = Directory.systemTemp.createTempSync('fleury_metrics_');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (var i = 0; i < 200; i++) {
        File('${dir.path}/file_$i').writeAsStringSync('');
      }
      return FileBrowser(
        initialDirectory: dir.path,
        semanticLabel: 'collection',
      );
    },
    'LogRegion': () => LogRegion(
      controller: _owned(LogRegionController(followTail: false)),
      entries: [for (var i = 0; i < 200; i++) LogEntry(message: 'line $i')],
      semanticLabel: 'collection',
    ),
    'JsonView': () => JsonView(
      value: [for (var i = 0; i < 200; i++) i],
      semanticLabel: 'collection',
    ),
    'MessageList': () => MessageList(
      controller: _owned(MessageListController(followTail: false)),
      messages: [for (var i = 0; i < 200; i++) MessageEntry(text: 'line $i')],
      semanticLabel: 'collection',
    ),
    'TaskGraph': () => TaskGraph(
      nodes: [
        for (var i = 0; i < 200; i++) TaskGraphNode(id: '$i', title: 'task $i'),
      ],
      semanticLabel: 'collection',
    ),
    'PatchReview': () => PatchReview(
      diff: '',
      files: [
        for (var i = 0; i < 200; i++)
          PatchReviewFile(path: 'file_$i', fileIndex: i),
      ],
      showDiff: false,
      maxVisibleFiles: 8,
      label: 'collection',
    ),
    'FileMentionPicker': () => FileMentionPicker(
      entries: [
        for (var i = 0; i < 200; i++) FileMentionEntry(path: 'file_$i'),
      ],
      semanticLabel: 'collection',
    ),
    'TraceTimeline': () => TraceTimeline(
      events: [
        for (var i = 0; i < 200; i++)
          TraceTimelineEntry(id: '$i', label: 'event $i'),
      ],
      label: 'collection',
    ),
    'TreeTable': () => TreeTable<int>(
      roots: [
        for (var i = 0; i < 200; i++)
          TreeTableNode(key: '$i', label: 'node $i'),
      ],
      columns: const [
        DataTableColumn(id: 'name', title: 'Name', width: FixedColumnWidth(20)),
      ],
      semanticLabel: 'collection',
    ),
    'ContextPanel': () => ContextPanel(
      items: [
        for (var i = 0; i < 200; i++) ContextItem(id: '$i', label: 'item $i'),
      ],
      label: 'collection',
    ),
    'ConversationNavigator': () => ConversationNavigator(
      conversations: [
        for (var i = 0; i < 200; i++)
          ConversationEntry(id: '$i', title: 'chat $i'),
      ],
      semanticLabel: 'collection',
    ),
    'SearchPanel': () => SearchPanel(
      results: [for (var i = 0; i < 200; i++) SearchResult(title: 'result $i')],
      semanticLabel: 'collection',
    ),
    'Tree': () => Tree<int>(
      roots: [for (var i = 0; i < 200; i++) TreeNode('node $i')],
      semanticLabel: 'collection',
    ),
  };
  for (final MapEntry(key: name, value: panel) in panels.entries) {
    testWidgets('$name publishes viewport metrics without a follow-up build', (
      tester,
    ) {
      tester.pumpWidget(SizedBox(height: 12, width: 60, child: panel()));
      tester.pump();
      tester.pump();
      for (var step = 0; step < 20; step++) {
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.scrollDown,
            button: MouseButton.none,
            col: 2,
            row: 4,
          ),
        );
        tester.pump();
        expect(
          tester.owner.flushBuild().rebuiltElementCount,
          0,
          reason: 'completed metrics must not dirty widget content, step $step',
        );
        tester.pump();
      }
      expect(
        tester
            .semantics()
            .single(label: 'collection')
            .state['visibleRangeStart'],
        greaterThan(0),
      );
    });
  }
}

T _owned<T extends Notifier>(T controller) {
  addTearDown(controller.dispose);
  return controller;
}

class _CountingList<T> extends ListBase<T> {
  _CountingList(this.values);
  final List<T> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read-only');
  @override
  T operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('read-only');
}
