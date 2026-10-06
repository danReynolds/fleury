import 'package:fleury/fleury_core.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Count: $count'),
      Button(
        text: 'Add one',
        autofocus: true,
        onPressed: () => setState(() => count++),
      ),
    ],
  );
}
