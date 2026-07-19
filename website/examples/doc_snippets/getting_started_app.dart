import 'package:fleury/fleury.dart';

import 'status_app.dart';

/// Native app wrapper produced by the final getting-started step.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const FleuryApp(title: 'Status monitor', home: StatusApp());
  }
}
