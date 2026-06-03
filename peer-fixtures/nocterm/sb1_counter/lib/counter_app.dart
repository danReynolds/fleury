import 'package:nocterm/nocterm.dart';

class Sb1Counter extends StatefulComponent {
  const Sb1Counter({super.key});

  @override
  State<Sb1Counter> createState() => _Sb1CounterState();
}

class _Sb1CounterState extends State<Sb1Counter> {
  var _count = 0;

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space) {
          setState(() {
            _count += 1;
          });
          return true;
        }
        return false;
      },
      child: Center(child: Text('Count: $_count')),
    );
  }
}
