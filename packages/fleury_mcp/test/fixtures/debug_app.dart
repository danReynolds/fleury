// A deterministic Fleury app for the MCP debug-accuracy e2e. Spawned by
// FleuryAppBridge.spawn (which sets FLEURY_HANDLE, so runApp auto-connects over
// the remote wire). Under `dart run` the debug tooling is enabled by default
// (dart.vm.product is false), so the debug channel — read_frames / read_logs /
// read_errors — is live.
//
// Three semantic buttons, each producing one kind of debug signal an agent can
// then read back:
//
//   • tick  — setState() → a real render → a frame in read_frames
//   • log   — print()s   → captured stdout in read_logs
//   • boom  — throws      → caught + reported → an entry in read_errors

import 'package:fleury/fleury.dart';

void main() {
  runApp(const DebugApp());
}

class DebugApp extends StatefulWidget {
  const DebugApp({super.key});

  @override
  State<DebugApp> createState() => _DebugAppState();
}

class _DebugAppState extends State<DebugApp> {
  int _ticks = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          id: const SemanticNodeId('ticks'),
          role: SemanticRole.text,
          label: 'Ticks',
          value: _ticks,
          child: Text('ticks: $_ticks'),
        ),
        Semantics(
          id: const SemanticNodeId('tick'),
          role: SemanticRole.button,
          label: 'Tick',
          actions: const <SemanticAction>{SemanticAction.activate},
          onAction: (_) => setState(() => _ticks++),
          child: const Text('[ tick ]'),
        ),
        Semantics(
          id: const SemanticNodeId('log'),
          role: SemanticRole.button,
          label: 'Log',
          actions: const <SemanticAction>{SemanticAction.activate},
          onAction: (_) {
            for (var i = 1; i <= 3; i++) {
              print('debug-app: log line $i');
            }
          },
          child: const Text('[ log ]'),
        ),
        Semantics(
          id: const SemanticNodeId('boom'),
          role: SemanticRole.button,
          label: 'Boom',
          actions: const <SemanticAction>{SemanticAction.activate},
          // Uncaught on purpose: runApp's per-boundary containment reports it to
          // the error history (read_errors) and keeps the app running.
          onAction: (_) => throw StateError('debug-app: boom'),
          child: const Text('[ boom ]'),
        ),
      ],
    );
  }
}
