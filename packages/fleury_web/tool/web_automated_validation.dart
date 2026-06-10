import 'dart:convert';
import 'dart:io';

import 'readiness_bundle_verifier.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    return;
  }

  final generatedAt = DateTime.now().toUtc().toIso8601String();
  final commandWorkingDirectory = Directory.current.absolute.path;
  final browserCheck = await _runValidationCommand(
    id: 'browser',
    label: 'Retained DOM browser tests',
    command: options.browserCommand,
    testFiles: webAutomatedBrowserTestPaths,
  );
  final vmCheck = await _runValidationCommand(
    id: 'vm',
    label: 'Retained DOM VM tests',
    command: options.vmCommand,
    testFiles: webAutomatedVmTestPaths,
  );

  final checks = <Map<String, Object?>>[browserCheck, vmCheck];
  final validation = <String, Object?>{
    'schemaVersion': 1,
    'kind': 'fleuryWebAutomatedValidation',
    'generatedAt': generatedAt,
    'commandWorkingDirectory': commandWorkingDirectory,
    'strictPass': checks.every((check) => check['strictPass'] == true),
    'sourceInputGroup': 'webAutomatedTestFiles',
    'browserTestFiles': webAutomatedBrowserTestPaths,
    'vmTestFiles': webAutomatedVmTestPaths,
    'fixtureFiles': webAutomatedFixturePaths,
    'sourceInputFingerprints': <String, Object?>{
      'webAutomatedTestFiles': webAutomatedTestSourceInputFingerprints(),
    },
    'checks': checks,
  };

  final jsonText = const JsonEncoder.withIndent('  ').convert(validation);
  if (options.jsonOutputPath != null) {
    final output = File(options.jsonOutputPath!);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$jsonText\n');
  }
  if (options.json) {
    stdout.writeln(jsonText);
  } else {
    stdout
      ..writeln('Fleury web automated validation')
      ..writeln('  strictPass: ${validation['strictPass']}')
      ..writeln('  browser: ${browserCheck['strictPass']}')
      ..writeln('  vm: ${vmCheck['strictPass']}');
    if (options.jsonOutputPath != null) {
      stdout.writeln('  output: ${options.jsonOutputPath}');
    }
  }

  if (options.strict && validation['strictPass'] != true) exit(1);
}

Future<Map<String, Object?>> _runValidationCommand({
  required String id,
  required String label,
  required List<String> command,
  required List<String> testFiles,
}) async {
  final stopwatch = Stopwatch()..start();
  try {
    final result = await Process.run(
      command.first,
      command.skip(1).toList(),
      workingDirectory: Directory.current.path,
    );
    stopwatch.stop();
    return <String, Object?>{
      'id': id,
      'label': label,
      'command': command,
      'testFiles': testFiles,
      'testFileCount': testFiles.length,
      'durationMs': stopwatch.elapsedMilliseconds,
      'exitCode': result.exitCode,
      'strictPass': result.exitCode == 0,
      'stdoutTail': _tail(result.stdout.toString()),
      'stderrTail': _tail(result.stderr.toString()),
    };
  } on ProcessException catch (error) {
    stopwatch.stop();
    return <String, Object?>{
      'id': id,
      'label': label,
      'command': command,
      'testFiles': testFiles,
      'testFileCount': testFiles.length,
      'durationMs': stopwatch.elapsedMilliseconds,
      'exitCode': null,
      'strictPass': false,
      'blockers': <String>['failed to start command: ${error.message}'],
      'stdoutTail': '',
      'stderrTail': _tail(error.toString()),
    };
  }
}

String _tail(String value, {int maxCharacters = 4000}) {
  if (value.length <= maxCharacters) return value;
  return value.substring(value.length - maxCharacters);
}

final class _Options {
  const _Options({
    required this.help,
    required this.json,
    required this.strict,
    required this.jsonOutputPath,
    required this.browserCommand,
    required this.vmCommand,
  });

  final bool help;
  final bool json;
  final bool strict;
  final String? jsonOutputPath;
  final List<String> browserCommand;
  final List<String> vmCommand;

  static _Options parse(List<String> args) {
    var help = false;
    var json = false;
    var strict = false;
    String? jsonOutputPath;
    var browserCommand = webAutomatedBrowserTestCommand();
    var vmCommand = webAutomatedVmTestCommand();

    for (final arg in args) {
      if (arg == '-h' || arg == '--help' || arg == 'help') {
        help = true;
      } else if (arg == '--json') {
        json = true;
      } else if (arg == '--strict') {
        strict = true;
      } else if (arg.startsWith('--json-output=')) {
        jsonOutputPath = arg.substring('--json-output='.length).trim();
      } else if (arg.startsWith('--browser-command-json=')) {
        browserCommand = _parseCommandJson(
          arg.substring('--browser-command-json='.length),
          option: '--browser-command-json',
        );
      } else if (arg.startsWith('--vm-command-json=')) {
        vmCommand = _parseCommandJson(
          arg.substring('--vm-command-json='.length),
          option: '--vm-command-json',
        );
      } else {
        stderr.writeln('Unknown option for web_automated_validation: $arg');
        _printUsage();
        exit(2);
      }
    }

    if (jsonOutputPath != null && jsonOutputPath.isEmpty) {
      stderr.writeln('--json-output requires a non-empty path.');
      exit(2);
    }

    return _Options(
      help: help,
      json: json,
      strict: strict,
      jsonOutputPath: jsonOutputPath,
      browserCommand: browserCommand,
      vmCommand: vmCommand,
    );
  }
}

List<String> _parseCommandJson(String value, {required String option}) {
  Object? decoded;
  try {
    decoded = jsonDecode(value);
  } on FormatException catch (error) {
    stderr.writeln('$option must be a JSON array of strings: ${error.message}');
    exit(2);
  }
  if (decoded is! List ||
      decoded.isEmpty ||
      decoded.any((entry) => entry is! String || entry.trim().isEmpty)) {
    stderr.writeln('$option must be a non-empty JSON array of strings.');
    exit(2);
  }
  return decoded.cast<String>();
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/web_automated_validation.dart [options]',
  );
  stdout.writeln('');
  stdout.writeln(
    'Runs the retained DOM automated browser and VM validation commands and',
  );
  stdout.writeln('writes durable JSON evidence for default-preflight gates.');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln('  --json-output=PATH          Write validation JSON.');
  stdout.writeln(
    '  --strict                    Exit non-zero unless all checks pass.',
  );
  stdout.writeln('  --json                      Print validation JSON.');
  stdout.writeln(
    '  --browser-command-json=JSON Override browser command; tests only.',
  );
  stdout.writeln(
    '  --vm-command-json=JSON      Override VM command; tests only.',
  );
}
