import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: shell_cli_e2e_runner <package-root> <work-dir>');
    exit(2);
  }

  final packageRoot = Directory(args[0]).absolute;
  final workDir = Directory(args[1]).absolute;
  File('${workDir.path}/pubspec.yaml').writeAsStringSync('''
name: shell_cli_e2e_fixture
environment:
  sdk: ^3.10.4
''');
  final nestedWorkDir = Directory('${workDir.path}/nested/app')
    ..createSync(recursive: true);
  final handle = File('${workDir.path}/.fleury/handle');

  Process? shell;
  Process? contender;
  Process? app;
  try {
    shell = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', '${packageRoot.path}/bin/fleury.dart', 'shell'],
      workingDirectory: workDir.path,
      mode: ProcessStartMode.inheritStdio,
    );

    await _waitFor(
      handle.existsSync,
      timeout: const Duration(seconds: 15),
      what: 'shell handle at ${handle.path}',
    );
    final socketPath = handle.readAsStringSync().trim();
    if (socketPath.isEmpty || File(socketPath).absolute.path != socketPath) {
      throw StateError('shell handle was not absolute: "$socketPath"');
    }
    stdout.writeln('SHELL-CLI-E2E-ABSOLUTE-HANDLE');

    contender = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', '${packageRoot.path}/bin/fleury.dart', 'shell'],
      workingDirectory: workDir.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final contenderCode = await contender.exitCode.timeout(
      const Duration(seconds: 15),
    );
    if (contenderCode != 2) {
      throw StateError('competing shell exited $contenderCode instead of 2');
    }
    var originalExited = false;
    unawaited(shell.exitCode.then((_) => originalExited = true));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (originalExited) {
      throw StateError('the competing shell terminated the original shell');
    }
    stdout.writeln('SHELL-CLI-E2E-DUPLICATE-REFUSED');

    app = await Process.start(
      Platform.resolvedExecutable,
      <String>['${packageRoot.path}/test/fixtures/shell_cli_e2e_app.dart'],
      workingDirectory: nestedWorkDir.path,
      environment: <String, String>{'FLEURY_HANDLE': ''},
    );
    final appStdout = StringBuffer();
    final appStderr = StringBuffer();
    final stdoutSub = app.stdout
        .transform(utf8.decoder)
        .listen(appStdout.write);
    final stderrSub = app.stderr
        .transform(utf8.decoder)
        .listen(appStderr.write);

    final appCode = await app.exitCode.timeout(const Duration(seconds: 20));
    await stdoutSub.cancel();
    await stderrSub.cancel();
    if (appCode != 0) {
      throw StateError(
        'app exited $appCode\nstdout:\n$appStdout\nstderr:\n$appStderr',
      );
    }

    final shellCode = await shell.exitCode.timeout(const Duration(seconds: 10));
    if (shellCode != 0) {
      throw StateError('shell exited $shellCode');
    }
    await _waitFor(
      () => !handle.existsSync() && !File(socketPath).existsSync(),
      timeout: const Duration(seconds: 5),
      what: 'shell handle and socket cleanup',
    );
    stdout.writeln('SHELL-CLI-E2E-CLEANUP');
  } on Object catch (error, stack) {
    stderr
      ..writeln('shell CLI E2E runner failed: $error')
      ..writeln(stack);
    shell?.kill(ProcessSignal.sigkill);
    contender?.kill(ProcessSignal.sigkill);
    app?.kill(ProcessSignal.sigkill);
    if (shell != null) {
      await shell.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }
    if (app != null) {
      await app.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }
    if (contender != null) {
      await contender.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }
    exit(1);
  }
}

Future<void> _waitFor(
  bool Function() check, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('Timed out waiting for $what', timeout);
}
