// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class HorizontalList extends StatefulWidget {
  const HorizontalList({super.key});

  @override
  State<HorizontalList> createState() =>
      _HorizontalListState();
}

class _HorizontalListState extends State<HorizontalList> {
  final projects = const [
    'Editor',
    'Preview',
    'Search',
    'Terminal',
    'Settings',
    'Outline',
  ];
  int? selected;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 2,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: projects.length,
          autofocus: true,
          scrollbar: true,
          onSelect: (index) =>
              setState(() => selected = index),
          separatorBuilder: (_, _) =>
              const SizedBox(width: 2),
          itemBuilder: (context, index, _) => SizedBox(
            width: 12,
            child: Text(
              projects[index],
              style: index == selected
                  ? CellStyle(
                      foreground: context.colors.success,
                      bold: true,
                    )
                  : CellStyle.none,
            ),
          ),
        ),
      ),
      const SizedBox(height: 1),
      Text(
        'Selected: ${selected == null ? 'None' : projects[selected!]}',
      ),
    ],
  );
}
