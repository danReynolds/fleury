import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'dev subcommand delegates to the repo-local development launcher',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/fleury.dart',
        'dev',
        '--help',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout.toString(),
        contains('Fleury local development launcher'),
      );
      expect(result.stdout.toString(), contains('mvp-final-gate'));
    },
  );

  test('diagnose writes JSON to a file without piping stdout', () async {
    final temp = Directory.systemTemp.createTempSync('fleury_diagnose_cli_');
    try {
      final output = File('${temp.path}/diagnosis.json');
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/fleury.dart',
        'diagnose',
        '--json-output=${output.path}',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), isEmpty);
      expect(output.existsSync(), isTrue);

      final json = jsonDecode(output.readAsStringSync());
      expect(json, isA<Map<String, Object?>>());
      final map = json as Map<String, Object?>;
      expect(map['schemaVersion'], 1);
      expect(map['terminal'], isA<Map<String, Object?>>());
      final platform = map['platform'];
      expect(platform, isA<Map<String, Object?>>());
      expect((platform as Map<String, Object?>)['operatingSystem'], isNotEmpty);
      expect(platform['dartVersion'], isNotEmpty);
      expect(map['capabilities'], isA<Map<String, Object?>>());
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
