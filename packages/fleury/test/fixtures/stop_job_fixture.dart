// For test/fixtures/stop_job_pty_harness.py: stops its own job [iterations]
// times with PosixJobControl.stopJob and, each time the call returns, writes
// one byte to file descriptor 3 with write(2) through FFI, the kind of call
// the driver's resume makes next (tcsetattr, then the terminal writes). The
// harness continues the job after each stop and counts the bytes it finds
// while the job is stopped: a byte there was written after stopJob returned
// but before the job stopped.
//
// usage: stop_job_fixture.dart <iterations>

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fleury/src/terminal/posix_driver.dart';

final _write = DynamicLibrary.process()
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)
    >('write');

void main(List<String> args) {
  final iterations = int.parse(args[0]);
  final byte = calloc<Uint8>()..value = 0x41;
  for (var i = 0; i < iterations; i++) {
    if (!PosixJobControl.stopJob()) {
      stderr.writeln('stopJob declined at iteration $i');
      exit(2);
    }
    if (_write(3, byte, 1) != 1) {
      stderr.writeln('write failed at iteration $i');
      exit(3);
    }
  }
}
