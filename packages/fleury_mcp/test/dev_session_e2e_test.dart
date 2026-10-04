@TestOn('posix')
@Tags(['integration'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_dev_io.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native attachment preserves draft on reload, reports errors and resets on restart',
    () async {
      final repo = Directory.current.parent.parent;
      final temp = Directory.systemTemp.createTempSync('fleury_agent_e2e_');
      final app = Directory('${temp.path}/app')..createSync();
      File('${app.path}/pubspec.yaml').writeAsStringSync('''
name: agent_fixture
environment:
  sdk: ^3.10.4
dependencies:
  fleury:
    path: ${repo.path}/packages/fleury
''');
      Directory('${app.path}/bin').createSync();
      Directory('${app.path}/lib').createSync();
      final marker = File('${app.path}/lib/marker.dart')
        ..writeAsStringSync(_marker('BEFORE', 4));
      File('${app.path}/bin/main.dart').writeAsStringSync(_fixture);
      final pub = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--no-example',
      ], workingDirectory: app.path);
      expect(pub.exitCode, 0, reason: '${pub.stdout}\n${pub.stderr}');
      final output = StringBuffer();
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          '${repo.path}/profiling/capture_pty.dart',
          '--out',
          '${temp.path}/capture',
          '--timeout',
          '180',
          '--',
          Platform.resolvedExecutable,
          '${repo.path}/packages/fleury/bin/fleury.dart',
          'run',
          '--agent',
          'bin/main.dart',
        ],
        workingDirectory: app.path,
        environment: {
          'FLEURY_DEV_BOOTSTRAP_LOG': '${temp.path}/supervisor.log',
        },
      );
      process.stdout.transform(utf8.decoder).listen(output.write);
      process.stderr.transform(utf8.decoder).listen(output.write);
      FleuryDevBridge? bridge;
      McpServer? server;
      DevSessionClient? client;
      int? supervisorPid;
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (client == null && DateTime.now().isBefore(deadline)) {
          try {
            client = await DevSessionClient.connect(projectDirectory: app.path);
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        expect(client, isNotNull, reason: 'no native session: $output');
        final descriptor =
            Directory(
                  '${app.path}/.dart_tool/fleury/sessions',
                ).listSync().single
                as File;
        supervisorPid =
            (jsonDecode(descriptor.readAsStringSync()) as Map)['pid'] as int;
        bridge = await FleuryDevBridge.attach(projectDirectory: app.path);
        final replies = <String>[];
        server = McpServer(bridge: bridge, send: replies.add);
        var rpcId = 0;
        Future<Map<String, dynamic>> rpc(
          String method, [
          Map<String, Object?> params = const {},
        ]) async {
          final id = ++rpcId;
          await server!.handleLine(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'method': method,
              'params': params,
            }),
          );
          return replies
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              .singleWhere((r) => r['id'] == id);
        }

        await rpc('initialize', {
          'protocolVersion': mcpLegacyProtocolVersion,
          'capabilities': <String, Object?>{},
        });
        Future<Map<String, dynamic>> tool(
          String name, [
          Map<String, Object?> args = const {},
          bool error = false,
        ]) async {
          final response = await rpc('tools/call', {
            'name': name,
            'arguments': args,
          });
          expect(response['error'], isNull, reason: '$response');
          final result = response['result'] as Map;
          expect(result['isError'] == true, error, reason: '$result');
          if (error) {
            return (result['structuredContent'] as Map).cast<String, dynamic>();
          }
          return jsonDecode(
                ((result['content'] as List).first as Map)['text'] as String,
              )
              as Map<String, dynamic>;
        }

        final tools =
            ((await rpc('tools/list'))['result'] as Map)['tools'] as List;
        expect(
          tools.map((t) => (t as Map)['name']),
          containsAll([
            'get_inspection',
            'get_dev_status',
            'reload_app',
            'restart_app',
          ]),
        );
        expect(tools.map((t) => (t as Map)['name']), isNot(contains('resize')));
        final modernTools =
            ((await rpc('tools/list', {
                      '_meta': {
                        'io.modelcontextprotocol/protocolVersion':
                            mcpProtocolVersion,
                        'io.modelcontextprotocol/clientInfo': {
                          'name': 'test',
                          'version': '1',
                        },
                        'io.modelcontextprotocol/clientCapabilities':
                            <String, Object?>{},
                      },
                    }))['result']
                    as Map)['tools']
                as List;
        final setTool = modernTools.cast<Map<String, dynamic>>().singleWhere(
          (t) => t['name'] == 'set_value',
        );
        expect(
          (setTool['inputSchema'] as Map)['required'],
          contains('targetRef'),
        );
        final inspection = await tool('get_inspection');
        expect(jsonEncode(inspection['render']), contains('BEFORE'));
        final rendered = inspection['render'] as Map;
        expect(jsonEncode(rendered['cells']), contains('continuation'));
        expect(
          (rendered['styles'] as List).any(
            (style) => (style as Map)['bold'] == true,
          ),
          isTrue,
        );
        for (final row in rendered['cells'] as List) {
          expect(
            (row as List).fold<int>(
              0,
              (sum, run) => sum + ((run as List).first as int),
            ),
            (rendered['region'] as Map)['cols'],
          );
        }
        Map<String, dynamic> find(Map<String, dynamic> ui, String label) {
          Map<String, dynamic>? found;
          void walk(Map<String, dynamic> node) {
            if (node['label'] == label && found == null) found = node;
            for (final child in node['children'] as List? ?? const []) {
              walk((child as Map).cast<String, dynamic>());
            }
          }

          walk((ui['root'] as Map).cast<String, dynamic>());
          return found!;
        }

        final field = find(
          (inspection['ui'] as Map).cast<String, dynamic>(),
          'Draft',
        );
        final originalEpoch = inspection['epoch'];
        final set = await tool('set_value', {
          'id': field['id'],
          'targetRef': field['targetRef'],
          'value': 'unsaved draft',
        });
        expect(set['status'], 'completed');
        final draftNode = find(
          (set['ui'] as Map).cast<String, dynamic>(),
          'Draft',
        );
        expect(draftNode['value'], 'unsaved draft');
        final layout = await tool('get_inspection', {'node': draftNode['id']});
        expect(layout['ancestry'], isNotEmpty);
        expect(
          (layout['ancestry'] as List).any(
            (a) => ((a as Map)['constraints'] as Map?)?['maxCols'] == 4,
          ),
          isTrue,
        );
        expect(
          (layout['ancestry'] as List).any(
            (a) => (a as Map)['constraints'] != null,
          ),
          isTrue,
        );

        // Exercise the real stdio attach CLI and its stdin-close ownership.
        final mcp = await Process.start(Platform.resolvedExecutable, [
          '${repo.path}/packages/fleury_mcp/bin/fleury_mcp.dart',
          '--attach',
          '--project=${app.path}',
        ]);
        final mcpErrors = StringBuffer();
        mcp.stderr.transform(utf8.decoder).listen(mcpErrors.write);
        final messages = mcp.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .map((line) => jsonDecode(line) as Map)
            .asBroadcastStream();
        try {
          final initialized = messages.firstWhere((m) => m['id'] == 1);
          mcp.stdin.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'initialize',
              'params': {
                'protocolVersion': mcpLegacyProtocolVersion,
                'capabilities': <String, Object?>{},
              },
            }),
          );
          expect(
            (await initialized.timeout(const Duration(seconds: 15)))['error'],
            isNull,
          );
          final inspected = messages.firstWhere((m) => m['id'] == 2);
          mcp.stdin.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 2,
              'method': 'tools/call',
              'params': {'name': 'get_ui', 'arguments': <String, Object?>{}},
            }),
          );
          expect(
            jsonEncode(await inspected.timeout(const Duration(seconds: 10))),
            contains('unsaved draft'),
          );
          await mcp.stdin.close();
          expect(
            await mcp.exitCode.timeout(const Duration(seconds: 8)),
            0,
            reason: '$mcpErrors',
          );
        } finally {
          mcp.kill();
        }

        // Disconnect is not process ownership. Reattach to the same draft.
        server.dispose();
        await bridge.close();
        bridge = await FleuryDevBridge.attach(projectDirectory: app.path);
        expect(
          bridge.snapshot!.where(label: 'Draft').single.value,
          'unsaved draft',
        );
        server = McpServer(bridge: bridge, send: replies.add);
        await rpc('initialize', {
          'protocolVersion': mcpLegacyProtocolVersion,
          'capabilities': <String, Object?>{},
        });

        Future<Map<String, Object?>> waitReload(int after) async {
          final until = DateTime.now().add(const Duration(seconds: 40));
          while (DateTime.now().isBefore(until)) {
            final status = await client!.request('status');
            final last = status['lastReload'];
            if (last is Map &&
                (last['sequence'] as int) > after &&
                status['reloading'] == false) {
              return last.cast<String, Object?>();
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          fail('No completed reload');
        }

        marker.writeAsStringSync(_marker('AFTER', 30));
        final good = await waitReload(0);
        expect(good['success'], isTrue, reason: '$good');
        final after = await tool('get_inspection');
        expect(after['epoch'], originalEpoch);
        expect(jsonEncode(after['render']), contains('AFTER'));
        expect(jsonEncode(after['render']), contains('unsaved draft'));
        final afterField = find(
          (after['ui'] as Map).cast<String, dynamic>(),
          'Draft',
        );
        final expanded = await tool('get_inspection', {
          'node': afterField['id'],
        });
        expect(
          (expanded['ancestry'] as List).any(
            (a) => ((a as Map)['constraints'] as Map?)?['maxCols'] == 30,
          ),
          isTrue,
        );
        expect(
          find((after['ui'] as Map).cast<String, dynamic>(), 'Draft')['value'],
          'unsaved draft',
        );

        marker.writeAsStringSync('this is not valid Dart;\n');
        final bad = await waitReload(good['sequence'] as int);
        expect(bad['success'], isFalse);
        expect(bad['restartRequired'], isFalse);
        expect(bad['message'], isNotEmpty);
        final status = await tool('get_dev_status');
        expect((status['lastReload'] as Map)['success'], isFalse);
        marker.writeAsStringSync(_marker('RECOVERED', 30));
        final recovered = await waitReload(bad['sequence'] as int);
        expect(recovered['success'], isTrue, reason: '$recovered');
        final explicitReload = await tool('reload_app');
        expect(explicitReload['stateReset'], isFalse);
        marker.writeAsStringSync(_marker('RECOVERED', 30, generic: true));
        final rejected = await waitReload(
          (explicitReload['lastReload'] as Map)['sequence'] as int,
        );
        expect(rejected['success'], isFalse, reason: '$rejected');
        expect(rejected['restartRequired'], isTrue, reason: '$rejected');
        final beforeRestart = await tool('get_inspection');
        final oldField = find(
          (beforeRestart['ui'] as Map).cast<String, dynamic>(),
          'Draft',
        );
        final restarted = await tool('restart_app');
        expect(restarted['stateReset'], isTrue);
        final restartedInspection = restarted['inspection'] as Map;
        expect(restartedInspection['epoch'], isNot(originalEpoch));
        expect(
          find(
            (restartedInspection['ui'] as Map).cast<String, dynamic>(),
            'Draft',
          )['value'],
          '',
        );
        final stale = await tool('set_value', {
          'id': oldField['id'],
          'targetRef': oldField['targetRef'],
          'value': 'wrong generation',
        }, true);
        expect(jsonEncode(stale), contains('stale'));
        expect((await tool('get_dev_status'))['ready'], isTrue);
        await expectLater(
          client!.request('action', {
            'epoch': originalEpoch,
            'id': find(
              (restartedInspection['ui'] as Map).cast<String, dynamic>(),
              'Draft',
            )['id'],
            'action': 'setValue',
            'value': 'wrong generation',
          }),
          throwsA(isA<DevSessionException>()),
        );
        final logNode = find(
          (restartedInspection['ui'] as Map).cast<String, dynamic>(),
          'Log',
        );
        expect(
          (await tool('invoke_action', {
            'id': logNode['id'],
            'targetRef': logNode['targetRef'],
            'action': 'activate',
          }))['status'],
          'completed',
        );
        expect(
          jsonEncode(await tool('read_logs')),
          contains('native agent log'),
        );
        final failNode = find(
          (restartedInspection['ui'] as Map).cast<String, dynamic>(),
          'Fail',
        );
        expect(
          (await tool('invoke_action', {
            'id': failNode['id'],
            'targetRef': failNode['targetRef'],
            'action': 'activate',
          }, true))['code'],
          'action_failed',
        );
        expect(
          jsonEncode(await tool('read_errors')),
          contains('native agent failure'),
        );
        expect((await tool('get_dev_status'))['ready'], isTrue);
        Process.killPid(supervisorPid, ProcessSignal.sigterm);
        supervisorPid = null;
        await process.exitCode.timeout(const Duration(seconds: 8));
        expect(descriptor.existsSync(), isFalse);
        // capture_pty writes its artifact when the supervised process exits.
        final bytes = File('${temp.path}/capture.bin').readAsBytesSync();
        expect(latin1.decode(bytes), contains('RECOVERED'));
      } finally {
        server?.dispose();
        await bridge?.close();
        client?.close();
        if (supervisorPid != null) {
          Process.killPid(supervisorPid, ProcessSignal.sigterm);
        }
        try {
          await process.exitCode.timeout(const Duration(seconds: 8));
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
        }
        printOnFailure(output.toString());
        final log = File('${temp.path}/supervisor.log');
        if (log.existsSync()) printOnFailure(log.readAsStringSync());
        final capture = File('${temp.path}/capture.bin');
        if (capture.existsSync()) {
          final text = latin1.decode(capture.readAsBytesSync());
          printOnFailure(
            text.substring(text.length > 5000 ? text.length - 5000 : 0),
          );
        }
        temp.deleteSync(recursive: true);
      }
    },
  );
}

