// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class TaskBrowser extends StatefulWidget {
  const TaskBrowser({super.key});

  @override
  State<TaskBrowser> createState() => _TaskBrowserState();
}

class _TaskBrowserState extends State<TaskBrowser> {
  // #docregion interaction
  final list = ListController(initialIndex: 24);
  // #enddocregion interaction
  int focused = 24;
  int? selected;
  bool listFocused = false;

  @override
  void dispose() {
    list.dispose();
    super.dispose();
  }

  Widget buildTask(
    BuildContext context,
    int index,
    bool _,
  ) {
    final chosen = selected == index;
    final label = 'Task ${index + 1}';
    return Text(
      '${chosen ? '✓' : ' '} $label',
      style: chosen
          ? CellStyle(
              foreground: context.colors.success,
              bold: true,
            )
          : CellStyle.none,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListenableBuilder(
        listenable: list,
        builder: (context, _) {
          final range = list.visibleRange;
          return Text(
            'Current: ${(list.currentIndex ?? -1) + 1} / 1000\n'
            'Showing: ${range == null ? '…' : '${range.first + 1}–${range.last + 1}'}',
          );
        },
      ),
      const SizedBox(height: 1),
      FocusDetector(
        onFocusChange: (value) =>
            setState(() => listFocused = value),
        child:
            // #docregion interaction
            SizedBox(
              height: 10,
              child: ListView.builder(
                controller: list,
                itemCount: 1000,
                autofocus: true,
                scrollbar: true,
                onFocusedItemChanged: (index) =>
                    setState(() => focused = index),
                onSelect: (index) =>
                    setState(() => selected = index),
                itemBuilder: buildTask,
              ),
            ),
        // #enddocregion interaction
      ),
      const SizedBox(height: 1),
      Row(
        children: [
          // #docregion interaction
          Button(
            label: 'Go to 25',
            onPressed: () {
              list
                ..currentIndex = 24
                ..jumpToIndex(24);
              setState(() => focused = 24);
            },
          ),
          Button(
            label: 'Scroll to 500',
            onPressed: () => list.jumpToIndex(499),
          ),
          // #enddocregion interaction
        ],
      ),
      Text(
        listFocused
            ? 'Focused: Task ${focused + 1}'
            : 'Focused: outside list',
      ),
      Text(
        selected == null
            ? 'Selected: None'
            : 'Selected: Task ${selected! + 1}',
      ),
    ],
  );
}
