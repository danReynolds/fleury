@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/readiness_bundle_verifier.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'fleury_web_automated_validation_test_',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('web automated validation writes passing JSON evidence', () async {
    final outputPath = '${tempDir.path}/$webAutomatedValidationFileName';
    final dartVersionCommand = jsonEncode(<String>[
      Platform.resolvedExecutable,
      '--version',
    ]);

    final result = await _run([
      '--json-output=$outputPath',
      '--browser-command-json=$dartVersionCommand',
      '--vm-command-json=$dartVersionCommand',
      '--strict',
      '--json',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final validation = _jsonObject(result.stdout);
    expect(validation['kind'], 'fleuryWebAutomatedValidation');
    expect(validation['strictPass'], isTrue);
    expect(validation['sourceInputGroup'], 'webAutomatedTestFiles');
    expect(validation['browserTestFiles'], webAutomatedBrowserTestPaths);
    expect(validation['vmTestFiles'], webAutomatedVmTestPaths);
    expect(validation['fixtureFiles'], webAutomatedFixturePaths);
    expect(File(outputPath).existsSync(), isTrue);

    final persisted = _jsonObject(File(outputPath).readAsStringSync());
    expect(persisted['strictPass'], isTrue);
    final checks = (persisted['checks'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(checks, hasLength(2));
    expect(checks.map((check) => check['id']), ['browser', 'vm']);
    expect(checks.every((check) => check['exitCode'] == 0), isTrue);
    expect(checks.every((check) => check['strictPass'] == true), isTrue);
    final fingerprints =
        persisted['sourceInputFingerprints'] as Map<String, Object?>;
    expect(fingerprints['webAutomatedTestFiles'] as List<Object?>, isNotEmpty);
  });

  test(
    'web automated validation strict mode fails on command failure',
    () async {
      final outputPath = '${tempDir.path}/$webAutomatedValidationFileName';
      final goodCommand = jsonEncode(<String>[
        Platform.resolvedExecutable,
        '--version',
      ]);
      final badCommand = jsonEncode(<String>[
        Platform.resolvedExecutable,
        '--not-a-real-dart-option-for-fleury-web-test',
      ]);

      final result = await _run([
        '--json-output=$outputPath',
        '--browser-command-json=$goodCommand',
        '--vm-command-json=$badCommand',
        '--strict',
        '--json',
      ]);

      expect(result.exitCode, isNot(0));
      final validation = _jsonObject(result.stdout);
      expect(validation['strictPass'], isFalse);
      final checks = (validation['checks'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final vm = checks.singleWhere((check) => check['id'] == 'vm');
      expect(vm['strictPass'], isFalse);
      expect(vm['exitCode'], isNot(0));
      final persisted = _jsonObject(File(outputPath).readAsStringSync());
      expect(persisted['strictPass'], isFalse);
    },
  );
}

Future<ProcessResult> _run(List<String> args) {
  return Process.run(Platform.resolvedExecutable, [
    'run',
    'tool/web_automated_validation.dart',
    ...args,
  ], workingDirectory: Directory.current.path);
}

Map<String, Object?> _jsonObject(Object? text) {
  return jsonDecode(text.toString()) as Map<String, Object?>;
}
