import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main() => runApp(const Toaster(maxToasts: 1, child: ToastDemo()));

/// Synthetic operation feedback: no clipboard, storage or network access.
class ToastDemo extends StatefulWidget {
  const ToastDemo({super.key});

  @override
  State<ToastDemo> createState() => _ToastDemoState();
}

class _ToastDemoState extends State<ToastDemo> {
  final _copyResultId = Object();
  ToastHandle? _toast;

  void _result({required bool failure}) {
    _toast = Toaster.show(
      context,
      failure ? 'Copy could not be confirmed. Try again.' : 'Copied',
      id: _copyResultId,
      severity: failure ? ToastSeverity.error : ToastSeverity.success,
      persistent: failure,
      duration: failure ? null : const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _toast?.dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('One copy result, updated in place'),
      Button(
        text: 'Copy succeeds',
        autofocus: true,
        onPressed: () => _result(failure: false),
      ),
      Button(text: 'Copy fails', onPressed: () => _result(failure: true)),
      Button(text: 'Dismiss', onPressed: () => _toast?.dismiss()),
      const Text('Tab moves focus · Enter activates · Esc dismisses toast'),
    ],
  );
}
