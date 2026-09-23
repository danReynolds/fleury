import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class ScrollPanes extends StatefulWidget {
  const ScrollPanes({super.key});

  @override
  State<ScrollPanes> createState() => _ScrollPanesState();
}

class _ScrollPanesState extends State<ScrollPanes> {
  bool contain = false;

  // #docregion focus
  Widget get recentScroll => ScrollView(
    edgeBehavior: contain ? EdgeBehavior.contain : EdgeBehavior.bubble,
    child: const Text(
      '1  Sketches\n2  Research\n3  Draft\n4  Feedback\n5  Revision\n6  Final',
    ),
  );
  // #enddocregion focus

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
                  child: Panel(title: 'Recent', child: recentScroll),
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
