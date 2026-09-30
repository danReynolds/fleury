// Fleury host; DartPad owns compilation, analysis, and scheduling.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fleury_dartpad_host/request_policy.dart';
import 'package:fleury_dartpad_host/compiler_backend.dart';
import 'package:fleury_dartpad_host/precompiled_starter.dart';
import 'package:fleury_dartpad_host/docs_origin.dart';
import 'package:fleury_dartpad_host/watchdog.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf;

Future<void> main() async {
  final watchdog = Watchdog();
  final port = int.parse(Platform.environment['PORT'] ?? '4346');
  final bind = Platform.environment['FLEURY_PAD_BIND'] ?? '127.0.0.1';
  final configuredOrigin = Platform.environment['FLEURY_PAD_ORIGIN'];
  final proxyOrigin = Platform.environment['FLEURY_PAD_PROXY_ORIGIN'];
  final docsOrigin = DocsOrigin(Platform.environment['FLEURY_PAD_DOCS_ORIGIN']);
  if (proxyOrigin != null) {
    final uri = Uri.parse(proxyOrigin);
    if (uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'FLEURY_PAD_PROXY_ORIGIN must be an HTTP loopback origin.',
      );
    }
  }
  final cloudRun = Platform.environment.containsKey('K_SERVICE');
  final key = Platform.environment['FLEURY_CHECKPOINT_KEY'];
  if (bind != '127.0.0.1' &&
      ((configuredOrigin == null && !cloudRun) ||
          key == null ||
          Platform.environment['FLEURY_WATCHDOG_FD'] == null)) {
    throw StateError(
      'Hosted mode requires an explicit origin, checkpoint key, and supervisor.',
    );
  }
  final origin = configuredOrigin ?? 'http://127.0.0.1:$port';
  final originUri = Uri.parse(origin);
  if (!{'http', 'https'}.contains(originUri.scheme) ||
      originUri.host.isEmpty ||
      originUri.userInfo.isNotEmpty ||
      originUri.path.isNotEmpty ||
      originUri.hasQuery ||
      originUri.hasFragment ||
      (originUri.scheme != 'https' && originUri.host != '127.0.0.1')) {
    throw StateError(
      'FLEURY_PAD_ORIGIN must be an HTTPS origin (HTTP loopback is allowed).',
    );
  }
  final hostRoot = File.fromUri(Platform.script).parent.parent.path;
  final root = path.dirname(hostRoot);
  final build = path.join(root, '.build');
  // A compiled host lives beside this source, outside the Dart SDK.
  final sdkPath =
      Platform.environment['DART_SDK'] ??
      path.dirname(path.dirname(Platform.resolvedExecutable));
  final manifest = File(path.join(build, 'manifest.json')).readAsStringSync();
  final buildId =
      (jsonDecode(manifest) as Map<String, dynamic>)['buildId'] as String;
  final checkpoints = Checkpoints(
    buildId,
    key == null ? Checkpoints.ephemeralKey() : base64Decode(key),
  );
  final api = createCompilerBackend(root, sdkPath);
  final starter = PrecompiledStarter.fromJson(
    jsonDecode(File(path.join(build, 'starter.json')).readAsStringSync()),
    buildId: buildId,
    source: File(path.join(root, 'lib/main.dart')).readAsStringSync(),
  );
  // HTTP assets are usable while language services initialize. Compiler
  // requests share this barrier and remain bounded by the process watchdog.
  final backendReady = Completer<bool>();
  final assets = <String, (String, String)>{
    '': (path.join(hostRoot, 'web/index.html'), 'text/html'),
    'frame.html': (path.join(root, 'frame.html'), 'text/html'),
    'frame.js': (path.join(root, 'frame.js'), 'text/javascript'),
    'loader.js': (
      path.join(sdkPath, 'lib/dev_compiler/ddc/ddc_module_loader.js'),
      'text/javascript',
    ),
    'sdk.js': (path.join(build, 'sdk.js'), 'text/javascript'),
    'deps.js': (path.join(build, 'deps.js'), 'text/javascript'),
    'sample.dart': (path.join(root, 'lib/main.dart'), 'text/plain'),
    // The docs examples' font, so a reader's run matches the prebuilt preview.
    'fleury-mono.woff2': (
      path.join(root, '../../website/public/fonts/fleury-mono.woff2'),
      'font/woff2',
    ),
  };
  // The frame names its runtime by build, so browsers keep one copy per build
  // instead of downloading it again for every run.
  final versioned = {'frame.js', 'loader.js', 'sdk.js', 'deps.js'};
  final frameHtml = versioned.fold(
    File(path.join(root, 'frame.html')).readAsStringSync(),
    (html, name) => html.replaceAll('"/$name"', '"/$name?v=$buildId"'),
  ).replaceAll('fleury-mono.woff2', 'fleury-mono.woff2?v=$buildId');
  for (final file in Directory(
    path.join(build, 'editor'),
  ).listSync().whereType<File>()) {
    final name = path.basename(file.path);
    final mime = name.endsWith('.css')
        ? 'text/css'
        : name.endsWith('.ttf')
        ? 'font/ttf'
        : 'text/javascript';
    assets['editor/$name'] = (file.path, mime);
  }
  const methods = {
    'compileNewDDC',
    'compileNewDDCReload',
    'analyze',
    'complete',
    'format',
    'document',
  };
  bool isDocsApi(Request request) =>
      request.url.path == 'api/build' ||
      (request.url.pathSegments.length == 3 &&
          request.url.pathSegments[0] == 'api' &&
          request.url.pathSegments[1] == 'v3' &&
          methods.contains(request.url.pathSegments[2]));
  var active = 0;
  var stopping = false;
  Response jsonError(int status, String message) => Response(
    status,
    body: jsonEncode({'error': message}),
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      if (status == 429 || status == 503) 'retry-after': '2',
    },
  );
  Future<Response> handle(Request request) async {
    if (request.method == 'GET' && request.url.path == 'healthz') {
      return stopping ? jsonError(503, 'Stopping.') : Response.ok('ready');
    }
    if (stopping) return jsonError(503, 'Compiler restarting. Try again.');
    // Cloud Run checks routing and IAM before forwarding requests, including
    // revision URLs used to verify candidates before promotion.
    final requestOrigin = cloudRun && configuredOrigin == null
        ? 'https://${request.headers['host']}'
        : origin;
    if ((!cloudRun || configuredOrigin != null) &&
        request.headers['host'] != originUri.authority) {
      return jsonError(403, 'Unrecognized host.');
    }
    if (request.method == 'OPTIONS' && isDocsApi(request))
      return docsOrigin.preflight(request);
    if (request.method == 'GET') {
      if (request.url.path == 'api/build') {
        return Response.ok(
          manifest,
          headers: {
            'content-type': 'application/json',
            'cache-control': 'no-store',
          },
        );
      }
      if (request.url.path == 'api/v3/version') {
        if (!await backendReady.future)
          return jsonError(503, 'Compiler restarting. Try again.');
        return api.router.call(request);
      }
      final asset = assets[request.url.path];
      if (asset == null) return Response.notFound('Not found');
      final immutable = request.url.queryParameters['v'] == buildId;
      final font = request.url.path == 'fleury-mono.woff2';
      return Response.ok(
        request.url.path == 'frame.html'
            ? frameHtml
            : File(asset.$1).openRead(),
        headers: {
          'content-type': asset.$2,
          'cache-control': immutable
              ? 'public, max-age=31536000, immutable'
              : 'no-cache',
          // The opaque-origin frame loads the font with CORS.
          if (font) 'access-control-allow-origin': '*',
          // Apps may reach only the image service the loading-data guide
          // demonstrates; any other request from user code is blocked.
          if (request.url.path == 'frame.html')
            'content-security-policy':
                "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'unsafe-inline'; font-src 'self'; img-src data: blob:; connect-src https://picsum.photos https://fastly.picsum.photos; base-uri 'none'; form-action 'none'; frame-ancestors 'self' ${docsOrigin.origin ?? ''}",
          if (request.url.path.isEmpty)
            'content-security-policy':
                "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; worker-src 'self' blob:; frame-src 'self'; connect-src 'self'; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        },
      );
    }
    if (request.method != 'POST' ||
        request.url.pathSegments.length != 3 ||
        request.url.pathSegments[0] != 'api' ||
        request.url.pathSegments[1] != 'v3' ||
        !methods.contains(request.url.pathSegments[2]))
      return Response.notFound('Not found');
    if ((request.headers['origin'] != null &&
            request.headers['origin'] != requestOrigin &&
            request.headers['origin'] != proxyOrigin &&
            !docsOrigin.allows(request.headers['origin'])) ||
        request.mimeType != 'application/json')
      return jsonError(403, 'Same-origin JSON requests only.');
    if (request.headers['x-fleury-build'] != buildId) {
      return jsonError(
        409,
        'Compiler build changed. Reload the page; your source is saved.',
      );
    }
    if (active >= 8) return jsonError(429, 'Compiler busy. Try again.');
    active++;
    final operation = watchdog.start();
    final timer = Stopwatch()..start();
    final method = request.url.pathSegments.last;
    var precompiled = false;
    try {
      if ((request.contentLength ?? 0) > 2100000)
        return jsonError(413, 'Request too large.');
      final bytes = <int>[];
      try {
        await for (final chunk in request.read().timeout(
          const Duration(seconds: 5),
        )) {
          if (bytes.length + chunk.length > 2100000)
            return jsonError(413, 'Request too large.');
          bytes.addAll(chunk);
        }
      } on TimeoutException {
        return jsonError(408, 'Request body timed out.');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final payload = validatePayload(decoded, method);
      if (method == 'compileNewDDCReload') {
        try {
          payload['deltaDill'] = checkpoints.open(decoded['deltaDill']);
        } on FormatException {
          return Response(
            400,
            body: jsonEncode({
              'error': 'Invalid or expired reload checkpoint. Restart the app.',
              'code': 'checkpoint_rejected',
            }),
            headers: {
              'content-type': 'application/json',
              'cache-control': 'no-store',
            },
          );
        }
      } else if ((decoded as Map).containsKey('deltaDill')) {
        return jsonError(400, 'Checkpoints are only accepted for reload.');
      }
      if (!payload.containsKey('files') &&
          starter.matches(method, payload['source'] as String)) {
        precompiled = true;
        // All request guards still apply. The known starter needs neither a
        // compiler job nor the language-service initialization barrier.
        return Response.ok(
          jsonEncode(starter.response(checkpoints)),
          headers: {
            'content-type': 'application/json',
            'cache-control': 'no-store',
            'x-fleury-precompiled': 'starter',
          },
        );
      }
      // Preserve upstream scheduling and diagnostics. Authenticate checkpoints
      // without changing the browser's opaque-token protocol.
      if (!await backendReady.future)
        return jsonError(503, 'Compiler restarting. Try again.');
      final response =
          await (payload.containsKey('files')
                  ? handleProject(api, method, payload)
                  : api.router.call(request.change(body: jsonEncode(payload))))
              .timeout(const Duration(seconds: 24));
      if (response.statusCode == 200 && method.startsWith('compile')) {
        final result =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        result['deltaDill'] = checkpoints.seal(result['deltaDill'] as String);
        return Response.ok(
          jsonEncode(result),
          headers: {
            'content-type': 'application/json',
            'x-compile-ms': '${timer.elapsedMilliseconds}',
            'cache-control': 'no-store',
          },
        );
      }
      return response.change(headers: {'cache-control': 'no-store'});
    } on FormatException catch (error) {
      return jsonError(400, error.message);
    } on TimeoutException {
      // A timeout must not leave the worker accepting new requests. Container
      // PID 1 kills its process group on exit; the independent deadline also
      // catches synchronous stalls. Never merely abandon a compiler Future.
      stopping = true;
      Timer(const Duration(milliseconds: 100), () => exit(124));
      return jsonError(503, 'Compiler timed out and is restarting. Try again.');
    } catch (_) {
      return jsonError(500, 'Compiler request failed. Try again.');
    } finally {
      active--;
      watchdog.end(operation);
      print(
        jsonEncode({
          'event': 'request',
          'method': method,
          'precompiled': precompiled,
          'elapsedMs': timer.elapsedMilliseconds,
          'buildId': buildId,
        }),
      );
    }
  }

  final handler = const Pipeline()
      .addMiddleware(
        (inner) => (request) async {
          final response = await inner(request);
          return response.change(
            headers: {
              if (isDocsApi(request)) ...docsOrigin.headers(request),
              if (request.url.path != 'frame.html')
                'x-frame-options': 'SAMEORIGIN',
              'x-content-type-options': 'nosniff',
              'referrer-policy': 'no-referrer',
              'permissions-policy': 'camera=(), microphone=(), geolocation=()',
            },
          );
        },
      )
      .addHandler(handle);
  final server = await shelf.serve(handler, bind, port);
  // The frame's CSP permits only the compiler and the configured docs origin.
  // Dart's default SAMEORIGIN header would otherwise block that explicit embed.
  server.defaultResponseHeaders.removeAll('X-Frame-Options');
  server.autoCompress = true;
  watchdog.ready();
  print(
    jsonEncode({'event': 'http_ready', 'origin': origin, 'buildId': buildId}),
  );
  unawaited(() async {
    // Once HTTP is open, initialization has the same independent deadline as
    // work. A broken analyzer must not leave an apparently healthy idle host.
    final operation = watchdog.start();
    final timer = Stopwatch()..start();
    try {
      await api.init();
      backendReady.complete(true);
      print(
        jsonEncode({
          'event': 'ready',
          'buildId': buildId,
          'backendInitMs': timer.elapsedMilliseconds,
        }),
      );
    } catch (_) {
      backendReady.complete(false);
      stopping = true;
      print(jsonEncode({'event': 'backend_start_failed', 'buildId': buildId}));
      Timer(const Duration(milliseconds: 100), () => exit(1));
    } finally {
      watchdog.end(operation);
    }
  }());
  Future<void> stop(ProcessSignal _) async {
    if (stopping) return;
    stopping = true;
    await server
        .close()
        .then<void>((_) {})
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () async {
            await server.close(force: true);
          },
        );
    await (() async {
      if (await backendReady.future) await api.shutdown();
    })().timeout(const Duration(seconds: 1), onTimeout: () {});
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  ProcessSignal.sigterm.watch().listen(stop);
}
