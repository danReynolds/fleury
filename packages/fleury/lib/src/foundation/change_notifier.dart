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
///
/// Notification honors the `Listenable` contract: a listener removed (or the
/// notifier disposed) *during* a `notifyListeners` pass is not invoked
/// afterwards. Removal during notification nulls the listener's slot rather
/// than shrinking the backing list, so the in-progress index walk stays valid
/// and skips it; the list is compacted once the outermost pass completes. This
/// is allocation-free in the common case — no per-notify copy — which matters
/// because `notifyListeners` is a per-frame hot path.
mixin class ChangeNotifier implements Listenable {
  // Grows on demand; slots past [_count] are unused, and slots nulled by a
  // mid-notification removal are compacted out once notification unwinds.
  List<VoidCallback?> _listeners = List<VoidCallback?>.filled(0, null);
  int _count = 0;

  // Re-entrancy depth of [notifyListeners] and how many live slots were nulled
  // by a removal during the current notification, deferred to a single compact.
  int _notificationDepth = 0;
  int _reentrantlyRemoved = 0;
  bool _disposed = false;

  /// Whether at least one listener is registered.
  bool get hasListeners => _count > 0;

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) {
      throw StateError('addListener called on disposed ChangeNotifier.');
    }
    if (_count == _listeners.length) {
      final newCapacity = _count == 0 ? 1 : _count * 2;
      final grown = List<VoidCallback?>.filled(newCapacity, null);
      for (var i = 0; i < _count; i++) {
        grown[i] = _listeners[i];
      }
      _listeners = grown;
    }
    _listeners[_count++] = listener;
  }

  @override
  void removeListener(VoidCallback listener) {
    for (var i = 0; i < _count; i++) {
      if (_listeners[i] == listener) {
        if (_notificationDepth > 0) {
          // Null the slot instead of shrinking so the in-progress index walk
          // stays valid; the not-yet-called listener is skipped, and the gap
          // is compacted away when the outermost notification returns.
          _listeners[i] = null;
          _reentrantlyRemoved += 1;
        } else {
          _removeAt(i);
        }
        return; // Remove only the first matching registration.
      }
    }
  }

  void _removeAt(int index) {
    _count -= 1;
    for (var i = index; i < _count; i++) {
      _listeners[i] = _listeners[i + 1];
    }
    _listeners[_count] = null;
  }

  /// Invokes every listener registered when the pass began. A listener added
  /// during notification runs on the next pass, not this one; one removed
  /// during notification (or lost to [dispose]) is skipped.
  @protected
  void notifyListeners() {
    if (_disposed || _count == 0) return;
    _notificationDepth += 1;
    // Snapshot the length only; read live slots each step so a mid-pass
    // removal/dispose (which nulls slots in place) is observed.
    final end = _count;
    try {
      for (var i = 0; i < end; i++) {
        _listeners[i]?.call();
      }
    } finally {
      _notificationDepth -= 1;
      if (_notificationDepth == 0 && _reentrantlyRemoved > 0) {
        _compact();
      }
    }
  }

  void _compact() {
    var write = 0;
    for (var read = 0; read < _count; read++) {
      final listener = _listeners[read];
      if (listener != null) _listeners[write++] = listener;
    }
    for (var i = write; i < _count; i++) {
      _listeners[i] = null;
    }
    _count = write;
    _reentrantlyRemoved = 0;
  }

  /// Marks this notifier as disposed and drops its listeners. Nulls the slots
  /// in place (rather than replacing the backing list) so a [dispose] called
  /// from within a listener leaves any in-progress [notifyListeners] walk
  /// reading valid, now-empty slots. After dispose, [addListener] throws.
  @mustCallSuper
  void dispose() {
    _disposed = true;
    for (var i = 0; i < _count; i++) {
      _listeners[i] = null;
    }
    _count = 0;
  }
}
