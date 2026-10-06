// Compiled to JavaScript by test/widgets/route_label_minified_test.dart at
// several dart2js optimization levels and run under Node. Prints the active
// route's semantic label and routeName ("null" when unnamed).

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';

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
  print('${route.label} ${route.state.routeName}');
}
