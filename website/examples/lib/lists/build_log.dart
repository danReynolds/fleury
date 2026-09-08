import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class BuildLog extends StatefulWidget {
  const BuildLog({super.key});

  @override
  State<BuildLog> createState() => _BuildLogState();
}

class _BuildLogState extends State<BuildLog> {
  // #docregion interaction
  final log = ListController(followTail: true);
  // #enddocregion interaction
  final lines = [for (var i = 1; i <= 12; i++) 'Step $i complete'];
  int detail = 0;

  @override
  void dispose() {
    log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListenableBuilder(
        listenable: log,
        builder: (context, _) => Text(
          log.isFollowing
              ? 'Following latest output'
              : 'Paused · ${log.unseenCount} new entries',
        ),
      ),
      const SizedBox(height: 1),
      // #docregion interaction
      SizedBox(
        height: 6,
        child: ListView.builder(
          controller: log,
          selectable: false,
          autofocus: true,
          scrollbar: true,
          itemCount: lines.length,
          itemBuilder: (context, index, highlighted) => Text(lines[index]),
        ),
      ),
      // #enddocregion interaction
      const SizedBox(height: 1),
      Row(
        children: [
          // #docregion interaction
          Button(
            label: 'Append',
            onPressed: () =>
                setState(() => lines.add('Step ${lines.length + 1} complete')),
          ),
          Button(label: 'Latest', onPressed: log.jumpToBottom),
          // #enddocregion interaction
          Button(
            label: 'Grow last entry',
            onPressed: () => setState(
              () => lines[lines.length - 1] += '\n  Detail ${++detail}',
            ),
          ),
        ],
      ),
    ],
  );
}
