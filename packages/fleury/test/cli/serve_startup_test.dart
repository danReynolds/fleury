@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.absolute.path;
  final cli = '$packageRoot/bin/fleury.dart';
  final packageConfig = '$packageRoot/.dart_tool/package_config.json';
  late Directory working;

  setUp(() {
    working = Directory.systemTemp.createTempSync('fleury_serve_startup_');
  });
  tearDown(() {
    working.deleteSync(recursive: true);
  });

  List<String> command(List<String> flags, {bool spawn = false}) => [
    '--packages=$packageConfig',
    cli,
    'serve',
    ...flags,
    if (spawn) ...[
      '--spawn',
      Platform.resolvedExecutable,
      '--packages=$packageConfig',
      '$packageRoot/test/fixtures/spawn_app.dart',
      'startup-probe',
    ],
  ];

  for (final port in ['abc', '-1', '65536', '']) {
    test('rejects --port=$port with a usable argument error', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        command(['--port=$port'], spawn: true),
        workingDirectory: working.path,
      );
      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains('--port requires an integer from 0 to 65535'),
      );
      expect(result.stderr, isNot(contains('Unhandled exception')));
      expect(working.listSync(), isEmpty);
    });
  }

  for (final spawn in [false, true]) {
    final mode = spawn ? 'spawn' : 'bridge';
    test(
      '$mode reports a busy port and releases startup resources',
      () async {
        final listener = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        try {
          final result = await Process.run(
            Platform.resolvedExecutable,
            command(['--port=${listener.port}'], spawn: spawn),
            workingDirectory: working.path,
          );
          expect(result.exitCode, 1);
          expect(
            result.stderr,
            contains('could not bind 127.0.0.1:${listener.port}'),
          );
          expect(result.stderr, isNot(contains('Unhandled exception')));
          expect(File('${working.path}/.fleury/handle').existsSync(), isFalse);
        } finally {
          await listener.close();
        }
        // A failed bridge bind must also release its local handle lock.
        await _verifyFreePort(command(['--port=0'], spawn: spawn), working);
      },
      skip: Platform.isWindows ? 'Serve uses Unix-domain sockets.' : false,
    );

    test(
      '$mode --port=0 prints a reachable selected port',
      () async {
        await _verifyFreePort(command(['--port=0'], spawn: spawn), working);
      },
      skip: Platform.isWindows ? 'Serve uses Unix-domain sockets.' : false,
    );
  }
}

Future<void> _verifyFreePort(List<String> args, Directory working) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    args,
    workingDirectory: working.path,
  );
  final output = StringBuffer();
  final ready = Completer<Uri>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        output.writeln(line);
        final match = RegExp(r'^  browser:\s+(http://\S+)').firstMatch(line);
        if (match != null && !ready.isCompleted) {
          ready.complete(Uri.parse(match.group(1)!));
        }
      });
  final stdoutDone = process.stdout.drain<void>();
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(StateError('serve exited $code: $output'));
      }
    }),
  );
  final client = HttpClient();
  try {
    final uri = await ready.future.timeout(const Duration(seconds: 15));
    expect(uri.port, inInclusiveRange(1, 65535), reason: '$output');
    final response = await (await client.getUrl(uri)).close();
    expect(response.statusCode, HttpStatus.ok);
    await response.drain<void>();
  } finally {
    client.close(force: true);
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await stderrDone.cancel();
    await stdoutDone;
  }
  expect(File('${working.path}/.fleury/handle').existsSync(), isFalse);
}
