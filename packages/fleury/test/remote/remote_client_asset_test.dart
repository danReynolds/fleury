// Freshness gate for the embedded serve client bundle.
//
// `fleury serve` ships the compiled remote client embedded in the binary
// (remote_client_asset.dart). This test recompiles the client from source
// and fails if the committed asset is stale — i.e. someone changed the
// remote-client source without running:
//
//     dart run tool/fleury_dev.dart build-remote-client
//
// Tagged `integration` (it invokes dart2js); run with `-t integration`.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/remote/remote_client_asset.dart';
import 'package:test/test.dart';

void main() {
  test(
    'embedded client asset is in sync with its source',
    () async {
      // test/remote/ -> packages/fleury -> packages -> repo root
      final repoRoot = Directory.current.parent.parent.path;
      final webPkg = '$repoRoot/packages/fleury_web';
      final tmpDir = Directory.systemTemp.createTempSync('fleury-asset-');
      final out = '${tmpDir.path}/rc.js';

      final result = await Process.run('dart', [
        'compile',
        'js',
        'web/remote_client.dart',
        '-o',
        out,
        '-O2',
        '--no-source-maps',
      ], workingDirectory: webPkg);
      expect(
        result.exitCode,
        0,
        reason: 'client must compile:\n${result.stderr}',
      );

      final fresh = File(out).readAsBytesSync();
      final embedded = remoteClientJs();
      tmpDir.deleteSync(recursive: true);
      expect(
        base64.encode(embedded),
        base64.encode(fresh),
        reason:
            'embedded client is stale — run '
            '`dart run tool/fleury_dev.dart build-remote-client`',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
