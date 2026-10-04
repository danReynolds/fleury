@TestOn('posix')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fleury/src/runtime/dev_session.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;
  final servers = <DevSessionServer>[];
  setUp(() {
    project = Directory.systemTemp.createTempSync('fleury_agent_');
    File('${project.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
  });
  tearDown(() async {
    for (final server in servers) {
      await server.close();
    }
    servers.clear();
    project.deleteSync(recursive: true);
  });
  Future<DevSessionServer> start() async {
    final server = await DevSessionServer.start(
      projectDirectory: project.path,
      entrypoint: 'bin/main.dart',
      handle: (method, params) async => method == 'oversized'
          ? {'data': 'x' * (8 * 1024 * 1024)}
          : {'method': method},
    );
    servers.add(server);
    return server;
  }

  test(
    'private project discovery, disconnect and descriptor cleanup',
    () async {
      final server = await start();
      Directory('${project.path}/bin').createSync();
      final client = await DevSessionClient.connect(
        projectDirectory: '${project.path}/bin',
      );
      expect(await client.request('inspect'), {'method': 'inspect'});
      client.close();
      final reattached = await DevSessionClient.connect(
        projectDirectory: project.path,
      );
      expect(await reattached.request('status'), {'method': 'status'});
      reattached.close();
      await server.close();
      servers.clear();
      expect(
        Directory('${project.path}/.dart_tool/fleury/sessions').listSync(),
        isEmpty,
      );
      await expectLater(
        DevSessionClient.connect(projectDirectory: project.path),
        throwsA(isA<DevSessionException>()),
      );
    },
  );

  test(
    'multiple live sessions require explicit selection; ignores stale files',
    () async {
      await start();
      final first = await DevSessionClient.connect(
        projectDirectory: project.path,
      );
      final id = first.sessionId;
      first.close();
      await start();
      File(
        '${project.path}/.dart_tool/fleury/sessions/stale.json',
      ).writeAsStringSync('invalid');
      await expectLater(
        DevSessionClient.connect(projectDirectory: project.path),
        throwsA(
          isA<DevSessionException>().having(
            (e) => e.message,
            'message',
            contains('Multiple'),
          ),
        ),
      );
      final selected = await DevSessionClient.connect(
        projectDirectory: project.path,
        sessionId: id,
      );
      expect(selected.sessionId, id);
      selected.close();
    },
  );

  test('payload and response limits fail without losing the session', () async {
    await start();
    final client = await DevSessionClient.connect(
      projectDirectory: project.path,
    );
    addTearDown(client.close);
    await expectLater(
      client.request('oversized'),
      throwsA(isA<DevSessionException>()),
    );
    await expectLater(
      client.request('status', {'data': 'x' * (8 * 1024 * 1024)}),
      throwsA(isA<DevSessionException>()),
    );
    expect(await client.request('status'), {'method': 'status'});
  });

  test(
    'rejects unauthenticated, browser-origin and version-skew requests',
    () async {
      await start();
      final descriptor =
          Directory(
                '${project.path}/.dart_tool/fleury/sessions',
              ).listSync().single
              as File;
      final data = jsonDecode(descriptor.readAsStringSync()) as Map;
      expect(descriptor.statSync().mode & 0x1ff, 0x180); // 0600
      expect(descriptor.parent.statSync().mode & 0x1ff, 0x1c0); // 0700
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      Future<int> send({
        bool auth = true,
        bool origin = false,
        int version = devSessionProtocolVersion,
      }) async {
        final request = await http.postUrl(
          Uri.parse('http://127.0.0.1:${data['port']}/'),
        );
        if (auth) {
          request.headers.set('Authorization', 'Bearer ${data['token']}');
        }
        if (origin) request.headers.set('Origin', 'https://example.com');
        request.write(
          jsonEncode({
            'protocol': version,
            'method': 'status',
            'params': <String, Object?>{},
          }),
        );
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await send(auth: false), 403);
      expect(await send(origin: true), 403);
      expect(await send(version: 999), 400);
      expect(await send(), 200);
    },
  );
}
