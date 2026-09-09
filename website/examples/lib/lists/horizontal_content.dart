// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class HorizontalContent extends StatefulWidget {
  const HorizontalContent({super.key});

  @override
  State<HorizontalContent> createState() =>
      _HorizontalContentState();
}

class _HorizontalContentState
    extends State<HorizontalContent> {
  final scroll = ScrollController();
  static const report =
      'NAME         STATUS    DURATION    OUTPUT                   RESULT\n'
      'compile      done      2.4s        build/application.js     SUCCESS\n'
      'test         done      1.1s        build/test-results.txt   SUCCESS';

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 4,
        child: ScrollView(
          scrollDirection: Axis.horizontal,
          controller: scroll,
          autofocus: true,
          scrollbar: true,
          child: const Text(report),
        ),
      ),
      const SizedBox(height: 1),
      ListenableBuilder(
        listenable: scroll,
        builder: (_, _) => Text(
          'Columns ${scroll.offset + 1}–'
          '${scroll.offset + scroll.viewportExtent}'
          ' / ${scroll.contentExtent}'
          '${scroll.atStart ? ' · START' : ''}'
          '${scroll.atEnd ? ' · END' : ''}',
        ),
      ),
    ],
  );
}
