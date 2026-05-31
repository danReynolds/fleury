// Drives the hot reload probe end to end. See ../README.md for context.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _targetRelativePath = 'tool/hot_reload_probe/target.dart';

Future<void> main() async {
  final targetFile = File(_targetRelativePath);
  if (!await targetFile.exists()) {
    stderr.writeln(
      'driver: cannot find $_targetRelativePath '
      '(run from the fleury package root).',
    );
    exit(2);
  }

  final originalSource = await targetFile.readAsString();
  Process? child;
  VmService? vm;
  var exitCode = 0;

  try {
    final dartExecutable = Platform.resolvedExecutable;
    child = await Process.start(dartExecutable, [
      'run',
      '--enable-vm-service=0',
      '--disable-service-auth-codes',
      _targetRelativePath,
    ]);

    final wsUri = await _awaitWebSocketUri(child);
    print('driver: connected to ${wsUri.toString()}');

    vm = await vmServiceConnectUri(wsUri.toString());
    await vm.streamListen(EventStreams.kIsolate);

    final isolateId = await _firstIsolateId(vm);
    await _awaitExtension(vm, isolateId, 'ext.fleury.probe');

    final preReload = await _snapshot(vm, isolateId);
    _printSnapshot('pre-reload', preReload);

    await _mutateSource(targetFile, originalSource);

    final reloadReport = await vm.reloadSources(isolateId);
    print('driver: reloadSources success=${reloadReport.success}');
    if (reloadReport.success != true) {
      stderr.writeln('driver: reload failed: ${reloadReport.toJson()}');
      exitCode = 3;
      return;
    }

    // Give the runtime a beat to settle before we re-snapshot.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final postReload = await _snapshot(vm, isolateId);
    _printSnapshot('post-reload', postReload);

    final verdict = _verdict(preReload, postReload);
    print('\ndriver: verdict');
    for (final line in verdict.lines) {
      print('  $line');
    }
    if (!verdict.allPassed) {
      exitCode = 1;
    }
  } catch (error, stack) {
    stderr.writeln('driver: error: $error');
    stderr.writeln(stack);
    exitCode = 4;
  } finally {
    await targetFile.writeAsString(originalSource);
    await vm?.dispose();
    child?.kill(ProcessSignal.sigterm);
    if (child != null) {
      await child.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          child!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  exit(exitCode);
}

Future<Uri> _awaitWebSocketUri(Process child) {
  final completer = Completer<Uri>();
  final stdoutLines = child.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  late StreamSubscription<String> sub;
  sub = stdoutLines.listen((line) {
    print('target| $line');
    if (completer.isCompleted) return;
    final uri = _parseObservatoryUri(line);
    if (uri != null) {
      completer.complete(uri);
      // ignore: unawaited_futures
      sub.cancel();
    }
  });
  child.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr.writeln('target!| $line'));
  return completer.future.timeout(const Duration(seconds: 15));
}

Uri? _parseObservatoryUri(String line) {
  final match = RegExp(r'(http://[^\s]+)').firstMatch(line);
  if (match == null) return null;
  final httpUri = Uri.parse(match.group(1)!);
  return httpUri.replace(
    scheme: 'ws',
    path: httpUri.path.endsWith('/')
        ? '${httpUri.path}ws'
        : '${httpUri.path}/ws',
  );
}

Future<String> _firstIsolateId(VmService vm) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final vmInfo = await vm.getVM();
    final isolates = vmInfo.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('No isolate appeared on the VM service.');
}

Future<void> _awaitExtension(
  VmService vm,
  String isolateId,
  String name,
) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final isolate = await vm.getIsolate(isolateId);
    final extensions = isolate.extensionRPCs ?? const <String>[];
    if (extensions.contains(name)) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Extension $name never registered.');
}

Future<Map<String, Object?>> _snapshot(VmService vm, String isolateId) async {
  final response = await vm.callServiceExtension(
    'ext.fleury.probe',
    isolateId: isolateId,
  );
  final json = response.json;
  if (json == null) {
    throw StateError('probe extension returned no payload');
  }
  return Map<String, Object?>.from(json);
}

Future<void> _mutateSource(File file, String original) async {
  const needle = "'Counter v1: \$value'";
  const replacement = "'Counter v2 [reloaded]: \$value'";
  if (!original.contains(needle)) {
    throw StateError(
      'Source did not contain the expected literal $needle; '
      'the probe needs adjusting.',
    );
  }
  final mutated = original.replaceFirst(needle, replacement);
  await file.writeAsString(mutated);
  print('driver: mutated target source ($needle -> $replacement)');
}

void _printSnapshot(String label, Map<String, Object?> snap) {
  print('\ndriver: $label snapshot');
  final chords = snap.keys.toList()..sort();
  for (final key in chords) {
    print('  $key = ${snap[key]}');
  }
}

class _Verdict {
  _Verdict({required this.lines, required this.allPassed});
  final List<String> lines;
  final bool allPassed;
}

_Verdict _verdict(Map<String, Object?> pre, Map<String, Object?> post) {
  final lines = <String>[];
  bool allPassed = true;

  void check(String name, bool passed, {String? detail}) {
    final status = passed ? 'PASS' : 'FAIL';
    lines.add('[$status] $name${detail == null ? '' : ' — $detail'}');
    if (!passed) allPassed = false;
  }

  // 1. Instance identity survives reload.
  final identityPreserved = post['identity_preserved'] == true;
  check(
    'instance identity preserved across reload',
    identityPreserved,
    detail:
        'pre=${pre['instance_identity_hash']}, '
        'post=${post['instance_identity_hash']}',
  );

  // 2. Type identity: post-reload instance type matches the type of a
  //    fresh post-reload instance (== and ideally identical).
  final typeEqualsFresh = post['instance_type_equals_fresh'] == true;
  check(
    'instance.runtimeType == fresh.runtimeType after reload',
    typeEqualsFresh,
  );
  final typeIdenticalFresh = post['instance_type_identical_fresh'] == true;
  check(
    'identical(instance.runtimeType, fresh.runtimeType) after reload',
    typeIdenticalFresh,
  );

  // 3. Type identity: post-reload instance type matches the type
  //    captured before reload (stable Type object across reload).
  final typeEqualsCaptured = post['instance_type_equals_captured'] == true;
  check(
    'instance.runtimeType == capturedRuntimeType after reload',
    typeEqualsCaptured,
  );
  final typeIdenticalCaptured =
      post['instance_type_identical_captured'] == true;
  check(
    'identical(instance.runtimeType, capturedRuntimeType) after reload',
    typeIdenticalCaptured,
  );

  // 4. Field preservation: the counter value stays at 5.
  final valuePreserved = post['instance_value'] == pre['instance_value'];
  check(
    'instance field value preserved across reload',
    valuePreserved,
    detail: 'pre=${pre['instance_value']}, post=${post['instance_value']}',
  );

  // 5. Method-body refresh: post-reload label() returns the new literal.
  final preLabel = pre['instance_label']?.toString() ?? '';
  final postLabel = post['instance_label']?.toString() ?? '';
  final methodBodyRefreshed =
      postLabel.contains('v2 [reloaded]') && !preLabel.contains('v2');
  check(
    'method body dispatches to reloaded code',
    methodBodyRefreshed,
    detail: 'pre.label="$preLabel", post.label="$postLabel"',
  );

  return _Verdict(lines: lines, allPassed: allPassed);
}
