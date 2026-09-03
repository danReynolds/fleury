import 'dart:io';

import 'package:fleury/src/cli/run_command.dart';
import 'package:test/test.dart';

void main() {
  group('parseRunCommand', () {
    test('the first non-flag argument is the script, the rest is its argv', () {
      final run = parseRunCommand(['bin/main.dart', 'asteroids', '--fast'])!;
      expect(run.scriptPath, 'bin/main.dart');
      expect(run.vmOptions, isEmpty);
      expect(run.args, ['asteroids', '--fast']);
    });

    test('flags before the script are VM options for the app process', () {
      final run = parseRunCommand([
        '--enable-asserts',
        '--define=API_URL=https://x',
        'bin/main.dart',
        '--flag',
      ])!;
      expect(run.vmOptions, ['--enable-asserts', '--define=API_URL=https://x']);
      expect(run.scriptPath, 'bin/main.dart');
      expect(run.args, [
        '--flag',
      ], reason: 'after the script, argv is verbatim');
    });

    test('-- ends option parsing so a dash-leading script still runs', () {
      final run = parseRunCommand(['--', '-weird.dart', '--x'])!;
      expect(run.scriptPath, '-weird.dart');
      expect(run.args, ['--x']);
    });

    test('no script is a valid invocation: the entrypoint gets resolved', () {
      expect(parseRunCommand([])!.scriptPath, isNull);
      final withVm = parseRunCommand(['--enable-asserts'])!;
      expect(withVm.scriptPath, isNull);
      expect(withVm.vmOptions, ['--enable-asserts']);
      expect(parseRunCommand(['--'])!.scriptPath, isNull);
    });

    test('a help flag means usage', () {
      expect(parseRunCommand(['--help']), isNull);
      expect(parseRunCommand(['-h']), isNull);
    });
  });

  group('resolveRunEntrypoint', () {
    late Directory project;
    setUp(() {
      project = Directory.systemTemp.createTempSync('fleury_run_entry_');
    });
    tearDown(() => project.deleteSync(recursive: true));

    void write(String relative, [String body = 'void main() {}\n']) {
      File('${project.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(body);
    }

    test('the only Dart file in bin/ is the entrypoint', () {
      write('bin/anything.dart');
      write('bin/notes.txt', 'not dart');
      final r = resolveRunEntrypoint(project);
      expect(r.error, isNull);
      expect(r.path, '${project.path}/bin/anything.dart');
    });

    test('main.dart wins over other files, then run_app.dart', () {
      write('bin/tool.dart');
      write('bin/run_app.dart');
      expect(resolveRunEntrypoint(project).path, endsWith('/bin/run_app.dart'));
      write('bin/main.dart');
      expect(resolveRunEntrypoint(project).path, endsWith('/bin/main.dart'));
    });

    test('the file named after the package is the fallback preference', () {
      write('pubspec.yaml', 'name: myapp\nenvironment:\n  sdk: ^3.6.0\n');
      write('bin/myapp.dart');
      write('bin/helper.dart');
      expect(resolveRunEntrypoint(project).path, endsWith('/bin/myapp.dart'));
    });

    test('an ambiguous bin/ names the candidates instead of guessing', () {
      write('bin/alpha.dart');
      write('bin/beta.dart');
      final r = resolveRunEntrypoint(project);
      expect(r.path, isNull);
      expect(r.error, contains('alpha.dart, beta.dart'));
      expect(r.error, contains('fleury run bin/<file>.dart'));
    });

    test('no bin/ or no Dart files says how to name a script', () {
      expect(resolveRunEntrypoint(project).error, contains('no bin/'));
      write('bin/readme.md', 'x');
      expect(resolveRunEntrypoint(project).error, contains('no Dart files'));
    });
  });
}
