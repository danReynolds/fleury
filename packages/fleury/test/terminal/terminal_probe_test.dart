import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('runTerminalProbeSuite', () {
    test('confirms DA, Kitty keyboard, and Kitty graphics replies', () async {
      final report = await runTerminalProbeSuite(
        _FakeTerminalProbeTransport((request) {
          if (request.contains('_G')) {
            return '\x1B_Gi=31;OK\x1B\\\x1B[?1;2c'.codeUnits;
          }
          if (request.contains('[?u')) {
            return '\x1B[?5u\x1B[?1;2c'.codeUnits;
          }
          return '\x1B[?1;2c'.codeUnits;
        }),
      );

      expect(
        report.resultFor('primaryDeviceAttributes')!.status,
        TerminalProbeStatus.confirmed,
      );
      expect(
        report.resultFor('kittyKeyboardStatus')!.status,
        TerminalProbeStatus.confirmed,
      );
      expect(
        report.resultFor('kittyKeyboardStatus')!.details,
        containsPair('flags', 5),
      );
      expect(
        report.resultFor('kittyGraphicsQuery')!.status,
        TerminalProbeStatus.confirmed,
      );
      expect(
        report.confirmedFeatures,
        containsAll(<TerminalFeature>[
          TerminalFeature.kittyKeyboard,
          TerminalFeature.imageKitty,
        ]),
      );
      expect(
        report.toJson()['confirmedFeatures'],
        containsAll(<String>['kittyKeyboard', 'imageKitty']),
      );
      final summary = report.toJson()['summary'] as Map<String, Object?>;
      expect(summary['confirmed'], 3);
      expect(summary['unsupported'], 0);
    });

    test(
      'marks optional protocol probes unsupported when DA replies',
      () async {
        final report = await runTerminalProbeSuite(
          _FakeTerminalProbeTransport((_) => '\x1B[?6c'.codeUnits),
        );

        expect(
          report.resultFor('primaryDeviceAttributes')!.status,
          TerminalProbeStatus.confirmed,
        );
        expect(
          report.resultFor('kittyKeyboardStatus')!.status,
          TerminalProbeStatus.unsupported,
        );
        expect(
          report.resultFor('kittyGraphicsQuery')!.status,
          TerminalProbeStatus.unsupported,
        );
        expect(report.confirmedFeatures, isEmpty);
      },
    );

    test('times out when no terminal replies arrive', () async {
      final report = await runTerminalProbeSuite(
        _FakeTerminalProbeTransport((_) => const <int>[]),
      );

      expect(
        report.probes.map((probe) => probe.status),
        everyElement(TerminalProbeStatus.timeout),
      );
      expect(
        report.resultFor('primaryDeviceAttributes')!.detail,
        contains('No terminal response'),
      );
    });

    test(
      'classifies transport timeout exceptions separately from errors',
      () async {
        final report = await runTerminalProbeSuite(
          _ThrowingTerminalProbeTransport(
            (_) => TimeoutException('scripted timeout'),
          ),
          perProbeTimeout: const Duration(milliseconds: 25),
        );

        expect(
          report.probes.map((probe) => probe.status),
          everyElement(TerminalProbeStatus.timeout),
        );
        expect(
          report.resultFor('primaryDeviceAttributes')!.details,
          containsPair('timeoutMs', 25),
        );
        expect(
          report.resultFor('primaryDeviceAttributes')!.details,
          containsPair('message', 'scripted timeout'),
        );
        final summary = report.toJson()['summary'] as Map<String, Object?>;
        expect(summary['timeout'], 3);
        expect(summary['error'], 0);
      },
    );

    test('keeps non-timeout transport failures as errors', () async {
      final report = await runTerminalProbeSuite(
        _ThrowingTerminalProbeTransport((_) => StateError('broken fixture')),
      );

      expect(
        report.probes.map((probe) => probe.status),
        everyElement(TerminalProbeStatus.error),
      );
      expect(
        report.resultFor('primaryDeviceAttributes')!.detail,
        contains('broken fixture'),
      );
    });

    test(
      'runs probes through a pseudo-terminal fixture when available',
      () async {
        final transport = await _ScriptPseudoTerminalProbeTransport.tryCreate((
          request,
        ) {
          if (request.contains('_G')) {
            return '\x1B_Gi=31;OK\x1B\\\x1B[?1;2c'.codeUnits;
          }
          if (request.contains('[?u')) {
            return '\x1B[?7u\x1B[?1;2c'.codeUnits;
          }
          return '\x1B[?1;2c'.codeUnits;
        });
        if (transport == null) {
          markTestSkipped('script(1) pseudo-terminal fixture is unavailable.');
          return;
        }

        final report = await runTerminalProbeSuite(
          transport,
          perProbeTimeout: const Duration(seconds: 2),
        );

        expect(
          report.probes.map((probe) => probe.status),
          everyElement(TerminalProbeStatus.confirmed),
        );
        expect(
          report.resultFor('kittyKeyboardStatus')!.details,
          containsPair('flags', 7),
        );
        expect(report.summary['confirmed'], 3);
        expect(
          report.confirmedFeatures,
          containsAll(<TerminalFeature>[
            TerminalFeature.kittyKeyboard,
            TerminalFeature.imageKitty,
          ]),
        );
      },
    );
  });
}

final class _FakeTerminalProbeTransport implements TerminalProbeTransport {
  const _FakeTerminalProbeTransport(this.respond);

  final List<int> Function(String request) respond;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    return respond(bytes);
  }
}

final class _ThrowingTerminalProbeTransport implements TerminalProbeTransport {
  const _ThrowingTerminalProbeTransport(this.errorFor);

  final Object Function(String request) errorFor;

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    throw errorFor(bytes);
  }
}

final class _ScriptPseudoTerminalProbeTransport
    implements TerminalProbeTransport {
  const _ScriptPseudoTerminalProbeTransport(this.respond);

  final List<int> Function(String request) respond;

  static Future<_ScriptPseudoTerminalProbeTransport?> tryCreate(
    List<int> Function(String request) respond,
  ) async {
    if (Platform.isWindows) return null;
    try {
      final result = await Process.run('script', const <String>[
        '-q',
        '/dev/null',
        '/bin/sh',
        '-c',
        'printf ok',
      ]).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0 || !result.stdout.toString().contains('ok')) {
        return null;
      }
      return _ScriptPseudoTerminalProbeTransport(respond);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<int>> request(String bytes, {required Duration timeout}) async {
    final response = _printfOctalEscaped(respond(bytes));
    final readLength = bytes.codeUnits.length;
    final command =
        'stty raw -echo 2>/dev/null || true; '
        'dd bs=1 count=$readLength of=/dev/null 2>/dev/null; '
        "printf '$response'";
    final process = await Process.start('script', <String>[
      '-q',
      '/dev/null',
      '/bin/sh',
      '-c',
      command,
    ]);
    process.stdin.add(bytes.codeUnits);
    await process.stdin.close();

    final stdoutBytes = process.stdout.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final stderrText = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();

    try {
      final exitCode = await process.exitCode.timeout(timeout);
      final output = await stdoutBytes;
      final stderr = await stderrText;
      if (exitCode != 0) {
        throw StateError('script pseudo-terminal exited $exitCode: $stderr');
      }
      return output;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      throw TimeoutException('script pseudo-terminal fixture timed out');
    }
  }
}

String _printfOctalEscaped(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(r'\');
    buffer.write(byte.toRadixString(8).padLeft(3, '0'));
  }
  return buffer.toString();
}
