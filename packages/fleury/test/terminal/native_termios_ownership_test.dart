@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fleury/src/terminal/posix_driver.dart';
import 'package:test/test.dart';

void main() {
  late _TermiosSystem system;
  late NativePosixTerminalModeController mode;
  setUp(() {
    system = _TermiosSystem();
    mode = NativePosixTerminalModeController.withBindings(system.bindings);
  });
  tearDown(() => calloc.free(system.errno));

  test('unavailable bindings permit fallback without an owned handle', () {
    final unavailable = NativePosixTerminalModeController.withBindings(null);
    expect(unavailable.enableRawMode(), isFalse);
    expect(unavailable.restoreMode(), isTrue);
  });

  test('dup failure is an entry error with nothing left to restore', () {
    system.duplicateError = 24;
    expect(mode.enableRawMode, throwsA(_osError(24)));
    expect(mode.restoreMode(), isTrue);
    expect(system.closed, isEmpty);
    expect(system.writtenModes, isEmpty);
  });

  test('snapshot failure retains its handle until cleanup closes it', () {
    system.snapshotError = 5;
    expect(mode.enableRawMode, throwsA(_osError(5)));
    expect(system.closed, isEmpty);
    expect(mode.restoreMode(), isTrue);
    expect(system.closed, [40]);
    expect(system.writtenModes, isEmpty);
    expect(mode.restoreMode(), isTrue);
    expect(system.closed, [40]);
  });

  test('failed raw entry can roll back a partial terminal mutation', () {
    system.rawError = 5;
    expect(mode.enableRawMode, throwsA(_osError(5)));
    expect(system.currentMode, _raw);
    expect(system.closed, isEmpty);
    expect(mode.restoreMode(), isTrue);
    expect(system.currentMode, _original);
    expect(system.writtenModes, [_raw, _original]);
    expect(system.closed, [40]);
  });

  test('failed restore remains a failure after its handle is retired', () {
    expect(mode.enableRawMode(), isTrue);
    system.restoreError = 5;
    final failure = _failure(mode.restoreMode);
    expect(failure, _osError(5));
    expect(system.closed, [40]);
    expect(mode.restoreMode, throwsA(same(failure)));
    expect(mode.enableRawMode, throwsA(same(failure)));
    expect(system.closed, [40], reason: 'never close a possibly reused fd');
    expect(system.duplicateCalls, 1);
  });

  test('failed close is retained and its descriptor is never retried', () {
    expect(mode.enableRawMode(), isTrue);
    system.closeError = 4;
    final failure = _failure(mode.restoreMode);
    expect(failure, _osError(4));
    expect(system.currentMode, _original);
    expect(mode.restoreMode, throwsA(same(failure)));
    expect(mode.enableRawMode, throwsA(same(failure)));
    expect(system.closed, [40]);
    expect(system.duplicateCalls, 1);
  });

  test('snapshot and close failures cannot disappear behind fallback', () {
    system.snapshotError = 5;
    system.closeError = 4;
    expect(mode.enableRawMode, throwsA(_osError(5)));
    final failure = _failure(mode.restoreMode);
    expect(failure, _osError(4));
    expect(mode.restoreMode, throwsA(same(failure)));
    expect(system.closed, [40]);
  });

  test(
    'restoration failure takes precedence over a following close failure',
    () {
      expect(mode.enableRawMode(), isTrue);
      system.restoreError = 5;
      system.closeError = 4;
      final failure = _failure(mode.restoreMode);
      expect(failure, _osError(5));
      expect(mode.restoreMode, throwsA(same(failure)));
      expect(system.closed, [40]);
    },
  );

  test('physical hangup excuses mode failure only, never close failure', () {
    expect(mode.enableRawMode(), isTrue);
    system.restoreError = 5;
    system.hungUp = true;
    system.closeError = 4;
    final failure = _failure(mode.restoreMode);
    expect(failure, _osError(4));
    expect(system.hangupProbes, [40]);
    expect(mode.restoreMode, throwsA(same(failure)));
    expect(system.closed, [40]);
  });

  test('physical hangup with completed close is fully released', () {
    expect(mode.enableRawMode(), isTrue);
    system.restoreError = 5;
    system.hungUp = true;
    expect(mode.restoreMode(), isTrue);
    expect(system.hangupProbes, [40]);
    expect(system.closed, [40]);
    expect(mode.restoreMode(), isTrue);
  });

  test('successful handoff cycles retain the first complete snapshot', () {
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(mode.enableRawMode(), isTrue);
      expect(system.currentMode, _raw);
      expect(mode.restoreMode(), isTrue);
      expect(system.currentMode, _original);
    }
    expect(system.snapshotCalls, 1);
    expect(system.closed, [40, 41, 42]);
  });
}

Matcher _osError(int code) =>
    isA<OSError>().having((error) => error.errorCode, 'errno', code);

Object _failure(bool Function() operation) {
  try {
    operation();
  } catch (error) {
    return error;
  }
  fail('Expected terminal operation to fail');
}

const _original = 0x41;
const _raw = 0x52;

final class _TermiosSystem {
  final errno = calloc<Int32>();
  int currentMode = _original;
  int duplicateError = 0;
  int snapshotError = 0;
  int rawError = 0;
  int restoreError = 0;
  int closeError = 0;
  bool hungUp = false;
  int duplicateCalls = 0;
  int snapshotCalls = 0;
  final writtenModes = <int>[];
  final closed = <int>[];
  final hangupProbes = <int>[];

  late final bindings = PosixTermiosBindings(
    duplicate: (source, command, minimum) {
      final fd = 40 + duplicateCalls++;
      errno.value = duplicateError;
      return duplicateError == 0 ? fd : -1;
    },
    tcgetattr: (fd, storage) {
      snapshotCalls++;
      errno.value = snapshotError;
      if (snapshotError != 0) return -1;
      storage.cast<Uint8>().value = currentMode;
      return 0;
    },
    cfmakeraw: (storage) => storage.cast<Uint8>().value = _raw,
    tcsetattr: (fd, action, storage) {
      final requested = storage.cast<Uint8>().value;
      writtenModes.add(requested);
      final failure = requested == _raw ? rawError : restoreError;
      // Deliberately mutate even when raw entry fails: ownership must survive
      // a possibly partial native operation until the snapshot is restored.
      if (failure == 0 || requested == _raw) currentMode = requested;
      errno.value = failure;
      return failure == 0 ? 0 : -1;
    },
    close: (fd) {
      closed.add(fd);
      errno.value = closeError;
      return closeError == 0 ? 0 : -1;
    },
    errno: () => errno,
    descriptorHungUp: (fd) {
      hangupProbes.add(fd);
      return hungUp;
    },
  );
}
