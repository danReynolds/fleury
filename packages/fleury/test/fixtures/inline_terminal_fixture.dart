import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/runtime/dev_bootstrap.dart';

Future<void> main(List<String> args) async {
  if (!DevBootstrap.isSupervisedChild) {
    for (var line = 0; line < 10; line++) {
      stdout.writeln('SHELL-KEEP-$line');
    }
    await stdout.flush();
  }
  final result = await runApp(
    const FleuryApp(title: 'Inline viewport', home: _InlineFixture()),
    mode: const TerminalMode.inline(rows: 8, mouse: true, mouseMotion: true),
    enableHotReload: args.contains('--supervised'),
    debug: const DebugConfig(enabled: false),
    args: args,
  );
  stdout.writeln('INLINE-DONE');
  await stdout.flush();
  exit(switch (result.signal) {
    AppSignal.interrupt => 130,
    AppSignal.terminate => 143,
    AppSignal.hangup => 129,
    null => 0,
  });
}

class _InlineFixture extends StatefulWidget {
  const _InlineFixture();
  @override
  State<_InlineFixture> createState() => _InlineFixtureState();
}

class _InlineFixtureState extends State<_InlineFixture> {
  final controller = TextEditingController();
  var clicks = 0;
  var handedOff = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final session = TerminalSession.of(context);
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeySequence.ctrl.g,
          onTrigger: (_) => session.resizeInline(12),
        ),
        KeyBinding(
          KeySequence.ctrl.s,
          onTrigger: (_) => session.resizeInline(6),
        ),
        KeyBinding(KeySequence.ctrl.q, onTrigger: (_) => requestExit()),
        KeyBinding(
          KeySequence.ctrl.r,
          onTrigger: (_) => DevBootstrap.requestRestartFromApp(),
        ),
        KeyBinding(
          KeySequence.ctrl.k,
          onTrigger: (_) => Process.killPid(pid, ProcessSignal.sigkill),
        ),
        KeyBinding(KeySequence.ctrl.e, onTrigger: (_) => exit(7)),
        KeyBinding(
          KeySequence.ctrl.o,
          onTrigger: (_) async {
            await session.runWithHandoff(() async {
              final child = await Process.start('/bin/sh', [
                '-c',
                'printf "CHILD-OUTPUT\\n"',
              ], mode: ProcessStartMode.inheritStdio);
              await child.exitCode;
            });
            setState(() => handedOff = true);
          },
        ),
      ],
      child: Column(
        children: [
          Text('INLINE-READY $pid ${size.cols}x${size.rows}'),
          Text('clicks=$clicks value=${controller.text}'),
          Button(text: 'Click me', onPressed: () => setState(() => clicks++)),
          TextInput(
            controller: controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          Text(handedOff ? 'AFTER-HANDOFF' : 'Ctrl+G grow / Ctrl+S shrink'),
        ],
      ),
    );
  }
}
