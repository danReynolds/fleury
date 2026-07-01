// A tiny, deterministic Fleury app used by the MCP integration tests. It is
// spawned as a subprocess by FleuryAppBridge.spawn (which sets FLEURY_HANDLE,
// so runTui auto-connects over the remote wire). The UI is built entirely from
// `Semantics` widgets with stable ids so a test can target nodes precisely:
//
//   • count      — text node whose value is the running count
//   • increment  — button advertising `activate`; bumps the count
//   • reset      — button advertising `activate`; zeroes the count

import 'package:fleury/fleury.dart';

void main() {
  runTui(const CounterApp());
}

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          id: const SemanticNodeId('count'),
          role: SemanticRole.text,
          label: 'Count',
          value: _count,
          child: Text('Count: $_count'),
        ),
        Semantics(
          id: const SemanticNodeId('increment'),
          role: SemanticRole.button,
          label: 'Increment',
          actions: const <SemanticAction>{SemanticAction.activate},
          onAction: (_) => setState(() => _count++),
          child: const Text('[ Increment ]'),
        ),
        Semantics(
          id: const SemanticNodeId('reset'),
          role: SemanticRole.button,
          label: 'Reset',
          actions: const <SemanticAction>{SemanticAction.activate},
          onAction: (_) => setState(() => _count = 0),
          child: const Text('[ Reset ]'),
        ),
      ],
    );
  }
}
