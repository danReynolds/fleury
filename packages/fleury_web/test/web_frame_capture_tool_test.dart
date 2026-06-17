@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/web_frame_capture.dart' as web_frame_capture;

void main() {
  test(
    'web frame capture static server confines requests to page directory',
    () {
      final root = Directory.systemTemp.createTempSync(
        'fleury_web_static_root_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      File('${root.path}/index.html').writeAsStringSync('');
      File('${root.path}/benchmark_capture.dart.js').writeAsStringSync('');

      expect(
        web_frame_capture
            .resolveFrameCaptureStaticFile(root, Uri.parse('/'))!
            .path,
        '${root.path}${Platform.pathSeparator}index.html',
      );
      expect(
        web_frame_capture
            .resolveFrameCaptureStaticFile(
              root,
              Uri.parse('/benchmark_capture.dart.js'),
            )!
            .path,
        '${root.path}${Platform.pathSeparator}benchmark_capture.dart.js',
      );
      expect(
        web_frame_capture
            .resolveFrameCaptureStaticFile(root, Uri.parse('/../secret.txt'))!
            .path,
        '${root.path}${Platform.pathSeparator}secret.txt',
      );
      expect(
        web_frame_capture
            .resolveFrameCaptureStaticFile(
              root,
              Uri.parse('/%2e%2e/secret.txt'),
            )!
            .path,
        '${root.path}${Platform.pathSeparator}secret.txt',
      );
      expect(
        web_frame_capture.resolveFrameCaptureStaticFile(
          root,
          Uri.parse('/..%2Fsecret.txt'),
        ),
        isNull,
      );
      expect(
        web_frame_capture.resolveFrameCaptureStaticFile(
          root,
          Uri.parse('/encoded%2Fseparator.txt'),
        ),
        isNull,
      );
    },
  );

  test('web frame capture tool lists browser scenarios as JSON', () async {
    final result = await _runCaptureTool(['--list', '--json']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final decoded = jsonDecode(result.stdout.toString());
    expect(decoded, isA<Map<String, Object?>>());
    final scenarios = (decoded as Map<String, Object?>)['scenarios'];
    expect(scenarios, isA<List<Object?>>());
    final ids = [
      for (final scenario in scenarios as List<Object?>)
        (scenario as Map<String, Object?>)['id'],
    ];
    expect(ids, contains('normal-80x24'));
    expect(ids, contains('large-160x50'));
    expect(ids, contains('stress-300x100'));
    expect(ids, contains('text-input-burst-80x24'));
  });

  test('web frame capture tool lists browser scenarios as text', () async {
    final result = await _runCaptureTool(['--list']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('Web benchmark scenarios:'));
    expect(result.stdout, contains('normal-80x24'));
    expect(result.stdout, contains('single-dirty-cell-160x50'));
  });

  test('web frame capture help documents visual-only diagnostics', () async {
    final result = await _runCaptureTool(['--help']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('--disable-semantics'));
    expect(result.stdout, contains('inaccessible visual-only run'));
  });

  test(
    'web frame capture tool rejects unknown scenario before browser work',
    () async {
      final result = await _runCaptureTool(['--scenario=missing', '--json']);

      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains('Unknown web benchmark scenario: missing'),
      );
      expect(result.stdout, contains('Web benchmark scenarios:'));
    },
  );

  test(
    'web frame capture tool validates numeric options before browser work',
    () async {
      final invalidFrames = await _runCaptureTool(['--frames=0']);
      expect(invalidFrames.exitCode, 2);
      expect(
        invalidFrames.stderr,
        contains('--frames= requires a positive integer.'),
      );

      final invalidWarmup = await _runCaptureTool(['--warmup=-1']);
      expect(invalidWarmup.exitCode, 2);
      expect(
        invalidWarmup.stderr,
        contains('--warmup= requires a non-negative integer.'),
      );

      final invalidBudget = await _runCaptureTool(['--budget-ms=0']);
      expect(invalidBudget.exitCode, 2);
      expect(
        invalidBudget.stderr,
        contains('--budget-ms= requires a positive number.'),
      );

      final emptyPageDir = await _runCaptureTool(['--page-dir=']);
      expect(emptyPageDir.exitCode, 2);
      expect(
        emptyPageDir.stderr,
        contains('--page-dir requires a non-empty path.'),
      );
    },
  );

  test(
    'web frame capture tool rejects unknown options before browser work',
    () async {
      final result = await _runCaptureTool(['--bogus']);

      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains('Unknown option for web_frame_capture: --bogus'),
      );
      expect(
        result.stdout,
        contains('Usage: dart run tool/web_frame_capture.dart'),
      );
    },
  );

  test(
    'web frame capture compile-only JSON is clean and preserves page directory',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'fleury_web_compile_page_root_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final pageDir = Directory('${root.path}/compiled-page');
      final result = await _runCaptureTool([
        '--compile-only',
        '--page-dir=${pageDir.path}',
        '--json',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final decoded =
          jsonDecode(result.stdout.toString()) as Map<String, Object?>;
      expect(decoded['kind'], 'fleuryWebFrameCompileResult');
      expect(decoded['pageDir'], pageDir.absolute.path);
      expect(pageDir.existsSync(), isTrue);
      expect(File('${pageDir.path}/index.html').existsSync(), isTrue);
      expect(
        File('${pageDir.path}/benchmark_capture.dart.js').existsSync(),
        isTrue,
      );
      expect(result.stdout, isNot(contains('Compiled ')));
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'web frame capture cleans up Chrome process when DevTools never starts',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('fake Chrome shell script is Unix-only');
      }

      final tempDir = Directory.systemTemp.createTempSync(
        'fleury_web_fake_chrome_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final pidFile = File('${tempDir.path}/pid');
      final terminatedFile = File('${tempDir.path}/terminated');
      final fakeChrome = File('${tempDir.path}/fake-chrome.sh');
      fakeChrome.writeAsStringSync('''
#!/bin/sh
echo "\$\$" > "${pidFile.path}"
trap 'echo terminated > "${terminatedFile.path}"; exit 0' TERM INT
while :; do
  sleep 1 &
  wait \$!
done
''');
      final chmod = await Process.run('chmod', ['+x', fakeChrome.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());

      final result = await _runCaptureTool([
        '--scenario=normal-80x24',
        '--frames=1',
        '--warmup=0',
        '--chrome=${fakeChrome.path}',
        '--timeout=1',
        '--json',
      ]);
      addTearDown(() async {
        final pidText = pidFile.existsSync() ? pidFile.readAsStringSync() : '';
        final pid = int.tryParse(pidText.trim());
        if (pid != null) {
          await Process.run('kill', ['-TERM', '$pid']);
        }
      });

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Timed out waiting for Chrome DevTools'));
      await _waitForFile(terminatedFile);
      expect(terminatedFile.readAsStringSync().trim(), 'terminated');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'web frame capture cleans up Chrome profile when executable cannot start',
    () async {
      final tempRoot = Directory.systemTemp.createTempSync(
        'fleury_web_missing_chrome_root_',
      );
      addTearDown(() {
        if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
      });

      final missingChrome = File('${tempRoot.path}/missing-chrome');
      final result = await _runCaptureTool(
        [
          '--scenario=normal-80x24',
          '--frames=1',
          '--warmup=0',
          '--chrome=${missingChrome.path}',
          '--timeout=1',
          '--json',
        ],
        environment: {'TMPDIR': tempRoot.path},
      );

      expect(result.exitCode, isNot(0));
      final leakedProfileDirs = tempRoot
          .listSync()
          .where(
            (entry) =>
                entry is Directory &&
                entry.uri.pathSegments.last.startsWith(
                  'fleury_web_chrome_profile_',
                ),
          )
          .toList();
      expect(leakedProfileDirs, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

Future<ProcessResult> _runCaptureTool(
  List<String> args, {
  Map<String, String>? environment,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/web_frame_capture.dart', ...args],
    workingDirectory: Directory.current.path,
    environment: environment,
  );
}

Future<void> _waitForFile(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for ${file.path}');
}
