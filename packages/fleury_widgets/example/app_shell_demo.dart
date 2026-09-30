// A small, production-shaped Fleury app: one app shell, widget routes, and
// commands shared by shortcuts, the command palette, and semantic drivers.
//
// Run (from the repository root):
//
//   dart tool/fleury_dev.dart widget-demo app-shell
//
// Keys:
//   Ctrl+K   open the command palette
//   Ctrl+O   open the production deployment
//   Ctrl+R   refresh the active deployment (detail screen only)
//   Esc      go back / dismiss
//   Ctrl+C   quit

import 'dart:async' show unawaited;

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

const _openPaletteId = CommandId('app.open-palette');
const _openProductionId = CommandId('deployment.open-production');
const _refreshProductionId = CommandId('deployment.refresh-production');

Future<void> main() => runApp(const AppShellDemo());

/// Canonical multi-screen, command-driven Fleury example.
class AppShellDemo extends StatelessWidget {
  const AppShellDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return FleuryApp(
      title: 'Fleury Launchpad',
      theme: ThemeData.dark(),
      commands: <AppCommand>[
        AppCommand(
          id: _openPaletteId,
          title: 'Commands',
          description: 'Search app-wide and active-screen commands',
          category: 'Application',
          shortcuts: <KeySequence>[KeySequence.ctrl.k],
          showInPalette: false,
          semanticAction: SemanticAction.open,
          run: (command) {
            final source = command.buildContext;
            if (source != null) unawaited(CommandPalette.open(source));
          },
        ),
      ],
      status: (_) => <StatusItem>[
        StatusItem.success('Production', id: 'environment', value: 'healthy'),
      ],
      home: const _DeploymentsScreen(),
    );
  }
}

class _DeploymentsScreen extends StatelessWidget {
  const _DeploymentsScreen();

  void _openProduction(BuildContext context) {
    unawaited(
      context.push<void>(
        const _DeploymentScreen(),
        transition: RouteTransition.slide,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommandScope(
      label: 'Deployment commands',
      commands: <AppCommand>[
        AppCommand(
          id: _openProductionId,
          title: 'Open production',
          description: 'Show the current production deployment',
          category: 'Navigation',
          shortcuts: <KeySequence>[KeySequence.ctrl.o],
          semanticAction: SemanticAction.navigate,
          run: (command) {
            final source = command.buildContext;
            if (source != null) _openProduction(source);
          },
        ),
      ],
      child: _ScreenLayout(
        children: <Widget>[
          const Text('Fleury Launchpad', style: CellStyle(bold: true)),
          const Text(
            'Commands, shortcuts, and routes stay in sync.',
            style: CellStyle(dim: true),
          ),
          const SizedBox(height: 1),
          const Text('Production deployment'),
          const Text('api · v1.12.0 · healthy', style: CellStyle(dim: true)),
          const SizedBox(height: 1),
          Button(
            text: 'Open production',
            autofocus: true,
            variant: ButtonVariant.primary,
            onPressed: () => _openProduction(context),
          ),
        ],
      ),
    );
  }
}

class _DeploymentScreen extends StatefulWidget {
  const _DeploymentScreen();

  @override
  State<_DeploymentScreen> createState() => _DeploymentScreenState();
}

class _DeploymentScreenState extends State<_DeploymentScreen> {
  var _refreshCount = 0;

  void _refresh() => setState(() => _refreshCount += 1);

  @override
  Widget build(BuildContext context) {
    return CommandScope(
      label: 'Production deployment commands',
      commands: <AppCommand>[
        AppCommand(
          id: _refreshProductionId,
          title: 'Refresh status',
          description: 'Fetch the latest production status',
          category: 'Deployment',
          shortcuts: <KeySequence>[KeySequence.ctrl.r],
          run: (_) => _refresh(),
        ),
      ],
      child: _ScreenLayout(
        children: <Widget>[
          const Text('Production deployment', style: CellStyle(bold: true)),
          const Text('api · v1.12.0', style: CellStyle(dim: true)),
          const SizedBox(height: 1),
          const Text('status: healthy'),
          Text('refreshes: $_refreshCount'),
          const SizedBox(height: 1),
          Button(text: 'Refresh status', autofocus: true, onPressed: _refresh),
          Button(text: 'Back', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}

/// Keep app chrome visible while the screen body can scroll in a short terminal.
class _ScreenLayout extends StatelessWidget {
  const _ScreenLayout({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ScrollView(
            scrollbar: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        const AppStatusBar(),
        const KeyHintBar(style: CellStyle(dim: true)),
      ],
    ),
  );
}
