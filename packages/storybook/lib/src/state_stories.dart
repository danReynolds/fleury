import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

import 'story.dart';

/// State APIs share focused scenarios while retaining separate catalog entries.
final List<Story> stateStories = <Story>[
  Story(
    id: 'state.tree',
    title: 'Shared project',
    category: 'State',
    description:
        'Share a plain project through Scope. Switch projects and watch two '
        'descendants update without passing the project through constructors.',
    widgets: const <String>['Scope', 'ScopeBuilder'],
    controls: const <StoryControl>[_readerControl],
    variants: const <StoryVariant>[_contextVariant],
    usage: 'Activate Switch project to update both readers',
    initialHeight: 8,
    builder: (context) => _ProjectStory(
      contextReader: context.option('reader') == 'BuildContext',
      onAction: context.action,
    ),
  ),
  Story(
    id: 'state.model',
    title: 'Observable cart',
    category: 'State',
    description:
        'A cart publishes changes with Notifier.notify. The model is passed to '
        'its reader; adding an item does not call setState.',
    widgets: const <String>['Notifier', 'NotifierBuilder'],
    controls: const <StoryControl>[_readerControl],
    variants: const <StoryVariant>[_contextVariant],
    usage: 'Activate Add item to notify the cart reader',
    initialHeight: 7,
    builder: (context) => _CartStory(
      contextReader: context.option('reader') == 'BuildContext',
      onAction: context.action,
    ),
  ),
  Story(
    id: 'state.value',
    title: 'Observable value',
    category: 'State',
    description:
        'ValueNotifier holds one value and publishes assignments automatically. '
        'Read it with context.listen or the same typed NotifierBuilder.',
    widgets: const <String>['ValueNotifier'],
    controls: const <StoryControl>[
      StoryControl.option(
        id: 'reader',
        label: 'Reader',
        options: <String>['Builder', 'BuildContext'],
        initialIndex: 1,
      ),
    ],
    variants: const <StoryVariant>[
      StoryVariant(
        id: 'builder-reader',
        label: 'NotifierBuilder',
        description: 'Observe the same value through a typed builder.',
        controlValues: <String, Object?>{'reader': 0},
      ),
    ],
    usage: 'Activate Add item to change count.value',
    initialHeight: 7,
    builder: (context) => _ValueStory(
      contextReader: context.option('reader') == 'BuildContext',
      onAction: context.action,
    ),
  ),
];

const _readerControl = StoryControl.option(
  id: 'reader',
  label: 'Reader',
  options: <String>['Builder', 'BuildContext'],
);

const _contextVariant = StoryVariant(
  id: 'context-reader',
  label: 'BuildContext reader',
  description: 'Read the same source directly during the descendant build.',
  controlValues: <String, Object?>{'reader': 1},
);

class _Project {
  const _Project(this.name, this.openTasks);

  final String name;
  final int openTasks;
}

class _ProjectStory extends StatefulWidget {
  const _ProjectStory({required this.contextReader, required this.onAction});

  final bool contextReader;
  final StoryActionRecorder onAction;

  @override
  State<_ProjectStory> createState() => _ProjectStoryState();
}

class _ProjectStoryState extends State<_ProjectStory> {
  var _project = const _Project('Atlas', 3);

  void _switchProject() {
    setState(() {
      _project = _project.name == 'Atlas'
          ? const _Project('Beacon', 7)
          : const _Project('Atlas', 3);
    });
    widget.onAction('project.changed', <String, Object?>{
      'project': _project.name,
      'openTasks': _project.openTasks,
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(widget.contextReader ? 'context.scope<Project>()' : 'ScopeBuilder'),
      Scope(
        _project,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ProjectName(contextReader: widget.contextReader),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _ProjectTasks(contextReader: widget.contextReader),
            ),
          ],
        ),
      ),
      Button(text: 'Switch project', onPressed: _switchProject),
    ],
  );
}

class _ProjectName extends StatelessWidget {
  const _ProjectName({required this.contextReader});

  final bool contextReader;

  @override
  Widget build(BuildContext context) {
    if (contextReader) {
      final project = context.scope<_Project>();
      return Text('Project: ${project.name}');
    }
    return ScopeBuilder<_Project>(
      builder: (context, project) => Text('Project: ${project.name}'),
    );
  }
}

class _ProjectTasks extends StatelessWidget {
  const _ProjectTasks({required this.contextReader});

  final bool contextReader;

  @override
  Widget build(BuildContext context) {
    if (contextReader) {
      final project = context.scope<_Project>();
      return Text('Open tasks: ${project.openTasks}');
    }
    return ScopeBuilder<_Project>(
      builder: (context, project) => Text('Open tasks: ${project.openTasks}'),
    );
  }
}

class _Cart extends Notifier {
  int _itemCount = 0;
  int get itemCount => _itemCount;

  void addItem() {
    _itemCount++;
    notify();
  }
}

class _CartStory extends StatefulWidget {
  const _CartStory({required this.contextReader, required this.onAction});

  final bool contextReader;
  final StoryActionRecorder onAction;

  @override
  State<_CartStory> createState() => _CartStoryState();
}

class _CartStoryState extends State<_CartStory> {
  final _cart = _Cart();

  @override
  void dispose() {
    _cart.dispose();
    super.dispose();
  }

  void _addItem() {
    _cart.addItem();
    widget.onAction('cart.add-item', <String, Object?>{
      'items': _cart.itemCount,
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(widget.contextReader ? 'context.listen(cart)' : 'NotifierBuilder'),
      _CartCount(cart: _cart, contextReader: widget.contextReader),
      Button(text: 'Add item', onPressed: _addItem),
    ],
  );
}

class _CartCount extends StatelessWidget {
  const _CartCount({required this.cart, required this.contextReader});

  final _Cart cart;
  final bool contextReader;

  @override
  Widget build(BuildContext context) {
    if (contextReader) {
      final model = context.listen(cart);
      return Text('Items: ${model.itemCount}');
    }
    return NotifierBuilder(
      notifier: cart,
      builder: (context, cart) => Text('Items: ${cart.itemCount}'),
    );
  }
}

class _ValueStory extends StatefulWidget {
  const _ValueStory({required this.contextReader, required this.onAction});

  final bool contextReader;
  final StoryActionRecorder onAction;

  @override
  State<_ValueStory> createState() => _ValueStoryState();
}

class _ValueStoryState extends State<_ValueStory> {
  final _count = ValueNotifier<int>(0);

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  void _addItem() {
    _count.value++;
    widget.onAction('count.changed', <String, Object?>{'items': _count.value});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(widget.contextReader ? 'context.listen(count)' : 'NotifierBuilder'),
      _ValueCount(count: _count, contextReader: widget.contextReader),
      Button(text: 'Add item', onPressed: _addItem),
    ],
  );
}

class _ValueCount extends StatelessWidget {
  const _ValueCount({required this.count, required this.contextReader});

  final ValueNotifier<int> count;
  final bool contextReader;

  @override
  Widget build(BuildContext context) {
    if (contextReader) {
      final value = context.listen(count).value;
      return Text('Items: $value');
    }
    return NotifierBuilder(
      notifier: count,
      builder: (context, count) => Text('Items: ${count.value}'),
    );
  }
}
