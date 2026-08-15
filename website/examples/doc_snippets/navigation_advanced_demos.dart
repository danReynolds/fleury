// Compile-checked source behind the focused Navigation guide demos: dialog
// placement, PopScope, transitions, and an embedded multi-step Navigator.
// Guarded by ../test/doc_snippets_test.dart.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Widget placementDemoApp() =>
    const FleuryApp(title: 'Dialog placement', home: PlacementDemo());

class PlacementDemo extends StatefulWidget {
  const PlacementDemo({super.key});

  @override
  State<PlacementDemo> createState() => _PlacementDemoState();
}

class _PlacementDemoState extends State<PlacementDemo> {
  Alignment _alignment = Alignment.center;

  Future<void> _show(BuildContext context, Alignment alignment) async {
    setState(() => _alignment = alignment);
    await context.present<void>(
      const _PlacedDialog(),
      alignment: alignment,
      transition: RouteTransition.none,
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CHOOSE WHERE TO PRESENT'),
        const SizedBox(height: 1),
        Select<Alignment>(
          semanticLabel: 'Dialog placement',
          autofocus: true,
          value: _alignment,
          options: const [
            SelectOption(value: Alignment.topLeft, label: 'Top left'),
            SelectOption(value: Alignment.center, label: 'Center'),
            SelectOption(value: Alignment.bottomRight, label: 'Bottom right'),
          ],
          onChanged: (value) => unawaited(_show(context, value)),
        ),
        const Spacer(),
        const Text('Choosing an option presents the dialog.'),
      ],
    ),
  );
}

class _PlacedDialog extends StatelessWidget {
  const _PlacedDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 26,
    height: 6,
    child: Panel(
      title: 'PLACED DIALOG',
      focused: true,
      child: Center(
        child: Button(label: 'Close', autofocus: true, onPressed: context.pop),
      ),
    ),
  );
}

Widget backGuardDemoApp() =>
    const FleuryApp(title: 'Guarding back', home: BackGuardHome());

class BackGuardHome extends StatefulWidget {
  const BackGuardHome({super.key});

  @override
  State<BackGuardHome> createState() => _BackGuardHomeState();
}

class _BackGuardHomeState extends State<BackGuardHome> {
  String _savedText = 'Release notes';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DRAFTS'),
        Text('saved: $_savedText'),
        const SizedBox(height: 1),
        Button(
          label: 'Edit draft',
          autofocus: true,
          onPressed: () => context.push<void>(
            GuardedEditor(
              initialText: _savedText,
              onSave: (value) => setState(() => _savedText = value),
            ),
          ),
        ),
      ],
    ),
  );
}

class GuardedEditor extends StatefulWidget {
  const GuardedEditor({
    required this.initialText,
    required this.onSave,
    super.key,
  });

  final String initialText;
  final void Function(String) onSave;

  @override
  State<GuardedEditor> createState() => _GuardedEditorState();
}

class _GuardedEditorState extends State<GuardedEditor> {
  late final TextEditingController _controller;
  late String _savedText;
  bool _dirty = false;
  String _status = 'No unsaved changes';

  @override
  void initState() {
    super.initState();
    _savedText = widget.initialText;
    _controller = TextEditingController(text: _savedText);
  }

  void _handleChanged(String value) {
    final dirty = value != _savedText;
    setState(() {
      _dirty = dirty;
      _status = dirty ? 'Unsaved changes' : 'No unsaved changes';
    });
  }

  void _save() {
    final value = _controller.text;
    widget.onSave(value);
    setState(() {
      _savedText = value;
      _dirty = false;
      _status = 'Saved — back is allowed';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onBlocked: () => setState(() => _status = 'Back blocked — save first'),
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EDITOR'),
          Text('status: $_status'),
          const SizedBox(height: 1),
          TextInput(
            autofocus: true,
            semanticLabel: 'Draft text',
            controller: _controller,
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 1),
          Button(
            label: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Button(label: 'Save', onPressed: _save),
          Button(label: 'Discard', onPressed: context.pop),
        ],
      ),
    ),
  );
}

Widget transitionDemoApp() =>
    const FleuryApp(title: 'Route transitions', home: TransitionDemo());

enum TransitionKind { fade, slide, none }

class TransitionDemo extends StatefulWidget {
  const TransitionDemo({super.key});

  @override
  State<TransitionDemo> createState() => _TransitionDemoState();
}

class _TransitionDemoState extends State<TransitionDemo> {
  TransitionKind _kind = TransitionKind.slide;

  RouteTransition get _transition => switch (_kind) {
    TransitionKind.fade => RouteTransition.fade,
    TransitionKind.slide => RouteTransition.slide,
    TransitionKind.none => RouteTransition.none,
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ROUTE TRANSITIONS'),
        const SizedBox(height: 1),
        Select<TransitionKind>(
          semanticLabel: 'Transition',
          autofocus: true,
          value: _kind,
          options: const [
            SelectOption(value: TransitionKind.fade, label: 'Fade'),
            SelectOption(value: TransitionKind.slide, label: 'Slide'),
            SelectOption(value: TransitionKind.none, label: 'None'),
          ],
          onChanged: (value) => setState(() => _kind = value),
        ),
        Button(
          label: 'Preview push',
          onPressed: () => context.push<void>(
            TransitionScreen(kind: _kind),
            transition: _transition,
          ),
        ),
      ],
    ),
  );
}

class TransitionScreen extends StatelessWidget {
  const TransitionScreen({required this.kind, super.key});

  final TransitionKind kind;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${kind.name.toUpperCase()} · PUSHED SCREEN'),
        const Spacer(),
        Button(label: 'Preview pop', autofocus: true, onPressed: context.pop),
      ],
    ),
  );
}

Widget nestedFlowDemoApp() => const FleuryApp(
  title: 'Embedded flow',
  home: ProjectsScreen(), // FleuryApp inserts the outer Navigator.
);

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Button(
      label: 'Start setup',
      onPressed: () => context.push<void>(const SetupFlow()),
    ),
  );
}

class SetupFlow extends StatelessWidget {
  const SetupFlow({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('SETUP · OUTER ROUTE'),
        const SizedBox(height: 1),
        Expanded(
          child: Panel(
            title: 'INNER FLOW',
            child: Navigator(
              transition: RouteTransition.none,
              home: const SetupStep(step: 1),
            ),
          ),
        ),
        const SizedBox(height: 1),
        const Text('All three steps belong to this one outer route.'),
      ],
    ),
  );
}

class SetupStep extends StatelessWidget {
  const SetupStep({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STEP $step OF 3'),
        Text(switch (step) {
          1 => 'Choose a project',
          2 => 'Configure access',
          _ => 'Review and finish',
        }),
        const Spacer(),
        if (step < 3)
          Button(
            label: 'Next step',
            autofocus: true,
            onPressed: () => context.push<void>(SetupStep(step: step + 1)),
          )
        else
          Button(
            label: 'Finish setup',
            autofocus: true,
            onPressed: () => context.rootNavigator.pushReplacement<void>(
              const ProjectReadyScreen(),
            ),
          ),
        if (step > 1) Button(label: 'Previous', onPressed: context.pop),
      ],
    ),
  );
}

class ProjectReadyScreen extends StatelessWidget {
  const ProjectReadyScreen({super.key});

  @override
  Widget build(BuildContext context) => Button(
    label: 'Back to projects',
    autofocus: true,
    onPressed: context.pop,
  );
}
