import 'dart:convert';

import 'package:fleury_dartpad_host/precompiled_starter.dart';
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
  const source = 'Widget buildApp() => const Text("Starter");';
  final kernel = base64Encode([1, 2, 3]);
  final artifact = {
    'buildId': 'build-a',
    'source': source,
    'result': 'starter JavaScript',
    'deltaDill': kernel,
  };
  final starter = PrecompiledStarter.fromJson(
    artifact,
    buildId: 'build-a',
    source: source,
  );
  assert(starter.matches('compileNewDDC', source));
  assert(!starter.matches('compileNewDDC', '$source\n// edited'));
  assert(!starter.matches('compileNewDDCReload', source));
  rejects(
    () => PrecompiledStarter.fromJson(
      artifact,
      buildId: 'build-b',
      source: source,
    ),
  );
  rejects(
    () => PrecompiledStarter.fromJson(
      artifact,
      buildId: 'build-a',
      source: 'changed',
    ),
  );
  for (final broken in [
    null,
    {},
    {...artifact, 'result': ''},
    {...artifact, 'deltaDill': 'not base64'},
    {...artifact, 'deltaDill': ''},
  ]) {
    rejects(
      () => PrecompiledStarter.fromJson(
        broken,
        buildId: 'build-a',
        source: source,
      ),
    );
  }
  var now = 100;
  final signer = Checkpoints('build-a', List.filled(32, 1), now: () => now);
  final first = starter.response(signer);
  assert(first['result'] == artifact['result']);
  assert(signer.open(first['deltaDill']) == kernel);
  now += Checkpoints.lifetimeSeconds;
  rejects(() => signer.open(first['deltaDill']));
  final later = starter.response(signer);
  assert(later['deltaDill'] != first['deltaDill']);
  assert(signer.open(later['deltaDill']) == kernel);
  final replacement = Checkpoints(
    'build-a',
    List.filled(32, 2),
    now: () => now,
  );
  assert(
    replacement.open(starter.response(replacement)['deltaDill']) == kernel,
  );
  rejects(() => replacement.open(later['deltaDill']));
  print('Starter build/source matching and fresh checkpoint checks passed.');
}
