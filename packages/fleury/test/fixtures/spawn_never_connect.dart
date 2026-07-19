// Adversarial child for `fleury serve --spawn` shutdown tests.
//
// It proves the child has started by recording its PID and assigned socket,
// then deliberately never connects. This leaves serve's warm session in the
// vulnerable Process.start-to-socket-attach window until its supervisor asks
// it to stop.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: spawn_never_connect.dart <state-file>');
    exit(2);
  }

  final handle = Platform.environment['FLEURY_HANDLE'];
  if (handle == null || handle.isEmpty) {
    stderr.writeln('spawn_never_connect fixture: FLEURY_HANDLE not set');
    exit(2);
  }

  final state = <String, Object>{'pid': pid, 'handle': handle};
  final stateFile = File(args.single);
  final childStateDirectory = Directory('${stateFile.path}.children')
    ..createSync(recursive: true);

  // Session 2 deliberately takes the supervisor's full SIGTERM grace period.
  // In the upgraded-browser regression this keeps cleanup awaiting one
  // snapshotted child after session 1's warmup future has completed, making an
  // otherwise tiny post-snapshot spawn race deterministic.
  final sessionMatch = RegExp(r'spawn-\d+-(\d+)\.sock$').firstMatch(handle);
  final sessionId = int.tryParse(sessionMatch?.group(1) ?? '');
  StreamSubscription<ProcessSignal>? termSub;
  if (!Platform.isWindows && sessionId == 2) {
    termSub = ProcessSignal.sigterm.watch().listen((_) {});
  }

  File(
    '${childStateDirectory.path}/$pid.json',
  ).writeAsStringSync(jsonEncode(state), flush: true);
  stateFile.writeAsStringSync(jsonEncode(state), flush: true);

  // Keep a real timer source registered with the isolate. Awaiting a bare,
  // uncompleted Completer does not itself keep the Dart process alive.
  await Future<void>.delayed(const Duration(days: 1));
  await termSub?.cancel();
}
