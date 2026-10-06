import 'package:fleury/fleury_core.dart';

import 'save_status.dart';

class TestingSaveDemo extends StatelessWidget {
  const TestingSaveDemo({super.key});

  @override
  Widget build(BuildContext context) => SaveStatus(
    save: () => Future<void>.delayed(const Duration(milliseconds: 800)),
  );
}
