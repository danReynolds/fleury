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
  bool contain = false;
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
        Checkbox(
          label: 'Contain arrows',
          value: contain,
          onChanged: (value) =>
              setState(() => contain = value),
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
                    edgeBehavior: contain
                        ? EdgeBehavior.contain
                        : EdgeBehavior.bubble,
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
