// The package example (pub.dev's Example tab) and the README tell users what
// to install and run. These tests hold both to this package: the dependency
// tracks the release, every command starts the server the way a dev
// dependency provides it, and the hand-run smoke test sends requests that this
// server answers.

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

import 'support/fake_app.dart';

void main() {
  final example = File('example/README.md').readAsStringSync();
  final readme = File('README.md').readAsStringSync();
  final version = RegExp(
    r'^version: (\S+)$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;

  test('the example adds this release as a dev dependency', () {
    expect(example, contains('dev_dependencies:\n  fleury_mcp: ^$version\n'));
    expect(example, contains('dart pub add --dev fleury_mcp'));
  });

  test('the example starts the server through the dev dependency', () {
    expect(
      example,
      contains('dart run fleury_mcp -- dart run bin/run_app.dart'),
    );
    expect(
      example,
      contains(
        'claude mcp add my-app -- '
        'dart run fleury_mcp -- dart run bin/run_app.dart',
      ),
    );
    // Only a global or source activation puts a bare `fleury_mcp` on PATH.
    expect(
      RegExp(r'(?<!dart run )\bfleury_mcp -- ').allMatches(example),
      isEmpty,
    );
  });

  for (final (name, markdown) in [('example', example), ('README', readme)]) {
    test('the $name smoke test is answered by this server', () async {
      final smokeTest = _smokeTest(markdown);
      expect(
        smokeTest.pipe,
        '| dart run fleury_mcp -- dart run bin/run_app.dart',
      );
      expect(smokeTest.requests, hasLength(2));

      final transport = FakeAppTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);
      transport.addIncoming(appInit(remoteProtocolVersion));
      final counter = SemanticInspectionSnapshot.fromJson(<String, Object?>{
        'schemaVersion': 1,
        'root': counterRoot(0),
      });
      final before = bridge.revision;
      transport.addIncoming(
        SemanticsFrame(SemanticsWireEncoder().encode(counter)!),
      );
      while (bridge.revision == before) {
        await Future<void>.delayed(Duration.zero);
      }

      final responses = <Map<String, Object?>>[];
      final server = McpServer(
        bridge: bridge,
        send: (line) => responses.add(jsonDecode(line) as Map<String, Object?>),
      );
      final results = <String, Map<String, Object?>>{};
      for (final request in smokeTest.requests) {
        final decoded = jsonDecode(request) as Map<String, Object?>;
        await server.handleLine(request);
        final response = responses.singleWhere(
          (message) => message['id'] == decoded['id'],
        );
        expect(response, contains('result'), reason: '$request\n$response');
        results[decoded['method']! as String] =
            response['result']! as Map<String, Object?>;
      }

      expect(
        results['initialize']!['protocolVersion'],
        mcpLegacyProtocolVersion,
      );
      final getUi = results['tools/call']!;
      expect(getUi['isError'], isFalse);
      final content = (getUi['content']! as List<Object?>).single;
      expect((content! as Map<String, Object?>)['text'], contains('Increment'));
    });
  }
}

/// The JSON-RPC lines of the documented `printf … | dart run fleury_mcp` pipe,
/// and the pipe's final command line.
({List<String> requests, String pipe}) _smokeTest(String markdown) {
  final block = RegExp(r'```bash\n([\s\S]*?)```')
      .allMatches(markdown)
      .map((match) => match.group(1)!)
      .singleWhere((body) => body.startsWith('printf '));
  final lines = block.trimRight().split('\n');
  return (
    requests: [
      for (final line in lines)
        if (RegExp(r"^\s*'(\{.*\})' \\$").firstMatch(line) case final match?)
          match.group(1)!,
    ],
    pipe: lines.last.trim(),
  );
}
