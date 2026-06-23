// Protocol-level tests for the MCP server. They drive the real McpServer and a
// real FleuryAppBridge, but over a fake in-memory transport so no subprocess is
// spawned: semantic snapshots are pushed in as SEMANTICS frames (encoded with
// the same SemanticsWireEncoder the serve host uses), and the frames the bridge
// sends back (INIT, SEMANTIC_ACTION, INPUT_EVENT) are captured and asserted.

import 'dart:async';
import 'dart:convert';

import 'package:fleury/src/mcp/app_bridge.dart';
import 'package:fleury/src/mcp/mcp_server.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:fleury/src/remote/remote_semantics.dart';
import 'package:fleury/src/remote/remote_transport.dart';
import 'package:fleury/src/semantics/inspection.dart';
import 'package:fleury/src/semantics/semantics.dart';
import 'package:fleury/src/terminal/events.dart';
import 'package:test/test.dart';

void main() {
  late _FakeTransport transport;
  late FleuryAppBridge bridge;
  late SemanticsWireEncoder encoder;
  late List<String> out;
  late McpServer server;

  setUp(() {
    transport = _FakeTransport();
    bridge = FleuryAppBridge(transport)..start();
    encoder = SemanticsWireEncoder();
    out = <String>[];
    server = McpServer(bridge: bridge, send: out.add);
  });

  tearDown(() async {
    await bridge.close();
  });

  /// Pushes a fresh semantic snapshot (counter at [count]) to the bridge.
  void pushCount(int count) {
    final snapshot = SemanticInspectionSnapshot.fromJson(_counterTree(count));
    final bytes = encoder.encode(snapshot);
    expect(bytes, isNotNull, reason: 'snapshot should differ from the last');
    transport.addIncoming(SemanticsFrame(bytes!));
  }

  /// Decodes the last response line and returns its `result` map.
  Map<String, Object?> lastResult() {
    final message = jsonDecode(out.removeLast()) as Map<String, Object?>;
    expect(message['jsonrpc'], '2.0');
    return message['result'] as Map<String, Object?>;
  }

  /// Decodes a tool-call result's single text block as JSON.
  Map<String, Object?> toolJson(Map<String, Object?> result) {
    expect(result['isError'], isFalse);
    final content = result['content'] as List;
    final text = (content.single as Map<String, Object?>)['text'] as String;
    return jsonDecode(text) as Map<String, Object?>;
  }

  test('start sends an INIT handshake at protocol v2', () {
    final init = transport.sent.whereType<InitFrame>().single;
    expect(init.protocolVersion, remoteProtocolVersion);
  });

  test('initialize advertises tools + resources and identifies the server',
      () async {
    await server.handleLine(_rpc(1, 'initialize', <String, Object?>{
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{'name': 'test', 'version': '1'},
    }));
    final result = lastResult();
    expect(result['protocolVersion'], '2025-06-18');
    expect((result['serverInfo'] as Map<String, Object?>)['name'], 'fleury');
    final caps = result['capabilities'] as Map<String, Object?>;
    expect(caps.containsKey('tools'), isTrue);
    expect(caps.containsKey('resources'), isTrue);
  });

  test('notifications get no response', () async {
    await server.handleLine(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}',
    );
    expect(out, isEmpty);
  });

  test('tools/list exposes the five driving tools with schemas', () async {
    await server.handleLine(_rpc(2, 'tools/list'));
    final tools = (lastResult()['tools'] as List).cast<Map<String, Object?>>();
    expect(
      tools.map((t) => t['name']),
      containsAll(<String>[
        'get_ui',
        'find_nodes',
        'invoke_action',
        'type_text',
        'press_key',
      ]),
    );
    for (final tool in tools) {
      expect(tool['description'], isA<String>());
      expect((tool['inputSchema'] as Map<String, Object?>)['type'], 'object');
    }
  });

  test('resources/list + resources/read expose the live tree', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(_rpc(3, 'resources/list'));
    final resources = (lastResult()['resources'] as List).cast<Map<String, Object?>>();
    expect(resources.single['uri'], 'fleury://ui/tree');

    await server.handleLine(
      _rpc(4, 'resources/read', <String, Object?>{'uri': 'fleury://ui/tree'}),
    );
    final contents = (lastResult()['contents'] as List).cast<Map<String, Object?>>();
    final tree = jsonDecode(contents.single['text'] as String) as Map<String, Object?>;
    expect(tree['nodeCount'], greaterThan(0));
  });

  test('get_ui returns the semantic tree with ids and actions', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(5, 'tools/call', <String, Object?>{
        'name': 'get_ui',
        'arguments': <String, Object?>{},
      }),
    );
    final tree = toolJson(lastResult());
    final flat = jsonEncode(tree);
    expect(flat, contains('"id":"increment"'));
    expect(flat, contains('"activate"'));
    expect(tree['focusedNodeId'], isNull);
  });

  test('find_nodes filters by role and by advertised action', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(6, 'tools/call', <String, Object?>{
        'name': 'find_nodes',
        'arguments': <String, Object?>{'role': 'button'},
      }),
    );
    final byRole = toolJson(lastResult());
    expect(byRole['matchCount'], 2);
    final ids = (byRole['nodes'] as List)
        .map((n) => (n as Map<String, Object?>)['id'])
        .toList();
    expect(ids, containsAll(<String>['increment', 'reset']));

    await server.handleLine(
      _rpc(7, 'tools/call', <String, Object?>{
        'name': 'find_nodes',
        'arguments': <String, Object?>{'label': 'incr'},
      }),
    );
    final byLabel = toolJson(lastResult());
    expect(byLabel['matchCount'], 1);
    expect(((byLabel['nodes'] as List).single as Map<String, Object?>)['id'], 'increment');
  });

  test('invoke_action sends a SEMANTIC_ACTION frame and reports the result',
      () async {
    pushCount(0);
    await bridge.ready;

    final before = bridge.revision;
    final pending = server.handleLine(
      _rpc(8, 'tools/call', <String, Object?>{
        'name': 'invoke_action',
        'arguments': <String, Object?>{'id': 'increment', 'action': 'activate'},
      }),
    );
    // The app reacts to the activation: count climbs to 1.
    pushCount(1);
    await pending;

    final action = transport.sent.whereType<SemanticActionFrame>().single;
    expect(action.id.value, 'increment');
    expect(action.action, SemanticAction.activate);

    final result = toolJson(lastResult());
    expect(result['changed'], isTrue);
    expect(bridge.revision, greaterThan(before));
    expect(jsonEncode(result['ui']), contains('"value":1'));
  });

  test('invoke_action rejects an unknown id', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(9, 'tools/call', <String, Object?>{
        'name': 'invoke_action',
        'arguments': <String, Object?>{'id': 'nope', 'action': 'activate'},
      }),
    );
    final result = lastResult();
    expect(result['isError'], isTrue);
    expect((result['content'] as List).single, isA<Map<String, Object?>>());
    expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);
  });

  test('invoke_action rejects an action the node does not advertise', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(10, 'tools/call', <String, Object?>{
        'name': 'invoke_action',
        'arguments': <String, Object?>{'id': 'count', 'action': 'activate'},
      }),
    );
    final result = lastResult();
    expect(result['isError'], isTrue);
    final message = ((result['content'] as List).single as Map<String, Object?>)['text'];
    expect(message, contains('does not advertise'));
    expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);
  });

  test('invoke_action rejects an unknown action name', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(11, 'tools/call', <String, Object?>{
        'name': 'invoke_action',
        'arguments': <String, Object?>{'id': 'increment', 'action': 'wiggle'},
      }),
    );
    expect(lastResult()['isError'], isTrue);
  });

  test('type_text emits a TextInputEvent frame', () async {
    pushCount(0);
    await bridge.ready;

    final pending = server.handleLine(
      _rpc(12, 'tools/call', <String, Object?>{
        'name': 'type_text',
        'arguments': <String, Object?>{'text': 'hello'},
      }),
    );
    await pending; // no reacting frame — settle times out quickly, fine.

    final event = transport.sent.whereType<InputEventFrame>().single.event;
    expect(event, isA<TextInputEvent>());
    expect((event as TextInputEvent).text, 'hello');
  });

  test('press_key maps named keys and literal characters', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(13, 'tools/call', <String, Object?>{
        'name': 'press_key',
        'arguments': <String, Object?>{
          'key': 'enter',
          'modifiers': <String>['ctrl'],
        },
      }),
    );
    final key = transport.sent.whereType<InputEventFrame>().last.event;
    expect(key, isA<KeyEvent>());
    final keyEvent = key as KeyEvent;
    expect(keyEvent.keyCode, KeyCode.enter);
    expect(keyEvent.modifiers, contains(KeyModifier.ctrl));

    await server.handleLine(
      _rpc(14, 'tools/call', <String, Object?>{
        'name': 'press_key',
        'arguments': <String, Object?>{'key': 'x'},
      }),
    );
    final literal =
        transport.sent.whereType<InputEventFrame>().last.event as KeyEvent;
    expect(literal.keyCode, isNull);
    expect(literal.char, 'x');
  });

  test('press_key rejects an unrecognized multi-char key', () async {
    pushCount(0);
    await bridge.ready;

    await server.handleLine(
      _rpc(15, 'tools/call', <String, Object?>{
        'name': 'press_key',
        'arguments': <String, Object?>{'key': 'frobnicate'},
      }),
    );
    expect(lastResult()['isError'], isTrue);
  });

  test('unknown method returns a JSON-RPC method-not-found error', () async {
    await server.handleLine(_rpc(16, 'does/not/exist'));
    final message = jsonDecode(out.removeLast()) as Map<String, Object?>;
    expect((message['error'] as Map<String, Object?>)['code'], -32601);
  });

  test('malformed JSON returns a parse error', () async {
    await server.handleLine('{not json');
    final message = jsonDecode(out.removeLast()) as Map<String, Object?>;
    expect((message['error'] as Map<String, Object?>)['code'], -32700);
  });

  test('tools refuse to run once the app has exited', () async {
    pushCount(0);
    await bridge.ready;
    await transport.dropPeer(); // app disconnects
    expect(bridge.isRunning, isFalse);

    await server.handleLine(
      _rpc(17, 'tools/call', <String, Object?>{
        'name': 'get_ui',
        'arguments': <String, Object?>{},
      }),
    );
    expect(lastResult()['isError'], isTrue);
  });
}

