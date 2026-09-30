// The browser entrypoint for Getting started's MyApp (web/main.dart in
// Getting started).
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

import 'getting_started_app.dart';

Future<void> main() async {
  await mountApp(
    () => const MyApp(),
    into: web.document.getElementById('app')!,
  );
}
