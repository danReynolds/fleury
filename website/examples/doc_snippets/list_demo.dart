// Compile-checked source behind the Lists & scrolling guide. It demonstrates
// lazy rows, selection, activation, paging, and a visible scrollbar.
// Guarded by ../test/doc_snippets_test.dart.

import 'package:fleury/fleury.dart';

void main() => runApp(listsDemoApp());

Widget listsDemoApp() => const FleuryApp(title: 'Tasks', home: TaskList());

class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  static const _count = 1000;
  var _selected = 0;
  String _lastAction = 'Choose a task';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('TASKS', style: CellStyle(bold: true)),
        Text('selected: ${_selected + 1} / $_count'),
        const SizedBox(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _count,
            autofocus: true,
            edgeBehavior: EdgeBehavior.contain,
            scrollbar: true,
            onSelectionChanged: (index) => setState(() => _selected = index),
            onActivate: (index) => setState(() {
              _lastAction = 'Opened task ${index + 1}';
            }),
            itemBuilder: (context, index, selected) => Text(
              '${selected ? '›' : ' '} Task ${(index + 1).toString().padLeft(4, '0')}',
              style: selected
                  ? Theme.of(context).selectionStyle
                  : CellStyle.empty,
            ),
          ),
        ),
        const SizedBox(height: 1),
        Text('last: $_lastAction'),
      ],
    ),
  );
}
