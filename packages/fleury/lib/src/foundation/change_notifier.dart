import 'package:meta/meta.dart';

import '../widgets/framework.dart' show VoidCallback;

/// An object that can notify listeners when something about it changes.
///
/// Used by `ListenableBuilder`, `InheritedNotifier`, and any mutable
/// model that wants to broadcast changes without imposing a Stream
/// subscription model on consumers.
abstract interface class Listenable {
  /// Registers [listener] to be called when this object changes.
  void addListener(VoidCallback listener);

  /// Removes a previously-registered listener.
  void removeListener(VoidCallback listener);
}

/// Concrete [Listenable] with a `notifyListeners` hook for subclasses.
///
/// Mirrors `package:flutter/foundation.dart`'s `ChangeNotifier` minus
/// the debug-mode disposed-after-use assertions (worth adding later
/// alongside other diagnostics).
mixin class ChangeNotifier implements Listenable {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _disposed = false;

  /// Whether at least one listener is registered.
  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) {
      throw StateError('addListener called on disposed ChangeNotifier.');
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Invokes every registered listener. Iterates over a copy so a
  /// listener can add or remove listeners during notification without
  /// disturbing the iteration.
  @protected
  void notifyListeners() {
    if (_disposed) return;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// Marks this notifier as disposed and clears its listener list.
  /// After dispose, [addListener] throws.
  @mustCallSuper
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}
