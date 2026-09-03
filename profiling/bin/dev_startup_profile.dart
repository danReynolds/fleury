// Dev-mode startup profile: how long from spawning a command until the app's
// runtime is entered and until its first frame is on the terminal.
//
// Runs the command under `capture_pty.dart --answer-probes` (a cooperative
// terminal) with `FLEURY_RUNTIME_MARKERS` set, then combines the capture's
// epoch clock with the runtime's marker epochs. Reports per run and medians:
//
//   spawn→vm      first "VM service is listening" banner on the PTY, i.e. the
//                 moment a flag-enabled VM (a supervised child, or the only
//                 process under `fleury run`) started — blank when none
//   spawn→runApp  the runtime entry of whichever process ended up owning the
//                 terminal (a supervised child overwrites its parent's marks)
//   spawn→frame   the first frame's bytes written
//
//   dart run bin/dev_startup_profile.dart [--runs 3] [--timeout 8] \
//       [--cwd <dir>] -- <command...>
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  var runs = 3;
  var timeout = 8.0;
  String? cwd;
  final cmd = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--runs') {
      runs = int.parse(args[++i]);
    } else if (a == '--timeout') {
      timeout = double.parse(args[++i]);
    } else if (a == '--cwd') {
      cwd = args[++i];
    } else if (a == '--') {
      cmd.addAll(args.sublist(i + 1));
      break;
    } else {
      stderr.writeln('unknown option $a');
      exit(64);
    }
  }
  if (cmd.isEmpty) {
    stderr.writeln('usage: dev_startup_profile [--runs N] [--timeout S] '
        '[--cwd DIR] -- <command...>');
    exit(64);
  }
  final profilingDir = File.fromUri(Platform.script).parent.parent.path;
  final tmp = Directory.systemTemp.createTempSync('fleury_dev_startup_');
  final rows = <_Row>[];
  print('command: ${cmd.join(' ')}${cwd == null ? '' : '  (cwd $cwd)'}');
  for (var i = 0; i < runs; i++) {
    final marks = '${tmp.path}/marks_$i.json';
    final cap = '${tmp.path}/cap_$i';
    final shell = [
      if (cwd != null) 'cd ${_quote(cwd)} &&',
      'FLEURY_RUNTIME_MARKERS=${_quote(marks)}',
      'exec',
      ...cmd.map(_quote),
    ].join(' ');
    final result = await Process.run(
        'dart',
        [
          'run',
          'capture_pty.dart',
          '--answer-probes',
          '--out',
          cap,
          '--timeout',
          '$timeout',
          '--',
          '/bin/sh',
          '-c',
          shell,
        ],
        workingDirectory: profilingDir);
    final row = _parse(cap, marks);
    if (row == null) {
      print('run ${i + 1}: no runtime markers — did the app reach runApp? '
          '(${result.stderr.toString().trim().split('\n').last})');
      continue;
    }
    rows.add(row);
    print('run ${i + 1}: ${row.format()}');
  }
  if (rows.isEmpty) exit(1);
  final med = _Row(
    toVm: _median(rows.map((r) => r.toVm).whereType<double>().toList()),
    toEntry: _median(rows.map((r) => r.toEntry).toList())!,
    toFrame: _median(rows.map((r) => r.toFrame).toList())!,
  );
  print('median: ${med.format()}  (${rows.length} runs)');
  tmp.deleteSync(recursive: true);
}

final class _Row {
  const _Row(
      {required this.toVm, required this.toEntry, required this.toFrame});
  final double? toVm;
  final double toEntry;
  final double toFrame;

  String format() => 'spawn→vm ${toVm == null ? '     -' : _ms(toVm!)}  '
      'spawn→runApp ${_ms(toEntry)}  spawn→frame ${_ms(toFrame)}  '
      '(runtime ${_ms(toFrame - toEntry)})';
}

String _ms(double v) => '${v.toStringAsFixed(0).padLeft(5)} ms';

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

_Row? _parse(String cap, String marks) {
  final capJson = File('$cap.json');
  final marksFile = File(marks);
  if (!capJson.existsSync() || !marksFile.existsSync()) return null;
  final capture =
      jsonDecode(capJson.readAsStringSync()) as Map<String, Object?>;
  final t0 = capture['captureStartEpochMicros'] as int;
  final markers = (jsonDecode(marksFile.readAsStringSync())
      as Map<String, Object?>)['markers'] as List<Object?>;
  int? epochOf(String label) {
    for (final m in markers.cast<Map<String, Object?>>()) {
      if (m['label'] == label) return m['epochMicros'] as int;
    }
    return null;
  }

  final entry = epochOf('runApp.entry');
  final frame = epochOf('first.output.write');
  if (entry == null || frame == null) return null;
  // The VM banner is the first PTY read whose bytes carry it.
  double? toVm;
  final bytes = File('$cap.bin').readAsBytesSync();
  var offset = 0;
  for (final read
      in (capture['reads'] as List<Object?>).cast<List<Object?>>()) {
    final at = (read[0] as num).toDouble();
    final n = read[1] as int;
    final chunk = latin1.decode(bytes.sublist(offset, offset + n));
    offset += n;
    if (chunk.contains('VM service is listening')) {
      toVm = at;
      break;
    }
  }
  return _Row(
    toVm: toVm,
    toEntry: (entry - t0) / 1000,
    toFrame: (frame - t0) / 1000,
  );
}

String _quote(String s) => "'${s.replaceAll("'", r"'\''")}'";
