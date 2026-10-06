// Compiled to JavaScript by test/widgets/route_label_minified_test.dart and
// run under Node. Prints the active route's semantic label and routeName
// ("null" when unnamed).

import 'package:fleury/fleury_test_support.dart';
import 'package:fleury/src/primitives.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('Settings');
}

void main() {
  final tester = FleuryTester()
    ..pumpWidget(const FleuryApp(title: 'Probe', home: SettingsScreen()))
    ..render();
  final route = tester.semantics().single(
    role: SemanticRole.route,
    selected: true,
  );
  print('label=${route.label} routeName=${route.state.routeName}');
}
