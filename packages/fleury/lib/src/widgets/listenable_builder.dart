// ListenableBuilder: a general-purpose Listenable consumer. Subscribes
// to any Listenable (an Animation, a FrameTicker, any ChangeNotifier-
// backed model) and rebuilds the `builder`-produced subtree each
// time it notifies.
//
// For an Animation, reading `animation.value` directly in a build already
// auto-subscribes the element, so ListenableBuilder is mainly for
// other Listenables, or for scoping a rebuild to a small subtree via
// the reused `child`.
//
// The optional `child` is reused across rebuilds - a performance
// escape hatch for subtree content that doesn't depend on the
// notifier. Common pattern: build expensive static content outside,
// pass it as `child`, have the builder wrap it in something that
// does depend on the notifier:
//
//   ListenableBuilder(
//     listenable: model,
//     child: ExpensiveStatic(),
//     builder: (ctx, child) => Padding(
//       padding: EdgeInsets.only(left: model.indent),
//       child: child,
//     ),
//   )

import '../foundation/change_notifier.dart';
import 'framework.dart';

/// Builds a widget by subscribing to a [Listenable] and invoking
/// [builder] each time it notifies.
class ListenableBuilder extends StatefulWidget {
  const ListenableBuilder({
    super.key,
    Listenable? listenable,
    @Deprecated('Use listenable instead. This alias will be removed later.')
    Listenable? animation,
    required this.builder,
    this.child,
  }) : assert(
         listenable != null || animation != null,
         'ListenableBuilder requires a listenable.',
       ),
       assert(
         listenable == null || animation == null,
         'Pass either listenable or animation, not both.',
       ),
       _listenable = listenable,
       _animation = animation;

  final Listenable? _listenable;
  final Listenable? _animation;

  /// The notifier to listen to. An `Animation`, a `FrameTicker`, or any
  /// other [Listenable].
  Listenable get listenable => _listenable ?? _animation!;

  /// Compatibility alias for older Fleury code.
  @Deprecated('Use listenable instead. This alias will be removed later.')
  Listenable get animation => listenable;

  /// Called on every notification. Receives the BuildContext of
  /// the builder's location in the tree and the (unchanged) [child]
  /// passed to this widget — handy for wrapping a static subtree
  /// in a transform that depends on the animation.
  final Widget Function(BuildContext context, Widget? child) builder;

  /// Pre-built subtree passed unchanged to [builder] on each
  /// rebuild. Use for content that doesn't depend on the animation,
  /// to avoid rebuilding it.
  final Widget? child;

  @override
  State<ListenableBuilder> createState() => _ListenableBuilderState();
}

class _ListenableBuilderState extends State<ListenableBuilder> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onListenableChanged);
  }

  @override
  void didUpdateWidget(ListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.listenable, oldWidget.listenable)) {
      oldWidget.listenable.removeListener(_onListenableChanged);
      widget.listenable.addListener(_onListenableChanged);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onListenableChanged);
    super.dispose();
  }

  void _onListenableChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.child);
  }
}
