// End-to-end MCP tests: spawn the real counter fixture as a subprocess, attach
// over the live remote wire, and drive it — first through the bridge directly,
// then through the full McpServer (the same JSON-RPC an agent host speaks).
// These exercise the actual socket, the real app's semantics, and the real
// SemanticAction dispatch closing back to a re-render.
//
// Tagged `integration` (per dart_test.yaml) since they spawn `dart run` and
// take seconds: `dart test -x integration` excludes them. They run by default.
@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  final fixture = _fixturePath();

  test(
    'bridge spawns a real app, reads its tree, and drives an action',
    () async {
      final bridge = await FleuryAppBridge.spawn(
        command: <String>['dart', 'run', fixture],
        viewport: const CellSize(80, 24),
        log: (_) {},
      );
      addTearDown(bridge.close);

      await bridge.ready;
      expect(bridge.isRunning, isTrue);
      final initial = bridge.snapshot;
      expect(initial, isNotNull, reason: 'app should render a first frame');

      final increment = initial!.single(role: 'button', label: 'Increment');
      expect(increment.actions, contains('activate'));
      expect(initial.single(role: 'text', label: 'Count').value, 0);

      final before = bridge.revision;
      bridge.invokeAction(
        const SemanticNodeId('increment'),
        SemanticAction.activate,
      );
      final after = await bridge.settle(sinceRevision: before);

      expect(after, isNotNull);
      expect(after!.single(role: 'text', label: 'Count').value, 1);

      // And again — the loop is repeatable.
      final before2 = bridge.revision;
      bridge.invokeAction(
        const SemanticNodeId('increment'),
        SemanticAction.activate,
      );
      final after2 = await bridge.settle(sinceRevision: before2);
      expect(after2!.single(role: 'text', label: 'Count').value, 2);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'an MCP client drives the app end-to-end over stdio JSON-RPC',
    () async {
      final bridge = await FleuryAppBridge.spawn(
        command: <String>['dart', 'run', fixture],
        log: (_) {},
      );
      addTearDown(bridge.close);
      await bridge.ready;

      final out = <String>[];
      final server = McpServer(bridge: bridge, send: out.add);

      await server.handleLine(
        _rpc(1, 'initialize', <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
        }),
      );
      final init = jsonDecode(out.removeLast()) as Map<String, Object?>;
      expect(
        (init['result'] as Map<String, Object?>)['serverInfo'],
        isA<Map<String, Object?>>(),
      );

      await server.handleLine(
        _rpc(2, 'tools/call', <String, Object?>{
          'name': 'get_ui',
          'arguments': <String, Object?>{},
        }),
      );
      final ui = _toolJson(out.removeLast());
      expect(jsonEncode(ui), contains('"id":"increment"'));

      await server.handleLine(
        _rpc(3, 'tools/call', <String, Object?>{
          'name': 'invoke_action',
          'arguments': <String, Object?>{
            'id': 'increment',
            'action': 'activate',
          },
        }),
      );
      final invoked = _toolJson(out.removeLast());
      expect(invoked['changed'], isTrue);
      expect(jsonEncode(invoked['ui']), contains('"value":1'));

      // reset via its advertised action zeroes the count.
      await server.handleLine(
        _rpc(4, 'tools/call', <String, Object?>{
          'name': 'invoke_action',
          'arguments': <String, Object?>{'id': 'reset', 'action': 'activate'},
        }),
      );
      final reset = _toolJson(out.removeLast());
      expect(jsonEncode(reset['ui']), contains('"value":0'));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

String _rpc(int id, String method, [Map<String, Object?>? params]) {
  return jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': ?params,
  });
}

Map<String, Object?> _toolJson(String line) {
  final result =
      (jsonDecode(line) as Map<String, Object?>)['result']
          as Map<String, Object?>;
  expect(result['isError'], isFalse);
  final content = (result['content'] as List).single as Map<String, Object?>;
  return jsonDecode(content['text'] as String) as Map<String, Object?>;
}

/// Resolves the counter fixture to an absolute path so `dart run` works
/// regardless of the test runner's working directory.
String _fixturePath() {
  const rel = 'test/fixtures/counter_app.dart';
  final candidates = <String>[
    '${Directory.current.path}/$rel',
    '${Directory.current.path}/packages/fleury_mcp/$rel',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError(
    'counter_app.dart fixture not found from ${Directory.current.path}',
  );
}
