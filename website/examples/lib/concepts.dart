// Live demos for the "Widgets & state" concepts page, which shows these
// `#docregion` excerpts beside them.
import 'dart:async';

import 'package:fleury/fleury_core.dart';

// #docregion clock
class Clock extends StatefulWidget {
  const Clock({super.key});

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel(); // started in initState → cleaned up here
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('$_now'.substring(0, 19));
}

// #enddocregion clock
