import 'package:fleury/fleury_core.dart';

// A finite, in-memory task for this example. No files or network requests.
class DemoWork extends Notifier {
  Future<void>? _finishing;
  bool finished = false;
  bool _closed = false;
  bool get finishing => _finishing != null;

  Future<void> finish() => _finishing ??= _finish();

  Future<void> _finish() async {
    // Notify after finish() has assigned the shared future.
    await Future<void>.delayed(Duration.zero);
    if (_closed) return;
    notify();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    finished = true;
    if (!_closed) notify();
  }

  Future<void> close() async {
    _closed = true;
    await _finishing;
    dispose();
  }
}

class ShutdownPanel extends StatelessWidget {
  const ShutdownPanel({required this.work, required this.onFinish, super.key});
  final DemoWork work;
  final void Function() onFinish;

  @override
  Widget build(BuildContext context) => NotifierBuilder(
    notifier: work,
    builder: (context, work) => Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(work.finishing ? 'Finishing current item…' : 'Sample task'),
          const SizedBox(height: 1),
          Button(
            text: 'Finish',
            autofocus: true,
            onPressed: work.finishing ? null : onFinish,
          ),
        ],
      ),
    ),
  );
}

int signalExitCode(AppSignal? signal) => switch (signal) {
  AppSignal.interrupt => 130,
  AppSignal.terminate => 143,
  AppSignal.hangup => 129,
  null => 0,
};
