// Compile-checked source behind App entry points and Theming. It proves the
// canonical FleuryApp(home:, theme:) shape and the explicit custom-shell path.

import 'package:fleury/fleury.dart';

void main() => runApp(
  const FleuryApp(
    title: 'Status monitor',
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme(primary: RgbColor(0x3D, 0xDC, 0x97)),
    ),
    home: HomeScreen(),
  ),
);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push<void>(const DetailScreen()),
    child: const Text('Open details'),
  );
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: () => context.pop(), child: const Text('Back'));
}

/// An explicit custom shell owns its Navigator instead of asking FleuryApp to
/// create one from `home`.
Widget customShellExample() => const FleuryApp(
  title: 'Workspace',
  child: Row(
    children: [
      SizedBox(width: 18, child: Text('Workspace')),
      Expanded(child: Navigator(home: HomeScreen())),
    ],
  ),
);