String _marker(String label, int width, {bool generic = false}) =>
    "String label() => '$label';\nint width() => $width;\nclass Shape${generic ? '<T>' : ''} {}\n";

const _fixture = r'''
import 'dart:io';
import 'package:fleury/fleury.dart';
import 'package:agent_fixture/marker.dart' as marker;

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => AppState();
}
class AppState extends State<App> {
  final draft = TextEditingController();
  final shape = marker.Shape();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(marker.label()),
      Text(shape.runtimeType.toString()),
      const Text('A界', style: CellStyle(bold: true, foreground: AnsiColor(2))),
      SizedBox(width: marker.width(), child: TextInput(
        key: const ValueKey('draft'), controller: draft, semanticLabel: 'Draft',
      )),
      Semantics(id: const SemanticNodeId('log'), role: SemanticRole.button,
        label: 'Log', actions: const {SemanticAction.activate},
        onAction: (_) => print('native agent log'), child: const Text('Log')),
      Semantics(id: const SemanticNodeId('fail'), role: SemanticRole.button,
        label: 'Fail', actions: const {SemanticAction.activate},
        onAction: (_) => throw StateError('native agent failure'), child: const Text('Fail')),
    ],
  );
  @override
  void dispose() { draft.dispose(); super.dispose(); }
}
Future<void> main() async {
  final result = await runApp(const App());
  exit(result.signal == null ? 0 : 143);
}
''';
