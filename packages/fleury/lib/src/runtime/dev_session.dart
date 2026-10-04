import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const devSessionProtocolVersion = 1;
const devAgentEnvironment = 'FLEURY_DEV_AGENT';
const _maxBytes = 8 * 1024 * 1024;

final class DevSessionException implements Exception {
  const DevSessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One loopback endpoint owned by the supervisor, surviving child restarts.
/// Only a private descriptor grants access. Never accepts browser origins.
final class DevSessionServer {
  DevSessionServer._(this._server, this._descriptor, this._token, this._handle);
  final HttpServer _server;
  final File _descriptor;
  final String _token;
  final Future<Map<String, Object?>> Function(String, Map<String, Object?>)
  _handle;
  int _active = 0;

  static Future<DevSessionServer> start({
    required String projectDirectory,
    required String entrypoint,
    required Future<Map<String, Object?>> Function(String, Map<String, Object?>)
    handle,
  }) async {
    final directory = Directory(
      '${_projectRoot(projectDirectory).path}/.dart_tool/fleury/sessions',
    );
    await directory.create(recursive: true);
    await _private(directory.path, '700');
    final random = Random.secure();
    final token = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final id = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final descriptor = File('${directory.path}/$id.json');
    try {
      await descriptor.writeAsString(
        jsonEncode({
          'protocol': devSessionProtocolVersion,
          'sessionId': id,
          'pid': pid,
          'entrypoint': entrypoint,
          'port': server.port,
          'token': token,
        }),
      );
      await _private(descriptor.path, '600');
      final result = DevSessionServer._(server, descriptor, token, handle);
      server.listen(result._request);
      return result;
    } catch (_) {
      await server.close(force: true);
      if (await descriptor.exists()) await descriptor.delete();
      rethrow;
    }
  }

  Future<void> _request(HttpRequest request) async {
    if (request.method != 'POST' ||
        request.uri.path != '/' ||
        request.headers['origin'] != null ||
        request.headers[HttpHeaders.authorizationHeader]?.join(',') !=
            'Bearer $_token') {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (_active >= 16) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    _active++;
    try {
      final body = jsonDecode(
        await _readBounded(request).timeout(const Duration(seconds: 5)),
      );
      if (body is! Map<String, dynamic> ||
          body['protocol'] != devSessionProtocolVersion ||
          body['method'] is! String ||
          body['params'] is! Map<String, dynamic>) {
        throw const DevSessionException('Invalid development request/version.');
      }
      final result =
          await _handle(
            body['method'] as String,
            (body['params'] as Map).cast<String, Object?>(),
          ).timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw const DevSessionException(
              'Development request timed out; an operation may still be running. Read status before retrying.',
            ),
          );
      final bytes = utf8.encode(jsonEncode({'result': result}));
      if (bytes.length > _maxBytes) {
        throw const DevSessionException(
          'Inspection exceeds the response limit.',
        );
      }
      request.response.headers.contentType = ContentType.json;
      request.response.add(bytes);
    } catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': error.toString()}));
    } finally {
      _active--;
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    if (await _descriptor.exists()) await _descriptor.delete();
  }
}

/// A client disconnect never stops the supervisor or its app.
final class DevSessionClient {
  DevSessionClient._(this.sessionId, this._port, this._token);
  final String sessionId;
  final int _port;
  final String _token;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2);

  /// Resolves only sessions in this project. Stale descriptors are ignored;
  /// multiple live sessions require an explicit id, never an arbitrary choice.
  static Future<DevSessionClient> connect({
    required String projectDirectory,
    String? sessionId,
  }) async {
    final directory = Directory(
      '${_projectRoot(projectDirectory).path}/.dart_tool/fleury/sessions',
    );
    final candidates = <DevSessionClient>[];
    if (await directory.exists()) {
      await for (final file in directory.list()) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        DevSessionClient? client;
        try {
          final data = jsonDecode(await file.readAsString()) as Map;
          if (data['protocol'] != devSessionProtocolVersion ||
              (sessionId != null && data['sessionId'] != sessionId)) {
            continue;
          }
          client = DevSessionClient._(
            data['sessionId'] as String,
            data['port'] as int,
            data['token'] as String,
          );
          await client.request('status').timeout(const Duration(seconds: 2));
          candidates.add(client);
        } catch (_) {
          client?.close();
        }
      }
    }
    if (candidates.length == 1) return candidates.single;
    for (final candidate in candidates) {
      candidate.close();
    }
    throw DevSessionException(
      candidates.isEmpty
          ? 'No live Fleury development session. Start fleury run --agent in this project.'
          : 'Multiple Fleury sessions: ${candidates.map((c) => c.sessionId).join(', ')}. Pass --session=<id>.',
    );
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final bytes = utf8.encode(
      jsonEncode({
        'protocol': devSessionProtocolVersion,
        'method': method,
        'params': params,
      }),
    );
    if (bytes.length > _maxBytes) {
      throw const DevSessionException(
        'Development payload exceeds the size limit.',
      );
    }
    final request = await _http.postUrl(Uri.parse('http://127.0.0.1:$_port/'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 46));
    final data = jsonDecode(await _readBounded(response)) as Map;
    if (response.statusCode != HttpStatus.ok || data['result'] is! Map) {
      throw DevSessionException(
        data['error']?.toString() ?? 'Development session unavailable.',
      );
    }
    return (data['result'] as Map).cast<String, Object?>();
  }

  void close() => _http.close(force: true);
}

Directory _projectRoot(String path) {
  var directory = Directory(path).absolute;
  while (!File(
    '${directory.path}/.dart_tool/package_config.json',
  ).existsSync()) {
    if (directory.parent.path == directory.path) {
      throw const DevSessionException('No Dart project found.');
    }
    directory = directory.parent;
  }
  return Directory(directory.resolveSymbolicLinksSync());
}

Future<void> _private(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw const DevSessionException(
      'Cannot protect development session descriptor.',
    );
  }
}

Future<String> _readBounded(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream.timeout(const Duration(seconds: 46))) {
    if (bytes.length + chunk.length > _maxBytes) {
      throw const DevSessionException(
        'Development payload exceeds the size limit.',
      );
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}