String _rpc(int id, String method, [Map<String, Object?>? params]) {
  return jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': ?params,
  });
}

Map<String, Object?> _counterTree(int count) => <String, Object?>{
  'schemaVersion': 1,
  'root': <String, Object?>{
    'id': 'root',
    'role': 'app',
    'label': 'Counter',
    'children': <Object?>[
      <String, Object?>{
        'id': 'count',
        'role': 'text',
        'label': 'Count',
        'value': count,
      },
      <String, Object?>{
        'id': 'increment',
        'role': 'button',
        'label': 'Increment',
        'actions': <String>['activate'],
      },
      <String, Object?>{
        'id': 'reset',
        'role': 'button',
        'label': 'Reset',
        'actions': <String>['activate'],
      },
    ],
  },
};

final class _FakeTransport implements RemoteFrameTransport {
  final StreamController<RemoteFrame> _incoming =
      StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = <RemoteFrame>[];

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  void send(RemoteFrame frame) => sent.add(frame);

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  void addIncoming(RemoteFrame frame) => _incoming.add(frame);

  /// Simulates the app disconnecting — the bridge sees `onDone` and exits.
  Future<void> dropPeer() async {
    if (!_incoming.isClosed) await _incoming.close();
    // Let the bridge's onDone handler run.
    await Future<void>.delayed(Duration.zero);
  }
}
