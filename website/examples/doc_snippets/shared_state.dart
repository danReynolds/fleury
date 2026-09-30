// Executable entry point behind the State management guide. The web-safe
// widgets below are also the exact widgets rendered by the live docs embeds.
//
// Run it: dart run doc_snippets/shared_state.dart

import 'package:fleury/fleury.dart';

import '../lib/state_management_guide.dart';

export '../lib/state_management_guide.dart';

// #docregion external-owner
Future<void> main(List<String> args) async {
  final cart = Cart();
  try {
    await runApp(
      FleuryApp(
        title: 'Shop',
        home: Scope(cart, child: const ShopScreen()),
      ),
      args: args,
    );
  } finally {
    cart.dispose();
  }
}
// #enddocregion external-owner

Widget localStateDemoApp() =>
    const FleuryApp(title: 'Counter', home: LocalCounter());

Widget projectScopeDemoApp() =>
    const FleuryApp(title: 'Project', home: ProjectScreen());

Widget shopDemoApp() => const FleuryApp(title: 'Shop', home: Shop());

Widget cartNotifierDemoApp() =>
    const FleuryApp(title: 'Cart', home: CartDemo());
