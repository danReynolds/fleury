import 'framework.dart';

/// Rebuilds a subtree when its nearest [Scope] changes or its value notifies.
///
/// The widget form of [BuildContext.scope]: it reads exactly what
/// `context.scope<T>()` reads and subscribes the same way, but rebuilds only
/// this builder rather than the enclosing widget. A nullable type argument
/// (`ScopeBuilder<Model?>`) makes the scope optional. The scope keeps
/// ownership of its value.
class ScopeBuilder<T> extends StatelessWidget {
  const ScopeBuilder({super.key, required this.builder});

  /// Builds from the nearest scoped value whenever it changes or notifies.
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) => builder(context, context.scope<T>());
}
