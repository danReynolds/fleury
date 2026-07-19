import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// The target-neutral widget tree shared by the getting-started entrypoints.
class StatusApp extends StatelessWidget {
  const StatusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Gauge(value: 0.62, label: 'CPU'),
          Gauge(value: 0.81, label: 'MEM'),
          Gauge(value: 0.34, label: 'DISK'),
          const SizedBox(height: 1),
          Sparkline(data: const [3, 5, 4, 8, 6, 9, 7, 5, 8, 6]),
        ],
      ),
    );
  }
}
