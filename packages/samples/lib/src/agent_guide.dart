import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// The small release workflow used by the Driving with an agent guide.
///
/// It deliberately uses ordinary Fleury controls. Their existing roles,
/// labels, values, and actions are enough for a person, a widget test, or an
/// MCP agent to drive the same workflow.
class AgentGuideApp extends StatefulWidget {
  const AgentGuideApp({super.key});

  @override
  State<AgentGuideApp> createState() => _AgentGuideAppState();
}

class _AgentGuideAppState extends State<AgentGuideApp> {
  final version = TextEditingController(text: '0.9.0');
  bool testsPassed = false;
  String status = 'Draft';

  @override
  void dispose() {
    version.dispose();
    super.dispose();
  }

  void prepareRelease() {
    final release = version.text.trim();
    setState(() {
      status = switch ((release.isEmpty, testsPassed)) {
        (true, _) => 'Blocked: enter a version',
        (false, false) => 'Blocked: mark tests passed',
        (false, true) => 'Ready to publish $release',
      };
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Release checklist', style: CellStyle(bold: true)),
        const Text('Complete the checks, then prepare the release.'),
        const SizedBox(height: 1),
        const Text('Version'),
        SizedBox(
          width: 28,
          child: TextInput(
            controller: version,
            semanticLabel: 'Release version',
            autofocus: true,
          ),
        ),
        Checkbox(
          label: 'Tests passed',
          value: testsPassed,
          onChanged: (value) => setState(() => testsPassed = value),
        ),
        const SizedBox(height: 1),
        Button(
          text: 'Prepare release',
          variant: ButtonVariant.primary,
          onPressed: prepareRelease,
        ),
        const SizedBox(height: 1),
        Text('Status: $status'),
      ],
    ),
  );
}
