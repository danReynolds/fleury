import 'dart:convert';
import 'dart:io';

import 'package:fleury_dartpad_host/compiler_backend.dart';
import 'package:fleury_dartpad_host/precompiled_starter.dart';
import 'package:fleury_dartpad_host/request_policy.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.parent.path;
  final build = path.join(root, '.build');
  final sdkPath =
      Platform.environment['DART_SDK'] ??
      path.dirname(path.dirname(Platform.resolvedExecutable));
  final manifest = jsonDecode(
    File(path.join(build, 'manifest.json')).readAsStringSync(),
  );
  final source = File(path.join(root, 'lib/main.dart')).readAsStringSync();
  validateSource(source);
  final api = createCompilerBackend(root, sdkPath);
  await api.init();
  try {
    final response = await api.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v3/compileNewDDC'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'source': source}),
      ),
    );
    final body = await response.readAsString();
    if (response.statusCode != 200)
      throw StateError('Starter compilation failed: $body');
    final result = jsonDecode(body) as Map<String, dynamic>;
    final artifact = {
      'buildId': manifest['buildId'],
      'source': source,
      'result': result['result'],
      'deltaDill': result['deltaDill'],
    };
    PrecompiledStarter.fromJson(
      artifact,
      buildId: manifest['buildId'] as String,
      source: source,
    );
    // Publish only after successful compilation and validation.
    final output = File(path.join(build, 'starter.json'));
    final temporary = File('${output.path}.tmp');
    temporary.writeAsStringSync(jsonEncode(artifact));
    temporary.renameSync(output.path);
    print(
      'Precompiled starter for ${manifest['buildId']} (${output.lengthSync()} bytes).',
    );
  } finally {
    await api.shutdown();
  }
}
