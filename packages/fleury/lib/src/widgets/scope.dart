import 'framework.dart';

/// Rebuilds a subtree when its nearest [Scope] changes or its value notifies.
///
/// The builder receives the value and its own build context. Dependencies are
/// reconciled after every build, and the scope retains ownership of its value.
class ScopeBuilder<T extends Object> extends StatelessWidget {
  const ScopeBuilder({super.key, required this.builder});

  /// Builds from the nearest scoped value whenever it changes or notifies.
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) => builder(context, context.scope<T>());
}
