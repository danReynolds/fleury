// End-to-end MCP tests: spawn real Fleury apps as subprocesses, attach over
// the live remote wire, and drive them — through the bridge directly and
// through the full McpServer (the same JSON-RPC an agent host speaks).
// These exercise the actual socket, the real app's semantics, and the real
// SemanticAction dispatch closing back to a re-render.
//
// The README's own counter (test/fixtures/readme_counter_app.dart, which must
// match the README's Dart fence) is spawned once. It serves the socket check
// and keeps the README's "What the agent sees" example real server output.
//
// Tagged `integration` (per dart_test.yaml) since they spawn `dart run` and
// take seconds: `dart test -x integration` excludes them. They run by default.
@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_host_io.dart'
    show SpawnedFleuryApp, spawnFleuryApp;
import 'package:fleury/fleury_wire_io.dart' show UnixSocketFrameTransport;
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  final fixture = _fixturePath();

  group('the README counter', () {
    late String readme;
    late String readmeApp;
    late Directory dir;
    late String socketPath;
    late SpawnedFleuryApp app;
    late FleuryAppBridge bridge;

    setUpAll(() async {
      final root = await _packageRoot();
      readme = File('$root/README.md').readAsStringSync();
      readmeApp = '$root/test/fixtures/readme_counter_app.dart';
      dir = Directory.systemTemp.createTempSync('spawn-refuse-');
      socketPath = '${dir.path}/app.sock';
      app = await spawnFleuryApp(
        command: <String>['dart', 'run', readmeApp],
        socketPath: socketPath,
      );
      bridge = FleuryAppBridge(
        UnixSocketFrameTransport.fromSocket(app.socket),
        onClose: app.dispose,
      )..start();
      await bridge.ready;
    });

    tearDownAll(() async {
      await bridge.close();
      dir.deleteSync(recursive: true);
    });

    test('is the README app', () {
      final source = File(readmeApp).readAsStringSync();
      final firstImport = source.indexOf(
        "import 'package:fleury/fleury.dart';",
      );

      expect(firstImport, isNonNegative);
      expect(
        _fenceAfter(readme, '## Your app needs no MCP code', 'dart').trim(),
        source.substring(firstImport).trim(),
      );
    });

    test(
      'spawnFleuryApp refuses a second connection once the app has attached',
      () async {
        // The app connected; the listening socket was closed after the first
        // accept, so a second (rogue) connection to the same path is refused —
        // not silently queued in the OS backlog as before.
        await expectLater(
          Socket.connect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
          ),
          throwsA(isA<SocketException>()),
        );
      },
    );

    test('find_nodes for its button returns the README example', () async {
      final out = <String>[];
      final server = McpServer(bridge: bridge, send: out.add);
      await server.handleLine(
        _rpc(1, 'initialize', <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
        }),
      );
      await server.handleLine(
        _rpc(2, 'tools/call', <String, Object?>{
          'name': 'find_nodes',
          'arguments': <String, Object?>{'role': 'button'},
        }),
      );
      final reply = out
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .singleWhere((message) => message['id'] == 2);
      final result = reply['result'] as Map<String, Object?>;

      expect(result['isError'], isFalse);
      // The README shows every key, in order; `…` stands for text it shortens.
      _expectDocumented(
        jsonDecode(_fenceAfter(readme, '## What the agent sees', 'json')),
        result['structuredContent'],
        'find_nodes result',
      );
    });
  });

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

/// Expects [actual] to be the [documented] JSON, where `…` in a documented
/// string matches any text. [path] locates a mismatch in the failure.
void _expectDocumented(Object? documented, Object? actual, String path) {
  switch (documented) {
    case Map<String, Object?>():
      expect(actual, isA<Map<String, Object?>>(), reason: path);
      final object = actual! as Map<String, Object?>;
      expect(
        object.keys.toList(),
        documented.keys.toList(),
        reason: '$path: the README must show every key, in order',
      );
      for (final MapEntry(:key, :value) in documented.entries) {
        _expectDocumented(value, object[key], '$path.$key');
      }
    case List<Object?>():
      expect(actual, isA<List<Object?>>(), reason: path);
      final list = actual! as List<Object?>;
      expect(list, hasLength(documented.length), reason: path);
      for (var i = 0; i < documented.length; i++) {
        _expectDocumented(documented[i], list[i], '$path[$i]');
      }
    case String() when documented.contains('…'):
      final pattern = RegExp(
        '^${documented.split('…').map(RegExp.escape).join('.*')}\$',
        dotAll: true,
      );
      expect(actual, isA<String>(), reason: path);
      expect(
        pattern.hasMatch(actual! as String),
        isTrue,
        reason: '$path: "$actual" does not match "$documented"',
      );
    default:
      expect(actual, documented, reason: path);
  }
}

/// The body of the first [language] fence in [markdown]'s [heading] section.
String _fenceAfter(String markdown, String heading, String language) {
  final start = markdown.indexOf('\n$heading\n');
  if (start < 0) throw StateError('No "$heading" section');
  final next = markdown.indexOf('\n## ', start + heading.length + 1);
  final section = markdown.substring(start, next < 0 ? null : next);
  final fence = RegExp('```$language\\n([\\s\\S]*?)\\n```').firstMatch(section);
  if (fence == null) throw StateError('No $language fence under "$heading"');
  return fence.group(1)!;
}

/// This package's root, wherever the test runner was started.
Future<String> _packageRoot() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:fleury_mcp/fleury_mcp.dart'),
  );
  if (library == null) throw StateError('package:fleury_mcp does not resolve');
  return File.fromUri(library).parent.parent.path;
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
