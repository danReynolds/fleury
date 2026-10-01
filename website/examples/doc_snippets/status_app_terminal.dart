// The native entrypoint for Getting started's MyApp, passing the same runApp
// arguments as the bin/run_app.dart that `fleury create` generates.
import 'package:fleury/fleury.dart';

import 'getting_started_app.dart';

void main(List<String> args) =>
    runApp(const MyApp(), args: args, mode: const TerminalMode(mouse: true));
