import '../foundation/change_notifier.dart';
import 'framework.dart';

/// Builds a subtree when [notifier] publishes a change.
///
/// The builder receives the original, typed notifier and a context belonging to
/// this widget. Additional `context.listen` or `context.scope` calls inside the
/// builder also rebuild this widget, rather than its parent.
///
/// Subscriptions follow the sources used by each build and are removed when this
/// widget unmounts. The source remains owned by its caller and is never disposed
/// by this widget. Any [Listenable] is supported, including [Notifier],
/// [ValueNotifier], animations, and custom subscription sources.
class NotifierBuilder<T extends Listenable> extends StatelessWidget {
  const NotifierBuilder({
    super.key,
    required this.notifier,
    required this.builder,
  });

  /// The model or other subscription source to observe.
  final T notifier;

  /// Builds from the current state of [notifier] whenever it notifies.
  final Widget Function(BuildContext context, T notifier) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, context.listen(notifier));
}
