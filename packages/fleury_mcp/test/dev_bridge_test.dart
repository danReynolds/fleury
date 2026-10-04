import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_dev_io.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  late HttpServer endpoint;
  late FleuryDevBridge bridge;
  late McpServer server;
  late List<String> replies;
  late int sequence;
  late int rpcId;
  late int actionCount;
  late String value;
  late Future<String> Function() onAction;

  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, Object?> params = const {},
    bool modern = false,
  ]) async {
    final id = ++rpcId;
    await server.handleLine(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': {
          ...params,
          if (modern)
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': mcpProtocolVersion,
              'io.modelcontextprotocol/clientInfo': {
                'name': 'dev-bridge-test',
                'version': '1.0.0',
              },
              'io.modelcontextprotocol/clientCapabilities': <String, Object?>{},
            },
        },
      }),
    );
    return replies
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .singleWhere((reply) => reply['id'] == id)['result']
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> tool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final result = await rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    expect(result['isError'], isNot(true), reason: '$result');
    return result['structuredContent'] as Map<String, dynamic>;
  }

  setUp(() async {
    sequence = 0;
    rpcId = 0;
    actionCount = 0;
    value = 'Before';
    onAction = () async => 'completed';
    project = Directory.systemTemp.createTempSync('fleury_dev_bridge_test_');
    final descriptors = Directory('${project.path}/.dart_tool/fleury/sessions')
      ..createSync(recursive: true);
    File(
      '${project.path}/.dart_tool/package_config.json',
    ).writeAsStringSync('{}');
    endpoint = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    File('${descriptors.path}/fixture.json').writeAsStringSync(
      jsonEncode({
        'protocol': devSessionProtocolVersion,
        'sessionId': 'fixture',
        'port': endpoint.port,
        'token': 'fixture-token',
      }),
    );
    endpoint.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final Map<String, Object?> result;
      switch (body['method']) {
        case 'status':
          result = {'ready': true};
        case 'action':
          actionCount++;
          result = {'status': await onAction()};
        default:
          result = {
            'epoch': 'fixture-epoch',
            'generation': 1,
            'inspectionSequence': ++sequence,
            'viewport': {'cols': 80, 'rows': 24},
            'ui': {
              'root': {
                'id': 'control',
                'role': 'textField',
                'label': 'Draft',
                'value': value,
                'actions': ['activate', 'setValue'],
              },
            },
          };
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'result': result}));
      await request.response.close();
    });
    bridge = await FleuryDevBridge.attach(projectDirectory: project.path);
    replies = [];
    server = McpServer(bridge: bridge, send: replies.add);
    await rpc('initialize', {
      'protocolVersion': mcpLegacyProtocolVersion,
      'capabilities': <String, Object?>{},
    });
  });

  tearDown(() async {
    server.dispose();
    await bridge.close();
    await endpoint.close(force: true);
    project.deleteSync(recursive: true);
  });

  for (final name in ['invoke_action', 'set_value']) {
    test(
      '$name observes completion beyond the initial settle window',
      () async {
        onAction = () async {
          // Exceed the old two-second concurrent settle, but finish before the
          // runtime's action timeout. No other read drives the bridge.
          await Future<void>.delayed(const Duration(milliseconds: 2300));
          value = 'After';
          return 'completed';
        };
        final ui = await tool('get_ui');
        final result = await tool(name, {
          'id': 'control',
          'targetRef': (ui['root'] as Map)['targetRef'],
          if (name == 'invoke_action')
            'action': 'activate'
          else
            'value': 'After',
        });

        expect(actionCount, 1);
        expect(result['status'], 'completed');
        expect(result['changed'], isTrue);
        expect(((result['ui'] as Map)['root'] as Map)['value'], 'After');
        expect(result['note'], isNull);
      },
    );
  }

  test('pending action returns its observed UI without redispatch', () async {
    onAction = () async {
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      value = 'Waiting for confirmation';
      return 'pending';
    };
    final ui = await tool('get_ui');
    final result = await tool('invoke_action', {
      'id': 'control',
      'targetRef': (ui['root'] as Map)['targetRef'],
      'action': 'activate',
    });

    expect(actionCount, 1);
    expect(result['status'], 'pending');
    expect(result['changed'], isTrue);
    expect(
      ((result['ui'] as Map)['root'] as Map)['value'],
      'Waiting for confirmation',
    );
  });

  test(
    'legacy wait accepts the optional revision; modern wait requires it',
    () async {
      final legacy = await tool('wait_for_change', {'timeout_ms': 100});
      expect(legacy['changed'], isFalse);
      final modern = await rpc('tools/call', {
        'name': 'wait_for_change',
        'arguments': {'timeout_ms': 100},
      }, true);
      expect(modern['isError'], isTrue);
      expect((modern['structuredContent'] as Map)['code'], 'invalid_arguments');
    },
  );
}
