import 'package:fleury/fleury_core.dart';

class Preferences extends StatefulWidget {
  const Preferences({super.key, this.autofocus = false});
  final bool autofocus;

  @override
  State<Preferences> createState() => _PreferencesState();
}

class _PreferencesState extends State<Preferences> {
  String name = '';
  bool emailUpdates = false;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 26,
        child: TextInput(
          semanticLabel: 'Name',
          placeholder: 'Name',
          autofocus: widget.autofocus,
          onChanged: (value) => setState(() => name = value),
        ),
      ),
      Checkbox(
        label: 'Email updates',
        value: emailUpdates,
        onChanged: (value) => setState(() => emailUpdates = value),
      ),
      Text(emailUpdates ? 'Updates for $name' : 'Email updates off'),
    ],
  );
}

Widget preferencesPair() => const Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('PERSONAL', style: CellStyle(dim: true)),
    Preferences(key: ValueKey('personal')),
    SizedBox(height: 1),
    Text('WORK', style: CellStyle(dim: true)),
    Preferences(key: ValueKey('work'), autofocus: true),
  ],
);
