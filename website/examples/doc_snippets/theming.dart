// Compile-checked source behind the Theming guide. It demonstrates an app
// theme, shared control-state styling, and one local CellStyle override.
// Guarded by ../test/doc_snippets_test.dart and theme_source_parity_test.dart.

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(themingDemoApp());

const amber = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme(
    background: RgbColor(0x1C, 0x18, 0x14),
    foreground: RgbColor(0xEB, 0xDB, 0xB2),
    surface: RgbColor(0x2A, 0x24, 0x1E),
    primary: RgbColor(0xE8, 0xA3, 0x3D),
    focus: RgbColor(0xF2, 0xC5, 0x5C),
    success: RgbColor(0x8E, 0xC0, 0x7C),
    warning: RgbColor(0xE8, 0xA3, 0x3D),
    error: RgbColor(0xE5, 0x6B, 0x5B),
    info: RgbColor(0x83, 0xA5, 0x98),
  ),
  mutedStyle: CellStyle(dim: true),
  selectionStyle: CellStyle(inverse: true),
  focusedStyle: CellStyle(bold: true),
  interactiveStyle: CellStyle.state(
    focused: CellStyle(inverse: true, bold: true),
    hovered: CellStyle(underline: true),
    selected: CellStyle(foreground: Colors.green, bold: true),
    invalid: CellStyle(foreground: Colors.red, underline: true),
    disabled: CellStyle(dim: true),
  ),
  borderStyle: BorderStyle.rounded,
);

Widget themingDemoApp() =>
    const FleuryApp(title: 'Theming', theme: amber, home: DeploymentForm());

class DeploymentForm extends StatefulWidget {
  const DeploymentForm({super.key});

  @override
  State<DeploymentForm> createState() => _DeploymentFormState();
}

class _DeploymentFormState extends State<DeploymentForm> {
  final _form = FormController();
  final _name = TextEditingController();
  bool _approved = true;

  @override
  void dispose() {
    _form.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    controller: _form,
    onSubmit: () {},
    child: Column(
      children: [
        FormField(
          validator: () => _name.text.isEmpty ? 'Enter a service name.' : null,
          child: TextInput(controller: _name, placeholder: 'Service name'),
        ),
        Checkbox(
          value: _approved,
          label: 'Approved',
          onChanged: (value) => setState(() => _approved = value),
        ),
        Row(
          children: [
            Button(label: 'Deploy', onPressed: _form.submit),
            const Button(label: 'Queued', onPressed: null),
          ],
        ),
      ],
    ),
  );
}
