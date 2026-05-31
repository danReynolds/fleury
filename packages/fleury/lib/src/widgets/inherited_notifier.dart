import '../foundation/change_notifier.dart';
import 'framework.dart';

/// An [InheritedWidget] whose effective identity is its `notifier`'s
/// listener notifications, not its own widget instance.
///
/// Use this when ancestors want to share a mutable model (a
/// `FocusManager`, a `ChangeNotifier`-backed app state) and have
/// dependents rebuild automatically when the model fires.
///
/// Mirrors Flutter's `InheritedNotifier` minus the listening on
/// `notifier` itself — we do it explicitly via the element's
/// lifecycle to keep things readable.
abstract class InheritedNotifier<T extends Listenable> extends InheritedWidget {
  const InheritedNotifier({
    super.key,
    required this.notifier,
    required super.child,
  });

  /// The mutable listenable this widget shares with descendants.
  final T notifier;

  @override
  bool updateShouldNotify(covariant InheritedNotifier<T> oldWidget) {
    // Only the notifier identity matters; field changes on the same
    // notifier flow through listener notifications, not through widget
    // updates.
    return notifier != oldWidget.notifier;
  }

  @override
  InheritedElement createElement() => _InheritedNotifierElement<T>(this);
}

class _InheritedNotifierElement<T extends Listenable> extends InheritedElement {
  _InheritedNotifierElement(InheritedNotifier<T> super.widget);

  T? _attachedNotifier;
  late final VoidCallback _listener = _onNotifierChanged;

  void _onNotifierChanged() {
    notifyDependents();
  }

  @override
  InheritedNotifier<T> get widget => super.widget as InheritedNotifier<T>;

  @override
  void mount(Element? parent) {
    // Attach the listener BEFORE super.mount runs the child-build
    // cascade. Without this, a descendant whose initial build
    // triggers the notifier (e.g. a Focus widget's autofocus
    // calling manager.requestFocus during its own first build)
    // fires while no listener is subscribed — the notification
    // is lost and the descendant never learns about a focus change
    // that already happened.
    _attach(widget.notifier);
    super.mount(parent);
  }

  @override
  void update(covariant InheritedNotifier<T> newWidget) {
    if (!identical(_attachedNotifier, newWidget.notifier)) {
      _detach();
      super.update(newWidget);
      _attach(newWidget.notifier);
    } else {
      super.update(newWidget);
    }
  }

  @override
  void unmount() {
    _detach();
    super.unmount();
  }

  void _attach(T notifier) {
    _attachedNotifier = notifier;
    notifier.addListener(_listener);
  }

  void _detach() {
    _attachedNotifier?.removeListener(_listener);
    _attachedNotifier = null;
  }
}
