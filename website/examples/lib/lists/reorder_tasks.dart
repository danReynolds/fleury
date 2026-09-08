// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class ReorderTasks extends StatefulWidget {
  const ReorderTasks({super.key});

  @override
  State<ReorderTasks> createState() => _ReorderTasksState();
}

class _ReorderTasksState extends State<ReorderTasks> {
  final list = ListController(initialIndex: 1);
  var tasks = [
    (id: 'sketch', title: 'Sketch the layout'),
    (id: 'build', title: 'Build the prototype'),
    (id: 'test', title: 'Test the keyboard path'),
    (id: 'ship', title: 'Ship the guide'),
  ];

  @override
  void dispose() {
    list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // #docregion interaction
        SizedBox(
          height: 4,
          child: ListView.builder(
            controller: list,
            itemCount: tasks.length,
            itemKeyBuilder: (index) => tasks[index].id,
            itemBuilder: (context, i, highlighted) => Text(
              '${highlighted ? '›' : ' '} ${tasks[i].title}',
              style: highlighted
                  ? Theme.of(context).selectionStyle
                  : CellStyle.none,
            ),
          ),
        ),
        // #enddocregion interaction
        const SizedBox(height: 1),
        // #docregion interaction
        Button(
          label: 'Reverse order',
          onPressed: () => setState(
            () => tasks = tasks.reversed.toList(),
          ),
        ),
        // #enddocregion interaction
        ListenableBuilder(
          listenable: list,
          builder: (context, _) {
            final index = list.currentIndex;
            return Text(
              index == null
                  ? 'No current item'
                  : 'Current: ${tasks[index].title}',
            );
          },
        ),
      ],
    );
  }
}
