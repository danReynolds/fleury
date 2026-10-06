// The README's "What the agent sees" JSON is real server output. This spawns
// the README's own counter (test/fixtures/readme_counter_app.dart, which must
// match the README's Dart fence) and checks that `find_nodes` for its button
// returns exactly the documented result: the same keys in the same order and
// the same values, where `…` in a documented string stands for text the README
// shortens. When the server's output changes, update the README example.
//
// Tagged `integration` (per dart_test.yaml) since it spawns `dart run`.
@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  final readme = File(_packagePath('README.md')).readAsStringSync();
  final fixture = _packagePath('test/fixtures/readme_counter_app.dart');

  test('the fixture is the README counter', () {
    final app = File(fixture).readAsStringSync();
    final firstImport = app.indexOf("import 'package:fleury/fleury.dart';");

    expect(firstImport, isNonNegative);
    expect(_fence(readme, 'dart').trim(), app.substring(firstImport).trim());
  });

  test(
    'find_nodes for the button returns the documented result',
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
      _expectDocumented(
        jsonDecode(_fence(readme, 'json')),
        result['structuredContent'],
        'find_nodes result',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
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

/// The body of the README's only fenced block in [language].
String _fence(String markdown, String language) => RegExp(
  '```$language\\n([\\s\\S]*?)\\n```',
).allMatches(markdown).single.group(1)!;

String _rpc(int id, String method, Map<String, Object?> params) =>
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

/// Resolves [relative] inside this package, from the package or the
/// repository root.
String _packagePath(String relative) {
  for (final base in <String>[
    Directory.current.path,
    '${Directory.current.path}/packages/fleury_mcp',
  ]) {
    final file = File('$base/$relative');
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError('$relative not found from ${Directory.current.path}');
}
