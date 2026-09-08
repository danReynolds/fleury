import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;
import '../../../fleury/test/fixtures/list_interaction_widget.dart';

Future<void> main() async {
  await mountApp(
    () => const ListInteractionFixture(),
    into: web.document.getElementById('app')!,
  );
}
