import 'dart:async';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// The target-neutral widget tree shared by the getting-started entrypoints.
class StatusApp extends StatefulWidget {
  const StatusApp({super.key});

  @override
  State<StatusApp> createState() => _StatusAppState();
}

class _StatusAppState extends State<StatusApp> {
  var _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('uptime: ${_tick}s'),
          const SizedBox(height: 1),
          ProgressBar(value: (_tick % 60) / 60),
        ],
      ),
    );
  }
}
