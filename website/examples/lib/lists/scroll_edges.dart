// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class ScrollEdges extends StatefulWidget {
  const ScrollEdges({super.key});

  @override
  State<ScrollEdges> createState() => _ScrollEdgesState();
}

class _ScrollEdgesState extends State<ScrollEdges> {
  final scroll = ScrollController();
  EdgeBehavior edgeBehavior = EdgeBehavior.bubble;
  bool paneFocused = false;
  bool continued = false;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Edge behavior'),
        Select<EdgeBehavior>(
          semanticLabel: 'Edge behavior',
          value: edgeBehavior,
          options: const [
            SelectOption(
              value: EdgeBehavior.bubble,
              label: 'Bubble (leave pane)',
            ),
            SelectOption(
              value: EdgeBehavior.contain,
              label: 'Contain (stay in pane)',
            ),
          ],
          onChanged: (value) =>
              setState(() => edgeBehavior = value),
        ),
        const SizedBox(height: 1),
        ListenableBuilder(
          listenable: scroll,
          builder: (context, _) {
            final first = scroll.offset + 1;
            final last =
                scroll.offset + scroll.viewportExtent;
            final edge = scroll.atTop
                ? 'TOP'
                : scroll.atBottom
                ? 'BOTTOM'
                : 'MIDDLE';
            return Text('Rows $first–$last / 8 · $edge');
          },
        ),
        Panel(
          title: 'Scroll pane',
          expandChild: false,
          focused: paneFocused,
          child: FocusDetector(
            onFocusChange: (value) =>
                setState(() => paneFocused = value),
            child:
                // #docregion interaction
                SizedBox(
                  height: 4,
                  child: ScrollView(
                    controller: scroll,
                    autofocus: true,
                    scrollbar: true,
                    edgeBehavior: edgeBehavior,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('1 ─── TOP'),
                        for (var n = 2; n < 8; n++)
                          Text('$n'),
                        const Text('8 ─── BOTTOM'),
                      ],
                    ),
                  ),
                ),
            // #enddocregion interaction
          ),
        ),
        Button(
          label: 'Next',
          onPressed: () => setState(() => continued = true),
        ),
        Text(
          paneFocused
              ? 'Focus: scroll pane'
              : 'Focus: controls',
        ),
        if (continued) const Text('Next selected'),
      ],
    ),
  );
}
