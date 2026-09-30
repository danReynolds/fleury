// Dependency-free executable assertions, run with --enable-asserts.
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:fleury_dartpad_host/docs_origin.dart';
import 'package:fleury_dartpad_host/request_policy.dart';

void rejects(void Function() action) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected rejection');
}

void main() {
  final docs = DocsOrigin('https://docs.example.com');
  assert(!DocsOrigin(null).allows(null));
  assert(!docs.allows('null'));
  assert(!docs.allows('https://docs.example.com.evil.test'));
  assert(docs.allows('https://docs.example.com'));
  Request preflight(
    String origin, [
    String header = 'Content-Type, X-Fleury-Build',
  ]) => Request(
    'OPTIONS',
    Uri.parse('https://compiler.example.com/api/v3/compileNewDDC'),
    headers: {
      'origin': origin,
      'access-control-request-method': 'POST',
      'access-control-request-headers': header,
    },
  );
  assert(
    docs.preflight(preflight('https://docs.example.com')).statusCode == 204,
  );
  assert(docs.preflight(preflight('https://evil.test')).statusCode == 403);
  assert(
    docs
            .preflight(preflight('https://docs.example.com', 'Authorization'))
            .statusCode ==
        403,
  );
  assert(
    !docs
        .headers(preflight('https://evil.test'))
        .containsKey('access-control-allow-origin'),
  );
  assert(
    !docs
        .headers(preflight('https://docs.example.com'))
        .containsKey('access-control-allow-credentials'),
  );
  var now = 100;
  final key = List<int>.generate(32, (i) => i);
  final signer = Checkpoints('build-a', key, now: () => now);
  final peer = Checkpoints('build-a', key, now: () => now);
  final kernel = base64Encode([1, 2, 3]);
  final token = signer.seal(kernel);
  assert(peer.open(token) == kernel);
  rejects(() => signer.open(token.replaceFirst('AQID', 'AQIE')));
  rejects(() => signer.open('$token.extra'));
  rejects(() => signer.open(kernel));
  rejects(() => signer.open(42));
  rejects(() => signer.open('x' * (Checkpoints.maxTokenLength + 1)));
  rejects(() => Checkpoints('build-b', key, now: () => now).open(token));
  rejects(
    () =>
        Checkpoints('build-a', List.filled(32, 42), now: () => now).open(token),
  );
  now += Checkpoints.lifetimeSeconds;
  rejects(() => signer.open(token));
  for (final source in [
    "import 'file:///etc/passwd';",
    "export '../../secret.dart';",
    "part '/tmp/input.dart';",
    "part of 'file:///tmp/secret.dart';",
    "import 'dart:io';",
    "import 'dart:_internal';",
    "import 'package:fleury/../../secret.dart';",
    "import 'package:fleury/%2e%2e/secret.dart';",
    "import 'package:fleury/\\u002e\\u002e/secret.dart';",
    "import 'https://example.com/input.dart';",
    "import 'dart:core' if (dart.library.io) 'file:///etc/passwd';",
    "export 'dart:core' if (dart.library.io) '../../secret.dart';",
    "import 'package:fleury_pad/bootstrap.dart';",
  ]) {
    rejects(() => validateSource(source));
  }
  validateSource(
    "import 'package:fleury/fleury_core.dart'; Widget buildApp() => const Text('safe');",
  );
  validateSource(
    "import 'dart:math'; // import 'file:///etc/passwd';\nconst text = \"import 'file:///tmp';\";",
  );
  validateSource("import 'package:fleury/';"); // editor completion prefix
  rejects(() => validatePayload({'source': 'hello', 'offset': -1}, 'complete'));
  rejects(() => validatePayload({'source': 'hello', 'offset': 6}, 'complete'));
  rejects(() => validatePayload({'source': 'hello'}, 'complete'));
  rejects(() => validatePayload({'source': 'hello', 'offset': '1'}, 'format'));
  rejects(() => validatePayload({'source': 'é' * 32001}, 'analyze'));
  assert(
    validatePayload({'source': '', 'extra': 'ignored'}, 'analyze').length == 1,
  );
  final project = {'main.dart': "import 'views/card.dart';", 'views/card.dart': "import '../model.dart';", 'model.dart': 'class Model {}'};
  validatePayload({'source': project['main.dart'], 'files': project, 'activeFile': 'model.dart', 'offset': 5}, 'complete');
  for (final bad in ['../escape.dart', '/tmp/escape.dart', 'bootstrap.dart', 'a/../../escape.dart', 'a%2fb.dart', 'a\\b.dart']) {
    rejects(() => validatePayload({'source': '', 'files': {'main.dart': '', bad: ''}}, 'analyze'));
  }
  rejects(() => validatePayload({'source': '', 'files': {'main.dart': '', 'secret.dart': "import 'file:///etc/passwd';"}}, 'analyze'));
  rejects(() => validatePayload({'source': '', 'files': {'main.dart': '', 'secret.dart': "import '../outside.dart';"}}, 'analyze'));
  rejects(() => validatePayload({'source': '', 'files': {'main.dart': '', 'a.dart': 'x' * 64001}}, 'analyze'));
  rejects(() => validatePayload({'source': '', 'files': {'main.dart': 'mismatch'}}, 'analyze'));
  rejects(() => validatePayload({'source': '', 'files': {'main.dart': ''}, 'activeFile': '../outside.dart'}, 'analyze'));
  print(
    'Checkpoint authentication, expiry, cross-instance, URI and payload checks passed.',
  );
}
