// Executable entry point behind the State management guide. The web-safe
// widgets below are also the exact widgets rendered by the live docs embeds.
//
// Run it: dart run doc_snippets/shared_state.dart

import 'package:fleury/fleury.dart';

import '../lib/state_management_guide.dart';

export '../lib/state_management_guide.dart';

Future<void> main(List<String> args) async {
  final cart = Cart();
  try {
    await runApp(
      FleuryApp(
        title: 'Cart',
        home: CartView(cart: cart),
      ),
      args: args,
    );
  } finally {
    cart.dispose();
  }
}

Widget localStateDemoApp() =>
    const FleuryApp(title: 'Counter', home: LocalCounter());

Widget projectScopeDemoApp() =>
    const FleuryApp(title: 'Project', home: ProjectScopeScreen());

Widget projectContextDemoApp() =>
    const FleuryApp(title: 'Project', home: ProjectScreen());

Widget cartNotifierDemoApp() =>
    const FleuryApp(title: 'Cart', home: CartDemo());

Widget cartContextDemoApp() =>
    const FleuryApp(title: 'Cart', home: CartDemo(contextReader: true));

Widget cartValueDemoApp() =>
    const FleuryApp(title: 'Cart', home: CartValueDemo());
