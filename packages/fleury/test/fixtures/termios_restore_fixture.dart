import 'dart:ffi';
import 'dart:io';

import 'package:fleury/src/terminal/posix_driver.dart';

void main() {
  final mode = NativePosixTerminalModeController();
  if (!mode.enableRawMode()) exit(1);
  // dart:io may close stdin on another thread after subscription cancellation.
  // Make that ordering deterministic: restoration must no longer depend on 0.
  DynamicLibrary.process()
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close')(0);
  if (!mode.restoreMode()) exit(2);
  stdout.writeln('restored');
}
