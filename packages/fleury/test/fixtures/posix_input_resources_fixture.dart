// Descriptor accounting runs in a dedicated process: other dart:test workers
// share the process descriptor table and can invalidate a before/after count.
import 'dart:ffi';
import 'dart:io';

import 'package:fleury/src/terminal/posix_input_lease.dart';
import 'package:stdio/stdio.dart';

final fcntl = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
      int Function(int, int, int)
    >('fcntl');

int count() {
  var result = 0;
  for (var fd = 0; fd < 4096; fd++) {
    if (fcntl(fd, 1, 0) >= 0) result++;
  }
  return result;
}

Future<void> main(List<String> args) async {
  PosixInputLease lease({int source = 0, bool fail = false}) => PosixInputLease(
    source: source,
    onBytes: (_) => throw StateError('unexpected input'),
    onDone: () => throw StateError('unexpected EOF'),
    onError: (error, _) => throw error,
    beforeSpawn: fail
        ? () => throw StateError('injected startup failure')
        : null,
  );
  final initialFlags = fcntl(0, 3, 0);
  final warm = lease();
  await warm.start();
  if (args.contains('--fatal-owner')) {
    // A bounded native poll must not strand VM shutdown after root failure.
    throw StateError('intentional owner failure');
  }
  if (args.contains('--backpressure')) {
    stdout.writeln('PRESSURE READY');
    await stdout.flush();
    final output = FdTerminalSink(1);
    // stdin/stdout/stderr alias the same PTY open file description. The test
    // deliberately stops draining output, exercising EAGAIN in the real sink.
    for (var i = 0; i < 32; i++) {
      output.write('X' * 65536);
    }
    await warm.stop();
    final nonblocking = Platform.isMacOS ? 4 : 2048;
    if ((fcntl(0, 3, 0) & nonblocking) != (initialFlags & nonblocking)) {
      throw StateError('input blocking mode changed');
    }
    stdout.writeln('\nBACKPRESSURE PASS');
    return;
  }
  await warm.stop();
  final baseline = count();
  final flags = fcntl(0, 3, 0);
  for (var i = 0; i < 100; i++) {
    final input = lease();
    await input.start();
    await input.stop();
    for (final failed in [lease(source: -1), lease(fail: true)]) {
      var rejected = false;
      try {
        await failed.start();
      } catch (_) {
        rejected = true;
      }
      await failed.stop();
      if (!rejected) throw StateError('startup should fail');
    }
    if (count() != baseline) {
      throw StateError('descriptor leak: $baseline -> ${count()}');
    }
    if (fcntl(0, 3, 0) != flags) throw StateError('input flags changed');
  }
  stdout.writeln('LEASE RESOURCES PASS');
}
