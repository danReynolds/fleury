// First-load bundle-size gate for the served-browser client. A served session
// downloads `remote_client.dart.js` (the thin client that connects back to
// serve), shipped embedded as remote_client_asset.dart and served at
// `GET /client` (fleury.dart). web-capture validates the JS *exists*, not its
// *size* — so a stray import silently adds 100s of KB to first-load with no
// signal. This gates the raw + gzip size of the SHIPPED bytes (no recompile —
// it measures exactly what ships).
//
//   dart run bin/bundle_size_gate.dart [--gate]
//
// Thresholds are generous vs today and SDK-tolerant (dart2js output drifts a
// few % per SDK); a stray import (100s of KB) trips them, normal drift doesn't.

import 'dart:io';

import 'package:fleury/src/remote/remote_client_asset.dart';

const _maxRawKiB = 512;
const _maxGzipKiB = 160;

void main(List<String> args) {
  final raw = remoteClientJs();
  final gz = gzip.encode(raw);
  final rawKiB = raw.length / 1024;
  final gzKiB = gz.length / 1024;

  if (args.contains('--gate')) {
    final ok = rawKiB < _maxRawKiB && gzKiB < _maxGzipKiB;
    stdout.writeln('serve client bundle: ${rawKiB.toStringAsFixed(1)} KiB raw, '
        '${gzKiB.toStringAsFixed(1)} KiB gzip '
        '(limits ${_maxRawKiB} / ${_maxGzipKiB} KiB) ${ok ? 'ok' : 'FAIL'}');
    if (ok) {
      stdout.writeln('bundle-size gate: pass.');
    } else {
      stdout.writeln('bundle-size gate: FAIL — the served-browser first-load '
          'client grew past ${_maxRawKiB} KiB raw / ${_maxGzipKiB} KiB gzip. A '
          'stray import? Check `web/remote_client.dart` deps and rebuild with '
          '`dart tool/fleury_dev.dart build-remote-client`.');
      exitCode = 1;
    }
    return;
  }

  stdout.writeln('Served-browser first-load client '
      '(remote_client.dart.js, served at GET /client):');
  stdout.writeln('  raw:  ${rawKiB.toStringAsFixed(1)} KiB (${raw.length} B)');
  stdout.writeln('  gzip: ${gzKiB.toStringAsFixed(1)} KiB (${gz.length} B)  '
      '— the over-the-wire first-load weight');
}
