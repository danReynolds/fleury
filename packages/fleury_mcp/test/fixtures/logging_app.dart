// A tiny Fleury app that ALSO writes known lines to stdout and stderr at
// startup, so the host-e2e logging smoke can assert the app's own output is
// forwarded to the MCP client as notifications/message (stdout → info, stderr →
// warning). Renders one labelled node so the bridge has a tree to serve.
//
// Spawned as a subprocess by the real `fleury_mcp` binary (which sets
// FLEURY_HANDLE, so runTui auto-connects over the remote wire). The app's
// stdout/stderr is its LOG output — separate from the render wire (the socket)
// and from the binary's own JSON-RPC stdout.

import 'dart:io';

import 'package:fleury/fleury.dart';

void main() {
  // The markers the smoke asserts on: stdout is forwarded at `info`, stderr at
  // `warning`. Printed before runTui so they exercise the pre-handshake hold.
  stdout.writeln('FLEURY_LOG_OUT hello from app stdout');
  stderr.writeln('FLEURY_LOG_ERR uh-oh from app stderr');
  runTui(const _LoggingApp());
}

class _LoggingApp extends StatelessWidget {
  const _LoggingApp();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      id: const SemanticNodeId('label'),
      role: SemanticRole.text,
      label: 'Ready',
      child: const Text('ready'),
    );
  }
}
