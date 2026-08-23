// Compile-checked source behind the State management guide. It gives one
// ChangeNotifier model a clear owner and demonstrates constructor-based and
// inherited access to the same model.
//
// Run it:  dart run doc_snippets/shared_state.dart

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(stateManagementDemoApp());

Widget localStateDemoApp() =>
    const FleuryApp(title: 'Counter', home: LocalCounter());

Widget sharedStateDemoApp() =>
    const FleuryApp(title: 'Shared counter', home: SharedCounter());

Widget valueNotifierDemoApp() =>
    const FleuryApp(title: 'Connection', home: ConnectionPanel());

Widget stateManagementDemoApp() =>
    const FleuryApp(title: 'Deployment', home: DeploymentScreen());

Widget inheritedStateDemoApp() =>
    const FleuryApp(title: 'Workspace', home: ScopedDeploymentScreen());

class LocalCounter extends StatefulWidget {
  const LocalCounter({super.key});

  @override
  State<LocalCounter> createState() => _LocalCounterState();
}

class _LocalCounterState extends State<LocalCounter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Count: $count'),
        Button(label: 'Increment', onPressed: () => setState(() => count++)),
      ],
    ),
  );
}

class SharedCounter extends StatefulWidget {
  const SharedCounter({super.key});

  @override
  State<SharedCounter> createState() => _SharedCounterState();
}

class _SharedCounterState extends State<SharedCounter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CounterValue(value: count),
        CounterButton(onPressed: () => setState(() => count++)),
      ],
    ),
  );
}

class CounterValue extends StatelessWidget {
  const CounterValue({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) => Text('Count: $value');
}

class CounterButton extends StatelessWidget {
  const CounterButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      Button(label: 'Increment', onPressed: onPressed);
}

class ConnectionService {
  final online = ValueNotifier<bool>(false);

  void toggle() => online.value = !online.value;

  void dispose() => online.dispose();
}

class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({super.key});

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  final connection = ConnectionService();

  @override
  void dispose() {
    connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: ValueListenableBuilder<bool>(
      valueListenable: connection.online,
      builder: (context, online, child) => Row(
        children: <Widget>[
          Text(online ? 'Online' : 'Offline'),
          Button(
            label: online ? 'Disconnect' : 'Connect',
            onPressed: connection.toggle,
          ),
        ],
      ),
    ),
  );
}

class Deployment extends ChangeNotifier {
  int _completed = 1;
  bool _paused = false;

  int get completed => _completed;
  bool get paused => _paused;

  void completeNext() {
    if (_paused || _completed == 3) return;
    _completed++;
    notifyListeners();
  }

  void togglePaused() {
    _paused = !_paused;
    notifyListeners();
  }
}

class DeploymentScreen extends StatefulWidget {
  const DeploymentScreen({super.key});

  @override
  State<DeploymentScreen> createState() => _DeploymentScreenState();
}

class _DeploymentScreenState extends State<DeploymentScreen> {
  final _deployment = Deployment();

  @override
  void dispose() {
    _deployment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DeploymentView(deployment: _deployment);
}

class DeploymentView extends StatelessWidget {
  const DeploymentView({super.key, required this.deployment});

  final Deployment deployment;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: deployment,
    builder: (context, child) => Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('DEPLOYMENT', style: CellStyle(bold: true)),
          Text('${deployment.completed} of 3 complete'),
          Text(deployment.paused ? 'Paused' : 'Running'),
          Button(label: 'Complete next', onPressed: deployment.completeNext),
          Button(
            label: deployment.paused ? 'Resume' : 'Pause',
            onPressed: deployment.togglePaused,
          ),
        ],
      ),
    ),
  );
}

class DeploymentScope extends InheritedNotifier<Deployment> {
  const DeploymentScope({
    super.key,
    required Deployment deployment,
    required super.child,
  }) : super(notifier: deployment);

  static Deployment watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeploymentScope>()!.notifier;

  static Deployment read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DeploymentScope>()!.notifier;
}

class ScopedDeploymentScreen extends StatefulWidget {
  const ScopedDeploymentScreen({super.key});

  @override
  State<ScopedDeploymentScreen> createState() => _ScopedDeploymentScreenState();
}

class _ScopedDeploymentScreenState extends State<ScopedDeploymentScreen> {
  final _deployment = Deployment();

  @override
  void dispose() {
    _deployment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DeploymentScope(deployment: _deployment, child: const Workspace());
}

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('WORKSPACE', style: CellStyle(bold: true)),
        const WorkspaceBody(),
        Button(
          label: 'Complete next',
          onPressed: () => DeploymentScope.read(context).completeNext(),
        ),
      ],
    ),
  );
}

class WorkspaceBody extends StatelessWidget {
  const WorkspaceBody({super.key});

  @override
  Widget build(BuildContext context) => const NestedDeploymentStatus();
}

class NestedDeploymentStatus extends StatelessWidget {
  const NestedDeploymentStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final deployment = DeploymentScope.watch(context);
    return Text('${deployment.completed} of 3 complete');
  }
}
