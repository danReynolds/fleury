// Host-process end-to-end test: spawn the REAL `fleury_mcp` binary as a
// subprocess and talk to it the way an MCP host does — newline-delimited
// JSON-RPC 2.0 over its stdin/stdout — driving a real Fleury app behind it.
//
// This exercises the actual process boundary an MCP host (Claude Desktop,
// Claude Code, …) uses: the full `initialize` → `notifications/initialized` →
// `tools/list` → `tools/call` → `resources/read` handshake, end to end, with no
// in-process shortcuts. It is the regression that asserts host compatibility
// going forward.
//
// Tagged `integration` (it cold-spawns two `dart run` processes); runs by
// default, excludable with `dart test -x integration`.
@Tags(<String>['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final binary = _resolve('bin/fleury_mcp.dart');
  final fixture = _resolve('test/fixtures/counter_app.dart');

  test(
    'the real fleury_mcp binary speaks MCP over stdio to a host',
    () async {
      final process = await Process.start('dart', <String>[
        'run',
        binary,
        '--',
        'dart',
        'run',
        fixture,
      ]);
      final client = _McpStdioClient(process);
      addTearDown(client.close);

      // initialize → server identifies itself and negotiates the version.
      final init = await client.request(1, 'initialize', <String, Object?>{
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{'name': 'e2e-host', 'version': '1'},
      });
      final initResult = init['result'] as Map<String, Object?>;
      expect(initResult['protocolVersion'], '2025-06-18');
      expect(
        (initResult['serverInfo'] as Map<String, Object?>)['name'],
        'fleury',
      );
      client.notify('notifications/initialized');

      // tools/list → the full driving surface is advertised.
      final tools = await client.request(2, 'tools/list');
      final names = ((tools['result'] as Map<String, Object?>)['tools'] as List)
          .map((t) => (t as Map<String, Object?>)['name'])
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'get_ui',
          'find_nodes',
          'invoke_action',
          'type_text',
          'press_key',
          'resize',
          'wait_for_change',
        ]),
      );

      // get_ui → the real app's semantic tree, with the button and its action.
      final ui = _toolJson(
        await client.request(3, 'tools/call', <String, Object?>{
          'name': 'get_ui',
          'arguments': <String, Object?>{},
        }),
      );
      expect(jsonEncode(ui), contains('"id":"increment"'));
      expect(jsonEncode(ui), contains('"activate"'));

      // invoke_action → the count actually changes through a real re-render.
      final invoked = _toolJson(
        await client.request(4, 'tools/call', <String, Object?>{
          'name': 'invoke_action',
          'arguments': <String, Object?>{
            'id': 'increment',
            'action': 'activate',
          },
        }),
      );
      expect(invoked['changed'], isTrue);
      expect(jsonEncode(invoked['ui']), contains('"value":1'));

      // resources/read → the same tree is available as the resource.
      final read = await client.request(5, 'resources/read', <String, Object?>{
        'uri': 'fleury://ui/tree',
      });
      final contents =
          ((read['result'] as Map<String, Object?>)['contents'] as List).single
              as Map<String, Object?>;
      final tree = jsonDecode(contents['text'] as String);
      expect(tree, isA<Map<String, Object?>>());
      expect((tree as Map<String, Object?>)['nodeCount'], greaterThan(0));
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

Map<String, Object?> _toolJson(Map<String, Object?> response) {
  final result = response['result'] as Map<String, Object?>;
  expect(result['isError'], isFalse);
  final content = (result['content'] as List).single as Map<String, Object?>;
  return jsonDecode(content['text'] as String) as Map<String, Object?>;
}

/// A minimal MCP stdio client: writes JSON-RPC requests to the server's stdin
/// and matches responses (by id) off its stdout. Models exactly what a host
/// does over the same transport.
final class _McpStdioClient {
  _McpStdioClient(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isEmpty) return;
          final message = jsonDecode(line) as Map<String, Object?>;
          final completer = _pending.remove(message['id']);
          completer?.complete(message);
        });
    // Drain stderr (server + app logs) so the pipe never blocks; keep the tail
    // for failure diagnostics.
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }

  final Process _process;
  final Map<Object?, Completer<Map<String, Object?>>> _pending =
      <Object?, Completer<Map<String, Object?>>>{};
  final StringBuffer _stderr = StringBuffer();

  Future<Map<String, Object?>> request(
    Object id,
    String method, [
    Map<String, Object?>? params,
  ]) {
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _process.stdin.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    return completer.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () => throw StateError(
        'No response to $method (id $id) within 40s.\n--- server stderr ---\n'
        '$_stderr',
      ),
    );
  }

  void notify(String method, [Map<String, Object?>? params]) {
    _process.stdin.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'method': method,
        'params': ?params,
      }),
    );
  }

  Future<void> close() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    await _process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -9;
      },
    );
  }
}

/// Resolves a package-relative path to absolute so `dart run` works regardless
/// of the test runner's working directory.
String _resolve(String rel) {
  final candidates = <String>[
    '${Directory.current.path}/$rel',
    '${Directory.current.path}/packages/fleury_mcp/$rel',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError('$rel not found from ${Directory.current.path}');
}
