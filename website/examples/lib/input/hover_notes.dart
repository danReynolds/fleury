import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class HoverNotes extends StatefulWidget {
  const HoverNotes({super.key});

  @override
  State<HoverNotes> createState() => _HoverNotesState();
}

class _HoverNotesState extends State<HoverNotes> {
  bool overRow = false;
  bool contain = false;
  int pins = 0;

  Widget get fileRow => Row(
    children: [
      Expanded(
        child: Text('notes.md', style: CellStyle(inverse: overRow)),
      ),
      Button(label: 'Pin', onPressed: () => setState(() => pins++)),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // #docregion interaction
      MouseRegion(
        onEnter: () => setState(() => overRow = true),
        onExit: () => setState(() => overRow = false),
        child: fileRow,
      ),
      // #enddocregion interaction
      Text(overRow ? 'Over the row · pins: $pins' : 'Move over the row or Pin'),
      Checkbox(
        label: 'Keep scrolling in Recent',
        value: contain,
        onChanged: (value) => setState(() => contain = value),
      ),
      const SizedBox(height: 1),
      SizedBox(
        height: 10,
        child: Panel(
          title: 'All notes',
          child: ScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 6,
                  child: Panel(
                    title: 'Recent',
                    // #docregion interaction
                    child: ScrollView(
                      edgeBehavior: contain
                          ? EdgeBehavior.contain
                          : EdgeBehavior.bubble,
                      child: const Text(
                        '1  Sketches\n2  Research\n3  Draft\n4  Feedback\n5  Revision\n6  Final',
                      ),
                    ),
                    // #enddocregion interaction
                  ),
                ),
                const Text('OLDER NOTES\nJuly\nJune\nMay\nApril'),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
