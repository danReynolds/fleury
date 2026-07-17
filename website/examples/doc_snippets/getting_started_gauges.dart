import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

/// The gauges step of getting-started: the build the page swaps into
/// StatusApp before the entrypoint split (`status_app.dart` keeps the
/// uptime build the split ships with).
class GaugesPanel extends StatelessWidget {
  const GaugesPanel({super.key});

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
