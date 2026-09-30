import 'dart:convert';

import 'request_policy.dart';

/// One immutable build artifact, never a cache of submitted user code.
class PrecompiledStarter {
  PrecompiledStarter.fromJson(
    Object? value, {
    required String buildId,
    required this.source,
  }) {
    if (value is! Map<String, dynamic> ||
        value['buildId'] != buildId ||
        value['source'] != source ||
        value['result'] is! String ||
        (value['result'] as String).isEmpty ||
        value['deltaDill'] is! String ||
        (value['deltaDill'] as String).isEmpty ||
        (value['deltaDill'] as String).length > Checkpoints.maxKernelLength) {
      throw const FormatException(
        'Precompiled starter is stale or invalid. Rerun dartpad/setup.py.',
      );
    }
    javascript = value['result'] as String;
    kernel = value['deltaDill'] as String;
    base64Decode(kernel);
  }

  final String source;
  late final String javascript;
  late final String kernel;

  bool matches(String method, String requestedSource) =>
      method == 'compileNewDDC' && requestedSource == source;

  Map<String, String> response(Checkpoints checkpoints) => {
    'result': javascript,
    // Sign at request time, so the build artifact never expires or contains a key.
    'deltaDill': checkpoints.seal(kernel),
  };
}
