// Freshness gate for the embedded serve client bundle.
//
// `fleury serve` ships the compiled remote client embedded in the binary
// (remote_client_asset.dart). This test recompiles the client from source and
// fails if the committed asset is stale — i.e. someone changed the
// remote-client source without running:
//
//     dart run tool/fleury_dev.dart build-remote-client
//
// It delegates to that tool's `--check` mode, which compiles the client (so
// this also catches a client that no longer compiles) and compares a hash of
// the *source* closure — NOT the compiled bytes. dart2js output is not stable
// across SDK versions, so a byte-compare drifts red on any SDK skew between the
// machine that ran build-remote-client and CI; the source fingerprint tracks
// only what the gate actually cares about: did the source change without a
// rebuild.
//
// Tagged `integration` (it invokes dart2js); run with `-t integration`.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'embedded client asset is in sync with its source',
    () async {
      // test/remote/ -> packages/fleury -> packages -> repo root
      final repoRoot = Directory.current.parent.parent.path;
      final result = await Process.run('dart', [
        'run',
        'tool/fleury_dev.dart',
        'build-remote-client',
        '--check',
      ], workingDirectory: repoRoot);
      expect(
        result.exitCode,
        0,
        reason:
            'embedded client is stale or no longer compiles — run '
            '`dart run tool/fleury_dev.dart build-remote-client`.\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
