// Compile-checked source behind the Navigation guide. Exercises route-local
// commands, context.push/context.pop, returned results, PopScope, and a route
// transition against the real API. Guarded by ../test/doc_snippets_test.dart.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

const _openDetail = CommandId('navigation.open-detail');
const _confirmDetail = CommandId('navigation.confirm-detail');

void main() =>
    runApp(const FleuryApp(title: 'Navigation demo', home: HomeScreen()));

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _confirmed = false;

  Future<void> _showDetail(BuildContext context) async {
    final confirmed = await context.push<bool>(
      const DetailScreen(),
      transition: RouteTransition.slide,
    );
    if (mounted && confirmed == true) {
      setState(() => _confirmed = true);
    }
  }

  @override
  Widget build(BuildContext context) => CommandScope(
    commands: [
      AppCommand(
        id: _openDetail,
        title: 'Open detail',
        category: 'Navigation',
        shortcuts: [KeyChord.ctrl.o],
        semanticAction: SemanticAction.navigate,
        run: (command) {
          final source = command.buildContext;
          if (source != null) unawaited(_showDetail(source));
        },
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_confirmed ? 'Detail confirmed' : 'Home'),
        const SizedBox(height: 1),
        Button(
          label: 'Open detail',
          onPressed: () => unawaited(_showDetail(context)),
        ),
        const Spacer(),
        const KeyHintBar(),
      ],
    ),
  );
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    child: CommandScope(
      commands: [
        AppCommand(
          id: _confirmDetail,
          title: 'Confirm and go back',
          category: 'Navigation',
          shortcuts: [KeyChord.ctrl.enter],
          semanticAction: SemanticAction.activate,
          run: (command) => command.buildContext?.pop(true),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Detail'),
          const SizedBox(height: 1),
          Button(label: 'Confirm', onPressed: () => context.pop(true)),
          Button(label: 'Cancel', onPressed: () => context.pop(false)),
          const Spacer(),
          const KeyHintBar(),
        ],
      ),
    ),
  );
}
