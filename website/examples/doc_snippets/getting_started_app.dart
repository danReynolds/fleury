// The finished `lib/app.dart` from Getting started. Its imports are the
// web-safe libraries, so both the native entrypoint (status_app_terminal.dart)
// and the browser entrypoint (status_app_web.dart) run this same MyApp.
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const FleuryApp(title: 'Status monitor', home: StatusApp());
  }
}

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
