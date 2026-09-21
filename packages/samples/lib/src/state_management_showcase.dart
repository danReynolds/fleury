import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

/// Application state that can also be read or changed by a service or controller.
class StateManagementCart extends Notifier {
  int _itemCount = 0;

  int get itemCount => _itemCount;

  void addItem() {
    _itemCount++;
    notify();
  }
}

/// Three small, independent examples of local, tree, and application state.
///
/// Pass an application-owned [cart] to share it with code outside the tree.
/// The showcase borrows that model. Without one, it owns an isolated model for
/// its mounted lifetime, so browser previews do not share state with each other.
class StateManagementShowcaseApp extends StatefulWidget {
  const StateManagementShowcaseApp({super.key, this.cart});

  final StateManagementCart? cart;

  @override
  State<StateManagementShowcaseApp> createState() =>
      _StateManagementShowcaseAppState();
}

class _StateManagementShowcaseAppState
    extends State<StateManagementShowcaseApp> {
  StateManagementCart? _ownedCart;

  @override
  void dispose() {
    _ownedCart?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart ?? (_ownedCart ??= StateManagementCart());
    return SampleScaffold(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('STATE MANAGEMENT', style: CellStyle(bold: true)),
            const Text(
              'One widget, shared descendants, or an app-owned model.',
            ),
            const SizedBox(height: 1),
            const _LocalCounter(),
            const SizedBox(height: 1),
            const _ProjectPicker(),
            const SizedBox(height: 1),
            _CartPanel(cart: cart),
            const SizedBox(height: 1),
            const Text('Tab moves · Enter activates · Click any button'),
          ],
        ),
      ),
    );
  }
}

class _LocalCounter extends StatefulWidget {
  const _LocalCounter();

  @override
  State<_LocalCounter> createState() => _LocalCounterState();
}

class _LocalCounterState extends State<_LocalCounter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Panel(
    title: 'Local · setState',
    expandChild: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Count: $_count'),
        Button(
          text: 'Increment',
          autofocus: true,
          onPressed: () => setState(() => _count++),
        ),
      ],
    ),
  );
}

class _Project {
  const _Project(this.name);

  final String name;
}

class _ProjectPicker extends StatefulWidget {
  const _ProjectPicker();

  @override
  State<_ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<_ProjectPicker> {
  var _project = const _Project('Atlas');

  void _switchProject() => setState(() {
    _project = _project.name == 'Atlas'
        ? const _Project('Beacon')
        : const _Project('Atlas');
  });

  @override
  Widget build(BuildContext context) => Panel(
    title: 'Tree · Scope',
    expandChild: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Scope(_project, child: const _ProjectReaders()),
        Button(text: 'Switch project', onPressed: _switchProject),
      ],
    ),
  );
}

// Neither descendant receives a Project constructor argument.
class _ProjectReaders extends StatelessWidget {
  const _ProjectReaders();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      ScopeBuilder<_Project>(
        builder: (context, project) => Text('Project: ${project.name}'),
      ),
      const _ProjectSummary(),
    ],
  );
}

class _ProjectSummary extends StatelessWidget {
  const _ProjectSummary();

  @override
  Widget build(BuildContext context) {
    final project = context.scope<_Project>();
    return Text('Active project: ${project.name}');
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({required this.cart});

  final StateManagementCart cart;

  @override
  Widget build(BuildContext context) => Panel(
    title: 'Global · Notifier',
    expandChild: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NotifierBuilder(
          notifier: cart,
          builder: (context, cart) => Text('Items: ${cart.itemCount}'),
        ),
        _CartSummary(cart: cart),
        Button(text: 'Add item', onPressed: cart.addItem),
      ],
    ),
  );
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({required this.cart});

  final StateManagementCart cart;

  @override
  Widget build(BuildContext context) {
    final model = context.listen(cart);
    return Text('Cart summary: ${model.itemCount} items');
  }
}
