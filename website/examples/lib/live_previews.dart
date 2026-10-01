// The Toaster preview's buttons.
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class ToasterPreview extends StatelessWidget {
  const ToasterPreview({super.key});

  @override
  Widget build(BuildContext context) =>
      const Toaster(duration: Duration(seconds: 3), child: _ToastButtons());
}

class _ToastButtons extends StatelessWidget {
  const _ToastButtons();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Raise a toast:'),
      const SizedBox(height: 1),
      Row(
        children: [
          Button(
            text: 'Save',
            autofocus: true,
            onPressed: () =>
                Toaster.show(context, 'Saved', severity: ToastSeverity.success),
          ),
          const SizedBox(width: 1),
          Button(
            text: 'Retry',
            onPressed: () => Toaster.show(
              context,
              'Connection slow, retrying',
              severity: ToastSeverity.warning,
            ),
          ),
          const SizedBox(width: 1),
          Button(
            text: 'Fail',
            onPressed: () => Toaster.show(
              context,
              'Upload failed',
              severity: ToastSeverity.error,
            ),
          ),
        ],
      ),
    ],
  );
}
