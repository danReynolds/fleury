import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

import 'status_app.dart';

Future<void> main() async {
  final host = web.document.getElementById('app')!;
  await mountApp(
    () => const FleuryApp(title: 'Status monitor', home: StatusApp()),
    into: host,
  );
}
