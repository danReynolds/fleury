// Live demos for "Coming from Flutter". The page shows these regions with
// SourceExcerpt, so the code a reader compares against Flutter is the code
// running beside it.
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

// #docregion counter
class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Count: $_count'),
          const SizedBox(height: 1),
          Button(
            text: 'Increment',
            autofocus: true,
            onPressed: () => setState(() => _count++),
          ),
        ],
      ),
    );
  }
}
// #enddocregion counter

// #docregion cells
class CellBoxes extends StatelessWidget {
  const CellBoxes({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final ratio in [1.0, 2.0])
          SizedBox(
            width: 12,
            child: AspectRatio(
              aspectRatio: ratio,
              child: Container(
                border: const BoxBorder(),
                alignment: Alignment.center,
                child: Text(ratio.toStringAsFixed(1)),
              ),
            ),
          ),
      ],
    );
  }
}
// #enddocregion cells

// #docregion keys
class EditorShortcuts extends StatefulWidget {
  const EditorShortcuts({super.key});

  @override
  State<EditorShortcuts> createState() => _EditorShortcutsState();
}

class _EditorShortcutsState extends State<EditorShortcuts> {
  String _status = 'Type, then press Ctrl+S or Esc';

  void save() => setState(() => _status = 'Saved');
  void cancel() => setState(() => _status = 'Changes discarded');

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(KeySequence.ctrl.s, label: 'Save', onTrigger: (_) => save()),
        KeyBinding(
          KeySequence.escape,
          label: 'Cancel',
          onTrigger: (_) => cancel(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextInput(autofocus: true, placeholder: 'Notes'),
          const SizedBox(height: 1),
          Text(_status),
          const Spacer(),
          const KeyHintBar(),
        ],
      ),
    );
  }
}
// #enddocregion keys

// #docregion animation
class SelectionMeter extends StatefulWidget {
  const SelectionMeter({super.key});

  @override
  State<SelectionMeter> createState() => _SelectionMeterState();
}

class _SelectionMeterState extends State<SelectionMeter> {
  bool selected = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Button(
          text: selected ? 'Deselect' : 'Select',
          autofocus: true,
          onPressed: () => setState(() => selected = !selected),
        ),
        const SizedBox(height: 1),
        AnimationBuilder<double>(
          selected ? 1.0 : 0.0,
          builder: (context, t, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('selected: ${t.toStringAsFixed(2)}'),
              SizedBox(width: 30, child: ProgressBar(value: t)),
            ],
          ),
        ),
      ],
    );
  }
}
// #enddocregion animation

// #docregion routes
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Projects'),
        const SizedBox(height: 1),
        for (final id in ['atlas', 'borealis'])
          Button(
            text: 'Open $id',
            autofocus: id == 'atlas',
            onPressed: () => context.push<void>(DetailScreen(id: id)),
          ),
      ],
    );
  }
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Project $id'),
        const SizedBox(height: 1),
        Button(
          text: 'Open settings',
          autofocus: true,
          onPressed: () => context.push<void>(DetailScreen(id: '$id/settings')),
        ),
        Button(text: 'Back', onPressed: () => context.pop()),
        Button(
          text: 'All projects',
          onPressed: () => context.popUntil<HomeScreen>(),
        ),
      ],
    );
  }
}

// #enddocregion routes
