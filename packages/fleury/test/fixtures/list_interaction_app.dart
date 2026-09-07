import 'package:fleury/fleury.dart';
import 'list_interaction_widget.dart';

Future<void> main() => runApp(
  const ListInteractionFixture(),
  mode: const TerminalMode(mouse: true),
);
