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

    test('no script, or a help flag, means usage', () {
      expect(parseRunCommand([]), isNull);
      expect(parseRunCommand(['--enable-asserts']), isNull);
      expect(parseRunCommand(['--help']), isNull);
      expect(parseRunCommand(['--']), isNull);
    });
  });
}
