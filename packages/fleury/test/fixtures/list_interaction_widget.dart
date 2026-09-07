import 'package:fleury/fleury_core.dart';

/// Shared native-browser and served-runtime pointer regression fixture.
class ListInteractionFixture extends StatefulWidget {
  const ListInteractionFixture({super.key});
  @override
  State<ListInteractionFixture> createState() => _ListInteractionFixtureState();
}

class _ListInteractionFixtureState extends State<ListInteractionFixture> {
  int selected = 0;
  String activated = 'none';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Selected: $selected; activated: $activated'),
      SizedBox(
        width: 20,
        height: 3,
        child: ListView.builder(
          itemCount: 3,
          onSelectionChanged: (index) => setState(() => selected = index),
          onActivate: (index) => setState(() => activated = '$index'),
          itemBuilder: (_, index, active) => Text('Choice $index'),
        ),
      ),
      const Text('Tall content'),
      SizedBox(
        width: 20,
        height: 5,
        child: ListView.builder(
          itemCount: 2,
          selectable: false,
          scrollbar: true,
          itemBuilder: (_, index, active) => Text(
            index == 0
                ? List.generate(8, (line) => 'Line $line').join('\n')
                : 'Tail',
          ),
        ),
      ),
      const Text('Outside the viewport'),
    ],
  );
}
