// Showcase end-to-end: drive the REAL Fleury sample apps (the ones on the
// website) through the MCP server, the way an agent actually would — discover a
// node by role/label (the ids are auto-generated `element-$hash`, not known up
// front), then invoke the action it advertises and observe the change.
//
// This is the thorough counterpart to the counter fixture: it exercises real
// widget-emitted semantics (Tree, DataTable, TextInput), auto ids, windowing,
// and actions beyond `activate` — against apps that aren't built for the test.
//
// Tagged `integration` (cold-spawns `dart run`). Skips cleanly when the
// `samples` package isn't resolved (so `fleury_mcp` stays standalone-testable);
// runs in the monorepo, where samples is bootstrapped.
@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  final samplesBin = _resolveSamplesBin();
  final skip = samplesBin == null
      ? 'samples package not resolved from ${Directory.current.path}'
      : null;

  /// Spawns a named sample and returns a driver that calls MCP tools against it.
  Future<_Driver> drive(String app) async {
    final bridge = await FleuryAppBridge.spawn(
      command: <String>['dart', 'run', samplesBin!, app],
      log: (_) {},
    );
    addTearDown(bridge.close);
    await bridge.ready;
    return _Driver(bridge);
  }

  group(
    'MCP drives the real Fleury showcases',
    () {
      test(
        'files: open a folder (discovered by role+label) reveals its children',
        () async {
          final files = await drive('files');

          // Real Tree semantics, not a hand-built fixture.
          final ui = await files.tool('get_ui');
          final roles = (ui['roleCounts'] as Map<String, Object?>).keys;
          expect(roles, containsAll(<String>['tree', 'treeItem']));

          // Discover a collapsed folder by the action it advertises — its id is an
          // auto-generated element-$hash an agent can't know in advance.
          final before = await files.tool('find_nodes', <String, Object?>{
            'role': 'treeItem',
          });
          final items = (before['nodes'] as List).cast<Map<String, Object?>>();
          final folder = items.firstWhere(
            (n) => (n['actions'] as List?)?.contains('open') ?? false,
            orElse: () => throw StateError('no openable folder in $items'),
          );
          final beforeCount = before['matchCount'] as int;

          final opened = await files.tool('invoke_action', <String, Object?>{
            'id': folder['id'],
            'action': 'open',
          });
          expect(opened['changed'], isTrue);

          final after = await files.tool('find_nodes', <String, Object?>{
            'role': 'treeItem',
          });
          expect(
            after['matchCount'] as int,
            greaterThan(beforeCount),
            reason: 'opening ${folder['label']} should reveal child items',
          );
        },
      );

      test(
        'dashboard: resize surfaces more rows of the windowed DataTable',
        () async {
          final dashboard = await drive('dashboard');

          // Rich table semantics straight from the DataTable widget.
          final ui = await dashboard.tool('get_ui');
          final roles = ui['roleCounts'] as Map<String, Object?>;
          expect(roles['table'], isNotNull);
          expect(roles['tableCell'], isNotNull);

          final before = await dashboard.tool('find_nodes', <String, Object?>{
            'role': 'tableRow',
          });
          final beforeRows = before['matchCount'] as int;
          expect(beforeRows, greaterThan(0));

          // A taller viewport windows in more of the (24-row) table.
          await dashboard.tool('resize', <String, Object?>{
            'cols': 100,
            'rows': 60,
          });

          final after = await dashboard.tool('find_nodes', <String, Object?>{
            'role': 'tableRow',
          });
          expect(
            after['matchCount'] as int,
            greaterThan(beforeRows),
            reason: 'a taller grid should window in more rows',
          );
        },
      );

      test(
        'agent: type_text into the focused prompt updates its value',
        () async {
          final agent = await drive('agent');

          final field = await agent.tool('find_nodes', <String, Object?>{
            'role': 'textField',
          });
          final node = (field['nodes'] as List).single as Map<String, Object?>;
          expect(node['focused'], isTrue, reason: 'the prompt autofocuses');

          const text = 'refactor the parser';
          await agent.tool('type_text', <String, Object?>{'text': text});

          final after = await agent.tool('find_nodes', <String, Object?>{
            'role': 'textField',
          });
          final value =
              ((after['nodes'] as List).single
                  as Map<String, Object?>)['value'];
          expect('$value', contains(text));
        },
      );

      test(
        'agent: set_value sets the prompt in one call (no focus dance)',
        () async {
          final agent = await drive('agent');

          final field = await agent.tool('find_nodes', <String, Object?>{
            'role': 'textField',
          });
          final node = (field['nodes'] as List).single as Map<String, Object?>;
          final id = node['id'] as String;
          expect(
            node['actions'] as List,
            contains('setValue'),
            reason: 'the real TextInput advertises setValue over the wire',
          );

          // One call — no prior focus/type_text — carries the payload through the
          // full stack: MCP set_value → SEMANTIC_ACTION frame → live TextInput.
          const text = 'ship the release';
          final result = await agent.tool('set_value', <String, Object?>{
            'id': id,
            'value': text,
          });
          expect(result['changed'], isTrue);

          final after = await agent.tool('find_nodes', <String, Object?>{
            'role': 'textField',
          });
          final value =
              ((after['nodes'] as List).single
                  as Map<String, Object?>)['value'];
          expect('$value', contains(text));
        },
      );

      test('debug playground: an agent triggers each scenario and reads the '
          'evidence in the devtools', () async {
        // THE showcase claim, end-to-end: "your AI can use your debugger."
        // Drive the real debug-playground sample the way an agent would —
        // discover each scenario button semantically, activate it, then read
        // the debug channel back and find the evidence of what it just caused.
        final dbg = await drive('debug');

        Future<String> buttonId(String label) async {
          final found = await dbg.tool('find_nodes', <String, Object?>{
            'role': 'button',
            'label': label,
          });
          final nodes = (found['nodes'] as List).cast<Map<String, Object?>>();
          expect(nodes, isNotEmpty, reason: 'no "$label" button on screen');
          return nodes.first['id'] as String;
        }

        Future<List<Map<String, Object?>>> records(String tool) async {
          final res = await dbg.tool(tool, <String, Object?>{'limit': 100});
          expect(res['available'], isTrue, reason: '$tool: debug channel live');
          return (res['records'] as List).cast<Map<String, Object?>>();
        }

        Future<void> activate(String label) async {
          await dbg.tool('invoke_action', <String, Object?>{
            'id': await buttonId(label),
            'action': 'activate',
          });
        }

        // 1. Spike a slow frame → read_frames shows the ~120ms build.
        await activate('Spike a slow frame');
        final frames = await records('read_frames');
        expect(frames, isNotEmpty);
        expect(
          frames.any((f) => (f['buildUs'] as int) >= 100 * 1000),
          isTrue,
          reason: 'the deliberately janky build (~120ms) shows in read_frames',
        );

        // 2. Throw in a handler → invoke_action reports the app-side failure
        // (actionFailed — an agent learns its action threw, not a stale id),
        // and read_errors carries the real error + stack.
        final thrown = await dbg.toolExpectError('invoke_action', {
          'id': await buttonId('Throw in a handler'),
          'action': 'activate',
        });
        expect(thrown, contains('threw'));
        final errors = await records('read_errors');
        expect(errors, isNotEmpty);
        expect(
          '${errors.last['error']}',
          contains('simulated handler failure'),
        );
        expect('${errors.last['stack']}', isNotEmpty);

        // 3. Emit a log burst → read_logs has the whole burst, source-tagged.
        await activate('Emit a log burst');
        var logs = <Map<String, Object?>>[];
        for (var i = 0; i < 40; i++) {
          logs = await records('read_logs');
          if (logs.any((l) => '${l['text']}'.contains('line 40/40'))) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(
          logs.any((l) => '${l['text']}'.contains('log burst #1 line 1/40')),
          isTrue,
        );
        expect(
          logs.any((l) => '${l['text']}'.contains('line 40/40')),
          isTrue,
          reason: 'the whole burst reached the agent',
        );
        expect(
          logs.firstWhere(
            (l) => '${l['text']}'.contains('line 1/40'),
          )['source'],
          'stdout',
        );

        // 4. Toggle the live stream → frames keep arriving (the ticker renders
        // continuously). The button relabels to "Stop live stream" — itself
        // semantic evidence the UI updated — and stopping via the new label
        // closes the loop.
        await activate('Toggle live stream');
        final base = (await records('read_frames')).last['frame'] as int;
        var latest = base;
        for (var i = 0; i < 40 && latest < base + 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          latest = (await records('read_frames')).last['frame'] as int;
        }
        expect(
          latest,
          greaterThanOrEqualTo(base + 5),
          reason: 'streaming renders continuously — frames grow while it runs',
        );
        await activate('Stop live stream');
      });
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

/// Calls MCP tools against a spawned sample through a real [McpServer] +
/// [FleuryAppBridge], returning each tool's parsed JSON result.
final class _Driver {
  _Driver(FleuryAppBridge bridge) {
    _server = McpServer(bridge: bridge, send: _out.add);
  }

  final List<String> _out = <String>[];
  late final McpServer _server;
  int _id = 100;

  Future<Map<String, Object?>> tool(
    String name, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) async {
    _out.clear();
    await _server.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _id++,
        'method': 'tools/call',
        'params': <String, Object?>{'name': name, 'arguments': args},
      }),
    );
    final message = jsonDecode(_out.single) as Map<String, Object?>;
    final result = message['result'] as Map<String, Object?>;
    expect(
      result['isError'],
      isFalse,
      reason: '$name failed: ${result['content']}',
    );
    final content = (result['content'] as List).single as Map<String, Object?>;
    return jsonDecode(content['text'] as String) as Map<String, Object?>;
  }

  /// Like [tool], but the call is EXPECTED to fail (isError: true) — e.g.
  /// activating a deliberately-throwing handler. Returns the error text.
  Future<String> toolExpectError(
    String name, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) async {
    _out.clear();
    await _server.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _id++,
        'method': 'tools/call',
        'params': <String, Object?>{'name': name, 'arguments': args},
      }),
    );
    final message = jsonDecode(_out.single) as Map<String, Object?>;
    final result = message['result'] as Map<String, Object?>;
    expect(
      result['isError'],
      isTrue,
      reason: '$name unexpectedly succeeded: ${result['content']}',
    );
    final content = (result['content'] as List).single as Map<String, Object?>;
    return content['text'] as String;
  }
}

/// The `samples` package bin, if both it and its resolved package config exist.
String? _resolveSamplesBin() {
  final cwd = Directory.current.path;
  final dirs = <String>['$cwd/packages/samples', '$cwd/../samples'];
  for (final dir in dirs) {
    final bin = File('$dir/bin/samples.dart');
    final config = File('$dir/.dart_tool/package_config.json');
    if (bin.existsSync() && config.existsSync()) return bin.absolute.path;
  }
  return null;
}
