import 'dart:io';

import 'package:meta/meta.dart';

import 'posix_driver.dart';
import 'terminal_driver.dart';
import 'windows_driver.dart';

/// Creates the local `dart:io` terminal driver for the current platform.
TerminalDriver createNativeTerminalDriver({
  Stdin? stdinOverride,
  Stdout? stdoutOverride,
}) {
  return createNativeTerminalDriverForPlatform(
    isWindows: Platform.isWindows,
    stdinOverride: stdinOverride,
    stdoutOverride: stdoutOverride,
  );
}

@visibleForTesting
TerminalDriver createNativeTerminalDriverForPlatform({
  required bool isWindows,
  Stdin? stdinOverride,
  Stdout? stdoutOverride,
}) {
  if (isWindows) {
    return WindowsTerminalDriver(
      stdinOverride: stdinOverride,
      stdoutOverride: stdoutOverride,
    );
  }
  return PosixTerminalDriver(
    stdinOverride: stdinOverride,
    stdoutOverride: stdoutOverride,
  );
}
