import 'dart:convert';
import 'dart:io';

/// A dedicated pipe to the container supervisor, independent of logs and HTTP.
/// The supervisor enforces deadlines even if the Dart event loop stops responding.
class Watchdog {
  Watchdog()
    : _pipe = Platform.environment['FLEURY_WATCHDOG_FD'] == null
          ? null
          : File(
              '/dev/fd/${Platform.environment['FLEURY_WATCHDOG_FD']}',
            ).openSync(mode: FileMode.writeOnly);
  final RandomAccessFile? _pipe;
  int _next = 0;
  void ready() => _send('ready');
  int start() {
    final id = ++_next;
    _send('start $id');
    return id;
  }

  void end(int id) => _send('end $id');
  void _send(String message) => _pipe?.writeFromSync(utf8.encode('$message\n'));
}
